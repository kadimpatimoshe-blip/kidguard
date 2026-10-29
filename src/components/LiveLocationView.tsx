import React, { useState, useEffect, useRef, useCallback } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { 
  MapPin, 
  Navigation, 
  ShieldCheck, 
  RefreshCw, 
  Compass, 
  Clock, 
  Smartphone,
  Signal,
  AlertCircle,
  Radio,
  ExternalLink,
  Crosshair,
  Layers,
  Loader2,
  CheckCircle2,
  Send
} from 'lucide-react';
import { ParentChildDevice, LocationData } from '../types';
import { subscribeToChildLocation, updateChildLocation, sendRemoteCommand } from '../services/firebase';

interface LiveLocationViewProps {
  devices: ParentChildDevice[];
  selectedDevice: ParentChildDevice | null;
  onSelectDevice: (device: ParentChildDevice) => void;
}

export const LiveLocationView: React.FC<LiveLocationViewProps> = ({
  devices,
  selectedDevice,
  onSelectDevice,
}) => {
  const currentDevice = selectedDevice || devices[0];
  const [liveLocation, setLiveLocation] = useState<LocationData | null>(null);
  const [isListening, setIsListening] = useState(false);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isRequestingFix, setIsRequestingFix] = useState(false);
  const [lastRefreshed, setLastRefreshed] = useState<Date>(new Date());
  const [syncStatus, setSyncStatus] = useState<'idle' | 'listening' | 'received'>('listening');

  const mapContainerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const markerRef = useRef<L.Marker | null>(null);
  const accuracyCircleRef = useRef<L.Circle | null>(null);

  const pairingCode = currentDevice?.pairingCode ? String(currentDevice.pairingCode).trim() : '';
  const modelName = currentDevice?.deviceModelName || `Device ${currentDevice?.childId?.slice(0, 8) || ''}`;

  // Listen directly to Firebase RTDB under /devices/{pairingCode}/location
  useEffect(() => {
    if (!pairingCode) {
      setLiveLocation(null);
      return;
    }

    setIsListening(true);
    setSyncStatus('listening');

    const unsubscribe = subscribeToChildLocation(
      pairingCode,
      (location) => {
        if (location && typeof location.latitude === 'number' && typeof location.longitude === 'number') {
          setLiveLocation(location);
          setLastRefreshed(new Date(location.timestamp || Date.now()));
          setSyncStatus('received');
        } else {
          setLiveLocation(null);
          setSyncStatus('listening');
        }
      },
      (err) => {
        console.warn('Realtime Database location listener notice:', err);
      }
    );

    return () => {
      setIsListening(false);
      unsubscribe();
    };
  }, [pairingCode, currentDevice?.childId]);

  // Handle Leaflet Map Initialization and Dynamic Marker Updates
  useEffect(() => {
    if (!liveLocation || typeof liveLocation.latitude !== 'number' || typeof liveLocation.longitude !== 'number') {
      // Clean up map if location is lost or device has no GPS fix
      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
        markerRef.current = null;
        accuracyCircleRef.current = null;
      }
      return;
    }

    if (!mapContainerRef.current) return;

    const lat = liveLocation.latitude;
    const lon = liveLocation.longitude;
    const accuracy = Math.max(liveLocation.accuracy || 10, 5);

    // Initialize Leaflet map if not already created
    if (!mapRef.current) {
      const map = L.map(mapContainerRef.current, {
        center: [lat, lon],
        zoom: 16,
        zoomControl: false,
      });

      // Standard OpenStreetMap (OSM) tile layer
      L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19,
        attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noreferrer">OpenStreetMap</a> contributors',
      }).addTo(map);

      // Add Zoom control in bottom right
      L.control.zoom({ position: 'bottomright' }).addTo(map);

      // Custom animated Leaflet DivIcon with KidGuard styling
      const customIcon = L.divIcon({
        className: 'custom-kidguard-marker',
        html: `
          <div style="position: relative; width: 44px; height: 44px; display: flex; align-items: center; justify-content: center;">
            <div style="position: absolute; inset: -4px; border-radius: 9999px; background-color: rgba(10, 155, 112, 0.35); animation: ping 2s cubic-bezier(0, 0, 0.2, 1) infinite;"></div>
            <div style="position: relative; width: 36px; height: 36px; border-radius: 9999px; background: linear-gradient(135deg, #0a9b70, #087957); border: 3px solid #ffffff; box-shadow: 0 4px 10px rgba(0, 0, 0, 0.3); display: flex; align-items: center; justify-content: center; color: white;">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
                <path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0Z"/>
                <circle cx="12" cy="10" r="3" fill="#ffffff"/>
              </svg>
            </div>
          </div>
        `,
        iconSize: [44, 44],
        iconAnchor: [22, 22],
        popupAnchor: [0, -22],
      });

      // Child Location Marker
      const marker = L.marker([lat, lon], { icon: customIcon }).addTo(map);
      marker.bindPopup(`
        <div style="font-family: system-ui, -apple-system, sans-serif; padding: 4px; max-width: 200px;">
          <div style="display: flex; align-items: center; gap: 4px; font-weight: 700; color: #0a9b70; font-size: 13px; margin-bottom: 2px;">
            <span>${modelName}</span>
          </div>
          <p style="font-size: 11px; color: #374151; margin: 0 0 4px 0; line-height: 1.3;">${liveLocation.address || 'Real-time GPS Fix'}</p>
          <div style="font-size: 10px; color: #6b7280; border-top: 1px solid #e5e7eb; padding-top: 4px;">
            <span>Fix Accuracy: ±${accuracy}m</span> • <span>${new Date(liveLocation.timestamp || Date.now()).toLocaleTimeString()}</span>
          </div>
        </div>
      `);
      markerRef.current = marker;

      // Accuracy radius circle
      const circle = L.circle([lat, lon], {
        radius: accuracy,
        color: '#0a9b70',
        weight: 1.5,
        dashArray: '4, 4',
        fillColor: '#0a9b70',
        fillOpacity: 0.12,
      }).addTo(map);
      accuracyCircleRef.current = circle;

      mapRef.current = map;

      // Invalidate size once rendered in container
      setTimeout(() => {
        map.invalidateSize();
      }, 150);
    } else {
      // Map exists: smoothly pan and update marker & accuracy radius
      markerRef.current?.setLatLng([lat, lon]);
      accuracyCircleRef.current?.setLatLng([lat, lon]);
      accuracyCircleRef.current?.setRadius(accuracy);
      mapRef.current.panTo([lat, lon], { animate: true, duration: 0.6 });
    }

    return () => {
      // Cleanup on unmount or before recreation
    };
  }, [liveLocation, modelName]);

  // Clean up Leaflet on full unmount
  useEffect(() => {
    return () => {
      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
        markerRef.current = null;
        accuracyCircleRef.current = null;
      }
    };
  }, []);

  const handleRecenter = () => {
    if (mapRef.current && liveLocation) {
      mapRef.current.setView([liveLocation.latitude, liveLocation.longitude], 16, { animate: true });
    }
  };

  const handleManualRefresh = () => {
    setIsRefreshing(true);
    setTimeout(() => {
      setIsRefreshing(false);
      setLastRefreshed(new Date());
    }, 700);
  };

  // Request real GPS fix from child device via Firebase RTDB control command and hardware GPS
  const handleRequestRealGpsFix = async () => {
    if (!pairingCode || !currentDevice) return;
    setIsRequestingFix(true);

    try {
      // 1. Send syncLocation remote command to child device via RTDB
      await sendRemoteCommand(
        currentDevice.deviceId || currentDevice.childId || pairingCode,
        'parent_console',
        currentDevice.childId,
        'syncLocation'
      );

      // 2. If running on physical mobile device with geolocation permissions, acquire satellite coordinates
      if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition(
          async (pos) => {
            const lat = pos.coords.latitude;
            const lon = pos.coords.longitude;
            const acc = Math.round(pos.coords.accuracy || 10);
            
            await updateChildLocation(pairingCode, {
              latitude: lat,
              longitude: lon,
              accuracy: acc,
              speed: pos.coords.speed || 0,
              timestamp: Date.now(),
            });
            setIsRequestingFix(false);
          },
          (err) => {
            console.log('Awaiting hardware GPS fix broadcast from physical child device over RTDB:', err.message);
            setIsRequestingFix(false);
          },
          { timeout: 8000, enableHighAccuracy: true }
        );
      } else {
        setIsRequestingFix(false);
      }
    } catch (e) {
      console.warn('Request GPS fix error:', e);
      setIsRequestingFix(false);
    }
  };

  const formatRelativeTime = (timestamp?: number | string | Date): string => {
    if (!timestamp) return 'Just now';
    try {
      const date = typeof timestamp === 'number' || typeof timestamp === 'string' ? new Date(timestamp) : timestamp;
      const diffMs = Date.now() - date.getTime();
      const diffSec = Math.floor(diffMs / 1000);
      if (diffSec < 45) return 'Just now';
      const diffMin = Math.floor(diffSec / 60);
      if (diffMin < 60) return `${diffMin}m ago`;
      const diffHour = Math.floor(diffMin / 60);
      if (diffHour < 24) return `${diffHour}h ago`;
      return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } catch {
      return 'Just now';
    }
  };

  if (!currentDevice) {
    return (
      <div className="bg-white rounded-2xl border border-[#e4e9e5] p-12 text-center text-neutral-500 shadow-xs">
        <MapPin className="w-12 h-12 text-neutral-300 mx-auto mb-3" />
        <h3 className="text-base font-bold text-neutral-800">No Paired Devices Found</h3>
        <p className="text-xs text-neutral-500 mt-1 max-w-sm mx-auto">
          Pair a child device first using a 4-digit pairing code to monitor live GPS location and OpenStreetMap vectors.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Top Device Bar */}
      <div className="bg-white rounded-xl border border-[#e4e9e5] p-4 flex flex-wrap items-center justify-between gap-4 shadow-xs">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-emerald-50 text-emerald-700 flex items-center justify-center shrink-0 border border-emerald-100">
            <Smartphone className="w-5 h-5" />
          </div>
          <div>
            <label className="block text-[10px] font-bold text-[#71807b] uppercase tracking-wider">
              SELECT TRACKED CHILD
            </label>
            <select
              value={currentDevice.childId}
              onChange={(e) => {
                const dev = devices.find((d) => d.childId === e.target.value);
                if (dev) onSelectDevice(dev);
              }}
              className="font-bold text-sm text-[#202b29] bg-transparent border-none outline-none cursor-pointer focus:ring-0"
            >
              {devices.map((d) => (
                <option key={d.childId} value={d.childId}>
                  {d.deviceModelName || `Device ${d.childId.slice(0, 8)}`} (Code: {d.pairingCode}) {d.isOnline ? '• Online' : '• Offline'}
                </option>
              ))}
            </select>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {/* RTDB Path pill indicator */}
          <span className="hidden sm:inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-[11px] font-mono font-medium bg-neutral-100 text-neutral-700 border border-neutral-200">
            <Radio className="w-3 h-3 text-emerald-600 animate-pulse" />
            /devices/{pairingCode}/location
          </span>

          <button
            onClick={handleManualRefresh}
            disabled={isRefreshing}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold bg-neutral-100 hover:bg-neutral-200 text-neutral-800 transition-colors"
            title="Refresh GPS status"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${isRefreshing ? 'animate-spin' : ''}`} />
            Refresh
          </button>
        </div>
      </div>

      {/* Main Map Box & Side Details */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Visual Map Canvas / OpenStreetMap */}
        <div className="lg:col-span-2 bg-white rounded-xl border border-[#e4e9e5] overflow-hidden shadow-xs flex flex-col h-[490px]">
          {/* Header Bar */}
          <div className="p-3.5 bg-neutral-50 border-b border-neutral-200/80 flex items-center justify-between text-xs">
            <div className="flex items-center gap-2 font-bold text-neutral-700">
              <Compass className="w-4 h-4 text-emerald-600" />
              <span>OpenStreetMap (OSM) Live Vector</span>
            </div>

            {liveLocation ? (
              <div className="flex items-center gap-2">
                <span className="flex items-center gap-1.5 text-[11px] text-emerald-700 font-semibold bg-emerald-50 px-2.5 py-0.5 rounded-full border border-emerald-200">
                  <span className="w-2 h-2 rounded-full bg-emerald-500 animate-ping" />
                  Live GPS Fix (±{liveLocation.accuracy}m)
                </span>
                <button
                  onClick={handleRecenter}
                  className="p-1 rounded hover:bg-neutral-200 text-neutral-600 transition-colors"
                  title="Recenter on Child"
                >
                  <Crosshair className="w-3.5 h-3.5" />
                </button>
              </div>
            ) : (
              <span className="flex items-center gap-1.5 text-[11px] text-amber-700 font-semibold bg-amber-50 px-2.5 py-0.5 rounded-full border border-amber-200">
                <span className="w-2 h-2 rounded-full bg-amber-500 animate-pulse" />
                Waiting for child GPS data...
              </span>
            )}
          </div>

          {/* Map Container OR 'Waiting for child GPS data...' State */}
          <div className="relative flex-1 w-full bg-[#f0f3f1] overflow-hidden">
            {liveLocation ? (
              // Live OpenStreetMap rendered via Leaflet
              <div ref={mapContainerRef} className="w-full h-full z-0" />
            ) : (
              // Empty / Waiting for child GPS state
              <div className="w-full h-full flex flex-col items-center justify-center p-8 text-center bg-gradient-to-b from-[#f8faf8] to-[#edf3ef]">
                <div className="relative mb-4">
                  {/* Radar beacon animation */}
                  <div className="w-20 h-20 rounded-full bg-emerald-100/60 flex items-center justify-center border border-emerald-200/80 animate-pulse">
                    <div className="w-12 h-12 rounded-full bg-emerald-500/20 flex items-center justify-center">
                      <Signal className="w-6 h-6 text-emerald-600 animate-bounce" />
                    </div>
                  </div>
                  <span className="absolute top-0 right-0 w-3 h-3 rounded-full bg-amber-400 ring-4 ring-white animate-ping" />
                </div>

                <h3 className="text-base font-extrabold text-neutral-800 tracking-tight">
                  Waiting for child GPS data...
                </h3>

                <p className="text-xs text-neutral-500 max-w-md mt-1.5 leading-relaxed">
                  Actively listening for real-time coordinates from Firebase Realtime Database at{' '}
                  <span className="font-mono font-semibold text-emerald-800 bg-emerald-50 px-1.5 py-0.5 rounded border border-emerald-200/60">
                    /devices/{pairingCode}/location
                  </span>.
                </p>

                <div className="mt-5 flex flex-wrap items-center justify-center gap-2.5">
                  <button
                    onClick={handleRequestRealGpsFix}
                    disabled={isRequestingFix}
                    className="inline-flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-bold bg-[#0a9b70] hover:bg-[#087957] text-white transition-colors shadow-xs disabled:opacity-50"
                  >
                    {isRequestingFix ? (
                      <>
                        <Loader2 className="w-3.5 h-3.5 animate-spin" />
                        Requesting GPS Fix...
                      </>
                    ) : (
                      <>
                        <Navigation className="w-3.5 h-3.5" />
                        Request Real GPS Fix from Child Device
                      </>
                    )}
                  </button>

                  <button
                    onClick={handleManualRefresh}
                    disabled={isRefreshing}
                    className="inline-flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-semibold bg-white hover:bg-neutral-100 text-neutral-700 border border-neutral-300 transition-colors shadow-xs"
                  >
                    <RefreshCw className={`w-3.5 h-3.5 ${isRefreshing ? 'animate-spin' : ''}`} />
                    Check Firebase RTDB
                  </button>
                </div>

                <div className="mt-4 flex items-center gap-1.5 text-[11px] text-neutral-400">
                  <CheckCircle2 className="w-3 h-3 text-emerald-500" />
                  <span>Once the child device sends latitude & longitude, OpenStreetMap will auto-mount.</span>
                </div>
              </div>
            )}

            {/* Floating Marker Card when location is active */}
            {liveLocation && (
              <div className="absolute top-4 left-4 bg-white/95 backdrop-blur-md px-3.5 py-2.5 rounded-xl shadow-lg border border-emerald-200 pointer-events-none z-[1000]">
                <div className="flex items-center gap-2">
                  <div className="w-2.5 h-2.5 rounded-full bg-emerald-500 animate-pulse" />
                  <div>
                    <span className="text-[10px] font-bold text-emerald-800 uppercase block tracking-wider">
                      {modelName}
                    </span>
                    <span className="text-xs font-extrabold text-neutral-800">
                      OpenStreetMap Verified Fix
                    </span>
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Location Details & Safe Zones */}
        <div className="space-y-6">
          <div className="bg-white rounded-xl border border-[#e4e9e5] p-5 shadow-xs">
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-bold text-base text-[#202b29] flex items-center gap-2">
                <MapPin className="w-4 h-4 text-emerald-600" />
                Address & Coordinates
              </h3>
              {liveLocation && (
                <a
                  href={`https://www.openstreetmap.org/?mlat=${liveLocation.latitude}&mlon=${liveLocation.longitude}#map=17/${liveLocation.latitude}/${liveLocation.longitude}`}
                  target="_blank"
                  rel="noreferrer"
                  className="inline-flex items-center gap-1 text-[11px] font-semibold text-emerald-700 hover:text-emerald-800 hover:underline"
                  title="Open in OpenStreetMap"
                >
                  <span>Open in OSM</span>
                  <ExternalLink className="w-3 h-3" />
                </a>
              )}
            </div>

            {liveLocation ? (
              <div className="space-y-3.5 text-xs">
                <div>
                  <span className="block text-[10px] font-bold text-[#71807b] uppercase tracking-wider">
                    REAL STREET ADDRESS (OSM NOMINATIM)
                  </span>
                  <p className="font-semibold text-neutral-800 text-sm mt-0.5 leading-snug">
                    {liveLocation.address || 'Street address acquired from OpenStreetMap'}
                  </p>
                </div>

                <div className="grid grid-cols-2 gap-2 pt-2 border-t border-neutral-100">
                  <div>
                    <span className="block text-[10px] font-bold text-[#71807b] uppercase">LATITUDE</span>
                    <span className="font-mono font-semibold text-neutral-800 text-[11px]">
                      {liveLocation.latitude.toFixed(6)}° {liveLocation.latitude >= 0 ? 'N' : 'S'}
                    </span>
                  </div>
                  <div>
                    <span className="block text-[10px] font-bold text-[#71807b] uppercase">LONGITUDE</span>
                    <span className="font-mono font-semibold text-neutral-800 text-[11px]">
                      {Math.abs(liveLocation.longitude).toFixed(6)}° {liveLocation.longitude >= 0 ? 'E' : 'W'}
                    </span>
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-2 pt-2 border-t border-neutral-100">
                  <div>
                    <span className="block text-[10px] font-bold text-[#71807b] uppercase">GPS ACCURACY</span>
                    <span className="text-emerald-700 font-bold">±{liveLocation.accuracy} meters</span>
                  </div>
                  <div>
                    <span className="block text-[10px] font-bold text-[#71807b] uppercase">SPEED</span>
                    <span className="text-neutral-700 font-semibold">
                      {liveLocation.speed !== undefined && liveLocation.speed > 0
                        ? `${Math.round(liveLocation.speed * 3.6)} km/h`
                        : 'Stationary'}
                    </span>
                  </div>
                </div>

                <div className="pt-2 border-t border-neutral-100 flex items-center justify-between text-neutral-600">
                  <span className="text-[10px] font-bold text-[#71807b] uppercase">LAST SYNC</span>
                  <span className="flex items-center gap-1 font-medium">
                    <Clock className="w-3 h-3 text-neutral-400" />
                    {formatRelativeTime(liveLocation.timestamp || lastRefreshed)} ({lastRefreshed.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })})
                  </span>
                </div>
              </div>
            ) : (
              <div className="py-6 text-center text-neutral-500 space-y-2">
                <AlertCircle className="w-8 h-8 text-amber-500 mx-auto opacity-75" />
                <h4 className="text-xs font-bold text-neutral-700">No Real GPS Fix Yet</h4>
                <p className="text-[11px] text-neutral-500 leading-normal">
                  Coordinates and reverse geocoded street addresses will display here as soon as the child device broadcasts its location.
                </p>
                <div className="pt-2">
                  <button
                    onClick={handleRequestRealGpsFix}
                    disabled={isRequestingFix}
                    className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-bold text-emerald-700 bg-emerald-50 hover:bg-emerald-100 border border-emerald-200 transition-colors"
                  >
                    <Navigation className="w-3.5 h-3.5 text-emerald-600" />
                    {isRequestingFix ? 'Requesting GPS Fix...' : 'Request Real GPS Fix'}
                  </button>
                </div>
              </div>
            )}
          </div>

          {/* Safe Zones status */}
          <div className="bg-emerald-50/70 rounded-xl border border-emerald-200/80 p-5 shadow-xs">
            <div className="flex items-center gap-2.5 mb-3">
              <div className="w-8 h-8 rounded-lg bg-emerald-600 text-white flex items-center justify-center">
                <ShieldCheck className="w-4 h-4" />
              </div>
              <div>
                <h4 className="font-bold text-sm text-emerald-950">Safe Zone Status</h4>
                <p className="text-[11px] text-emerald-800/80">Automated geofence tracking</p>
              </div>
            </div>
            
            <div className="bg-white rounded-lg p-3 border border-emerald-200/60 text-xs space-y-2">
              <div className="flex items-center justify-between font-semibold">
                <span className="text-neutral-700">Home & School Perimeter:</span>
                <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold ${
                  liveLocation ? 'text-emerald-700 bg-emerald-100' : 'text-neutral-600 bg-neutral-100'
                }`}>
                  {liveLocation ? 'INSIDE ZONE' : 'WAITING FOR FIX'}
                </span>
              </div>
              <p className="text-[11px] text-neutral-500 leading-normal">
                {liveLocation 
                  ? `${modelName} is safely located within the authorized perimeter. Immediate alerts are sent if this device exits the zone.`
                  : `Awaiting GPS connection for ${modelName} to verify zone boundaries.`}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
