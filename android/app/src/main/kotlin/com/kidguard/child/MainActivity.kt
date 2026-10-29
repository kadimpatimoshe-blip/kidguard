package com.kidguard.child

import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.core.content.ContextCompat
import com.kidguard.child.service.AudioCaptureService
import com.kidguard.child.service.LocationForegroundService
import com.kidguard.child.service.MediaProjectionForegroundService
import com.kidguard.child.util.ServiceStarter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity
 * Native Flutter entry point bridging method channels to Android 14 Foreground Services.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL_NAME = "com.kidguard.child/native_services"
        private const val EVENT_CHANNEL_NOTIFICATIONS = "com.kidguard.child/notifications"
    }

    private var notificationEventSink: io.flutter.plugin.common.EventChannel.EventSink? = null
    private val notificationReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context?, intent: android.content.Intent?) {
            if (intent?.action == com.kidguard.child.service.ChildNotificationListenerService.ACTION_NEW_NOTIFICATION) {
                val data = mapOf(
                    "packageName" to intent.getStringExtra("package_name"),
                    "title" to intent.getStringExtra("title"),
                    "text" to intent.getStringExtra("text"),
                    "timestamp" to intent.getLongExtra("timestamp", System.currentTimeMillis())
                )
                notificationEventSink?.success(data)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAll" -> {
                    ServiceStarter.startAll(this)
                    result.success(true)
                }
                "stopAll" -> {
                    stopService(Intent(this, LocationForegroundService::class.java))
                    stopService(Intent(this, AudioCaptureService::class.java))
                    result.success(true)
                }
                "startLocationService" -> {
                    ServiceStarter.startService(this, LocationForegroundService::class.java)
                    result.success(true)
                }
                "stopLocationService" -> {
                    stopService(Intent(this, LocationForegroundService::class.java))
                    result.success(true)
                }
                "startAudioService" -> {
                    ServiceStarter.startService(this, AudioCaptureService::class.java)
                    result.success(true)
                }
                "stopAudioService" -> {
                    stopService(Intent(this, AudioCaptureService::class.java))
                    result.success(true)
                }
                "stopScreenMirrorService" -> {
                    val intent = Intent(this, MediaProjectionForegroundService::class.java).apply {
                        action = MediaProjectionForegroundService.ACTION_STOP_PROJECTION
                    }
                    startService(intent)
                    result.success(true)
                }
                "hasUsagePermission" -> {
                    val collector = com.kidguard.child.usage.UsageStatsCollector(this)
                    result.success(collector.hasPermission())
                }
                "getTopApps" -> {
                    val collector = com.kidguard.child.usage.UsageStatsCollector(this)
                    val limit = call.argument<Int>("limit") ?: 10
                    val days = call.argument<Int>("days") ?: 7
                    val pm = packageManager
                    val stats = collector.getTopApps(limit, days).map { usage ->
                        val appName = try {
                            val appInfo = pm.getApplicationInfo(usage.packageName, 0)
                            pm.getApplicationLabel(appInfo).toString()
                        } catch (e: Exception) {
                            usage.packageName
                        }
                        mapOf(
                            "packageName" to usage.packageName,
                            "appName" to appName,
                            "foregroundTimeMs" to usage.totalTimeInForeground,
                            "lastTimeUsed" to usage.lastTimeUsed
                        )
                    }
                    result.success(stats)
                }
                "getForegroundApp" -> {
                    val collector = com.kidguard.child.usage.UsageStatsCollector(this)
                    result.success(collector.getForegroundAppPackageName())
                }
                else -> result.notImplemented()
            }
        }

        io.flutter.plugin.common.EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL_NOTIFICATIONS).setStreamHandler(
            object : io.flutter.plugin.common.EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: io.flutter.plugin.common.EventChannel.EventSink?) {
                    notificationEventSink = events
                    val filter = android.content.IntentFilter(com.kidguard.child.service.ChildNotificationListenerService.ACTION_NEW_NOTIFICATION)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(notificationReceiver, filter, RECEIVER_EXPORTED)
                    } else {
                        registerReceiver(notificationReceiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    unregisterReceiver(notificationReceiver)
                    notificationEventSink = null
                }
            }
        )
    }
}
