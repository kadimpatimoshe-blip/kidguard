package com.example.kidguard

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.ContentResolver
import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.CallLog
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.database.DatabaseReference
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue
import java.util.concurrent.Executors

object CallLogSyncScheduler {
    const val LAST_SYNCED_CALL_DATE = "lastSyncedCallDate"
    private const val JOB_ID = 8315
    private const val SYNC_INTERVAL_MS = 15 * 60 * 1000L

    fun schedule(context: Context): Boolean {
        val scheduler =
            context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
                ?: return false
        val job = JobInfo.Builder(
            JOB_ID,
            ComponentName(context, CallLogSyncService::class.java),
        )
            .setPersisted(true)
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setPeriodic(SYNC_INTERVAL_MS)
            .build()
        return scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS
    }

    fun cancel(context: Context) {
        (context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler)
            ?.cancel(JOB_ID)
    }
}

class CallLogSyncService : JobService() {
    companion object {
        private const val TAG = "KidGuardCallLogs"
        private const val DATABASE_URL =
            "https://kidguard-3b499-default-rtdb.asia-southeast1.firebasedatabase.app"
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var activeJob: JobParameters? = null

    override fun onStartJob(parameters: JobParameters): Boolean {
        val preferences = getSharedPreferences(
            KidGuardNotificationListenerService.PREFERENCES,
            MODE_PRIVATE,
        )
        if (!preferences.getBoolean("callLogsEnabled", false)) return false
        if (!hasCallLogPermission()) {
            Log.w(TAG, "Call log permission was revoked; syncing has stopped.")
            preferences.edit()
                .putBoolean("callLogsEnabled", false)
                .putLong(
                    CallLogSyncScheduler.LAST_SYNCED_CALL_DATE,
                    System.currentTimeMillis(),
                )
                .apply()
            CallLogSyncScheduler.cancel(this)
            return false
        }

        activeJob = parameters
        try {
            val app = getOrInitializeFirebaseApp()
            val childUid = FirebaseAuth.getInstance(app).currentUser?.uid
            val parentUid = preferences.getString("parentUid", null)
            val childId = preferences.getString("childId", null)
            val deviceId = preferences.getString("deviceId", null)
            if (childUid == null || parentUid.isNullOrBlank() ||
                childId.isNullOrBlank() || deviceId.isNullOrBlank()
            ) {
                Log.e(TAG, "Paired child and authentication details are unavailable.")
                finishJob(parameters, retry = true)
                return true
            }

            val childReference = FirebaseDatabase.getInstance(app, DATABASE_URL)
                .reference
                .child("parents")
                .child(parentUid)
                .child("children")
                .child(childId)
            childReference.get()
                .addOnSuccessListener { snapshot ->
                    if (!isActive(parameters)) return@addOnSuccessListener
                    if (snapshot.child("status").getValue(String::class.java) != "paired" ||
                        snapshot.child("childUid").getValue(String::class.java) != childUid ||
                        snapshot.child("deviceId").getValue(String::class.java) != deviceId
                    ) {
                        disableSyncForUnpairedDevice(parameters, preferences)
                        return@addOnSuccessListener
                    }
                    executor.execute {
                        uploadNewCalls(parameters, childReference, preferences)
                    }
                }
                .addOnFailureListener { error ->
                    Log.e(TAG, "Could not verify the paired child device.", error)
                    finishJob(parameters, retry = true)
                }
        } catch (error: Exception) {
            Log.e(TAG, "Could not initialize call log syncing.", error)
            finishJob(parameters, retry = true)
        }
        return true
    }

    override fun onStopJob(parameters: JobParameters): Boolean {
        if (activeJob === parameters) activeJob = null
        return true
    }

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun uploadNewCalls(
        parameters: JobParameters,
        childReference: DatabaseReference,
        preferences: android.content.SharedPreferences,
    ) {
        try {
            val lastSyncedDate = preferences.getLong(
                CallLogSyncScheduler.LAST_SYNCED_CALL_DATE,
                System.currentTimeMillis() - 30L * 24 * 60 * 60 * 1000,
            )
            val records = queryCallLogs(contentResolver, lastSyncedDate)
            if (!isActive(parameters)) return
            if (records.isEmpty()) {
                finishJob(parameters, retry = false)
                return
            }

            val updates = records.associate { record ->
                "${record.date}_${record.id}" to record.toFirebaseValue()
            }
            childReference.child("callLogs").updateChildren(updates)
                .addOnSuccessListener {
                    val newestCallDate = records.maxOf { it.date }
                    preferences.edit()
                        .putLong(
                            CallLogSyncScheduler.LAST_SYNCED_CALL_DATE,
                            newestCallDate,
                        )
                        .apply()
                    finishJob(parameters, retry = false)
                }
                .addOnFailureListener { error ->
                    Log.e(TAG, "Could not upload call history.", error)
                    finishJob(parameters, retry = true)
                }
        } catch (error: Exception) {
            Log.e(TAG, "Could not read the device call history.", error)
            finishJob(parameters, retry = true)
        }
    }

    private fun queryCallLogs(
        resolver: ContentResolver,
        fromDate: Long,
    ): List<CallLogRecord> {
        val columns = arrayOf(
            CallLog.Calls._ID,
            CallLog.Calls.NUMBER,
            CallLog.Calls.CACHED_NAME,
            CallLog.Calls.TYPE,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION,
        )
        val records = mutableListOf<CallLogRecord>()
        val cursor = resolver.query(
            CallLog.Calls.CONTENT_URI,
            columns,
            "${CallLog.Calls.DATE} >= ?",
            arrayOf(fromDate.toString()),
            "${CallLog.Calls.DATE} ASC",
        ) ?: throw IllegalStateException("Android returned no call history cursor.")
        cursor.use {
            while (it.moveToNext()) {
                records.add(it.toRecord())
            }
        }
        return records
    }

    private fun Cursor.toRecord(): CallLogRecord {
        return CallLogRecord(
            id = getString(getColumnIndexOrThrow(CallLog.Calls._ID)),
            number = getString(getColumnIndexOrThrow(CallLog.Calls.NUMBER)),
            name = getString(getColumnIndexOrThrow(CallLog.Calls.CACHED_NAME)),
            type = when (getInt(getColumnIndexOrThrow(CallLog.Calls.TYPE))) {
                1 -> "incoming"
                2 -> "outgoing"
                3 -> "missed"
                4 -> "voicemail"
                5 -> "rejected"
                6 -> "blocked"
                7 -> "answered_externally"
                8 -> "screened"
                else -> "unknown"
            },
            date = getLong(getColumnIndexOrThrow(CallLog.Calls.DATE)),
            duration = getLong(getColumnIndexOrThrow(CallLog.Calls.DURATION)),
        )
    }

    private fun CallLogRecord.toFirebaseValue(): Map<String, Any> {
        val fields = mutableMapOf<String, Any>(
            "type" to type,
            "timestamp" to date,
            "durationSeconds" to duration,
            "syncedAt" to ServerValue.TIMESTAMP,
        )
        number?.let { fields["number"] = it }
        name?.let { fields["name"] = it }
        return fields
    }

    private fun disableSyncForUnpairedDevice(
        parameters: JobParameters,
        preferences: android.content.SharedPreferences,
    ) {
        preferences.edit()
            .putBoolean("callLogsEnabled", false)
            .putLong(
                CallLogSyncScheduler.LAST_SYNCED_CALL_DATE,
                System.currentTimeMillis(),
            )
            .apply()
        CallLogSyncScheduler.cancel(this)
        finishJob(parameters, retry = false)
    }

    private fun finishJob(parameters: JobParameters, retry: Boolean) {
        mainHandler.post {
            if (activeJob !== parameters) return@post
            activeJob = null
            jobFinished(parameters, retry)
        }
    }

    private fun isActive(parameters: JobParameters): Boolean {
        return activeJob === parameters
    }

    private fun hasCallLogPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(android.Manifest.permission.READ_CALL_LOG) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun getOrInitializeFirebaseApp(): FirebaseApp {
        FirebaseApp.getApps(this).firstOrNull()?.let { return it }
        val options = FirebaseOptions.Builder()
            .setApplicationId("1:897177192961:android:205829551a9fac30938e00")
            .setApiKey("AIzaSyCn_0mbkQNSlOIvUA3Tv9QKFn8skyZL0vg")
            .setProjectId("kidguard-3b499")
            .setGcmSenderId("897177192961")
            .setDatabaseUrl(DATABASE_URL)
            .setStorageBucket("kidguard-3b499.firebasestorage.app")
            .build()
        return FirebaseApp.initializeApp(this, options)
            ?: error("Firebase could not initialize call log syncing.")
    }

    private data class CallLogRecord(
        val id: String,
        val number: String?,
        val name: String?,
        val type: String,
        val date: Long,
        val duration: Long,
    )
}
