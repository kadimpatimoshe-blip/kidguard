import React, { useState, useEffect, useMemo } from 'react';
import { 
  BarChart3, 
  Smartphone, 
  Clock, 
  TrendingUp, 
  AlertTriangle, 
  Sparkles,
  Shield,
  Video,
  PlaySquare,
  Tv,
  MessageSquare,
  Gamepad2,
  Globe,
  Music,
  BookOpen,
  Camera,
  Phone,
  Layers,
  RefreshCw,
  CheckCircle2,
  Activity,
  Trash2,
  Send
} from 'lucide-react';
import { ParentChildDevice, AppUsageItem } from '../types';
import { subscribeToChildAppUsage, updateChildAppUsage } from '../services/firebase';

interface AppUsageViewProps {
  devices: ParentChildDevice[];
  selectedDevice: ParentChildDevice | null;
  onSelectDevice: (device: ParentChildDevice) => void;
}

/**
 * Renders an app icon using image URL or a styled icon fallback matching app category
 */
const RenderAppIcon: React.FC<{ 
  icon?: string; 
  appName: string; 
  color?: string; 
  category?: string;
}> = ({ icon, appName, color = '#6366F1' }) => {
  const [imageError, setImageError] = useState(false);

  if (icon && (icon.startsWith('http://') || icon.startsWith('https://') || icon.startsWith('data:')) && !imageError) {
    return (
      <img
        src={icon}
        alt={appName}
        onError={() => setImageError(true)}
        className="w-10 h-10 rounded-xl object-contain p-1 border border-neutral-100 bg-white shadow-xs shrink-0"
      />
    );
  }

  const iconName = (icon || '').toLowerCase();
  const nameLower = (appName || '').toLowerCase();

  const getIconComponent = () => {
    if (iconName.includes('youtube') || nameLower.includes('youtube')) return <PlaySquare className="w-5 h-5 text-white" />;
    if (iconName.includes('video') || iconName.includes('tv') || nameLower.includes('tiktok') || nameLower.includes('netflix')) return <Tv className="w-5 h-5 text-white" />;
    if (iconName.includes('message') || iconName.includes('chat') || nameLower.includes('whatsapp') || nameLower.includes('telegram')) return <MessageSquare className="w-5 h-5 text-white" />;
    if (iconName.includes('game') || iconName.includes('gamepad') || nameLower.includes('roblox') || nameLower.includes('free fire') || nameLower.includes('minecraft')) return <Gamepad2 className="w-5 h-5 text-white" />;
    if (iconName.includes('globe') || iconName.includes('browser') || nameLower.includes('chrome') || nameLower.includes('firefox')) return <Globe className="w-5 h-5 text-white" />;
    if (iconName.includes('music') || nameLower.includes('spotify') || nameLower.includes('audio')) return <Music className="w-5 h-5 text-white" />;
    if (iconName.includes('book') || nameLower.includes('duolingo') || nameLower.includes('learn')) return <BookOpen className="w-5 h-5 text-white" />;
    if (iconName.includes('camera') || iconName.includes('photo') || nameLower.includes('instagram') || nameLower.includes('snapchat')) return <Camera className="w-5 h-5 text-white" />;
    if (iconName.includes('phone') || nameLower.includes('call')) return <Phone className="w-5 h-5 text-white" />;
    return <Smartphone className="w-5 h-5 text-white" />;
  };

  return (
    <div
      className="w-10 h-10 rounded-xl flex items-center justify-center shrink-0 shadow-xs"
      style={{ backgroundColor: color || '#6366F1' }}
    >
      {getIconComponent()}
    </div>
  );
};

export const AppUsageView: React.FC<AppUsageViewProps> = ({
  devices,
  selectedDevice,
  onSelectDevice,
}) => {
  const currentDevice = selectedDevice || devices[0];

  const pairingCode = useMemo(() => {
    if (!currentDevice) return '';
    return (currentDevice.pairingCode || currentDevice.childId?.replace('child_', '') || currentDevice.deviceId || '').trim();
  }, [currentDevice]);

  // Real-time app usage state from Firebase RTDB
  const [appUsage, setAppUsage] = useState<AppUsageItem[]>([]);
  const [isListening, setIsListening] = useState(false);
  const [lastSyncTime, setLastSyncTime] = useState<Date | null>(null);
  const [hasLoadedInitial, setHasLoadedInitial] = useState(false);

  // Subscribe to real-time app usage from Firebase RTDB under /devices/{pairingCode}/appUsage
  useEffect(() => {
    if (!pairingCode) {
      setAppUsage([]);
      setHasLoadedInitial(true);
      return;
    }

    setHasLoadedInitial(false);
    setIsListening(true);

    const unsubscribe = subscribeToChildAppUsage(
      pairingCode,
      (liveUsage) => {
        setAppUsage(liveUsage || []);
        setLastSyncTime(new Date());
        setHasLoadedInitial(true);
      },
      (err) => {
        console.warn('App usage listener warning:', err);
        setHasLoadedInitial(true);
      }
    );

    return () => {
      unsubscribe();
      setIsListening(false);
    };
  }, [pairingCode]);

  // Helper to clear usage data in Firebase RTDB
  const handleClearAppUsage = async () => {
    if (!pairingCode) return;
    try {
      await updateChildAppUsage(pairingCode, []);
      setAppUsage([]);
    } catch (err) {
      console.error('Failed to clear app usage in Firebase RTDB:', err);
    }
  };

  if (!currentDevice) {
    return (
      <div className="bg-white rounded-2xl border border-[#e4e9e5] p-12 text-center text-neutral-500 shadow-xs">
        <BarChart3 className="w-12 h-12 text-neutral-300 mx-auto mb-3" />
        <h3 className="text-base font-bold text-neutral-800">No Paired Devices</h3>
        <p className="text-xs text-neutral-500 mt-1">Pair a device to monitor real-time app usage statistics.</p>
      </div>
    );
  }

  // Calculate statistics
  const totalHours = appUsage.reduce((acc, curr) => acc + (Number(curr?.hoursUsed) || 0), 0);
  const totalHoursFloor = Math.floor(totalHours);
  const totalMinutesRemainder = Math.round((totalHours % 1) * 60);
  const maxHours = Math.max(...appUsage.map(a => Number(a?.hoursUsed) || 0), 4);
  const mostUsedApp = appUsage.length > 0 ? appUsage[0] : null;

  // Group by category for insight
  const categorySummary = useMemo(() => {
    const summary: Record<string, number> = {};
    appUsage.forEach((item) => {
      const cat = item.category || 'Other';
      summary[cat] = (summary[cat] || 0) + (Number(item.hoursUsed) || 0);
    });
    return Object.entries(summary).sort((a, b) => b[1] - a[1]);
  }, [appUsage]);

  const topCategory = categorySummary.length > 0 ? categorySummary[0] : null;

  return (
    <div className="space-y-6">
      {/* Top Device Bar & Firebase Realtime Status */}
      <div className="bg-white rounded-2xl border border-[#e4e9e5] p-4 flex flex-wrap items-center justify-between gap-4 shadow-xs">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-orange-50 text-orange-700 flex items-center justify-center shrink-0 border border-orange-100">
            <BarChart3 className="w-5 h-5" />
          </div>
          <div>
            <label className="block text-[10px] font-bold text-[#71807b] uppercase tracking-wider">
              SELECT CHILD DEVICE
            </label>
            <select
              value={currentDevice.childId}
              onChange={(e) => {
                const dev = devices.find((d) => d.childId === e.target.value);
                if (dev) onSelectDevice(dev);
              }}
              className="font-bold text-sm text-[#202b29] bg-transparent border-none outline-none cursor-pointer focus:ring-0 pr-6"
            >
              {devices.map((d) => (
                <option key={d.childId} value={d.childId}>
                  {d.deviceModelName || `Device ${d.childId.slice(0, 8)}`} (Code: {d.pairingCode || 'N/A'})
                </option>
              ))}
            </select>
          </div>
        </div>

        {/* Live RTDB Sync Status Banner */}
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2 bg-emerald-50 border border-emerald-200/80 px-3 py-1.5 rounded-full text-xs text-emerald-800">
            <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
            <span className="font-semibold">RTDB Live Sync:</span>
            <span className="font-mono text-[11px] text-emerald-700">/devices/{pairingCode}/appUsage</span>
          </div>

          <div className="text-right pl-2 border-l border-neutral-100 hidden sm:block">
            <span className="text-[10px] font-bold text-[#71807b] uppercase block">TOTAL SCREEN TIME</span>
            <span className="text-base font-extrabold text-[#202b29] block">
              {appUsage.length > 0 ? `${totalHoursFloor}h ${totalMinutesRemainder}m` : '0h 0m'}
            </span>
          </div>
        </div>
      </div>

      {/* Main Content Area: Either Empty State or Real-time Usage Dashboards */}
      {hasLoadedInitial && appUsage.length === 0 ? (
        /* Empty State: Prompt explicitly requested: "If no usage data is sent from the child device yet, display 'No app usage data reported today" */
        <div className="bg-white rounded-2xl border border-[#e4e9e5] p-12 text-center shadow-xs">
          <div className="w-16 h-16 rounded-2xl bg-orange-50 text-orange-600 flex items-center justify-center mx-auto mb-4 border border-orange-100 shadow-xs">
            <BarChart3 className="w-8 h-8" />
          </div>
          
          <h3 className="text-lg font-extrabold text-neutral-800">No app usage data reported today</h3>
          
          <p className="text-xs text-neutral-500 max-w-md mx-auto mt-2 leading-relaxed">
            KidGuard is actively listening to real-time telemetry from Firebase Realtime Database at{' '}
            <code className="bg-neutral-100 text-neutral-800 px-1.5 py-0.5 rounded text-[11px] font-mono border border-neutral-200">
              /devices/{pairingCode}/appUsage
            </code>.
            As soon as apps are launched on the child device, live usage duration, categories, and icons will update here automatically.
          </p>

          <div className="mt-8 pt-6 border-t border-neutral-100 flex items-center justify-center gap-2 text-[11px] text-neutral-400">
            <Activity className="w-3.5 h-3.5 text-emerald-500" />
            <span>Real-time listener connected & waiting for background telemetry sync</span>
          </div>
        </div>
      ) : (
        /* Real-time App Usage Dashboard */
        <div className="space-y-6">
          {/* Quick Metrics Bar */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="bg-white rounded-xl border border-[#e4e9e5] p-4 shadow-xs">
              <div className="flex items-center justify-between text-neutral-400 mb-1">
                <span className="text-[10px] font-bold uppercase tracking-wider">Screen Time</span>
                <Clock className="w-4 h-4 text-emerald-600" />
              </div>
              <p className="text-xl font-extrabold text-neutral-900">
                {totalHoursFloor}h {totalMinutesRemainder}m
              </p>
              <span className="text-[10px] font-semibold text-emerald-600 flex items-center gap-1 mt-0.5">
                <CheckCircle2 className="w-3 h-3" /> Live RTDB total
              </span>
            </div>

            <div className="bg-white rounded-xl border border-[#e4e9e5] p-4 shadow-xs">
              <div className="flex items-center justify-between text-neutral-400 mb-1">
                <span className="text-[10px] font-bold uppercase tracking-wider">Active Apps</span>
                <Smartphone className="w-4 h-4 text-blue-600" />
              </div>
              <p className="text-xl font-extrabold text-neutral-900">{appUsage.length} Apps</p>
              <span className="text-[10px] font-semibold text-neutral-500">Tracked today</span>
            </div>

            <div className="bg-white rounded-xl border border-[#e4e9e5] p-4 shadow-xs">
              <div className="flex items-center justify-between text-neutral-400 mb-1">
                <span className="text-[10px] font-bold uppercase tracking-wider">Top App</span>
                <TrendingUp className="w-4 h-4 text-purple-600" />
              </div>
              <p className="text-xl font-extrabold text-neutral-900 truncate" title={mostUsedApp?.appName}>
                {mostUsedApp?.appName || 'N/A'}
              </p>
              <span className="text-[10px] font-semibold text-purple-700 truncate block">
                {mostUsedApp ? (mostUsedApp.durationText || `${mostUsedApp.hoursUsed}h`) : '0m'}
              </span>
            </div>

            <div className="bg-white rounded-xl border border-[#e4e9e5] p-4 shadow-xs">
              <div className="flex items-center justify-between text-neutral-400 mb-1">
                <span className="text-[10px] font-bold uppercase tracking-wider">Top Category</span>
                <Layers className="w-4 h-4 text-orange-600" />
              </div>
              <p className="text-xl font-extrabold text-neutral-900 truncate" title={topCategory ? topCategory[0] : 'N/A'}>
                {topCategory ? topCategory[0] : 'N/A'}
              </p>
              <span className="text-[10px] font-semibold text-orange-700">
                {topCategory ? `${Math.round((topCategory[1] / (totalHours || 1)) * 100)}% of total` : '0%'}
              </span>
            </div>
          </div>

          {/* Main Visualizations: Dynamic Bar Chart & Detailed App Breakdown */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            {/* Left 2 Cols: Dynamic Bar Chart */}
            <div className="lg:col-span-2 bg-white rounded-2xl border border-[#e4e9e5] p-6 shadow-xs flex flex-col justify-between">
              <div>
                <div className="flex flex-wrap items-center justify-between gap-3 mb-6">
                  <div>
                    <h3 className="font-extrabold text-lg text-[#202b29] flex items-center gap-2">
                      <span>Today's App Screen Time</span>
                      <span className="text-[10px] bg-emerald-100 text-emerald-800 font-bold px-2 py-0.5 rounded-full">
                        REAL-TIME
                      </span>
                    </h3>
                    <p className="text-xs text-[#71807b]">
                      Dynamically rendered from Firebase RTDB at /devices/{pairingCode}/appUsage
                    </p>
                  </div>

                  <div className="flex items-center gap-2">
                    <button
                      onClick={handleClearAppUsage}
                      title="Clear RTDB appUsage"
                      className="px-2.5 py-1 text-[11px] font-semibold bg-red-50 hover:bg-red-100 text-red-600 rounded-lg transition"
                    >
                      Clear Data
                    </button>
                  </div>
                </div>

                {/* Bar Chart Visualization */}
                <div className="h-64 flex items-end justify-around gap-3 pt-8 pb-4 border-b border-neutral-100">
                  {appUsage.map((app) => {
                    const hours = Number(app.hoursUsed) || 0;
                    const heightPercent = Math.max(8, Math.min(100, Math.round((hours / maxHours) * 100)));
                    const durationDisplay = app.durationText || `${hours.toFixed(1)}h`;

                    return (
                      <div key={app.id || app.appName} className="flex-1 flex flex-col items-center h-full justify-end group">
                        {/* Usage Duration Tooltip */}
                        <span className="text-[11px] font-extrabold text-neutral-700 opacity-90 group-hover:scale-110 transition-transform mb-2">
                          {durationDisplay}
                        </span>

                        {/* The Bar */}
                        <div className="w-full max-w-[44px] bg-neutral-100 rounded-t-xl overflow-hidden flex flex-col justify-end h-full">
                          <div
                            style={{ 
                              height: `${heightPercent}%`,
                              backgroundColor: app.color || '#6366F1'
                            }}
                            className="w-full rounded-t-xl transition-all duration-500 shadow-xs hover:brightness-110"
                          />
                        </div>

                        {/* App Icon & Label below */}
                        <div className="flex flex-col items-center mt-3 max-w-[80px]">
                          <div className="w-6 h-6 rounded-md overflow-hidden mb-1">
                            <RenderAppIcon 
                              icon={app.icon} 
                              appName={app.appName} 
                              color={app.color} 
                              category={app.category} 
                            />
                          </div>
                          <span className="text-[11px] font-bold text-neutral-800 truncate w-full text-center" title={app.appName}>
                            {app.appName}
                          </span>
                        </div>
                      </div>
                    );
                  })}
                </div>

                {/* Axis Labels */}
                <div className="flex items-center justify-between text-[11px] text-neutral-400 pt-3">
                  <span>0m</span>
                  <span>1h</span>
                  <span>2h</span>
                  <span>3h</span>
                  <span>{Math.round(maxHours)}h+</span>
                </div>
              </div>

              {lastSyncTime && (
                <div className="mt-4 pt-3 border-t border-neutral-100 flex items-center justify-between text-[11px] text-neutral-400">
                  <span>Last synced: {lastSyncTime.toLocaleTimeString()}</span>
                  <span className="text-emerald-600 font-semibold flex items-center gap-1">
                    <Activity className="w-3 h-3 animate-pulse" /> RTDB Connected
                  </span>
                </div>
              )}
            </div>

            {/* Right Col: Detailed Breakdown List with Name, Category, Icon, and Usage Duration */}
            <div className="bg-white rounded-2xl border border-[#e4e9e5] p-5 shadow-xs flex flex-col justify-between">
              <div>
                <div className="flex items-center justify-between mb-4">
                  <div>
                    <h3 className="font-extrabold text-base text-[#202b29]">App Breakdown</h3>
                    <p className="text-[11px] text-neutral-500">Name, category, icon & usage duration</p>
                  </div>
                  <span className="text-xs font-bold text-neutral-600 bg-neutral-100 px-2 py-0.5 rounded-full">
                    {appUsage.length} Apps
                  </span>
                </div>

                {/* List of Apps */}
                <div className="space-y-3.5 max-h-[380px] overflow-y-auto pr-1">
                  {appUsage.map((app) => {
                    const hours = Number(app.hoursUsed) || 0;
                    const percentage = totalHours > 0 ? Math.round((hours / totalHours) * 100) : 0;
                    const durationDisplay = app.durationText || (hours > 0 ? `${hours.toFixed(1)}h` : `${app.duration || '0m'}`);

                    return (
                      <div 
                        key={app.id || app.appName} 
                        className="p-2.5 rounded-xl border border-neutral-100 hover:border-neutral-200 transition bg-neutral-50/50 hover:bg-white"
                      >
                        <div className="flex items-center justify-between gap-3">
                          {/* App Icon */}
                          <RenderAppIcon 
                            icon={app.icon} 
                            appName={app.appName} 
                            color={app.color} 
                            category={app.category} 
                          />

                          {/* App Name and Category */}
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center justify-between gap-2">
                              <h4 className="font-bold text-xs text-neutral-800 truncate" title={app.appName}>
                                {app.appName}
                              </h4>
                              {/* Usage Duration */}
                              <span className="font-extrabold text-xs text-neutral-900 shrink-0">
                                {durationDisplay}
                              </span>
                            </div>

                            <div className="flex items-center justify-between mt-1 text-[10px]">
                              {/* Category Badge */}
                              <span 
                                className="inline-block px-1.5 py-0.5 rounded font-semibold text-neutral-700 bg-white border border-neutral-200/80 truncate max-w-[130px]"
                                title={app.category || 'General'}
                              >
                                {app.category || 'General'}
                              </span>

                              {/* Percentage */}
                              <span className="font-semibold text-neutral-500">
                                {percentage}% of total
                              </span>
                            </div>
                          </div>
                        </div>

                        {/* Progress Bar for Duration */}
                        <div className="w-full h-1.5 bg-neutral-200/80 rounded-full overflow-hidden mt-2">
                          <div 
                            className="h-full rounded-full transition-all duration-500" 
                            style={{ 
                              width: `${Math.max(4, percentage)}%`, 
                              backgroundColor: app.color || '#6366F1' 
                            }}
                          />
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>

              {/* Parental Insight tip */}
              <div className="mt-5 pt-4 border-t border-neutral-100 text-xs text-neutral-600 flex items-start gap-2 bg-neutral-50 p-3 rounded-xl">
                <Shield className="w-4 h-4 text-emerald-600 shrink-0 mt-0.5" />
                <p className="leading-relaxed text-[11px]">
                  Real-time statistics synced automatically from the child device. To set daily screen time caps, configure restrictions in Parent Settings.
                </p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
