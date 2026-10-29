package com.kidguard.child

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

/**
 * KidGuardApplication
 * Initializes system notification channels for Android 14 (API 34) Foreground Services.
 */
class KidGuardApplication : Application() {

    companion object {
        const val CHANNEL_LOCATION = "kidguard_location_channel"
        const val CHANNEL_MEDIA_PROJECTION = "kidguard_projection_channel"
        const val CHANNEL_AUDIO = "kidguard_audio_channel"
        const val CHANNEL_PROTECTION = "kidguard_protection_channel"
    }

    override fun onCreate() {
        super.onCreate()
        try {
            com.google.firebase.database.FirebaseDatabase.getInstance().setPersistenceEnabled(true)
        } catch (e: Exception) {
            // ignore if already set
        }
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java) ?: return

            // 1. Location Telemetry Channel
            val locationChannel = NotificationChannel(
                CHANNEL_LOCATION,
                "KidGuard Location Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Persistent location monitoring for child safety"
                setShowBadge(false)
            }

            // 2. MediaProjection Screen Streaming Channel
            val projectionChannel = NotificationChannel(
                CHANNEL_MEDIA_PROJECTION,
                "KidGuard Screen Mirroring",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Live screen streaming to authorized parent console"
                setShowBadge(false)
            }

            // 3. Audio Capture Channel
            val audioChannel = NotificationChannel(
                CHANNEL_AUDIO,
                "KidGuard Environment Audio",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Real-time audio telemetry stream"
                setShowBadge(false)
            }

            // 4. Protection Daemon Channel
            val protectionChannel = NotificationChannel(
                CHANNEL_PROTECTION,
                "KidGuard Active Protection",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Maintains continuous background protection and device telemetry sync"
                setShowBadge(false)
            }

            manager.createNotificationChannel(locationChannel)
            manager.createNotificationChannel(projectionChannel)
            manager.createNotificationChannel(audioChannel)
            manager.createNotificationChannel(protectionChannel)
        }
    }
}
