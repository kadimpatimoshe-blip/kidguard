package com.kidguard.child.service

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.util.Log
import android.view.accessibility.AccessibilityNodeInfo
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.DatabaseReference
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue
import com.google.firebase.database.ValueEventListener
import com.kidguard.child.usage.UsageStatsCollector
import com.kidguard.child.geofence.GeofenceManager

class KidGuardAccessibilityService : AccessibilityService() {

    private val db: DatabaseReference = FirebaseDatabase.getInstance().reference
    private lateinit var usageStatsCollector: UsageStatsCollector
    private lateinit var geofenceManager: GeofenceManager

    // Local cached variables to avoid heavy database reads on every window state change
    private var isAppLockEnabled: Boolean = false
    private var isWebFilterEnabled: Boolean = false
    private var isBedtimeEnabled: Boolean = false
    private var dailyScreenTimeLimitMs: Long = 0 // 0 means no limit
    private var bedtimeStartHour: Int = 22 // Default 10 PM
    private var bedtimeEndHour: Int = 6    // Default 6 AM
    private var blockedAppsList: Set<String> = emptySet()
    private var blockedDomains: Set<String> = setOf("adultsite.com", "badcontent.com", "phishing.net")
    private var policyListener: ValueEventListener? = null

    companion object {
        private const val TAG = "KidGuardAccessibility"
        const val ACTION_APP_BLOCKED = "com.kidguard.child.ACTION_APP_BLOCKED"
        const val EXTRA_BLOCKED_PACKAGE = "blocked_package"
        private const val PREFS_NAME = "kidguard_prefs"
        private const val KEY_PAIRING_CODE = "pairing_code"
        private const val KEY_BLOCKED_APPS = "blocked_packages"
        private const val KEY_BLOCKED_DOMAINS = "blocked_domains"
        private const val KEY_APP_LOCK_ENABLED = "app_lock_enabled"
        private const val KEY_WEB_FILTER_ENABLED = "web_filter_enabled"
        private const val KEY_BEDTIME_ENABLED = "bedtime_enabled"
        private const val KEY_SCREEN_TIME_LIMIT = "screen_time_limit"
        private const val KEY_BEDTIME_START = "bedtime_start"
        private const val KEY_BEDTIME_END = "bedtime_end"
    }

    override fun onCreate() {
        super.onCreate()
        usageStatsCollector = UsageStatsCollector(this)
        geofenceManager = GeofenceManager(this)
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d(TAG, "Accessibility service connected successfully.")
        loadLocalPolicyCache()
        startListeningToPolicy()
    }

    /**
     * Loads locally cached policy as an offline safeguard.
     */
    private fun loadLocalPolicyCache() {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            isAppLockEnabled = prefs.getBoolean(KEY_APP_LOCK_ENABLED, false)
            isWebFilterEnabled = prefs.getBoolean(KEY_WEB_FILTER_ENABLED, false)
            isBedtimeEnabled = prefs.getBoolean(KEY_BEDTIME_ENABLED, false)
            dailyScreenTimeLimitMs = prefs.getLong(KEY_SCREEN_TIME_LIMIT, 0)
            bedtimeStartHour = prefs.getInt(KEY_BEDTIME_START, 22)
            bedtimeEndHour = prefs.getInt(KEY_BEDTIME_END, 6)
            blockedAppsList = prefs.getStringSet(KEY_BLOCKED_APPS, emptySet()) ?: emptySet()
            blockedDomains = prefs.getStringSet(KEY_BLOCKED_DOMAINS, blockedDomains) ?: blockedDomains
        } catch (e: Exception) {
            Log.e(TAG, "Failed loading local policy cache: ${e.message}")
        }
    }

    /**
     * Real-time listener to sync policy and blocked apps from Firebase RTDB efficiently.
     */
    private fun startListeningToPolicy() {
        val deviceCode = getDeviceCode()
        if (deviceCode.isBlank()) return

        policyListener = object : ValueEventListener {
            override fun onDataChange(snapshot: DataSnapshot) {
                try {
                    isAppLockEnabled = snapshot.child("appLockEnabled").getValue(Boolean::class.java) ?: false
                    isWebFilterEnabled = snapshot.child("webFilterEnabled").getValue(Boolean::class.java) ?: false
                    isBedtimeEnabled = snapshot.child("bedtimeEnabled").getValue(Boolean::class.java) ?: false
                    dailyScreenTimeLimitMs = snapshot.child("dailyScreenTimeLimitMs").getValue(Long::class.java) ?: 0L
                    bedtimeStartHour = snapshot.child("bedtimeStartHour").getValue(Int::class.java) ?: 22
                    bedtimeEndHour = snapshot.child("bedtimeEndHour").getValue(Int::class.java) ?: 6
                    
                    // Sync Blocked Apps
                    val blockedSnapshot = snapshot.child("blockedApps")
                    blockedAppsList = parseSet(blockedSnapshot)

                    // Sync Blocked Domains
                    val domainSnapshot = snapshot.child("blockedDomains")
                    if (domainSnapshot.exists()) {
                        blockedDomains = parseSet(domainSnapshot)
                    }

                    // Persist to local cache for offline resiliency
                    getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                        .edit()
                        .putBoolean(KEY_APP_LOCK_ENABLED, isAppLockEnabled)
                        .putBoolean(KEY_WEB_FILTER_ENABLED, isWebFilterEnabled)
                        .putBoolean(KEY_BEDTIME_ENABLED, isBedtimeEnabled)
                        .putLong(KEY_SCREEN_TIME_LIMIT, dailyScreenTimeLimitMs)
                        .putBoolean(KEY_KEYWORD_ALERTS_ENABLED, snapshot.child("keywordAlertsEnabled").getValue(Boolean::class.java) ?: true)
                        .putStringSet(KEY_WATCH_KEYWORDS, parseSet(snapshot.child("watchKeywords")).ifEmpty { setOf("badword1", "badword2", "suicide", "drugs", "porn") })
                        .putInt(KEY_BEDTIME_START, bedtimeStartHour)
                        .putInt(KEY_BEDTIME_END, bedtimeEndHour)
                        .putStringSet(KEY_BLOCKED_APPS, blockedAppsList)
                        .putStringSet(KEY_BLOCKED_DOMAINS, blockedDomains)
                        .apply()
                    
                    // Sync Geofences
                    val safeZonesSnapshot = snapshot.child("safeZones")
                    if (safeZonesSnapshot.exists()) {
                        syncGeofences(safeZonesSnapshot)
                    }
                    
                    Log.d(TAG, "Policy synced: Apps=${blockedAppsList.size}, Bedtime=$bedtimeStartHour-$bedtimeEndHour")
                } catch (e: Exception) {
                    Log.e(TAG, "Error parsing policy update: ${e.message}")
                }
            }

            override fun onCancelled(error: DatabaseError) {
                Log.e(TAG, "Policy sync cancelled: ${error.message}")
            }
        }

        db.child("devices").child(deviceCode).child("policy")
            .addValueEventListener(policyListener!!)

        // Presence & Heartbeat logic
        val presenceRef = db.child("devices").child(deviceCode).child("presence")
        presenceRef.child("online").setValue(true)
        presenceRef.child("online").onDisconnect().setValue(false)
        presenceRef.child("lastSeen").setValue(ServerValue.TIMESTAMP)
        presenceRef.child("lastSeen").onDisconnect().setValue(ServerValue.TIMESTAMP)

        // Listen for remote control commands (startStream, startScreenShare, etc.)
        startListeningToControlCommands()

    private fun startListeningToControlCommands() {
        val deviceCode = getDeviceCode()
        if (deviceCode.isBlank()) return

        db.child("devices").child(deviceCode).child("control")
            .addValueEventListener(object : ValueEventListener {
                override fun onDataChange(snapshot: DataSnapshot) {
                    val command = snapshot.child("command").getValue(String::class.java) ?: return
                    val commandId = snapshot.child("commandId").getValue(String::class.java) ?: ""
                    val acknowledged = snapshot.child("acknowledged").getValue(Boolean::class.java) ?: false

                    if (acknowledged) return // Skip already processed commands

                    Log.i(TAG, "Received Remote Command: $command (ID: $commandId)")

                    when (command) {
                        "startStream" -> {
                            val facing = snapshot.child("cameraFacing").getValue(String::class.java) ?: "back"
                            startWebRTCService("camera", facing)
                        }
                        "startScreenShare" -> {
                            // Screen share usually needs a separate intent for permission result
                            // But for now we try to start the service
                            startWebRTCService("screen")
                        }
                        "stopStream", "stopScreenShare" -> {
                            stopWebRTCService()
                        }
                        "lockDevice" -> {
                            com.kidguard.child.security.DeviceControlManager(this@KidGuardAccessibilityService).lockDevice()
                        }
                    }

                    // Acknowledge the command
                    db.child("devices").child(deviceCode).child("control").child("acknowledged").setValue(true)
                }

                override fun onCancelled(error: DatabaseError) {
                    Log.e(TAG, "Control command listener cancelled: ${error.message}")
                }
            })
    }

    private fun startWebRTCService(type: String, facing: String = "back") {
        val intent = Intent(this, WebRTCSignalingService::class.java).apply {
            action = WebRTCSignalingService.ACTION_START
            putExtra(WebRTCSignalingService.EXTRA_TYPE, type)
            putExtra(WebRTCSignalingService.EXTRA_FACING, facing)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopWebRTCService() {
        val intent = Intent(this, WebRTCSignalingService::class.java).apply {
            action = WebRTCSignalingService.ACTION_STOP
        }
        startService(intent)
    }

    private fun parseSet(snapshot: DataSnapshot): Set<String> {
        val rawMap = snapshot.value as? Map<*, *>
        return if (rawMap != null) {
            rawMap.keys.map { it.toString() }.toSet()
        } else if (snapshot.value is List<*>) {
            (snapshot.value as List<*>).mapNotNull { it?.toString() }.toSet()
        } else {
            emptySet()
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val packageName = event.packageName?.toString() ?: return
        
        // 1. App Blocker & Screen Time Logic
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            handleAppBlocking(packageName)
        }

        // 2. Web Filter Logic (Inspects URL bars and content for browsers)
        if (isWebFilterEnabled && (
            event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED || 
            event.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED)
        ) {
            // Limited to common browser packages to save CPU
            val browsers = listOf("com.android.chrome", "org.mozilla.firefox", "com.microsoft.emmx", "com.opera.browser")
            if (browsers.any { packageName.startsWith(it) }) {
                checkAndBlockUrl(rootInActiveWindow)
            }
        }

        // 3. Keyword / Bad Words Detection (Monitoring Chats/Inputs)
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_KEYWORD_ALERTS_ENABLED, true)) {
            val keywords = prefs.getStringSet(KEY_WATCH_KEYWORDS, emptySet()) ?: emptySet()
            if (keywords.isNotEmpty()) {
                scanForKeywords(rootInActiveWindow, keywords)
            }
        }
    }

    private fun scanForKeywords(node: AccessibilityNodeInfo?, keywords: Set<String>) {
        if (node == null) return
        try {
            val text = (node.text?.toString() ?: node.contentDescription?.toString() ?: "").lowercase()
            if (text.isNotBlank()) {
                for (word in keywords) {
                    if (text.contains(word.lowercase())) {
                        Log.w(TAG, "Keyword Detected: $word in text: $text")
                        reportKeywordMatch(word, text)
                        // We don't return here because we want to scan the whole tree
                    }
                }
            }
            for (i in 0 until node.childCount) {
                scanForKeywords(node.getChild(i), keywords)
            }
        } catch (e: Exception) {}
    }

    private fun reportKeywordMatch(keyword: String, contextText: String) {
        val deviceCode = getDeviceCode()
        val alert = mapOf(
            "type" to "keyword_alert",
            "keyword" to keyword,
            "context" to contextText,
            "timestamp" to com.google.firebase.database.ServerValue.TIMESTAMP
        )
        db.child("devices").child(deviceCode).child("alerts").push().setValue(alert)
    }

    private fun syncGeofences(snapshot: DataSnapshot) {
        val activeZones = mutableListOf<String>()
        for (zoneSnap in snapshot.children) {
            val id = zoneSnap.key ?: continue
            val lat = zoneSnap.child("lat").getValue(Double::class.java) ?: continue
            val lon = zoneSnap.child("lon").getValue(Double::class.java) ?: continue
            val radius = zoneSnap.child("radiusMeters").getValue(Float::class.java) ?: 200f
            
            geofenceManager.registerZone(id, lat, lon, radius)
            activeZones.add(id)
        }
        // Ideally we would remove old zones not in activeZones, 
        // but GeofenceManager.registerZone overwrites by ID.
    }

    private fun handleAppBlocking(packageName: String) {
        if (packageName.isBlank()) return
        
        // NEVER block essential system components or our own app
        if (packageName == this.packageName || 
            packageName.contains("launcher") || 
            packageName.contains("systemui") ||
            packageName == "android" ||
            packageName == "com.google.android.packageinstaller" ||
            packageName == "com.android.settings") {
            return
        }

        // Check 1: Manual App Lock
        if (isAppLockEnabled && blockedAppsList.contains(packageName)) {
            Log.w(TAG, "App Locked: $packageName. Redirecting to home.")
            launchHomeScreen()
            broadcastBlockedEvent(packageName, "app_lock")
            return
        }

        // Check 2: Daily Screen Time Limit
        if (dailyScreenTimeLimitMs > 0) {
            if (usageStatsCollector.isDailyLimitExceeded(dailyScreenTimeLimitMs)) {
                Log.w(TAG, "Screen Time Limit Exceeded. Blocking $packageName.")
                launchHomeScreen()
                broadcastBlockedEvent(packageName, "screen_time_limit")
                return
            }
        }

        // Check 3: Bedtime Mode (FlashGet Kids feature parity)
        if (isBedtimeEnabled && isBedtimeActive()) {
            Log.w(TAG, "Bedtime Active. Blocking $packageName.")
            launchHomeScreen()
            broadcastBlockedEvent(packageName, "bedtime")
        }
    }

    /**
     * Checks if current time is within the bedtime range.
     */
    private fun isBedtimeActive(): Boolean {
        val calendar = java.util.Calendar.getInstance()
        val currentHour = calendar.get(java.util.Calendar.HOUR_OF_DAY)
        val currentMinute = calendar.get(java.util.Calendar.MINUTE)
        val currentTimeInMinutes = currentHour * 60 + currentMinute

        val startMinutes = bedtimeStartHour * 60
        val endMinutes = bedtimeEndHour * 60

        return if (startMinutes > endMinutes) {
            // Overlap midnight (e.g., 10 PM to 6 AM)
            currentTimeInMinutes >= startMinutes || currentTimeInMinutes <= endMinutes
        } else {
            // Same day (e.g., 1 PM to 3 PM)
            currentTimeInMinutes in startMinutes..endMinutes
        }
    }

    /**
     * Inspects accessibility nodes recursively to find and block restricted URLs.
     */
    private fun checkAndBlockUrl(node: AccessibilityNodeInfo?) {
        if (node == null) return
        
        try {
            // Check text or description for blocked keywords/domains
            val text = (node.text?.toString() ?: node.contentDescription?.toString() ?: "").lowercase()
            
            if (text.isNotBlank()) {
                for (domain in blockedDomains) {
                    if (text.contains(domain)) {
                        Log.w(TAG, "Web Filter: Blocked domain detected ($text). Blocking access.")
                        launchHomeScreen()
                        broadcastBlockedEvent("browser", "web_filter")
                        return
                    }
                }
            }

            // Recurse children
            for (i in 0 until node.childCount) {
                checkAndBlockUrl(node.getChild(i))
            }
        } catch (e: Exception) {
            // Ignore node state exceptions
        }
    }

    private fun broadcastBlockedEvent(packageName: String, reason: String) {
        try {
            val broadcast = Intent(ACTION_APP_BLOCKED).apply {
                putExtra(EXTRA_BLOCKED_PACKAGE, packageName)
                putExtra("reason", reason)
            }
            sendBroadcast(broadcast)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to broadcast app blocked event: ${e.message}")
        }
    }

    override fun onInterrupt() {
        Log.d(TAG, "Accessibility service interrupted.")
    }

    override fun onDestroy() {
        super.onDestroy()
        policyListener?.let {
            val deviceCode = getDeviceCode()
            if (deviceCode.isNotBlank()) {
                db.child("devices").child(deviceCode).child("policy").removeEventListener(it)
            }
        }
    }

    private fun launchHomeScreen() {
        try {
            val intent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch home screen: ${e.message}")
        }
    }

    private fun getDeviceCode(): String {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_PAIRING_CODE, null)?.takeIf { it.isNotBlank() } ?: "DEVICE_ABC123"
    }
}
