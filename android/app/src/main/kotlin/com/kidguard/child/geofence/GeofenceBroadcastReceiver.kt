package com.kidguard.child.geofence

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue

class GeofenceBroadcastReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "GeofenceReceiver"
        const val ACTION_GEOFENCE_ALERT = "com.kidguard.child.ACTION_GEOFENCE_ALERT"
        const val EXTRA_FENCE_ID = "fence_id"
        const val EXTRA_TRANSITION = "transition"
        private const val PREFS_NAME = "kidguard_prefs"
        private const val KEY_PAIRING_CODE = "pairing_code"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val geofencingEvent = GeofencingEvent.fromIntent(intent) ?: return

        if (geofencingEvent.hasError()) {
            Log.e(TAG, "Geofencing Error Code: ${geofencingEvent.errorCode}")
            return
        }

        val transition = geofencingEvent.geofenceTransition
        val triggerGeofences = geofencingEvent.triggeringGeofences ?: emptyList()

        val eventType = when (transition) {
            Geofence.GEOFENCE_TRANSITION_ENTER -> "enter"
            Geofence.GEOFENCE_TRANSITION_EXIT -> "exit"
            else -> null
        }

        if (eventType == null) return

        val db = FirebaseDatabase.getInstance().reference
        val deviceCode = getDeviceCode(context)

        for (geofence in triggerGeofences) {
            val zoneId = geofence.requestId
            
            val geoUpdate = mapOf(
                "event" to eventType,
                "timestamp" to ServerValue.TIMESTAMP
            )

            // 1. Update zone state in Firebase RTDB under /devices/{deviceCode}/geo/{zoneId}
            db.child("devices")
                .child(deviceCode)
                .child("geo")
                .child(zoneId)
                .setValue(geoUpdate)
                .addOnSuccessListener {
                    Log.i(TAG, "Geofence $zoneId $eventType logged successfully.")
                }
                .addOnFailureListener { e ->
                    Log.e(TAG, "Failed to log geofence event: ${e.message}")
                }

            // 2. Also append to historical geofence alert log
            db.child("devices")
                .child(deviceCode)
                .child("geofenceAlerts")
                .push()
                .setValue(mapOf(
                    "fenceId" to zoneId,
                    "transition" to eventType,
                    "timestamp" to ServerValue.TIMESTAMP
                ))

            // 3. Dispatch local broadcast for child UI notifications
            broadcastLocalAlert(context, zoneId, eventType, deviceCode)
        }
    }

    private fun broadcastLocalAlert(context: Context, zoneId: String, eventType: String, deviceCode: String) {
        try {
            val broadcast = Intent(ACTION_GEOFENCE_ALERT).apply {
                putExtra(EXTRA_FENCE_ID, zoneId)
                putExtra(EXTRA_TRANSITION, eventType)
                putExtra("pairing_code", deviceCode)
            }
            context.sendBroadcast(broadcast)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to dispatch local geofence broadcast: ${e.message}")
        }
    }

    private fun getDeviceCode(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_PAIRING_CODE, null)?.takeIf { it.isNotBlank() } ?: "DEVICE_ABC123"
    }
}
