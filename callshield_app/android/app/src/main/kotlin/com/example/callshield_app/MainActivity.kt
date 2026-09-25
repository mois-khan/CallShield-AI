package com.example.callshield_app

import android.content.Context
import android.content.Intent
import android.os.Build
import android.telecom.TelecomManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.callshield.native/telecom"

    // 🆕 MESSAGE SHIELD (additive only): separate channel, does not touch CHANNEL
    private var messageShieldBridge: MessageShieldNativeBridge? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 🆕 MESSAGE SHIELD (additive only)
        messageShieldBridge = MessageShieldNativeBridge(this, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "endCall") {
                val success = disconnectCall()
                if (success) {
                    result.success("Call ended successfully")
                } else {
                    result.error("UNAVAILABLE", "Could not end call. Permission denied or no active call.", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    // 🆕 MESSAGE SHIELD (additive only): forward share/process-text intents
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        messageShieldBridge?.handleNewIntent(intent)
    }

    private fun disconnectCall(): Boolean {
        try {
            val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            // Android 9 (API 28) and above allow this with ANSWER_PHONE_CALLS permission
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val success = telecomManager.endCall()
                println("🛡️ [Native] Call Terminated: $success")
                return success
            }
            return false
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }
}