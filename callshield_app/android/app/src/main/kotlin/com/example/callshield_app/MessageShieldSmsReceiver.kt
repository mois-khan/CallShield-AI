package com.example.callshield_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.telephony.SmsMessage
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

/**
 * Queues incoming SMS for Message Shield and hands them to Message Shield's
 * protection service for immediate on-device analysis.
 *
 * The receiver itself does no analysis: it records what Android actually gives
 * us (sender address, service-centre timestamp, subscription id, SIM slot and
 * carrier when the platform exposes them) and passes it on. Dart scores the
 * message fully on the device.
 *
 * It is a no-op unless the user explicitly enabled automatic protection in
 * Message Shield (a flag written by MessageShieldNativeBridge) and RECEIVE_SMS
 * was granted. Nothing here touches Call Shield.
 */
class MessageShieldSmsReceiver : BroadcastReceiver() {

    /** One part-grouped SMS with the metadata Android reported for it. */
    private class Incoming(
        val sender: String,
        val address: String,
        val body: String,
        val receivedAtMillis: Long,
    )

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        try {
            if (!MessageShieldNativeBridge.isAutoProtectionEnabled(context)) return
            if (!MessageShieldNativeBridge.hasSmsPermission(context)) return

            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
            if (messages.isEmpty()) return

            val subscriptions = subscriptionMetadata(context, subscriptionIdOf(intent))

            // Reassemble multipart messages per originating address.
            val grouped = LinkedHashMap<String, StringBuilder>()
            val meta = LinkedHashMap<String, Incoming>()
            for (message in messages) {
                val sender = senderOf(message)
                val body = message.messageBody ?: message.displayMessageBody ?: ""
                if (body.isEmpty()) continue
                grouped.getOrPut(sender) { StringBuilder() }.append(body)
                if (!meta.containsKey(sender)) {
                    meta[sender] = Incoming(
                        sender = sender,
                        address = addressOf(message),
                        body = body,
                        receivedAtMillis = message.timestampMillis.takeIf { it > 0L }
                            ?: System.currentTimeMillis(),
                    )
                }
            }
            if (grouped.isEmpty()) return

            val file = File(context.filesDir, QUEUE_FILE)
            val payloads = ArrayList<Map<String, Any?>>()
            synchronized(LOCK) {
                trimIfHuge(file)
                for ((sender, body) in grouped) {
                    val first = meta[sender]
                    val payload = HashMap<String, Any?>()
                    payload["id"] = UUID.randomUUID().toString()
                    payload["sender"] = sender
                    payload["address"] = first?.address ?: sender
                    payload["body"] = body.toString().take(MAX_BODY_CHARS)
                    payload["ts"] = isoNow()
                    payload["delivered"] = isoFrom(first?.receivedAtMillis ?: System.currentTimeMillis())
                    subscriptions.subscriptionId?.let { payload["subId"] = it }
                    subscriptions.slotIndex?.let { payload["slot"] = it }
                    subscriptions.carrierName?.let { payload["carrier"] = it }
                    payloads.add(payload)
                    // Queue file: the fallback path if the service cannot start
                    // right now (Android restrictions or a refused start).
                    file.appendText(JSONObject(payload).toString() + "\n", Charsets.UTF_8)
                }
            }

            // Immediate analysis, no polling: the foreground service is normally
            // already alive; if not, starting it is attempted here.
            for (payload in payloads) {
                MessageShieldProtectionService.deliver(context, payload)
            }
        } catch (t: Throwable) {
            // Never crash the SMS delivery path of the device.
            Log.w(TAG, "Message Shield receiver skipped a message", t)
        }
    }

    private fun senderOf(message: SmsMessage): String =
        (message.displayOriginatingAddress ?: message.originatingAddress ?: "").trim()

    private fun addressOf(message: SmsMessage): String =
        (message.originatingAddress ?: message.displayOriginatingAddress ?: "").trim()

    /**
     * Subscription id of the SMS.
     *
     * The public SDK does not expose a subscription id on `SmsMessage`, so this
     * reads the `subscription` extra AOSP adds to the SMS_RECEIVED broadcast and
     * falls back to the default SMS subscription. When neither is available the
     * SIM information is simply reported as unavailable.
     */
    private fun subscriptionIdOf(intent: Intent): Int {
        val fromIntent = intent.getIntExtra("subscription", SubscriptionManager.INVALID_SUBSCRIPTION_ID)
        if (fromIntent != SubscriptionManager.INVALID_SUBSCRIPTION_ID) return fromIntent
        return try {
            SubscriptionManager.getDefaultSmsSubscriptionId()
        } catch (t: Throwable) {
            SubscriptionManager.INVALID_SUBSCRIPTION_ID
        }
    }

    private class SubscriptionMetadata(
        val subscriptionId: Int?,
        val slotIndex: Int?,
        val carrierName: String?,
    )

    /** SIM slot + carrier name, when Android exposes them to this app. */
    private fun subscriptionMetadata(context: Context, subscriptionId: Int): SubscriptionMetadata {
        if (subscriptionId == SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
            return SubscriptionMetadata(null, null, null)
        }
        return try {
            val manager = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                as? SubscriptionManager
                ?: return SubscriptionMetadata(subscriptionId, null, null)
            @Suppress("DEPRECATION", "MissingPermission")
            val info: SubscriptionInfo? = manager.getActiveSubscriptionInfo(subscriptionId)
            SubscriptionMetadata(
                subscriptionId = subscriptionId,
                slotIndex = info?.simSlotIndex,
                carrierName = info?.carrierName?.toString()?.takeIf { it.isNotBlank() },
            )
        } catch (t: Throwable) {
            // READ_PHONE_STATE missing or the OEM hides subscription info.
            SubscriptionMetadata(subscriptionId, null, null)
        }
    }

    /** Keeps the queue bounded on devices that receive a lot of SMS. */
    private fun trimIfHuge(file: File) {
        if (!file.exists() || file.length() < MAX_QUEUE_BYTES) return
        val lines = file.readLines()
        val kept = lines.takeLast(MAX_QUEUE_LINES)
        file.writeText(kept.joinToString(separator = "\n"), Charsets.UTF_8)
    }

    private fun isoNow(): String = isoFrom(System.currentTimeMillis())

    private fun isoFrom(millis: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).format(Date(millis))

    companion object {
        private const val TAG = "MessageShieldSms"
        private const val QUEUE_FILE = "message_shield_inbox.jsonl"
        private const val MAX_BODY_CHARS = 4000
        private const val MAX_QUEUE_BYTES = 256 * 1024
        private const val MAX_QUEUE_LINES = 200
        private val LOCK = Any()
    }
}
