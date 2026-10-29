import React, { useEffect, useRef, useState, useCallback } from 'react';
import { 
  ArrowLeft, 
  Volume2, 
  VolumeX, 
  Maximize2, 
  Minimize2, 
  Radio, 
  RefreshCw,
  Video,
  Loader2,
  Play,
  RotateCcw,
  CheckCircle2,
  Copy,
  Link,
  ShieldAlert
} from 'lucide-react';
import { ParentChildDevice } from '../types';
import { 
  startParentWebRTCSession, 
  WebRTCSignalingSession,
  subscribeToChildPairingCodeValidity,
  regenerateChildPairingCode
} from '../services/webrtc';
import { sendRemoteCommand, claimPairingCode } from '../services/firebase';

interface LiveCameraModalProps {
  device: ParentChildDevice;
  parentUid: string;
  onClose: () => void;
  onRelink?: (newPairingCode: string) => void;
}

export const LiveCameraModal: React.FC<LiveCameraModalProps> = ({
  device,
  parentUid,
  onClose,
  onRelink,
}) => {
  const videoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const sessionRef = useRef<WebRTCSignalingSession | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const hasReceivedStreamRef = useRef(false);

  const modelName = device.deviceModelName || device.telemetry?.deviceModelName || `Device ${device.childId.slice(0, 8)}`;
  const deviceId = device.deviceId || device.childId;
  const initialPairingCode = (device.pairingCode || device.childId?.replace('child_', '') || device.deviceId?.replace('dev_', '') || '').trim();

  const [activePairingCode, setActivePairingCode] = useState(initialPairingCode);
  const [regeneratedCode, setRegeneratedCode] = useState<string | null>(null);
  const [isRelinking, setIsRelinking] = useState(false);
  const [copiedCode, setCopiedCode] = useState(false);

  const [cameraFacing, setCameraFacing] = useState<'front' | 'back'>('front');
  const [isMuted, setIsMuted] = useState(true);
  const [volume, setVolume] = useState(0.8);
  const [connectionState, setConnectionState] = useState<'connecting' | 'connected' | 'reconnecting' | 'fallback' | 'error'>('connecting');
  const [statusMessage, setStatusMessage] = useState('Initiating WebRTC signaling via Firebase RTDB…');
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [streamSource, setStreamSource] = useState<'live' | 'none'>('none');
  
  const [waitingForStream, setWaitingForStream] = useState(false);
  const [retryCount, setRetryCount] = useState(0);
  const [autoplayBlocked, setAutoplayBlocked] = useState(false);
  const [isVideoPlaying, setIsVideoPlaying] = useState(false);
  const [streamStats, setStreamStats] = useState<{ width?: number; height?: number; fps?: number } | null>(null);

  const attachStreamToVideo = useCallback((mediaStream: MediaStream) => {
    streamRef.current = mediaStream;
    hasReceivedStreamRef.current = true;
    setStreamSource('live');
    setConnectionState('connected');
    setWaitingForStream(false);

    if (videoRef.current) {
      videoRef.current.srcObject = mediaStream;
      videoRef.current.muted = isMuted;
      videoRef.current
        .play()
        .then(() => {
          setIsVideoPlaying(true);
          setAutoplayBlocked(false);
          const videoTrack = mediaStream.getVideoTracks()[0];
          if (videoTrack) {
            const settings = videoTrack.getSettings ? videoTrack.getSettings() : {};
            setStreamStats({
              width: settings.width || 1280,
              height: settings.height || 720,
              fps: Math.round(settings.frameRate || 30),
            });
          }
        })
        .catch((err) => {
          console.warn('HTML5 Video auto-play blocked by browser:', err);
          setAutoplayBlocked(true);
        });
    }
  }, [isMuted]);

  useEffect(() => {
    if (!activePairingCode) return;

    const unsubscribe = subscribeToChildPairingCodeValidity(
      activePairingCode,
      deviceId,
      device.childId,
      (result) => {
        if (!result.isValid && result.isRegenerated && result.newPairingCode) {
          const newCode = result.newPairingCode;
          setRegeneratedCode(newCode);
          setStatusMessage(`Child device regenerated code to ${newCode}`);
          setConnectionState('fallback');
        }
      }
    );

    return () => {
      unsubscribe();
    };
  }, [activePairingCode, deviceId, device.childId]);

  const initWebRTCSession = useCallback(async (codeToUse: string) => {
    try {
      if (sessionRef.current) {
        sessionRef.current.cleanup();
        sessionRef.current = null;
      }

      setConnectionState('connecting');
      setStatusMessage(`Signaling /devices/${codeToUse}/stream over Firebase RTDB…`);
      setWaitingForStream(false);
      hasReceivedStreamRef.current = false;
      setIsVideoPlaying(false);

      const session = await startParentWebRTCSession(
        codeToUse,
        parentUid,
        device.childId,
        {
          pairingCode: codeToUse,
          cameraFacing,
          onStream: (mediaStream) => {
            attachStreamToVideo(mediaStream);
          },
          onStatusChange: (status) => {
            setStatusMessage(status);
          },
          onConnectionStateChange: (state) => {
            if (state === 'connected') {
              setConnectionState('connected');
              setWaitingForStream(false);
            } else if (state === 'failed' || state === 'disconnected') {
              setConnectionState('error');
            }
          },
          onError: (err) => {
            console.warn('WebRTC peer error:', err);
            setConnectionState('error');
            setStatusMessage(`Stream connection issue: ${err.message || 'Waiting for child device'}`);
          },
          onPairingCodeInvalidated: (newCode) => {
            if (newCode) {
              setRegeneratedCode(newCode);
              setConnectionState('fallback');
            }
          },
        }
      );

      sessionRef.current = session;
    } catch (err: any) {
      console.warn('Failed initializing WebRTC session:', err);
      setConnectionState('error');
      setStatusMessage('Waiting for child camera hardware stream…');
    }
  }, [cameraFacing, device.childId, parentUid, attachStreamToVideo]);

  useEffect(() => {
    initWebRTCSession(activePairingCode);

    return () => {
      if (sessionRef.current) {
        sessionRef.current.cleanup();
        sessionRef.current = null;
      }
      if (streamRef.current) {
        streamRef.current.getTracks().forEach((track) => track.stop());
        streamRef.current = null;
      }
    };
  }, [activePairingCode, initWebRTCSession]);

  useEffect(() => {
    if (streamSource === 'live' || regeneratedCode) {
      setWaitingForStream(false);
      return;
    }

    const timer = setTimeout(() => {
      if (!hasReceivedStreamRef.current && streamSource === 'none') {
        setWaitingForStream(true);
        setRetryCount((prev) => prev + 1);
      }
    }, 4000);

    return () => clearTimeout(timer);
  }, [retryCount, streamSource, regeneratedCode]);

  const handleManualReinitialize = async () => {
    setWaitingForStream(false);
    setConnectionState('reconnecting');
    setStatusMessage('Re-dispatching WebRTC signaling offer…');
    await initWebRTCSession(activePairingCode);
  };

  const handleRelinkNewCode = async () => {
    if (!regeneratedCode) return;
    setIsRelinking(true);
    try {
      await claimPairingCode(parentUid, regeneratedCode, modelName);
      setActivePairingCode(regeneratedCode);
      setRegeneratedCode(null);
      if (onRelink) {
        onRelink(regeneratedCode);
      }
      await initWebRTCSession(regeneratedCode);
    } catch (err) {
      console.warn('Relink error:', err);
    } finally {
      setIsRelinking(false);
    }
  };

  const handleSwitchCameraLens = async () => {
    const nextFacing = cameraFacing === 'front' ? 'back' : 'front';
    setCameraFacing(nextFacing);
    setStatusMessage(`Requesting child device switch to ${nextFacing} camera…`);

    if (sessionRef.current) {
      await sessionRef.current.switchCamera(nextFacing);
    } else {
      await sendRemoteCommand(deviceId, parentUid, device.childId, 'switchCamera', {
        cameraFacing: nextFacing,
      });
    }
  };

  const toggleMute = () => {
    const nextMuted = !isMuted;
    setIsMuted(nextMuted);
    if (videoRef.current) {
      videoRef.current.muted = nextMuted;
    }
  };

  const handleVolumeChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = parseFloat(e.target.value);
    setVolume(val);
    if (videoRef.current) {
      videoRef.current.volume = val;
      if (val === 0) {
        setIsMuted(true);
        videoRef.current.muted = true;
      } else if (isMuted) {
        setIsMuted(false);
        videoRef.current.muted = false;
      }
    }
  };

  const toggleFullscreen = () => {
    if (!containerRef.current) return;
    if (!document.fullscreenElement) {
      containerRef.current.requestFullscreen().catch(() => {});
      setIsFullscreen(true);
    } else {
      document.exitFullscreen().catch(() => {});
      setIsFullscreen(false);
    }
  };

  const handleManualVideoPlay = () => {
    if (videoRef.current) {
      videoRef.current.play().then(() => {
        setIsVideoPlaying(true);
        setAutoplayBlocked(false);
      }).catch((e) => console.warn('Play attempt failed:', e));
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-[#0c1613]/95 backdrop-blur-md flex flex-col justify-between overflow-hidden animate-in fade-in duration-200">
      {/* Top Header Bar */}
      <header className="px-4 sm:px-6 py-4 flex items-center justify-between border-b border-white/10 bg-black/40 z-20">
        <div className="flex items-center gap-3">
          <button
            onClick={onClose}
            className="p-2 rounded-xl bg-white/10 hover:bg-white/20 text-white transition-colors"
            title="Back to Parent Console"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <div>
            <div className="flex items-center gap-2">
              <h2 className="text-base font-bold text-white tracking-tight leading-none">{modelName}</h2>
              <span className="px-2 py-0.5 rounded-md bg-white/10 text-white/80 font-mono text-[10px] font-semibold">
                {activePairingCode}
              </span>
            </div>
            <p className="text-xs text-[#9eb5ab] flex items-center gap-2 mt-1">
              <span className={`w-2 h-2 rounded-full ${
                connectionState === 'connected' ? 'bg-emerald-400 animate-pulse' : 'bg-amber-400'
              }`} />
              <span>{statusMessage}</span>
            </p>
          </div>
        </div>

        {/* Right Controls */}
        <div className="flex items-center gap-2">
          <button
            onClick={handleSwitchCameraLens}
            className="px-3 py-1.5 rounded-lg text-xs font-bold bg-[#0A9B70] hover:bg-[#087957] text-white transition-all shadow-xs flex items-center gap-1.5"
            title="Switch front/back lens"
          >
            <RefreshCw className="w-3.5 h-3.5" />
            <span>Switch Lens ({cameraFacing.toUpperCase()})</span>
          </button>

          <button
            onClick={toggleFullscreen}
            className="p-2 rounded-lg bg-white/10 hover:bg-white/20 text-white transition-colors"
            title={isFullscreen ? 'Exit Fullscreen' : 'Fullscreen'}
          >
            {isFullscreen ? <Minimize2 className="w-4 h-4" /> : <Maximize2 className="w-4 h-4" />}
          </button>
        </div>
      </header>

      {/* Main Video Viewport */}
      <main ref={containerRef} className="flex-1 relative flex items-center justify-center bg-black overflow-hidden">
        {/* HTML5 Video Element receiving WebRTC MediaStream */}
        <video
          ref={videoRef}
          autoPlay
          playsInline
          muted={isMuted}
          className={`w-full h-full object-contain transition-opacity duration-300 ${
            isVideoPlaying ? 'opacity-100' : 'opacity-0'
          }`}
        />

        {/* Banner: Child Device Regenerated Code */}
        {regeneratedCode && (
          <div className="absolute top-4 inset-x-4 mx-auto max-w-lg z-30 bg-rose-500/95 text-white px-5 py-4 rounded-2xl backdrop-blur-md shadow-2xl border border-rose-300 animate-in fade-in slide-in-from-top-4 duration-300">
            <div className="flex items-start gap-3">
              <ShieldAlert className="w-6 h-6 shrink-0 text-white" />
              <div className="flex-1 min-w-0">
                <h4 className="font-extrabold text-sm text-white">Child Pairing Code Changed</h4>
                <p className="text-xs text-rose-100 mt-1">
                  The child device generated fresh code <span className="font-mono font-bold text-white underline">{regeneratedCode}</span>.
                </p>
                <div className="mt-3 flex items-center gap-2">
                  <button
                    onClick={handleRelinkNewCode}
                    disabled={isRelinking}
                    className="px-3.5 py-1.5 rounded-lg text-xs font-bold bg-white text-rose-800 hover:bg-rose-50 transition-colors shadow-xs flex items-center gap-1.5"
                  >
                    {isRelinking ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Link className="w-3.5 h-3.5" />}
                    Re-link to {regeneratedCode}
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* 4-Second Waiting Banner */}
        {!regeneratedCode && waitingForStream && (
          <div className="absolute top-4 inset-x-4 mx-auto max-w-xl z-30 bg-amber-500/95 text-amber-950 px-4 py-3 rounded-xl backdrop-blur-md shadow-2xl border border-amber-300 flex flex-wrap items-center justify-between gap-3 animate-in fade-in slide-in-from-top-2 duration-300">
            <div className="flex items-center gap-3 min-w-0">
              <Loader2 className="w-5 h-5 animate-spin text-amber-950 shrink-0" />
              <div className="min-w-0">
                <span className="font-extrabold text-sm tracking-tight text-amber-950">
                  Waiting for child camera stream...
                </span>
                <p className="text-[11px] text-amber-900/90 truncate">
                  Signaling via RTDB: /devices/{activePairingCode}/stream (Attempt #{retryCount})
                </p>
              </div>
            </div>
            <button
              onClick={handleManualReinitialize}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-bold bg-amber-950 text-amber-100 hover:bg-amber-900 transition-colors shadow-xs"
            >
              <RefreshCw className="w-3.5 h-3.5" />
              Retry Signaling
            </button>
          </div>
        )}

        {/* Connecting Stage when video is not yet playing */}
        {(!isVideoPlaying && !regeneratedCode) && (
          <div className="absolute inset-0 flex flex-col items-center justify-center p-6 text-center bg-black/85 backdrop-blur-xs">
            <div className="relative mb-4">
              <div className="w-16 h-16 rounded-2xl bg-emerald-950/80 border border-emerald-500/30 flex items-center justify-center text-emerald-400">
                <Video className="w-8 h-8 animate-pulse" />
              </div>
            </div>

            <h3 className="text-base font-extrabold text-white">
              Connecting to {modelName}
            </h3>
            <p className="text-xs text-[#a5bbb1] max-w-sm mt-1">
              {statusMessage}
            </p>

            <div className="mt-5 grid grid-cols-3 gap-2 w-full max-w-md text-left">
              <div className="bg-white/5 border border-white/10 rounded-lg p-2.5">
                <span className="text-[10px] text-white/50 block font-mono">RTDB NODE</span>
                <span className="text-xs font-semibold text-emerald-300">
                  /stream/offer
                </span>
              </div>
              <div className="bg-white/5 border border-white/10 rounded-lg p-2.5">
                <span className="text-[10px] text-white/50 block font-mono">ICE PROTOCOL</span>
                <span className="text-xs font-semibold text-amber-300">
                  STUN P2P
                </span>
              </div>
              <div className="bg-white/5 border border-white/10 rounded-lg p-2.5">
                <span className="text-[10px] text-white/50 block font-mono">HARDWARE</span>
                <span className="text-xs font-semibold text-white/80">
                  {cameraFacing.toUpperCase()} Cam
                </span>
              </div>
            </div>

            <div className="mt-6">
              <button
                onClick={handleManualReinitialize}
                className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold bg-[#0A9B70] hover:bg-[#087957] text-white transition-colors"
              >
                <RotateCcw className="w-3.5 h-3.5" />
                Re-dispatch WebRTC Signaling Offer
              </button>
            </div>
          </div>
        )}

        {/* Autoplay blocked fallback banner */}
        {autoplayBlocked && (
          <div className="absolute inset-0 z-40 bg-black/75 flex flex-col items-center justify-center p-6 text-center">
            <div className="w-14 h-14 rounded-full bg-emerald-500/20 text-emerald-300 flex items-center justify-center mb-3">
              <Play className="w-7 h-7 fill-emerald-300" />
            </div>
            <h4 className="text-sm font-bold text-white">Browser Auto-play Policy Detected</h4>
            <p className="text-xs text-neutral-300 max-w-sm mt-1 mb-4">
              Click below to unpause and view the live hardware stream.
            </p>
            <button
              onClick={handleManualVideoPlay}
              className="px-5 py-2.5 rounded-xl font-bold text-xs bg-emerald-500 hover:bg-emerald-400 text-neutral-950 transition-colors flex items-center gap-2 shadow-lg"
            >
              <Play className="w-4 h-4 fill-current" />
              Resume Camera Stream
            </button>
          </div>
        )}

        {/* Overlay Badge */}
        <div className="absolute top-4 left-4 flex items-center gap-2 px-3 py-1.5 rounded-lg bg-black/60 backdrop-blur-md border border-white/15 text-xs pointer-events-none">
          <Radio className="w-3.5 h-3.5 text-emerald-400 animate-pulse" />
          <span className="font-bold tracking-wider text-emerald-300">
            LIVE WEBRTC
          </span>
          <span className="text-white/60">•</span>
          <span className="text-white/90 uppercase font-mono">{cameraFacing} lens</span>
        </div>
      </main>

      {/* Footer Controls */}
      <footer className="px-4 sm:px-6 py-3 border-t border-white/10 bg-black/40 z-20 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <button
            onClick={toggleMute}
            className="p-2 rounded-lg bg-white/10 hover:bg-white/20 text-white transition-colors"
            title={isMuted ? 'Unmute Audio' : 'Mute Audio'}
          >
            {isMuted ? <VolumeX className="w-4 h-4 text-rose-400" /> : <Volume2 className="w-4 h-4 text-emerald-400" />}
          </button>
          <div className="flex items-center gap-1.5 text-xs text-white/70">
            <span>Vol</span>
            <input
              type="range"
              min="0"
              max="1"
              step="0.05"
              value={isMuted ? 0 : volume}
              onChange={handleVolumeChange}
              className="w-20 accent-emerald-400"
            />
          </div>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={handleManualReinitialize}
            title="Re-run Firebase RTDB signaling handshake"
            className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium border border-white/15 text-neutral-300 hover:bg-white/10 hover:text-white transition-colors"
          >
            <RefreshCw className="w-3.5 h-3.5" />
            Re-init Signaling
          </button>
        </div>
      </footer>
    </div>
  );
};
