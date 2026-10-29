package com.kidguard.child.policy

data class SafeZone(
    val lat: Double = 0.0,
    val lon: Double = 0.0,
    val radiusMeters: Double = 200.0,
    val name: String? = null
)

data class Policy(
    val appLockEnabled: Boolean = false,
    val blockedApps: Map<String, Boolean> = emptyMap(),
    val safeZones: Map<String, SafeZone> = emptyMap(),
    val screenTimeLimitMinutes: Int = 120,
    val locationTrackingIntervalSeconds: Int = 30,
    val webFilterEnabled: Boolean = true,
    val geofenceAlertsEnabled: Boolean = true,
    val keywordAlertsEnabled: Boolean = true,
    val watchKeywords: List<String> = listOf("badword1", "badword2", "suicide", "drugs", "porn"),
    val bedtimeStart: String? = null,
    val bedtimeEnd: String? = null,
    val updatedAt: Long = System.currentTimeMillis()
)
