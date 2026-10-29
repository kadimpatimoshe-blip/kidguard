package com.kidguard.child.usage

import android.app.usage.UsageEvents
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Build
import android.util.Log

class UsageStatsCollector(private val context: Context) {
    
    private val tag = "UsageStatsCollector"
    private val usageStatsManager: UsageStatsManager? =
        context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager

    /**
     * Checks if the app has PACKAGE_USAGE_STATS permission granted by the user.
     */
    fun hasPermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? android.app.AppOpsManager ?: return false
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                context.packageName
            )
        }
        return mode == android.app.AppOpsManager.MODE_ALLOWED
    }

    /**
     * Retrieves top used apps over the last 7 days sorted by foreground time.
     */
    fun getTopApps(limit: Int = 10, days: Int = 7): List<UsageStats> {
        val manager = usageStatsManager ?: run {
            Log.w(tag, "UsageStatsManager not available on this device.")
            return emptyList()
        }

        return try {
            val end = System.currentTimeMillis()
            val start = end - days.toLong() * 24 * 60 * 60 * 1000L // 7 days window
            
            val usageStats = manager.queryUsageStats(
                UsageStatsManager.INTERVAL_BEST,
                start,
                end
            ) ?: return emptyList()

            usageStats.filter { it.totalTimeInForeground > 0 }
                .sortedByDescending { it.totalTimeInForeground }
                .take(limit)
        } catch (e: Exception) {
            Log.e(tag, "Error querying usage stats: ${e.message}", e)
            emptyList()
        }
    }

    /**
     * Real-time detection of the currently active foreground application package name.
     * Looks back 15 seconds to reliably catch recent ACTIVITY_RESUMED transitions.
     */
    fun getForegroundAppPackageName(): String? {
        val manager = usageStatsManager ?: return null

        return try {
            val now = System.currentTimeMillis()
            val start = now - 15_000L // Look back 15 seconds
            val usageEvents = manager.queryEvents(start, now) ?: return null

            var currentPackage: String? = null
            val event = UsageEvents.Event()

            while (usageEvents.hasNextEvent()) {
                usageEvents.getNextEvent(event)
                if (event.eventType == UsageEvents.Event.ACTIVITY_RESUMED) {
                    currentPackage = event.packageName
                }
            }
            currentPackage
        } catch (e: Exception) {
            Log.e(tag, "Error querying usage events: ${e.message}", e)
            null
        }
    /**
     * Calculates the total time (in milliseconds) all applications have spent in the foreground today (since midnight).
     */
    fun calculateTotalUsageToday(): Long {
        val manager = usageStatsManager ?: return 0L
        if (!hasPermission()) return 0L

        return try {
            val calendar = java.util.Calendar.getInstance()
            calendar.set(java.util.Calendar.HOUR_OF_DAY, 0)
            calendar.set(java.util.Calendar.MINUTE, 0)
            calendar.set(java.util.Calendar.SECOND, 0)
            calendar.set(java.util.Calendar.MILLISECOND, 0)
            
            val start = calendar.timeInMillis
            val end = System.currentTimeMillis()

            val stats = manager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                start,
                end
            ) ?: return 0L

            stats.filter { it.totalTimeInForeground > 0 }
                .sumOf { it.totalTimeInForeground }
        } catch (e: Exception) {
            Log.e(tag, "Error calculating daily usage: ${e.message}", e)
            0L
        }
    }

    /**
     * Checks if the cumulative foreground time of all apps today exceeds the specified limit.
     */
    fun isDailyLimitExceeded(limitMs: Long): Boolean {
        if (limitMs <= 0) return false
        val totalUsage = calculateTotalUsageToday()
        return totalUsage > limitMs
    }
}
