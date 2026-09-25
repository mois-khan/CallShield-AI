package com.example.callshield_app

import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Message Shield's own Android foreground service.
 *
 * Purpose (and only purpose): keep Message Shield able to screen incoming SMS
 * while the CallShield UI is closed, the phone is locked, or the user is in
 * another app.
 *
 *  * persistent, low-importance notification so the user always knows it is on;
 *  * a headless Flutter engine running `messageShieldProtectionMain`, so the
 *    analysis happens with no UI on screen (and the UI engine may not even
 *    exist);
 *  * event driven: the SMS receiver pushes each message here. There is no
 *    polling loop, no wake lock held open and no network traffic;
 *  * START_STICKY plus a boot receiver so Android can bring it back after a
 *    process kill or a reboot. A user force-stop is respected by Android and
 *    cannot be worked around - in that case protection resumes when the user
 *    next opens the app (documented in the UI and the report).
 *
 * Call Shield is not involved: this service never touches calls, alerts,
 * Twilio/Deepgram, Grandma Mode or reports.
 */
class MessageShieldProtectionService : Service() {

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null

    @Volatile
    private var dartReady = false

    /** Payloads that arrived before the Dart side was listening. */
    private val pending = ArrayDeque<Map<String, Any?>>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannels(this)
        isRunning = true
        Log.i(TAG, "protection service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Must happen immediately after startForegroundService() was requested.
        goForeground()

        when (intent?.action) {
            ACTION_STOP -> {
                Log.i(TAG, "stop requested")
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_ANALYZE -> {
                val payload = intent.getStringExtra(EXTRA_PAYLOAD)
                ensureEngine()
                if (payload.isNullOrBlank()) {
                    requestDrain("analyze intent without payload")
                } else {
                    deliverPayload(payload)
                }
            }
            ACTION_DRAIN -> {
                ensureEngine()
                requestDrain("drain requested")
            }
            else -> {
                // Plain start (toggle, boot, Android restart): make sure the
                // engine exists and pick up anything queued while we were away.
                ensureEngine()
                requestDrain("service start")
            }
        }
        // START_STICKY: if Android kills the process it restarts the service.
        return START_STICKY
    }

    /** Swiping the app away must not silently disable protection. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "task removed - protection service stays alive")
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        isRunning = false
        try {
            channel?.setMethodCallHandler(null)
            engine?.destroy()
        } catch (t: Throwable) {
            Log.w(TAG, "engine shutdown problem", t)
        }
        engine = null
        channel = null
        dartReady = false
        super.onDestroy()
        Log.i(TAG, "protection service destroyed")
    }

    // ------------------------------------------------------------------ engine

    private fun ensureEngine() {
        if (engine != null) return
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            if (!loader.initialized()) {
                loader.startInitialization(applicationContext)
            }
            loader.ensureInitializationComplete(applicationContext, null)

            // Same recipe flutter_background_service uses for its own engine:
            // a plain headless engine plus DartPluginRegistrant.ensureInitialized().
            val flutterEngine = FlutterEngine(this)
            channel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                CHANNEL_NAME,
            ).also { methodChannel ->
                methodChannel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        // Dart finished loading its engine: flush what we hold.
                        "dartReady" -> {
                            dartReady = true
                            Log.i(TAG, "dart side ready")
                            result.success(null)
                            flushPending()
                        }
                        else -> result.notImplemented()
                    }
                }
            }
            // Library URI + function name: in a release (AOT) build the engine
            // resolves the entry point from the library that declares it.
            flutterEngine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(),
                    DART_ENTRYPOINT_LIBRARY,
                    DART_ENTRYPOINT,
                ),
            )
            engine = flutterEngine
            Log.i(TAG, "headless engine started")
        } catch (t: Throwable) {
            Log.w(TAG, "headless engine failed to start", t)
            engine = null
            channel = null
        }
    }

    private fun deliverPayload(payloadJson: String) {
        val payload = try {
            jsonToMap(JSONObject(payloadJson))
        } catch (t: Throwable) {
            Log.w(TAG, "malformed payload", t)
            return
        }
        synchronized(pending) {
            if (!dartReady || channel == null) {
                if (pending.size > 20) pending.removeFirst()
                pending.addLast(payload)
                return
            }
        }
        sendToDart(payload)
    }

    private fun flushPending() {
        val queued: List<Map<String, Any?>>
        synchronized(pending) {
            queued = pending.toList()
            pending.clear()
        }
        for (payload in queued) {
            sendToDart(payload)
        }
        // Anything captured while the process was dead is still in the inbox
        // file; drain it now that Dart is listening.
        requestDrain("post ready drain")
    }

    private fun requestDrain(reason: String) {
        if (!dartReady || channel == null) return
        invoke("analyzePending", mapOf("appForeground" to isAppInForeground(), "reason" to reason))
    }

    private fun sendToDart(payload: Map<String, Any?>) {
        val args = HashMap<String, Any?>(payload)
        // The background engine reports notifications only when the UI is away
        // (mirrors the "only notify in the background" user setting).
        args["appForeground"] = isAppInForeground()
        invoke("analyzePayload", args)
    }

    private fun invoke(method: String, args: Any?) {
        val activeChannel = channel ?: return
        try {
            activeChannel.invokeMethod(method, args)
        } catch (t: Throwable) {
            Log.w(TAG, "channel call $method failed", t)
        }
    }

    // ------------------------------------------------------------ notification

    private fun goForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // specialUse: an on-device SMS screening service the user turned on.
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_PROTECTION)
            .setContentTitle("Message Shield is protecting your messages")
            .setContentText("Screening incoming SMS on this device. No message ever leaves the phone.")
            .setSmallIcon(R.drawable.ic_bubble)
            .setColor(0xFF10B981.toInt())
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(contentIntent)
            .build()
    }

    companion object {
        private const val TAG = "MessageShieldSvc"
        const val CHANNEL_NAME = "com.callshield.native/message_shield_bg"
        const val DART_ENTRYPOINT = "messageShieldProtectionMain"
        const val DART_ENTRYPOINT_LIBRARY =
            "package:callshield_app/message_shield/background/message_shield_protection_entry.dart"

        const val ACTION_START = "com.example.callshield_app.MS_START"
        const val ACTION_DRAIN = "com.example.callshield_app.MS_DRAIN"
        const val ACTION_ANALYZE = "com.example.callshield_app.MS_ANALYZE"
        const val ACTION_STOP = "com.example.callshield_app.MS_STOP"
        const val EXTRA_PAYLOAD = "payload"

        private const val NOTIFICATION_ID = 8891
        private const val CHANNEL_PROTECTION = "message_shield_protection"

        /** Mirrors the live state of the service for the settings screen. */
        @Volatile
        var isRunning: Boolean = false
            private set

        fun createChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(CHANNEL_PROTECTION) != null) return
            val channel = NotificationChannel(
                CHANNEL_PROTECTION,
                "Message Shield protection",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shows that Message Shield is screening incoming SMS in the background."
                setShowBadge(false)
                enableVibration(false)
                enableLights(false)
            }
            manager.createNotificationChannel(channel)
        }

        /** Starts (or keeps) protection. Safe to call from the background. */
        fun start(context: Context, reason: String) {
            createChannels(context)
            val intent = Intent(context, MessageShieldProtectionService::class.java)
                .setAction(ACTION_START)
            try {
                androidx.core.content.ContextCompat.startForegroundService(context, intent)
                Log.i(TAG, "start requested ($reason)")
            } catch (t: Throwable) {
                // Android 12+ can refuse a background start (for example after a
                // long idle). Nothing is faked: the queued message stays in the
                // inbox file and is analysed at the next allowed start.
                Log.w(TAG, "foreground start refused ($reason): ${t.message}")
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, MessageShieldProtectionService::class.java))
                Log.i(TAG, "stop requested")
            } catch (t: Throwable) {
                Log.w(TAG, "stop failed: ${t.message}")
            }
        }

        /** Hands one SMS payload to the running service. */
        fun deliver(context: Context, payload: Map<String, Any?>) {
            createChannels(context)
            val json = JSONObject(payload as Map<*, *>).toString()
            val intent = Intent(context, MessageShieldProtectionService::class.java)
                .setAction(ACTION_ANALYZE)
                .putExtra(EXTRA_PAYLOAD, json)
            try {
                androidx.core.content.ContextCompat.startForegroundService(context, intent)
            } catch (t: Throwable) {
                // Message stays in the inbox file; it is analysed later.
                Log.w(TAG, "could not hand payload to service: ${t.message}")
            }
        }

        fun drainLater(context: Context, reason: String) {
            createChannels(context)
            val intent = Intent(context, MessageShieldProtectionService::class.java)
                .setAction(ACTION_DRAIN)
            try {
                androidx.core.content.ContextCompat.startForegroundService(context, intent)
            } catch (t: Throwable) {
                Log.w(TAG, "could not request drain ($reason): ${t.message}")
            }
        }

        /** True when the CallShield UI is currently visible. */
        fun isAppInForeground(): Boolean = try {
            val info = ActivityManager.RunningAppProcessInfo()
            ActivityManager.getMyMemoryState(info)
            info.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE
        } catch (t: Throwable) {
            false
        }

        private fun jsonToMap(json: JSONObject): Map<String, Any?> {
            val out = HashMap<String, Any?>()
            for (key in json.keys()) {
                val value = json.get(key)
                out[key] = if (value == JSONObject.NULL) null else value
            }
            return out
        }
    }
}
