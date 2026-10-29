package com.kidguard.child.service

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
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue
import com.kidguard.child.telemetry.TelemetryPoint
import com.kidguard.child.telemetry.TelemetryThrottle

class LocationForegroundService : Service() {

    private val channelId = "kidguard_location_channel"
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private lateinit var locationRequest: LocationRequest
    private var locationCallback: LocationCallback? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val telemetryThrottle = TelemetryThrottle()

    companion object {
        private const val TAG = "LocationForegroundService"
        private const val NOTIFICATION_ID = 101
        private const val PREFS_NAME = "kidguard_prefs"
        private const val KEY_PAIRING_CODE = "pairing_code"
        const val ACTION_LOCATION_UPDATE = "com.kidguard.child.ACTION_LOCATION_UPDATE"
        const val EXTRA_LATITUDE = "latitude"
        const val EXTRA_LONGITUDE = "longitude"
        const val EXTRA_SPEED = "speed"
        const val EXTRA_ACCURACY = "accuracy"
    }

    override fun onCreate() {
        super.onCreate()
        acquireWakeLock()
        createNotificationChannel()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        startLocationUpdates()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Save pairing code if passed in intent
        intent?.getStringExtra(KEY_PAIRING_CODE)?.let { code ->
            if (code.isNotBlank()) {
                getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putString(KEY_PAIRING_CODE, code)
                    .apply()
            }
        }

        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        Log.i(TAG, "LocationForegroundService started successfully.")
        return START_STICKY
    }

    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "KidGuard::LocationWakeLock"
            ).apply {
                acquire(10 * 60 * 1000L) // 10 minutes timeout safeguard
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire WakeLock: ${e.message}", e)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Family Safety Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Runs background location monitoring for child safety"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("KidGuard Protection")
            .setContentText("Active safety monitoring in progress")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    private fun startLocationUpdates() {
        try {
            locationRequest = LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, 30_000L)
                .setMinUpdateDistanceMeters(15f) // Update if moved by 15 meters
                .setMinUpdateDelayMillis(15_000L)
                .build()

            locationCallback = object : LocationCallback() {
                override fun onLocationResult(locationResult: LocationResult) {
                    for (location in locationResult.locations) {
                        val point = TelemetryPoint(
                            lat = location.latitude,
                            lon = location.longitude,
                            speed = location.speed,
                            timestampMs = location.time
                        )
                        if (telemetryThrottle.shouldUpload(point)) {
                            uploadLocationToFirebase(location.latitude, location.longitude, location.speed, location.accuracy)
                        }
                        broadcastLocation(location.latitude, location.longitude, location.speed, location.accuracy)
                    }
                }
            }

            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback!!,
                mainLooper
            )
        } catch (e: SecurityException) {
            Log.e(TAG, "Location permission missing: ${e.message}", e)
        } catch (e: Exception) {
            Log.e(TAG, "Error starting location updates: ${e.message}", e)
        }
    }

    private fun getStoredPairingCode(): String {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_PAIRING_CODE, null)?.takeIf { it.isNotBlank() } ?: "DEFAULT_PAIRING_CODE"
    }

    private fun uploadLocationToFirebase(lat: Double, lon: Double, speed: Float, accuracy: Float) {
        try {
            val pairingCode = getStoredPairingCode()
            
            val locationData = mapOf(
                "latitude" to lat,
                "longitude" to lon,
                "speed" to speed,
                "accuracy" to accuracy,
                "timestamp" to ServerValue.TIMESTAMP
            )

            val db = FirebaseDatabase.getInstance()
            
            // 1. Update current location for live view
            db.getReference("devices/$pairingCode/location").setValue(locationData)
            
            // 2. Append to location history for path tracking (FlashGet Kids feature parity)
            db.getReference("devices/$pairingCode/locationHistory").push().setValue(locationData)
            
            Log.d(TAG, "Location & History synced to Firebase for $pairingCode")
        } catch (e: Exception) {
            Log.e(TAG, "Firebase upload error: ${e.message}", e)
        }
    }

    private fun broadcastLocation(lat: Double, lon: Double, speed: Float, accuracy: Float) {
        try {
            val broadcast = Intent(ACTION_LOCATION_UPDATE).apply {
                putExtra(EXTRA_LATITUDE, lat)
                putExtra(EXTRA_LONGITUDE, lon)
                putExtra(EXTRA_SPEED, speed.toDouble())
                putExtra(EXTRA_ACCURACY, accuracy.toDouble())
                putExtra("pairing_code", getStoredPairingCode())
            }
            sendBroadcast(broadcast)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send local location broadcast: ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            locationCallback?.let { fusedLocationClient.removeLocationUpdates(it) }
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error during service destruction: ${e.message}", e)
        }

        // Anti-kill auto restart mechanism
        try {
            val restartIntent = Intent(this, LocationForegroundService::class.java).apply {
                action = "com.kidguard.action.START"
            }
            startForegroundService(restartIntent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to restart service from onDestroy: ${e.message}", e)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
