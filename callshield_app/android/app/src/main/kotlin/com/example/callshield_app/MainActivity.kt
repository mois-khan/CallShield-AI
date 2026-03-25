package com.example.callshield_app

import android.content.Context
import android.os.Build
import android.telecom.TelecomManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.callshield.native/telecom"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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