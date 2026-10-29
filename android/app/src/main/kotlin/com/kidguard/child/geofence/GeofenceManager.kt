package com.kidguard.child.geofence

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices

class GeofenceManager(private val context: Context) {

    private val geofencingClient = LocationServices.getGeofencingClient(context)
    private val tag = "GeofenceManager"

    @SuppressLint("MissingPermission")
    fun registerZone(zoneId: String, lat: Double, lon: Double, radiusMeters: Float) {
        try {
            val geofence = Geofence.Builder()
                .setRequestId(zoneId)
                .setCircularRegion(lat, lon, radiusMeters)
                .setExpirationDuration(Geofence.NEVER_EXPIRE)
                .setTransitionTypes(
                    Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT
                )
                .build()

            val request = GeofencingRequest.Builder()
                .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                .addGeofence(geofence)
                .build()

            val intent = Intent(context, GeofenceBroadcastReceiver::class.java)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )

            geofencingClient.addGeofences(request, pendingIntent)
                .addOnSuccessListener {
                    Log.i(tag, "Successfully registered geofence zone: $zoneId")
                }
                .addOnFailureListener { e ->
                    Log.e(tag, "Failed to register geofence zone $zoneId: ${e.message}")
                }
        } catch (e: Exception) {
            Log.e(tag, "Error in registerZone: ${e.message}")
        }
    }

    /// Method to remove geofences by a list of zone IDs
    @SuppressLint("MissingPermission")
    fun removeZone(zoneIds: List<String>) {
        geofencingClient.removeGeofences(zoneIds)
            .addOnSuccessListener {
                Log.i(tag, "Successfully removed geofence zones: $zoneIds")
            }
            .addOnFailureListener { e ->
                Log.e(tag, "Failed to remove geofence zones: ${e.message}")
            }
    }

    /// Overload to remove a single geofence zone by ID
    fun removeZone(zoneId: String) {
        removeZone(listOf(zoneId))
    }
}
