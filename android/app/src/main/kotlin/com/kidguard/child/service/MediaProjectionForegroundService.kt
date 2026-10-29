package com.kidguard.child.service

import android.app.Activity
import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Base64
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import com.google.firebase.database.FirebaseDatabase
import com.kidguard.child.KidGuardApplication
import java.io.ByteArrayOutputStream

/**
 * MediaProjectionForegroundService
 * Android 14 (API 34) Foreground Service for real MediaProjection screen capture.
 * Strictly adheres to Android 14 requirements: starts foreground with type mediaProjection
 * BEFORE obtaining the MediaProjection token.
 */
class MediaProjectionForegroundService : Service() {

    companion object {
        private const val TAG = "KidGuardScreenSvc"
        private const val NOTIFICATION_ID = 9002
        const val ACTION_START_PROJECTION = "com.kidguard.child.ACTION_START_PROJECTION"
        const val ACTION_STOP_PROJECTION = "com.kidguard.child.ACTION_STOP_PROJECTION"
        const val EXTRA_RESULT_CODE = "extra_result_code"
        const val EXTRA_RESULT_DATA = "extra_result_data"
    }

    private var mediaProjectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var handlerThread: HandlerThread? = null
    private var handler: Handler? = null
    private var isStreaming = false
    private var pairingCode: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action

        if (action == ACTION_STOP_PROJECTION) {
            stopProjection()
            stopSelf()
            return START_NOT_STICKY
        }

        // 1. Android 14 Requirement: startForeground with FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION first
        val notification = createNotification("Screen Mirroring Active", "Live screen capture stream active")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        // 2. Obtain projection token using system intent result data
        val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, Activity.RESULT_CANCELED) ?: Activity.RESULT_CANCELED
        val resultData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra(EXTRA_RESULT_DATA)
        }

        if (resultCode == Activity.RESULT_OK && resultData != null) {
            initializeRealMediaProjection(resultCode, resultData)
        } else {
            Log.w(TAG, "MediaProjection permission data missing or denied. Waiting for user consent.")
        }

        return START_NOT_STICKY
    }

    private fun initializeRealMediaProjection(resultCode: Int, data: Intent) {
        try {
            val projection = mediaProjectionManager?.getMediaProjection(resultCode, data)
            if (projection == null) {
                Log.e(TAG, "Failed to get MediaProjection instance.")
                stopSelf()
                return
            }

            mediaProjection = projection
            isStreaming = true

            // Register callback to cleanly stop on external revocation
            mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    super.onStop()
                    Log.i(TAG, "MediaProjection stopped by system.")
                    stopProjection()
                    stopSelf()
                }
            }, null)

            startCaptureLoop()
            Log.i(TAG, "Real MediaProjection successfully established for WebRTC screen stream.")
        } catch (e: Exception) {
            Log.e(TAG, "Exception initializing MediaProjection: ${e.message}", e)
            stopSelf()
        }
    }

    private fun startCaptureLoop() {
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        windowManager.defaultDisplay.getRealMetrics(metrics)
        
        val width = 720
        val height = 1280
        val density = metrics.densityDpi

        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        
        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "KidGuardScreenCapture",
            width, height, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface, null, null
        )

        handlerThread = HandlerThread("ScreenCaptureThread")
        handlerThread?.start()
        handler = Handler(handlerThread!!.looper)

        imageReader?.setOnImageAvailableListener({ reader ->
            if (!isStreaming) return@setOnImageAvailableListener
            
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                val planes = image.planes
                val buffer = planes[0].buffer
                val pixelStride = planes[0].pixelStride
                val rowStride = planes[0].rowStride
                val rowPadding = rowStride - pixelStride * width

                val bitmap = Bitmap.createBitmap(
                    width + rowPadding / pixelStride,
                    height,
                    Bitmap.Config.ARGB_8888
                )
                bitmap.copyPixelsFromBuffer(buffer)
                
                // Crop to actual width if padding exists
                val croppedBitmap = Bitmap.createBitmap(bitmap, 0, 0, width, height)
                
                val outputStream = ByteArrayOutputStream()
                croppedBitmap.compress(Bitmap.CompressFormat.JPEG, 70, outputStream)
                val base64Frame = Base64.encodeToString(outputStream.toByteArray(), Base64.NO_WRAP)
                
                uploadFrameToFirebase(base64Frame)
                
                bitmap.recycle()
                croppedBitmap.recycle()
            } catch (e: Exception) {
                Log.e(TAG, "Frame capture error: ${e.message}")
            } finally {
                image.close()
            }
        }, handler)
    }

    private fun uploadFrameToFirebase(base64Frame: String) {
        if (pairingCode == null) {
            val prefs = getSharedPreferences("kidguard_prefs", Context.MODE_PRIVATE)
            pairingCode = prefs.getString("pairing_code", null)
        }
        
        val code = pairingCode ?: return
        val db = FirebaseDatabase.getInstance()
        val data = mapOf(
            "frame" to "data:image/jpeg;base64,$base64Frame",
            "timestamp" to System.currentTimeMillis(),
            "status" to "streaming"
        )
        db.getReference("devices/$code/screen").updateChildren(data)
    }

    private fun stopProjection() {
        try {
            isStreaming = false
            virtualDisplay?.release()
            virtualDisplay = null
            imageReader?.close()
            imageReader = null
            mediaProjection?.stop()
            mediaProjection = null
            handlerThread?.quitSafely()
            handlerThread = null
            Log.i(TAG, "MediaProjection stopped and released.")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping MediaProjection: ${e.message}")
        }
    }

    private fun createNotification(title: String, text: String): Notification {
        return NotificationCompat.Builder(this, KidGuardApplication.CHANNEL_MEDIA_PROJECTION)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_slideshow)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        stopProjection()
    }
}
