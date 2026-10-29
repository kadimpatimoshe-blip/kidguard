package com.kidguard.child.util

import android.content.Context
import android.content.Intent
import android.util.Log
import com.kidguard.child.service.LocationForegroundService
import com.kidguard.child.service.AudioCaptureService
import com.kidguard.child.service.MediaProjectionForegroundService

object ServiceStarter {
    private const val TAG = "ServiceStarter"

    /**
     * Starts all necessary child protection foreground services safely.
     * Compliant with Android 14 (API 34+) background execution rules.
     */
    fun startAll(context: Context) {
        try {
            startService(context, LocationForegroundService::class.java)
            startService(context, AudioCaptureService::class.java)
            // Note: MediaProjectionForegroundService usually requires runtime user consent 
            // for screen recording, so it should be started explicitly when screen share is triggered.
            
            Log.i(TAG, "All mandatory child background services started successfully.")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start background services: ${e.message}", e)
        }
    }

    /**
     * Helper method to safely launch a foreground service.
     */
    fun startService(context: Context, serviceClass: Class<*>) {
        try {
            val intent = Intent(context, serviceClass).apply {
                action = "com.kidguard.action.START"
            }
            
            // Android 14+ safe foreground service starter
            context.startForegroundService(intent)
            Log.d(TAG, "Successfully triggered foreground service: ${serviceClass.simpleName}")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting service ${serviceClass.simpleName}: ${e.message}", e)
        }
    }
}
