package com.kidguard.child.security

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

class KidGuardDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        // Admin permission enabled
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        // Admin permission disabled
    }
}
