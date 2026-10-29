package com.kidguard.child.telemetry

import android.util.Log
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.toRadians

data class TelemetryPoint(
    val lat: Double,
    val lon: Double,
    val speed: Float = 0f, // Speed in meters per second
    val timestampMs: Long = System.currentTimeMillis()
)

class TelemetryThrottle(
    private var baseMinDistanceMeters: Float = 50f, // 50m for accurate tracking
    private var baseMinIntervalMs: Long = 2 * 60_000L // 2 minutes interval
) {
    private var lastPoint: TelemetryPoint? = null
    private val tag = "TelemetryThrottle"

    /**
     * Determines whether the new location telemetry point should be uploaded
     * based on distance traveled, time elapsed, or child's movement speed.
     */
    fun shouldUpload(next: TelemetryPoint, forceUpload: Boolean = false): Boolean {
        if (forceUpload) {
            Log.d(tag, "Force upload triggered. Bypassing throttle.")
            lastPoint = next
            return true
        }

        val previous = lastPoint ?: run {
            lastPoint = next
            Log.d(tag, "First telemetry point recorded. Uploading...")
            return true
        }

        val distance = haversineMeters(previous.lat, previous.lon, next.lat, next.lon)
        val elapsed = next.timestampMs - previous.timestampMs

        // Dynamic throttling: If moving fast (e.g., in a vehicle > 5 m/s), reduce interval requirement
        val adjustedMinDistance = if (next.speed > 5f) baseMinDistanceMeters / 2 else baseMinDistanceMeters
        val adjustedMinInterval = if (next.speed > 5f) baseMinIntervalMs / 2 else baseMinIntervalMs

        val shouldUpload = distance >= adjustedMinDistance || elapsed >= adjustedMinInterval

        if (shouldUpload) {
            Log.d(tag, "Throttle passed: Distance=${distance}m, Elapsed=${elapsed}ms. Uploading...")
            lastPoint = next
        } else {
            // Log.v(tag, "Throttled: Distance=${distance}m (min $adjustedMinDistance), Elapsed=${elapsed}ms")
        }

        return shouldUpload
    }

    /**
     * Highly accurate Haversine formula to calculate distance in meters between two GPS coordinates.
     */
    private fun haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val earthRadiusMeters = 6371000.0
        try {
            val dLat = toRadians(lat2 - lat1)
            val dLon = toRadians(lon2 - lon1)
            val originLat = toRadians(lat1)
            val targetLat = toRadians(lat2)

            val a = sin(dLat / 2) * sin(dLat / 2) +
                    cos(originLat) * cos(targetLat) *
                    sin(dLon / 2) * sin(dLon / 2)
            
            val c = 2 * asin(sqrt(a.coerceIn(0.0, 1.0)))
            return earthRadiusMeters * c
        } catch (e: Exception) {
            Log.e(tag, "Error calculating Haversine distance: ${e.message}")
            return 0.0
        }
    }
}
