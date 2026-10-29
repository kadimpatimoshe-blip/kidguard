package com.kidguard.child.boot

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.kidguard.child.service.LocationForegroundService
import com.kidguard.child.util.ServiceStarter

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED -> {
                ServiceStarter.startAll(context)
            }
        }
    }
}
