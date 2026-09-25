package com.example.callshield_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Brings Message Shield's background protection back after a reboot or an app
 * update, but only when the user turned automatic protection on.
 *
 * Android does not deliver boot broadcasts to an app the user explicitly force
 * stopped, and does not allow arbitrary background service starts, so this is a
 * best-effort recovery - never a claim of guaranteed execution.
 */
class MessageShieldBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action !in RECOVERY_ACTIONS) return
        try {
            if (!MessageShieldNativeBridge.isAutoProtectionEnabled(context)) return
            if (!MessageShieldNativeBridge.hasSmsPermission(context)) {
                Log.i(TAG, "automatic protection on but SMS permission is missing")
                return
            }
            MessageShieldProtectionService.start(context, "recovery:$action")
        } catch (t: Throwable) {
            Log.w(TAG, "recovery start failed for $action", t)
        }
    }

    companion object {
        private const val TAG = "MessageShieldBoot"
        private val RECOVERY_ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
        )
    }
}
