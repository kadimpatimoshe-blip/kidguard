package com.kidguard.child.service

import android.app.Notification
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.firebase.database.*
import com.kidguard.child.KidGuardApplication
import org.webrtc.*
import java.util.concurrent.Executors

/**
 * WebRTCSignalingService
 * Handles real P2P video/audio streaming between Child and Parent.
 * Monitors Firebase RTDB at devices/{deviceCode}/stream for offers and candidates.
 */
class WebRTCSignalingService : Service() {

    companion object {
        private const val TAG = "KidGuardWebRTC"
        private const val NOTIFICATION_ID = 9005
        const val ACTION_START = "com.kidguard.child.START_WEBRTC"
        const val ACTION_STOP = "com.kidguard.child.STOP_WEBRTC"
        const val EXTRA_TYPE = "type" // "camera" or "screen"
        const val EXTRA_FACING = "facing" // "front" or "back"
    }

    private var peerConnectionFactory: PeerConnectionFactory? = null
    private var peerConnection: PeerConnection? = null
    private var videoCapturer: VideoCapturer? = null
    private var surfaceTextureHelper: SurfaceTextureHelper? = null
    private var videoTrack: VideoTrack? = null
    private var audioTrack: AudioTrack? = null
    
    private val db = FirebaseDatabase.getInstance().reference
    private val executor = Executors.newSingleThreadExecutor()
    private var deviceCode: String = ""
    private var currentType: String = "camera"

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val prefs = getSharedPreferences("kidguard_prefs", Context.MODE_PRIVATE)
        deviceCode = prefs.getString("pairing_code", "") ?: ""
        
        initializePeerConnectionFactory()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP) {
            stopStreaming()
            stopSelf()
            return START_NOT_STICKY
        }

        currentType = intent?.getStringExtra(EXTRA_TYPE) ?: "camera"
        val facing = intent?.getStringExtra(EXTRA_FACING) ?: "back"

        startForegroundService()
        
        if (deviceCode.isNotBlank()) {
            startStreaming(currentType, facing)
        } else {
            Log.e(TAG, "Device code missing. Cannot start WebRTC.")
            stopSelf()
        }

        return START_STICKY
    }

    private fun startForegroundService() {
        val channelId = if (currentType == "camera") KidGuardApplication.CHANNEL_PROTECTION else KidGuardApplication.CHANNEL_MEDIA_PROJECTION
        val title = if (currentType == "camera") "Camera Stream Active" else "Screen Mirroring Active"
        
        val notification = NotificationCompat.Builder(this, channelId)
            .setContentTitle(title)
            .setContentText("Safe connection established with parent console")
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val type = if (currentType == "camera") {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            } else {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            }
            startForeground(NOTIFICATION_ID, notification, type)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun initializePeerConnectionFactory() {
        val options = PeerConnectionFactory.InitializationOptions.builder(this)
            .setEnableInternalTracer(true)
            .createInitializationOptions()
        PeerConnectionFactory.initialize(options)

        val encoderFactory = DefaultVideoEncoderFactory(null, true, true)
        val decoderFactory = DefaultVideoDecoderFactory(null)

        peerConnectionFactory = PeerConnectionFactory.builder()
            .setVideoEncoderFactory(encoderFactory)
            .setVideoDecoderFactory(decoderFactory)
            .createPeerConnectionFactory()
    }

    private fun startStreaming(type: String, facing: String) {
        executor.execute {
            setupPeerConnection()
            if (type == "camera") {
                setupCameraStream(facing)
            } else {
                // Screen share implementation would go here (MediaProjection)
                Log.w(TAG, "Screen share via WebRTC not fully implemented in this module yet.")
            }
            startSignalingListener()
        }
    }

    private fun setupPeerConnection() {
        val iceServers = listOf(
            PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
            PeerConnection.IceServer.builder("stun:stun1.l.google.com:19302").createIceServer()
        )

        val rtcConfig = PeerConnection.RTCConfiguration(iceServers)
        rtcConfig.sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN

        peerConnection = peerConnectionFactory?.createPeerConnection(rtcConfig, object : PeerConnection.Observer {
            override fun onIceCandidate(candidate: IceCandidate) {
                Log.d(TAG, "New Ice Candidate: ${candidate.sdp}")
                uploadIceCandidate(candidate)
            }

            override fun onDataChannel(dc: DataChannel) {}
            override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {
                Log.d(TAG, "Ice Connection State: $state")
            }
            override fun onIceConnectionReceivingChange(b: Boolean) {}
            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {}
            override fun onSignalingChange(state: PeerConnection.SignalingState) {}
            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) {}
            override fun onRemoveStream(stream: MediaStream) {}
            override fun onRenegotiationNeeded() {}
            override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {}
            override fun onAddStream(stream: MediaStream) {}
        })
    }

    private fun setupCameraStream(facing: String) {
        surfaceTextureHelper = SurfaceTextureHelper.create("CaptureThread", null)
        videoCapturer = createVideoCapturer(facing)
        
        val videoSource = peerConnectionFactory?.createVideoSource(false)
        videoCapturer?.initialize(surfaceTextureHelper, this, videoSource?.capturerObserver)
        videoCapturer?.startCapture(1280, 720, 24)

        videoTrack = peerConnectionFactory?.createVideoTrack("VIDEO_TRACK_ID", videoSource)
        peerConnection?.addTrack(videoTrack)

        val audioSource = peerConnectionFactory?.createAudioSource(MediaConstraints())
        audioTrack = peerConnectionFactory?.createAudioTrack("AUDIO_TRACK_ID", audioSource)
        peerConnection?.addTrack(audioTrack)
    }

    private fun createVideoCapturer(facing: String): VideoCapturer? {
        val enumerator = Camera2Enumerator(this)
        val deviceNames = enumerator.deviceNames
        for (deviceName in deviceNames) {
            if (facing == "front" && enumerator.isFrontFacing(deviceName)) {
                return enumerator.createCapturer(deviceName, null)
            } else if (facing == "back" && enumerator.isBackFacing(deviceName)) {
                return enumerator.createCapturer(deviceName, null)
            }
        }
        return enumerator.createCapturer(deviceNames.firstOrNull(), null)
    }

    private fun startSignalingListener() {
        val streamPath = "devices/$deviceCode/stream"
        db.child(streamPath).child("offer").addValueEventListener(object : ValueEventListener {
            override fun onDataChange(snapshot: DataSnapshot) {
                val sdp = snapshot.child("sdp").getValue(String::class.java) ?: return
                val type = snapshot.child("type").getValue(String::class.java) ?: "offer"
                
                if (peerConnection?.signalingState() == PeerConnection.SignalingState.STABLE || 
                    peerConnection?.signalingState() == PeerConnection.SignalingState.HAVE_LOCAL_OFFER) {
                    handleOffer(sdp)
                }
            }
            override fun onCancelled(error: DatabaseError) {}
        })

        db.child(streamPath).child("parentCandidates").addChildEventListener(object : ChildEventListener {
            override fun onChildAdded(snapshot: DataSnapshot, previousChildName: String?) {
                val candidate = snapshot.child("candidate").getValue(String::class.java) ?: return
                val sdpMid = snapshot.child("sdpMid").getValue(String::class.java) ?: ""
                val sdpMLineIndex = snapshot.child("sdpMLineIndex").getValue(Int::class.java) ?: 0
                
                peerConnection?.addIceCandidate(IceCandidate(sdpMid, sdpMLineIndex, candidate))
            }
            override fun onChildChanged(snapshot: DataSnapshot, previousChildName: String?) {}
            override fun onChildRemoved(snapshot: DataSnapshot) {}
            override fun onChildMoved(snapshot: DataSnapshot, previousChildName: String?) {}
            override fun onCancelled(error: DatabaseError) {}
        })
    }

    private fun handleOffer(sdp: String) {
        val remoteDescription = SessionDescription(SessionDescription.Type.OFFER, sdp)
        peerConnection?.setRemoteDescription(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {}
            override fun onSetSuccess() {
                createAnswer()
            }
            override fun onCreateFailure(error: String) {}
            override fun onSetFailure(error: String) {}
        }, remoteDescription)
    }

    private fun createAnswer() {
        val constraints = MediaConstraints()
        peerConnection?.createAnswer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {
                peerConnection?.setLocalDescription(this, sdp)
                uploadAnswer(sdp)
            }
            override fun onSetSuccess() {}
            override fun onCreateFailure(error: String) {}
            override fun onSetFailure(error: String) {}
        }, constraints)
    }

    private fun uploadAnswer(sdp: SessionDescription) {
        val answer = mapOf(
            "type" to "answer",
            "sdp" to sdp.description,
            "timestamp" to System.currentTimeMillis()
        )
        db.child("devices/$deviceCode/stream/answer").setValue(answer)
    }

    private fun uploadIceCandidate(candidate: IceCandidate) {
        val candMap = mapOf(
            "candidate" to candidate.sdp,
            "sdpMid" to candidate.sdpMid,
            "sdpMLineIndex" to candidate.sdpMLineIndex,
            "timestamp" to System.currentTimeMillis()
        )
        db.child("devices/$deviceCode/stream/childCandidates").push().setValue(candMap)
    }

    private fun stopStreaming() {
        videoCapturer?.stopCapture()
        videoCapturer?.dispose()
        surfaceTextureHelper?.dispose()
        peerConnection?.close()
        peerConnectionFactory?.dispose()
        
        // Update status in RTDB
        if (deviceCode.isNotBlank()) {
            db.child("devices/$deviceCode/stream/status").setValue("stopped")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopStreaming()
    }
}
