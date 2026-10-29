package com.kidguard.child.geo

import kotlin.math.*

class GeoFilter {

    /**
     * Calculates great-circle distance in meters between two GPS coordinates using the Haversine formula.
     */
    fun calculateDistanceMeters(
        lat1: Double,
        lon1: Double,
        lat2: Double,
        lon2: Double
    ): Double {
        val earthRadius = 6371000.0 // Earth radius in meters
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2) * sin(dLat / 2) +
                cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
                sin(dLon / 2) * sin(dLon / 2)
        val c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }

    /**
     * Determines whether the movement between two GPS coordinate fixes meets or exceeds the threshold.
     */
    fun isSignificantMove(
        lat1: Double,
        lon1: Double,
        lat2: Double,
        lon2: Double,
        minDistanceMeters: Double = 100.0
    ): Boolean {
        val distance = calculateDistanceMeters(lat1, lon1, lat2, lon2)
        return distance >= minDistanceMeters
    }
}
