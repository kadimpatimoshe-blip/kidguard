package com.kidguard.child.security

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log

class DeviceControlManager(private val context: Context) {
    private val dpm = context.getSystemService(DevicePolicyManager::class.java)
    private val adminComponent = ComponentName(context, KidGuardDeviceAdminReceiver::class.java)

    companion object {
        private const val TAG = "DeviceControlManager"
    }

    /**
     * Checks if KidGuard has active Device Administrator privileges.
     */
    fun isAdminActive(): Boolean {
        return dpm?.isAdminActive(adminComponent) == true
    }

    /**
     * Instantly locks the child device screen if administrator permission is active.
     */
    fun lockDevice(): Boolean {
        return try {
            if (isAdminActive()) {
                dpm?.lockNow()
                Log.i(TAG, "Screen locked via DevicePolicyManager.")
                true
            } else {
                Log.w(TAG, "Cannot lock device: KidGuard is not an active Device Administrator.")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error executing lockNow: ${e.message}", e)
            false
        }
    }

    /**
     * Helper intent to prompt user to activate Device Administrator privileges.
     */
    fun getAdminActivationIntent(): Intent {
        return Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
            putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
            putExtra(
                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                "KidGuard requires Device Administrator rights to enforce screen time limits and lock the device when scheduled."
            )
        }
    }
}
