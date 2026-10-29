import React, { useState, useEffect, useRef, useCallback } from 'react';
import { 
  Cast, 
  RotateCw, 
  Camera, 
  Play, 
  Square, 
  ShieldAlert,
  BatteryCharging,
  Maximize2,
  Minimize2,
  RefreshCw,
  Loader2,
  AlertCircle,
  Wifi,
  CheckCircle2,
  Activity,
  Clock
} from 'lucide-react';
import { ParentChildDevice } from '../types';
import { 
  subscribeToDeviceScreen, 
  startParentScreenShareSession, 
  updateDeviceScreen,
  ScreenFrameData,
  WebRTCSignalingSession 
} from '../services/webrtc';

interface ScreenMirrorViewProps {
  devices: ParentChildDevice[];
  selectedDevice: ParentChildDevice | null;
  onSelectDevice: (device: ParentChildDevice) => void;
  parentUid?: string;
}

export const ScreenMirrorView: React.FC<ScreenMirrorViewProps> = ({
  devices,
  selectedDevice,
  onSelectDevice,
  parentUid = 'parent_console',
}) => {
  const currentDevice = selectedDevice || devices[0];
  
  // Controls & States
  const [isMirroring, setIsMirroring] = useState(true);
  const [streamSource, setStreamSource] = useState<'none' | 'webrtc' | 'rtdb'>('none');
  const [isWaitingForStream, setIsWaitingForStream] = useState(false);
  const [connectionState, setConnectionState] = useState<'connecting' | 'connected' | 'waiting' | 'reconnecting'>('connecting');
  const [statusMessage, setStatusMessage] = useState('Initiating screen stream connection…');
  const [retryCount, setRetryCount] = useState(0);
  const [snapshotTaken, setSnapshotTaken] = useState(false);
  const [isFullscreen, setIsFullscreen] = useState(false);
  
  // Real-time Screen Telemetry from RTDB or Stream
  const [screenData, setScreenData] = useState<ScreenFrameData | null>(null);
  const [activeApp, setActiveApp] = useState<string>('Home Screen');
  const [lastFrameTime, setLastFrameTime] = useState<number | null>(null);
  const [frameCounter, setFrameCounter] = useState(0);

  // References
  const videoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const sessionRef = useRef<WebRTCSignalingSession | null>(null);
  const hasReceivedStreamRef = useRef(false);
  const rtdbUnsubRef = useRef<(() => void) | null>(null);
  const threeSecondTimerRef = useRef<any>(null);

  const pairingCode = currentDevice?.pairingCode || '';
  const deviceId = currentDevice?.deviceId || currentDevice?.childId || pairingCode;
  const modelName = currentDevice?.deviceModelName || currentDevice?.telemetry?.deviceModelName || `Device ${currentDevice?.childId?.slice(0, 8) || 'Child'}`;

  // Stop all active streams and listeners
  const cleanupStream = useCallback(() => {
    if (threeSecondTimerRef.current) {
      clearTimeout(threeSecondTimerRef.current);
      threeSecondTimerRef.current = null;
    }
    if (rtdbUnsubRef.current) {
      rtdbUnsubRef.current();
      rtdbUnsubRef.current = null;
    }
    if (sessionRef.current) {
      sessionRef.current.cleanup();
      sessionRef.current = null;
    }
    if (videoRef.current && videoRef.current.srcObject) {
      const stream = videoRef.current.srcObject as MediaStream;
      stream.getTracks().forEach((t) => t.stop());
      videoRef.current.srcObject = null;
    }
  }, []);

  // Main stream subscription logic: WebRTC + Firebase RTDB
  const startStreamListening = useCallback(() => {
    if (!currentDevice || !isMirroring) return;

    cleanupStream();

    hasReceivedStreamRef.current = false;
    setIsWaitingForStream(false);
    setConnectionState('connecting');
    setStatusMessage(`Connecting to /devices/${pairingCode}/screen & WebRTC screen session…`);

    // Requirement: If no live screen stream is received within 3 seconds,
    // display fallback status: 'Waiting for child device screen stream...' with a retry connection button
    threeSecondTimerRef.current = setTimeout(() => {
      if (!hasReceivedStreamRef.current) {
        console.log('No live screen stream received within 3 seconds from child device. Setting fallback status.');
        setIsWaitingForStream(true);
        setConnectionState('waiting');
        setStatusMessage('Waiting for child device screen stream...');
      }
    }, 3000);

    // 1. Listen to live screen frame feeds from Firebase RTDB at /devices/{pairingCode}/screen
    const cleanCode = pairingCode.trim();
    if (cleanCode) {
      const unsub = subscribeToDeviceScreen(cleanCode, (data) => {
        if (data && (data.frame || data.status === 'streaming')) {
          hasReceivedStreamRef.current = true;
          setIsWaitingForStream(false);
          setConnectionState('connected');
          setStreamSource('rtdb');
          setScreenData(data);
          setLastFrameTime(Date.now());
          setFrameCounter((prev) => prev + 1);
          if (data.activeApp) {
            setActiveApp(data.activeApp);
          }
          setStatusMessage('Live screen frames streaming from Firebase RTDB');
        }
      });
      rtdbUnsubRef.current = unsub;
    }

    // 2. Also initialize WebRTC screen stream signaling
    startParentScreenShareSession(deviceId, parentUid, currentDevice.childId, {
      onStream: (remoteStream) => {
        console.log('WebRTC live screen media track received successfully from child device');
        hasReceivedStreamRef.current = true;
        setIsWaitingForStream(false);
        setConnectionState('connected');
        setStreamSource('webrtc');
        setStatusMessage('Live WebRTC screen stream connected');

        if (videoRef.current) {
          videoRef.current.srcObject = remoteStream;
          videoRef.current
            .play()
            .catch((err) => console.warn('HTML5 screen video auto-play blocked or failed:', err));
        }
      },
      onStatusChange: (status) => {
        if (!hasReceivedStreamRef.current) {
          setStatusMessage(status);
        }
      },
      onConnectionStateChange: (state) => {
        if (state === 'connected') {
          setConnectionState('connected');
        } else if (state === 'failed' || state === 'disconnected') {
          if (!hasReceivedStreamRef.current) {
            setConnectionState('waiting');
          }
        }
      },
      onError: (err) => {
        console.warn('WebRTC screen session error:', err);
      },
    }).then((session) => {
      sessionRef.current = session;
    }).catch((err) => {
      console.warn('Screen share initialization exception:', err);
    });

  }, [currentDevice, isMirroring, pairingCode, deviceId, parentUid, cleanupStream]);

  // Launch stream listening whenever current device or mirroring toggle changes
  useEffect(() => {
    if (isMirroring && currentDevice) {
      startStreamListening();
    } else {
      cleanupStream();
      setStreamSource('none');
      setConnectionState('waiting');
    }

    return () => {
      cleanupStream();
    };
  }, [currentDevice?.childId, isMirroring, startStreamListening, cleanupStream]);

  // Handle Retry Connection
  const handleRetryConnection = useCallback(() => {
    setRetryCount((prev) => prev + 1);
    setStatusMessage('Retrying connection to child device screen…');
    startStreamListening();
  }, [startStreamListening]);

  // Handle Parent toggle for Screen Mirroring (updates RTDB status: 'mirroring' vs 'standby')
  const handleToggleMirroring = useCallback(async (targetState: boolean) => {
    setIsMirroring(targetState);
    if (pairingCode) {
      try {
        if (targetState) {
          await updateDeviceScreen(pairingCode, {
            status: 'mirroring',
            isSharing: true,
            command: 'startScreenShare',
            commandId: `cmd_${Date.now()}`,
          });
        } else {
          await updateDeviceScreen(pairingCode, {
            status: 'standby',
            isSharing: false,
            command: 'stopScreenShare',
            commandId: `cmd_${Date.now()}`,
          });
        }
      } catch (err) {
        console.warn('Error syncing screen mirror state to RTDB:', err);
      }
    }
    if (targetState) {
      setRetryCount((prev) => prev + 1);
      setStatusMessage('Requesting screen mirror feed from child device…');
      startStreamListening();
    }
  }, [pairingCode, startStreamListening]);

  // Snapshot Capture handler
  const handleTakeSnapshot = useCallback(() => {
    setSnapshotTaken(true);
    setTimeout(() => setSnapshotTaken(false), 2500);

    // If canvas or video is available, capture screenshot
    if (videoRef.current && videoRef.current.videoWidth > 0) {
      try {
        const tempCanvas = document.createElement('canvas');
        tempCanvas.width = videoRef.current.videoWidth;
        tempCanvas.height = videoRef.current.videoHeight;
        const ctx = tempCanvas.getContext('2d');
        if (ctx) {
          ctx.drawImage(videoRef.current, 0, 0);
          const link = document.createElement('a');
          link.download = `screen_${modelName.replace(/\s+/g, '_')}_${Date.now()}.png`;
          link.href = tempCanvas.toDataURL('image/png');
          link.click();
        }
      } catch (e) {
        console.warn('Snapshot capture warning:', e);
      }
    } else if (screenData?.frame) {
      const link = document.createElement('a');
      link.download = `screen_${modelName.replace(/\s+/g, '_')}_${Date.now()}.jpg`;
      link.href = screenData.frame;
      link.click();
    }
  }, [modelName, screenData]);

  // Fullscreen toggle
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

  if (!currentDevice) {
    return (
      <div className="bg-white rounded-xl border border-[#e4e9e5] p-12 text-center text-neutral-500 shadow-xs">
        <Cast className="w-12 h-12 text-neutral-300 mx-auto mb-3" />
        <h3 className="text-base font-bold text-neutral-800">No Paired Devices Found</h3>
        <p className="text-xs text-neutral-500 mt-1">Pair a child device first to mirror their screen.</p>
      </div>
    );
  }

  const isLiveStreamActive = (streamSource === 'webrtc' || (streamSource === 'rtdb' && !!screenData?.frame)) && !isWaitingForStream;

  return (
    <div ref={containerRef} className="space-y-6">
      {/* Device Selector & Mirror Controls Bar */}
      <div className="bg-white rounded-xl border border-[#e4e9e5] p-4 flex flex-wrap items-center justify-between gap-4 shadow-xs">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-purple-50 text-purple-700 flex items-center justify-center shrink-0 border border-purple-100">
            <Cast className="w-5 h-5" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <label className="text-[10px] font-bold text-[#71807b] uppercase">SELECT CHILD DEVICE</label>
              <span className="text-[10px] font-mono font-semibold bg-emerald-50 text-emerald-700 px-1.5 py-0.2 rounded border border-emerald-200">
                Code: {pairingCode}
              </span>
            </div>
            <select
              value={currentDevice.childId}
              onChange={(e) => {
                const dev = devices.find((d) => d.childId === e.target.value);
                if (dev) onSelectDevice(dev);
              }}
              className="font-bold text-sm text-[#202b29] bg-transparent border-none outline-none cursor-pointer focus:ring-0 p-0"
            >
              {devices.map((d) => (
                <option key={d.childId} value={d.childId}>
                  {d.deviceModelName || `Device ${d.childId.slice(0, 8)}`} {d.isOnline ? '(Online)' : '(Offline)'}
                </option>
              ))}
            </select>
          </div>
        </div>

        {/* Action Buttons */}
        <div className="flex flex-wrap items-center gap-2">
          {/* Start / Stop Toggle */}
          {isMirroring ? (
            <button
              onClick={() => handleToggleMirroring(false)}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold bg-rose-50 text-rose-700 hover:bg-rose-100 border border-rose-200 transition-colors"
            >
              <Square className="w-3.5 h-3.5" />
              Stop Mirroring
            </button>
          ) : (
            <button
              onClick={() => handleToggleMirroring(true)}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-bold bg-[#0a9b70] hover:bg-[#087957] text-white transition-colors shadow-xs"
            >
              <Play className="w-3.5 h-3.5 fill-current" />
              Request Screen Mirror
            </button>
          )}

          {/* Retry Connection Button */}
          <button
            onClick={handleRetryConnection}
            title="Re-run connection handshake via Firebase RTDB and WebRTC"
            className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold bg-neutral-100 hover:bg-neutral-200 text-neutral-800 transition-colors border border-neutral-200"
          >
            <RefreshCw className="w-3.5 h-3.5 text-neutral-600" />
            Retry Connection
          </button>

          {/* Capture Snapshot Button */}
          <button
            onClick={handleTakeSnapshot}
            disabled={!isLiveStreamActive}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold bg-neutral-100 hover:bg-neutral-200 text-neutral-800 transition-colors disabled:opacity-40 border border-neutral-200"
          >
            <Camera className="w-3.5 h-3.5 text-neutral-600" />
            {snapshotTaken ? 'Snapshot Saved!' : 'Capture Snapshot'}
          </button>

          {/* Fullscreen Toggle */}
          <button
            onClick={toggleFullscreen}
            className="p-1.5 rounded-lg border border-neutral-200 hover:bg-neutral-100 text-neutral-700 transition-colors"
            title={isFullscreen ? 'Exit Fullscreen' : 'Fullscreen'}
          >
            {isFullscreen ? <Minimize2 className="w-4 h-4" /> : <Maximize2 className="w-4 h-4" />}
          </button>
        </div>
      </div>

      {/* Screen Mirroring Display Canvas & Sidebar */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* Mobile Device Canvas Display */}
        <div className="lg:col-span-2 bg-[#121c18] rounded-2xl p-6 flex flex-col items-center justify-center min-h-[580px] border border-neutral-800 shadow-xl relative overflow-hidden select-none">
          
          {/* Top connection status header badge */}
          <div className="w-full flex items-center justify-between pb-4 text-xs">
            <div className="flex items-center gap-2">
              <span
                className={`w-2.5 h-2.5 rounded-full ${
                  isLiveStreamActive
                    ? 'bg-emerald-400 animate-pulse shadow-[0_0_8px_#34d399]'
                    : isWaitingForStream
                    ? 'bg-amber-400 animate-ping'
                    : 'bg-amber-400'
                }`}
              />
              <span className={`font-semibold ${isLiveStreamActive ? 'text-emerald-300' : 'text-amber-300'}`}>
                {isLiveStreamActive
                  ? (streamSource === 'webrtc' ? 'Live WebRTC Screen Feed' : 'Live RTDB Screen Feed')
                  : isWaitingForStream
                  ? 'Waiting for Child Stream…'
                  : 'Connecting Signaling…'}
              </span>
            </div>

            <span className="font-mono text-[11px] text-neutral-400">
              RTDB: /devices/{pairingCode}/screen
            </span>
          </div>

          {/* Physical Phone Frame */}
          <div className="w-[320px] h-[600px] bg-black rounded-[44px] p-3 border-4 border-neutral-700 shadow-2xl flex flex-col justify-between relative overflow-hidden ring-1 ring-white/10">
            
            {/* Notch / Dynamic Island */}
            <div className="absolute top-4 left-1/2 -translate-x-1/2 w-28 h-5 bg-black rounded-full z-30 flex items-center justify-center border border-neutral-800">
              <span className="w-2.5 h-2.5 rounded-full bg-neutral-900 border border-neutral-700 block mr-2"></span>
              <span className="w-2 h-2 rounded-full bg-emerald-950 block"></span>
            </div>

            {/* Mobile Screen Surface */}
            <div className="w-full h-full bg-[#0a1512] rounded-[36px] overflow-hidden flex flex-col text-white relative">
              
              {/* Phone Status Bar */}
              <div className="h-8 px-5 flex items-center justify-between text-[11px] font-bold text-neutral-300 pt-1 shrink-0 z-20 bg-black/40 backdrop-blur-xs">
                <span>{new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>
                <div className="flex items-center gap-1.5">
                  <span className="text-[10px] font-mono text-emerald-400">5G</span>
                  <BatteryCharging className="w-3.5 h-3.5 text-emerald-400" />
                  <span>{screenData?.battery || currentDevice.telemetry?.batteryLevel || 84}%</span>
                </div>
              </div>

              {/* Main Content View Inside Phone */}
              <div className="flex-1 relative flex flex-col items-center justify-center overflow-hidden bg-neutral-950">
                
                {/* 1. Live WebRTC Stream Container */}
                <video
                  ref={videoRef}
                  autoPlay
                  playsInline
                  muted
                  className={`absolute inset-0 w-full h-full object-contain bg-black transition-opacity duration-300 ${
                    streamSource === 'webrtc' && isLiveStreamActive ? 'opacity-100 z-10' : 'opacity-0 pointer-events-none'
                  }`}
                  onError={(e) => console.warn('HTML5 Video error:', e)}
                />

                {/* 2. Live RTDB Image Frame Feed Container */}
                {streamSource === 'rtdb' && screenData?.frame && isLiveStreamActive && (
                  <div className="absolute inset-0 z-10 w-full h-full bg-black flex flex-col justify-between">
                    <img 
                      src={screenData.frame} 
                      alt="Live Child Screen Feed" 
                      className="w-full h-full object-contain"
                    />
                    {/* Timestamp & Frame Watermark */}
                    <div className="absolute bottom-2 left-2 right-2 flex items-center justify-between px-2 py-1 bg-black/70 backdrop-blur-xs rounded text-[10px] font-mono text-neutral-300">
                      <span>Live Frame #{frameCounter}</span>
                      <span className="text-emerald-400">{activeApp}</span>
                    </div>
                  </div>
                )}

                {/* 3. REQUIREMENT: FALLBACK STATUS BANNER & CARD
                    If no live screen stream is received within 3 seconds,
                    display a fallback status: 'Waiting for child device screen stream...' 
                    with a retry connection button instead of mock YouTube content */}
                {isWaitingForStream && !isLiveStreamActive && isMirroring && (
                  <div className="absolute inset-0 z-20 p-5 flex flex-col items-center justify-center text-center bg-[#0d1a16] text-[#f4f8f5] animate-in fade-in duration-300">
                    
                    {/* Pulsing Radar Icon */}
                    <div className="relative mb-4">
                      <div className="w-16 h-16 rounded-2xl bg-amber-500/10 border border-amber-500/30 flex items-center justify-center text-amber-400">
                        <Loader2 className="w-8 h-8 animate-spin text-amber-400" />
                      </div>
                      <span className="absolute -top-1 -right-1 flex h-4 w-4">
                        <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-amber-400 opacity-75"></span>
                        <span className="relative inline-flex rounded-full h-4 w-4 bg-amber-500"></span>
                      </span>
                    </div>

                    {/* Exact user-requested status label */}
                    <div className="space-y-1 max-w-[260px]">
                      <h4 className="text-sm font-extrabold text-amber-300 tracking-tight">
                        Waiting for child device screen stream...
                      </h4>
                      <p className="text-[11px] text-neutral-400 leading-relaxed">
                        No live screen frame received from <span className="text-white font-semibold">{modelName}</span> within 3 seconds.
                      </p>
                    </div>

                    {/* Firebase RTDB Location details */}
                    <div className="mt-4 p-2.5 rounded-xl bg-black/40 border border-white/10 text-left w-full max-w-[250px] space-y-1">
                      <div className="flex items-center justify-between text-[10px] text-neutral-400">
                        <span>Pairing Code:</span>
                        <span className="font-mono font-bold text-emerald-400">{pairingCode}</span>
                      </div>
                      <div className="flex items-center justify-between text-[10px] text-neutral-400">
                        <span>Listening at:</span>
                        <span className="font-mono text-neutral-300">/devices/{pairingCode}/screen</span>
                      </div>
                      <div className="flex items-center justify-between text-[10px] text-neutral-400">
                        <span>Signaling:</span>
                        <span className="text-amber-300 font-semibold">WebRTC Screen Offer</span>
                      </div>
                    </div>

                    {/* Prompt-mandated Retry Connection button */}
                    <div className="mt-5 w-full">
                      <button
                        onClick={handleRetryConnection}
                        className="w-full py-2.5 px-4 rounded-xl text-xs font-bold bg-[#0a9b70] hover:bg-[#087957] text-white transition-all shadow-md flex items-center justify-center gap-2 group"
                      >
                        <RefreshCw className="w-3.5 h-3.5 group-hover:rotate-180 transition-transform duration-500" />
                        Retry Connection
                      </button>
                    </div>
                  </div>
                )}

                {/* 4. Connecting initial state (< 3 seconds) */}
                {!isWaitingForStream && !isLiveStreamActive && isMirroring && (
                  <div className="absolute inset-0 z-20 flex flex-col items-center justify-center p-6 text-center bg-[#0d1a16] text-[#f4f8f5]">
                    <div className="w-14 h-14 rounded-2xl bg-emerald-950/80 border border-emerald-500/30 flex items-center justify-center text-emerald-400 mb-3 animate-pulse">
                      <Cast className="w-7 h-7 text-emerald-400" />
                    </div>
                    <h4 className="text-sm font-bold text-white">Connecting Screen Feed</h4>
                    <p className="text-[11px] text-neutral-400 max-w-[220px] mt-1">
                      {statusMessage}
                    </p>
                    <div className="mt-4 flex items-center gap-2 text-[10px] font-mono text-emerald-400">
                      <Loader2 className="w-3 h-3 animate-spin" />
                      Awaiting child stream (3s timeout)…
                    </div>
                  </div>
                )}

                {/* 5. Mirroring Paused State */}
                {!isMirroring && (
                  <div className="absolute inset-0 z-20 flex flex-col items-center justify-center p-6 text-center bg-[#0d1a16] text-neutral-400">
                    <Cast className="w-10 h-10 text-neutral-600 mb-2" />
                    <p className="text-xs font-semibold text-neutral-300">Screen Mirroring Paused</p>
                    <p className="text-[11px] text-neutral-500 mt-1 max-w-[220px]">
                      Click 'Request Screen Mirror' to resume real-time screen surveillance.
                    </p>
                    <button
                      onClick={() => handleToggleMirroring(true)}
                      className="mt-4 px-4 py-2 rounded-xl text-xs font-bold bg-[#0a9b70] hover:bg-[#087957] text-white transition-colors"
                    >
                      Request Screen Mirror
                    </button>
                  </div>
                )}

              </div>

              {/* Bottom Home Indicator */}
              <div className="h-5 flex items-center justify-center shrink-0 bg-black/40 backdrop-blur-xs z-20">
                <span className="w-24 h-1 bg-neutral-600 rounded-full"></span>
              </div>
            </div>
          </div>

          {/* Bottom Live Feed Status Footer inside canvas */}
          <div className="mt-4 flex flex-wrap items-center justify-center gap-4 text-xs text-neutral-400">
            <span className="flex items-center gap-1.5">
              <Activity className="w-3.5 h-3.5 text-emerald-400" />
              Source: <strong className="text-white capitalize">{streamSource === 'none' ? 'Disconnected' : streamSource}</strong>
            </span>
            <span>•</span>
            <span>Active App: <strong className="text-emerald-300">{activeApp}</strong></span>
            {lastFrameTime && (
              <>
                <span>•</span>
                <span className="flex items-center gap-1">
                  <Clock className="w-3 h-3" />
                  Synced {Math.round((Date.now() - lastFrameTime) / 1000)}s ago
                </span>
              </>
            )}
          </div>
        </div>

        {/* Supervision & Telemetry Controls Sidebar */}
        <div className="space-y-6">
          {/* Supervision Status Card */}
          <div className="bg-white rounded-xl border border-[#e4e9e5] p-5 shadow-xs space-y-4">
            <h3 className="font-bold text-base text-[#202b29] flex items-center gap-2">
              <ShieldAlert className="w-4 h-4 text-emerald-600" />
              Supervision Controls
            </h3>

            <div className="space-y-3.5 text-xs">
              <div>
                <span className="block text-[10px] font-bold text-[#71807b] uppercase">CURRENT FOREGROUND APP</span>
                <div className="mt-1 flex items-center justify-between p-2 rounded-lg bg-neutral-50 border border-neutral-200">
                  <span className="font-bold text-neutral-800">{activeApp}</span>
                  <span className={`text-[10px] font-semibold px-2 py-0.5 rounded ${
                    isLiveStreamActive ? 'bg-emerald-100 text-emerald-800' : 'bg-neutral-200 text-neutral-600'
                  }`}>
                    {isLiveStreamActive ? 'ACTIVE' : 'STANDBY'}
                  </span>
                </div>
              </div>

              <div className="pt-2 border-t border-neutral-100">
                <span className="block text-[10px] font-bold text-[#71807b] uppercase">STREAM PROTOCOL</span>
                <p className="font-semibold text-neutral-800 mt-0.5 flex items-center gap-1.5">
                  <Wifi className="w-3.5 h-3.5 text-emerald-600" />
                  WebRTC P2P + Firebase RTDB Feed
                </p>
                <p className="text-[11px] font-mono text-neutral-500 mt-0.5">
                  /devices/{pairingCode}/screen
                </p>
              </div>

              <div className="pt-2 border-t border-neutral-100">
                <span className="block text-[10px] font-bold text-[#71807b] uppercase">STREAM RESOLUTION & FPS</span>
                <p className="font-semibold text-neutral-800 mt-0.5">720 x 1280 (HD • 30 FPS)</p>
              </div>

              <div className="pt-2 border-t border-neutral-100">
                <span className="block text-[10px] font-bold text-[#71807b] uppercase">CHILD DEVICE INFO</span>
                <div className="mt-1 space-y-1 text-[11px] text-neutral-600">
                  <div className="flex justify-between">
                    <span>Model:</span>
                    <span className="font-semibold text-neutral-800">{modelName}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Pairing Code:</span>
                    <span className="font-mono font-bold text-emerald-700">{pairingCode}</span>
                  </div>
                  <div className="flex justify-between">
                    <span>Battery:</span>
                    <span className="font-semibold text-neutral-800">{screenData?.battery || currentDevice.telemetry?.batteryLevel || 84}%</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* Child Companion View Link */}
          <div className="bg-emerald-50/60 rounded-xl border border-emerald-100 p-4 text-xs text-emerald-950 space-y-1.5">
            <span className="font-bold block text-emerald-900">Child Companion Mode</span>
            <p className="text-[11px] text-emerald-800 leading-normal">
              Open the app in another browser tab and click <strong>"Child Mode"</strong> with code <span className="font-mono font-bold bg-white px-1 rounded border border-emerald-200">{pairingCode}</span> to broadcast the real device screen feed.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};
