import React from 'react';
import { 
  Smartphone, 
  Video, 
  MapPin, 
  Trash2, 
  Battery, 
  BatteryCharging, 
  CheckCircle2, 
  Clock, 
  ExternalLink 
} from 'lucide-react';
import { ParentChildDevice } from '../types';

interface DeviceCardProps {
  device: ParentChildDevice;
  onOpenLiveStream: (device: ParentChildDevice) => void;
  onOpenLocation: (device: ParentChildDevice) => void;
  onUnlink: (device: ParentChildDevice) => void;
}

export const DeviceCard: React.FC<DeviceCardProps> = ({
  device,
  onOpenLiveStream,
  onOpenLocation,
  onUnlink,
}) => {
  const modelName = device.deviceModelName || device.telemetry?.deviceModelName || `Device ${device.childId.slice(0, 8)}`;
  const isOnline = device.isOnline;
  const isPending = device.status === 'pending' || device.status === 'unpaired';

  const formatLastSeen = (timestamp?: string | Date) => {
    if (!timestamp) return 'Recently';
    try {
      const date = typeof timestamp === 'string' ? new Date(timestamp) : timestamp;
      const diffMs = Date.now() - date.getTime();
      const diffMins = Math.floor(diffMs / 60000);
      if (diffMins < 1) return 'Just now';
      if (diffMins < 60) return `${diffMins}m ago`;
      const diffHours = Math.floor(diffMins / 60);
      if (diffHours < 24) return `${diffHours}h ago`;
      return date.toLocaleDateString();
    } catch {
      return 'Recently';
    }
  };

  return (
    <article className="bg-white rounded-xl border border-[#e4e9e5] p-5 shadow-xs hover:shadow-md transition-all flex flex-col justify-between group">
      <div>
        {/* Card Top */}
        <div className="flex items-start justify-between gap-3 mb-4">
          <div className="flex items-center gap-3 min-w-0">
            <div className="w-11 h-11 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center shrink-0 border border-blue-100">
              <Smartphone className="w-5 h-5" />
            </div>
            <div className="min-w-0">
              <span className="block text-[10px] font-bold text-[#71807b] tracking-wider uppercase">
                DEVICE MODEL NAME
              </span>
              <h3 className="font-bold text-base text-[#202b29] truncate" title={modelName}>
                {modelName}
              </h3>
            </div>
          </div>

          {/* Status Badge */}
          <span
            className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-[11px] font-bold shrink-0 ${
              device.status === 'regenerated'
                ? 'bg-amber-100 text-amber-900 border border-amber-300'
                : isPending
                ? 'bg-amber-100 text-amber-800'
                : isOnline
                ? 'bg-emerald-100 text-emerald-800'
                : 'bg-neutral-100 text-neutral-600'
            }`}
          >
            <span
              className={`w-1.5 h-1.5 rounded-full ${
                device.status === 'regenerated'
                  ? 'bg-amber-600 animate-ping'
                  : isPending
                  ? 'bg-amber-500'
                  : isOnline
                  ? 'bg-emerald-600 animate-pulse'
                  : 'bg-neutral-400'
              }`}
            />
            {device.status === 'regenerated' ? 'Re-link Needed' : isPending ? 'Pending' : isOnline ? 'Online' : 'Offline'}
          </span>
        </div>

        {/* Device Attributes Grid */}
        <div className="grid grid-cols-2 gap-2.5 py-3 border-y border-neutral-100 text-xs mb-3">
          <div>
            <span className="block text-[10px] font-bold text-[#71807b] uppercase">DEVICE ID</span>
            <span className="font-mono text-[11px] text-neutral-700 truncate block" title={device.deviceId || device.childId}>
              {device.deviceId ? device.deviceId.slice(0, 14) + '...' : device.childId}
            </span>
          </div>

          <div>
            <span className="block text-[10px] font-bold text-[#71807b] uppercase">PAIRING CODE</span>
            <span className="font-mono font-bold text-emerald-800 bg-emerald-50 px-1.5 py-0.5 rounded border border-emerald-200/50 inline-block">
              {device.pairingCode || '—'}
            </span>
          </div>

          <div>
            <span className="block text-[10px] font-bold text-[#71807b] uppercase">PLATFORM & STATE</span>
            <span className="text-neutral-700 capitalize truncate block">
              {device.platform || 'Android'} {device.appState ? `• ${device.appState}` : ''}
            </span>
          </div>

          <div>
            <span className="block text-[10px] font-bold text-[#71807b] uppercase">LAST HEARTBEAT</span>
            <span className="text-neutral-700 flex items-center gap-1">
              <Clock className="w-3 h-3 text-neutral-400" />
              {isOnline ? 'Active now' : formatLastSeen(device.lastHeartbeat || device.lastSeen)}
            </span>
          </div>
        </div>

        {/* Telemetry Summary & Counters Strip */}
        <div className="bg-neutral-50 rounded-lg p-2.5 mb-4 border border-neutral-100 space-y-1.5 text-[11px]">
          <div className="flex items-center justify-between text-neutral-600">
            <div className="flex items-center gap-1.5 font-medium">
              {device.telemetry?.isCharging ? (
                <BatteryCharging className="w-3.5 h-3.5 text-emerald-600" />
              ) : (
                <Battery className="w-3.5 h-3.5 text-neutral-500" />
              )}
              <span>
                {device.telemetry?.batteryLevel !== undefined
                  ? `Battery: ${device.telemetry.batteryLevel}%`
                  : 'Battery: Synced'}
              </span>
              <span className="ml-1 text-[9px] font-bold text-emerald-500 bg-emerald-50 px-1 rounded border border-emerald-100 uppercase tracking-tighter">
                Live
              </span>
            </div>
            <span className="truncate max-w-[150px] text-neutral-500" title={device.location?.address || 'GPS Coordinates'}>
              {device.location?.address
                ? `📍 ${device.location.address.split(',')[0]}`
                : device.location?.latitude !== undefined && device.location?.longitude !== undefined
                ? `📍 ${device.location.latitude.toFixed(2)}°, ${device.location.longitude.toFixed(2)}°`
                : '📍 GPS: Standby'}
            </span>
          </div>

          {/* Quick telemetry counter pills */}
          <div className="flex items-center gap-2 pt-1 border-t border-neutral-200/60 text-[10px] text-neutral-500 font-medium">
            <span className="bg-white px-2 py-0.5 rounded border border-neutral-200">
              📞 {Array.isArray(device.callLogs) ? device.callLogs.length : 0} calls
            </span>
            <span className="bg-white px-2 py-0.5 rounded border border-neutral-200">
              📊 {Array.isArray(device.appUsage) ? device.appUsage.length : 0} apps
            </span>
            <span className="bg-white px-2 py-0.5 rounded border border-neutral-200">
              🔔 {Array.isArray(device.notifications) ? device.notifications.length : 0} alerts
            </span>
          </div>
        </div>
      </div>

      {/* Card Actions */}
      <div className="flex items-center justify-between gap-2 pt-2">
        <div className="flex items-center gap-1.5">
          <button
            onClick={() => onOpenLiveStream(device)}
            disabled={isPending}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-bold bg-[#3979c6] hover:bg-[#2d67aa] text-white transition-colors disabled:opacity-50 shadow-xs"
            title="Open real-time camera streaming with front/back lens toggle"
          >
            <Video className="w-3.5 h-3.5" />
            Live Stream
          </button>

          <button
            onClick={() => onOpenLocation(device)}
            className="inline-flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-xs font-semibold bg-neutral-100 hover:bg-neutral-200 text-neutral-700 transition-colors"
            title="Locate this device"
          >
            <MapPin className="w-3.5 h-3.5 text-neutral-500" />
            GPS
          </button>
        </div>

        <button
          onClick={() => onUnlink(device)}
          className="p-1.5 rounded-lg text-rose-500 hover:bg-rose-50 hover:text-rose-700 transition-colors border border-transparent hover:border-rose-200"
          title={`Remove & Unlink ${modelName}`}
        >
          <Trash2 className="w-4 h-4" />
        </button>
      </div>
    </article>
  );
};
