package com.example.kidguard

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val monitoringChannel = "com.kidguard/monitoring"
    private val callLogPermissionRequestCode = 4017
    private var callLogPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, monitoringChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestCallLogPermission" -> requestCallLogPermission(result)

                    "setCallLogSyncEnabled" -> {
                        val enabled = (call.arguments as? Map<*, *>)?.get("enabled")
                            as? Boolean
                        if (enabled == null) {
                            result.error(
                                "invalid_configuration",
                                "Call log sync state must be specified.",
                                null,
                            )
                        } else {
                            setCallLogSyncEnabled(enabled, result)
                        }
                    }

                    "configureNotificationSync" -> {
                        val arguments = call.arguments as? Map<*, *>
                        val deviceId = arguments?.get("deviceId") as? String
                        val parentUid = arguments?.get("parentUid") as? String
                        val childId = arguments?.get("childId") as? String
                        if (deviceId.isNullOrBlank() ||
                            parentUid.isNullOrBlank() ||
                            childId.isNullOrBlank()
                        ) {
                            result.error(
                                "invalid_configuration",
                                "Paired device identifiers are required.",
                                null,
                            )
                        } else {
                            getSharedPreferences(
                                KidGuardNotificationListenerService.PREFERENCES,
                                MODE_PRIVATE,
                            ).edit()
                                .putString("deviceId", deviceId)
                                .putString("parentUid", parentUid)
                                .putString("childId", childId)
                                .apply()
                            result.success(null)
                        }
                    }

                    "hasNotificationAccess" -> result.success(hasNotificationAccess())

                    "openNotificationAccessSettings" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS),
                            )
                            result.success(null)
                        } catch (error: Exception) {
                            result.error(
                                "settings_unavailable",
                                "Could not open notification access settings: ${error.message}",
                                null,
                            )
                        }
                    }

                    "startScreenProjectionService" -> {
                        try {
                            val serviceIntent = Intent(
                                this,
                                ScreenProjectionForegroundService::class.java,
                            )
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(serviceIntent)
                            } else {
                                startService(serviceIntent)
                            }
                            result.success(null)
                        } catch (error: Exception) {
                            result.error(
                                "projection_service_failed",
                                "Could not start the visible screen-sharing service: ${error.message}",
                                null,
                            )
                        }
                    }

                    "stopScreenProjectionService" -> {
                        try {
                            stopService(
                                Intent(
                                    this,
                                    ScreenProjectionForegroundService::class.java,
                                ),
                            )
                            result.success(null)
                        } catch (error: Exception) {
                            result.error(
                                "projection_service_stop_failed",
                                "Could not stop the screen-sharing service: ${error.message}",
                                null,
                            )
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun requestCallLogPermission(result: MethodChannel.Result) {
        if (hasCallLogPermission()) {
            result.success(true)
            return
        }
        if (callLogPermissionResult != null) {
            result.error(
                "permission_request_in_progress",
                "A call log permission request is already in progress.",
                null,
            )
            return
        }
        callLogPermissionResult = result
        requestPermissions(
            arrayOf(android.Manifest.permission.READ_CALL_LOG),
            callLogPermissionRequestCode,
        )
    }

    private fun setCallLogSyncEnabled(
        enabled: Boolean,
        result: MethodChannel.Result,
    ) {
        val preferences = getSharedPreferences(
            KidGuardNotificationListenerService.PREFERENCES,
            MODE_PRIVATE,
        )
        if (!enabled) {
            if (preferences.getBoolean("callLogsEnabled", false)) {
                preferences.edit()
                    .putLong(
                        CallLogSyncScheduler.LAST_SYNCED_CALL_DATE,
                        System.currentTimeMillis(),
                    )
                    .apply()
            }
            preferences.edit().putBoolean("callLogsEnabled", false).apply()
            CallLogSyncScheduler.cancel(this)
            result.success(null)
            return
        }
        preferences.edit().putBoolean("callLogsEnabled", true).apply()
        if (!hasCallLogPermission()) {
            preferences.edit().putBoolean("callLogsEnabled", false).apply()
            result.error(
                "call_log_permission_denied",
                "Call log access must be granted before syncing can start.",
                null,
            )
            return
        }
        if (CallLogSyncScheduler.schedule(this)) {
            result.success(null)
        } else {
            preferences.edit().putBoolean("callLogsEnabled", false).apply()
            result.error(
                "call_log_service_failed",
                "Could not schedule read-only call history syncing.",
                null,
            )
        }
    }

    private fun hasCallLogPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(android.Manifest.permission.READ_CALL_LOG) ==
            PackageManager.PERMISSION_GRANTED
    }

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != callLogPermissionRequestCode) return
        val result = callLogPermissionResult ?: return
        callLogPermissionResult = null
        result.success(
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
        )
    }

    private fun hasNotificationAccess(): Boolean {
        val enabledListeners =
            Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
                ?: return false
        val componentName = android.content.ComponentName(
            this,
            KidGuardNotificationListenerService::class.java,
        )
        return TextUtils.SimpleStringSplitter(':').run {
            setString(enabledListeners)
            any { android.content.ComponentName.unflattenFromString(it) == componentName }
        }
    }
}
