package com.example.callshield_app

import android.Manifest
import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.telephony.SubscriptionManager
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Native support for Message Shield.
 *
 * This class is completely separate from the Call Shield telecom channel
 * ("com.callshield.native/telecom"). It exposes:
 *   - `isAutoProtectionSupported()` / `setAutoProtection(enabled)`: the user
 *     switch. It persists the flag for the SMS receiver and starts/stops the
 *     Message Shield protection service.
 *   - `getProtectionStatus()`: real Android state (permissions, service alive,
 *     battery optimisation, declared receivers) for the settings screen.
 *   - `requestBatteryOptimizationExemption()` /
 *     `openBatteryOptimizationSettings()`: user-facing ways to make background
 *     screening reliable. Nothing is changed without the system dialog.
 *   - `getSharedPayload()`: a message shared (or selected) from another app,
 *     together with the source app package *when Android provides it*.
 *
 * Message contents are never sent anywhere by this class: it only moves text
 * between the Android intent/queue and Dart on the same device. No other app's
 * private data is read - only values Android itself puts in the intent.
 */
class MessageShieldNativeBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL_NAME).also {
        it.setMethodCallHandler(this)
    }

    /** Text waiting to be picked up by Dart (from ACTION_SEND / ACTION_PROCESS_TEXT). */
    private var pendingPayload: Map<String, Any?>? = null

    init {
        pendingPayload = extractPayload(activity.intent)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAutoProtectionSupported" ->
                result.success(receiverDeclared(MessageShieldSmsReceiver::class.java))

            "setAutoProtection" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                setAutoProtectionEnabled(activity, enabled)
                // Keep the background service in step with the user setting.
                if (enabled) {
                    MessageShieldProtectionService.start(activity, "user enabled automatic protection")
                } else {
                    MessageShieldProtectionService.stop(activity)
                }
                result.success(true)
            }

            "getProtectionStatus" -> result.success(protectionStatus())

            "requestBatteryOptimizationExemption" ->
                result.success(requestBatteryExemption())

            "openBatteryOptimizationSettings" -> {
                openBatterySettings()
                result.success(true)
            }

            "getSharedPayload" -> {
                val payload = pendingPayload
                pendingPayload = null
                // Clear the launch intent so a rotation or resume cannot re-ingest it.
                if (payload != null) {
                    activity.intent = Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_LAUNCHER)
                    }
                }
                result.success(payload)
            }

            else -> result.notImplemented()
        }
    }

    /** Called from MainActivity.onNewIntent when the app is already running. */
    fun handleNewIntent(intent: Intent) {
        val payload = extractPayload(intent) ?: return
        pendingPayload = payload
    }

    private fun extractPayload(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        val text: String? = when (intent.action) {
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            Intent.ACTION_PROCESS_TEXT ->
                intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
            Intent.ACTION_VIEW -> intent.dataString
            else -> null
        }
        if (text.isNullOrBlank()) return null
        val sourcePackage = sourcePackageOf(intent)
        val payload = HashMap<String, Any?>()
        payload["text"] = text.take(MAX_PAYLOAD_CHARS)
        payload["sender"] = senderHint(intent)
        payload["shareAction"] = intent.action ?: "unknown"
        if (!sourcePackage.isNullOrBlank()) {
            payload["appPackage"] = sourcePackage
            payload["appLabel"] = appLabelFor(sourcePackage)
        }
        return payload
    }

    /**
     * Best-effort source app for a shared/selected message.
     *
     * Only values Android itself attached to the launch are used: the referrer
     * extras that the system share sheet / text selection forwards, the reading
     * activity's referrer, and finally an explicit intent package. When none of
     * them is present the answer is null and the UI reports
     * "not provided by Android" - we never guess an app.
     */
    private fun sourcePackageOf(intent: Intent): String? {
        val candidates = ArrayList<String?>()
        // Public API: the referrer Uri (android-app://<package>).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            candidates.add(referrerUri(intent)?.host)
            candidates.add(activity.referrer?.host)
        }
        // The framework also forwards the referrer as a string extra. The
        // constant is hidden, so the documented string value is used here.
        val referrerName = intent.getStringExtra(EXTRA_REFERRER_NAME)
        if (!referrerName.isNullOrBlank()) {
            candidates.add(referrerName.removePrefix("android-app://").substringBefore('/'))
        }
        candidates.add(intent.`package`)
        return candidates.firstOrNull { candidate ->
            !candidate.isNullOrBlank() &&
                candidate != activity.packageName &&
                candidate != "android"
        }
    }

    private fun referrerUri(intent: Intent): Uri? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_REFERRER, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_REFERRER)
        }
    } catch (t: Throwable) {
        null
    }

    private fun appLabelFor(packageName: String): String? = try {
        val pm = activity.packageManager
        @Suppress("DEPRECATION")
        val info = pm.getApplicationInfo(packageName, 0)
        pm.getApplicationLabel(info).toString().takeIf { it.isNotBlank() }
    } catch (t: Throwable) {
        // Package visibility can hide the app; the Dart side falls back to a
        // local name table, and finally to the raw package name.
        null
    }

    /** Best-effort sender hint for shared chats; never guesses a phone number. */
    private fun senderHint(intent: Intent): String? {
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT) ?: return null
        return subject.take(60).ifBlank { null }
    }

    // ------------------------------------------------------------ status probes

    private fun protectionStatus(): Map<String, Any?> {
        val status = HashMap<String, Any?>()
        status["sdkInt"] = Build.VERSION.SDK_INT
        status["autoProtectionEnabled"] = isAutoProtectionEnabled(activity)
        status["smsPermissionGranted"] = hasSmsPermission(activity)
        status["notificationPermissionGranted"] = hasNotificationPermission(activity)
        status["batteryOptimizationIgnored"] = isIgnoringBatteryOptimizations()
        status["serviceRunning"] = MessageShieldProtectionService.isRunning
        status["bootRecoveryRegistered"] =
            receiverDeclared(MessageShieldBootReceiver::class.java)
        status["receiverRegistered"] = receiverDeclared(MessageShieldSmsReceiver::class.java)
        status["carrierLabel"] = defaultCarrier()
        return status
    }

    /** True only when the component really is declared in the merged manifest. */
    private fun receiverDeclared(clazz: Class<*>): Boolean = try {
        @Suppress("DEPRECATION")
        activity.packageManager.getReceiverInfo(
            ComponentName(activity.packageName, clazz.name),
            PackageManager.GET_RECEIVERS,
        )
        true
    } catch (t: Throwable) {
        false
    }

    private fun isIgnoringBatteryOptimizations(): Boolean = try {
        val power = activity.getSystemService(Context.POWER_SERVICE) as? PowerManager
        power?.isIgnoringBatteryOptimizations(activity.packageName) ?: false
    } catch (t: Throwable) {
        false
    }

    /** Shows the Android dialog that asks the user to exempt the app. */
    private fun requestBatteryExemption(): Boolean = try {
        val intent = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:${activity.packageName}"),
        )
        activity.startActivity(intent)
        true
    } catch (t: Throwable) {
        openBatterySettings()
        true
    }

    private fun openBatterySettings() {
        try {
            activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        } catch (t: Throwable) {
            // Some OEM builds hide that screen; nothing else we can do here.
        }
    }

    private fun defaultCarrier(): String? = try {
        val manager = activity.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
            as? SubscriptionManager ?: return null
        val subscriptionId = SubscriptionManager.getDefaultSmsSubscriptionId()
        @Suppress("DEPRECATION")
        val info = manager.getActiveSubscriptionInfo(subscriptionId)
        info?.carrierName?.toString()?.takeIf { it.isNotBlank() }
    } catch (t: Throwable) {
        null
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    companion object {
        const val CHANNEL_NAME = "com.callshield.native/message_shield"
        private const val PREFS_NAME = "message_shield_native"
        private const val KEY_AUTO = "auto_protection_enabled"
        private const val MAX_PAYLOAD_CHARS = 8000
        private const val EXTRA_REFERRER_NAME = "android.intent.extra.REFERRER_NAME"

        fun setAutoProtectionEnabled(context: Context, enabled: Boolean) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_AUTO, enabled)
                .apply()
        }

        fun isAutoProtectionEnabled(context: Context): Boolean =
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_AUTO, false)

        fun hasSmsPermission(context: Context): Boolean =
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECEIVE_SMS) ==
                PackageManager.PERMISSION_GRANTED

        fun hasNotificationPermission(context: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
    }
}
