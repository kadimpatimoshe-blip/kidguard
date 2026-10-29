import React, { useState, useEffect, useMemo } from 'react';
import { 
  Bell, 
  Search, 
  MessageSquare, 
  Gamepad2, 
  GraduationCap, 
  Share2, 
  Clock, 
  Smartphone,
  CheckCircle2,
  Radio,
  Sparkles,
  Trash2,
  Loader2,
  Filter,
  X,
  Send,
  AlertTriangle,
  Layers
} from 'lucide-react';
import { ParentChildDevice, NotificationItem } from '../types';
import { 
  subscribeToChildNotifications, 
  updateChildNotifications 
} from '../services/firebase';

interface NotificationsViewProps {
  devices: ParentChildDevice[];
  selectedDevice: ParentChildDevice | null;
  onSelectDevice: (device: ParentChildDevice) => void;
}

type CategoryFilter = 'all' | 'messaging' | 'social' | 'education' | 'game' | 'system';

export const NotificationsView: React.FC<NotificationsViewProps> = ({
  devices,
  selectedDevice,
  onSelectDevice,
}) => {
  const currentDevice = selectedDevice || devices[0];

  const pairingCode = useMemo(() => {
    if (!currentDevice) return '';
    return (currentDevice.pairingCode || currentDevice.childId?.replace('child_', '') || currentDevice.deviceId || '').trim();
  }, [currentDevice]);

  // Real-time notifications state from Firebase RTDB under /devices/{pairingCode}/notifications
  const [liveNotifications, setLiveNotifications] = useState<NotificationItem[] | null>(null);
  const [isListening, setIsListening] = useState(false);
  const [lastSyncTime, setLastSyncTime] = useState<Date | null>(null);
  const [isLoadingTest, setIsLoadingTest] = useState(false);
  const [actionFeedback, setActionFeedback] = useState<string | null>(null);

  // Filters & Search
  const [searchTerm, setSearchTerm] = useState('');
  const [categoryFilter, setCategoryFilter] = useState<CategoryFilter>('all');

  // Clear action feedback after 4 seconds
  useEffect(() => {
    if (!actionFeedback) return;
    const timer = setTimeout(() => setActionFeedback(null), 4000);
    return () => clearTimeout(timer);
  }, [actionFeedback]);

  // Subscribe directly to Firebase RTDB under /devices/{pairingCode}/notifications
  useEffect(() => {
    if (!pairingCode) {
      setLiveNotifications(null);
      return;
    }

    setIsListening(true);

    const unsubscribe = subscribeToChildNotifications(
      pairingCode,
      (liveList) => {
        setLiveNotifications(liveList);
        setIsListening(false);
        setLastSyncTime(new Date());
      },
      (err) => {
        console.warn('Realtime Database notifications listener warning:', err);
        setIsListening(false);
      }
    );

    return () => {
      unsubscribe();
    };
  }, [pairingCode, currentDevice?.childId]);

  if (!currentDevice) {
    return (
      <div className="bg-white rounded-2xl border border-[#e4e9e5] p-12 text-center text-neutral-500 shadow-xs">
        <Bell className="w-12 h-12 text-neutral-300 mx-auto mb-3" />
        <h3 className="text-base font-bold text-neutral-800">No Paired Devices</h3>
        <p className="text-xs text-neutral-500 mt-1">Pair a device to inspect synchronized real-time notifications.</p>
      </div>
    );
  }

  // Derive notifications list: prefer live RTDB snapshot, fallback to current device record
  const notifications: NotificationItem[] = useMemo(() => {
    if (liveNotifications !== null) {
      return liveNotifications;
    }
    const rawNotifications = currentDevice.notifications;
    if (Array.isArray(rawNotifications)) return rawNotifications;
    if (typeof rawNotifications === 'object' && rawNotifications !== null) {
      return Object.values(rawNotifications);
    }
    return [];
  }, [liveNotifications, currentDevice.notifications]);

  // Filtered notifications
  const filtered = useMemo(() => {
    return notifications.filter((item) => {
      if (!item || typeof item !== 'object') return false;
      const appName = String(item.appName || '').toLowerCase();
      const packageName = String(item.packageName || '').toLowerCase();
      const title = String(item.title || '').toLowerCase();
      const text = String(item.text || '').toLowerCase();
      const q = searchTerm.trim().toLowerCase();

      const matchesSearch = !q || appName.includes(q) || packageName.includes(q) || title.includes(q) || text.includes(q);
      const matchesCategory = categoryFilter === 'all' || item.category === categoryFilter;
      return matchesSearch && matchesCategory;
    });
  }, [notifications, searchTerm, categoryFilter]);

  // Category counts
  const messagingCount = notifications.filter(n => n.category === 'messaging').length;
  const socialCount = notifications.filter(n => n.category === 'social').length;
  const eduCount = notifications.filter(n => n.category === 'education').length;
  const gameCount = notifications.filter(n => n.category === 'game').length;

  const getCategoryIcon = (category?: string) => {
    switch (category) {
      case 'messaging': return <MessageSquare className="w-4 h-4 text-emerald-600" />;
      case 'social': return <Share2 className="w-4 h-4 text-pink-600" />;
      case 'game': return <Gamepad2 className="w-4 h-4 text-purple-600" />;
      case 'education': return <GraduationCap className="w-4 h-4 text-blue-600" />;
      default: return <Bell className="w-4 h-4 text-amber-600" />;
    }
  };

  const formatTime = (ts?: string | number | null): string => {
    if (ts === undefined || ts === null || ts === '') {
      return 'Just now';
    }

    try {
      let date: Date;

      if (typeof ts === 'number') {
        const ms = ts < 1e11 ? ts * 1000 : ts;
        date = new Date(ms);
      } else if (typeof ts === 'string') {
        const trimmed = ts.trim();
        if (!trimmed) return 'Just now';
        if (/^\d+$/.test(trimmed)) {
          const num = Number(trimmed);
          const ms = num < 1e11 ? num * 1000 : num;
          date = new Date(ms);
        } else {
          date = new Date(trimmed);
        }
      } else {
        date = new Date(Number(ts));
      }

      if (isNaN(date.getTime())) {
        return 'Just now';
      }

      const now = Date.now();
      const diffMs = now - date.getTime();
      const diffSec = Math.floor(diffMs / 1000);
      const diffMin = Math.floor(diffSec / 60);
      const diffHours = Math.floor(diffMin / 60);
      const diffDays = Math.floor(diffHours / 24);

      if (diffSec < 45 && diffSec >= -30) return 'Just now';
      if (diffMin < 60 && diffMin >= 1) return `${diffMin}m ago`;
      if (diffHours < 24 && diffHours >= 1) return `${diffHours}h ago`;
      if (diffDays === 1) return `Yesterday, ${date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
      if (diffDays > 1 && diffDays < 7) return `${diffDays}d ago`;

      return date.toLocaleDateString([], { month: 'short', day: 'numeric' }) + ', ' + date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } catch {
      return 'Just now';
    }
  };

  // Handler: Clear notifications in Firebase RTDB
  const handleClearNotifications = async () => {
    if (!pairingCode) return;
    setIsLoadingTest(true);
    try {
      await updateChildNotifications(pairingCode, []);
      setLiveNotifications([]);
      setActionFeedback('Cleared notifications in Firebase RTDB');
    } catch (err: any) {
      console.error('Failed to clear notifications in Firebase RTDB:', err);
    } finally {
      setIsLoadingTest(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Top Device Bar & RTDB Sync Status */}
      <div className="bg-white rounded-xl border border-[#e4e9e5] p-4 flex flex-wrap items-center justify-between gap-4 shadow-xs">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-amber-50 text-amber-700 flex items-center justify-center shrink-0 border border-amber-100">
            <Bell className="w-5 h-5" />
          </div>
          <div>
            <label className="block text-[10px] font-bold text-[#71807b] uppercase">SELECT CHILD DEVICE</label>
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
                  {d.deviceModelName || `Device ${d.childId.slice(0, 8)}`} {d.pairingCode ? `(${d.pairingCode})` : ''}
                </option>
              ))}
            </select>
          </div>
        </div>

        {/* RTDB Sync indicator & Controls */}
        <div className="flex items-center gap-2.5 flex-wrap">
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-neutral-50 border border-neutral-200/70 text-xs">
            <Radio className={`w-3.5 h-3.5 ${isListening ? 'text-amber-500 animate-pulse' : 'text-emerald-500'}`} />
            <span className="font-mono text-[11px] text-neutral-600">
              /devices/{pairingCode || 'code'}/notifications
            </span>
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-ping" />
          </div>

          {notifications.length > 0 && (
            <button
              onClick={handleClearNotifications}
              disabled={isLoadingTest}
              title="Clear notifications"
              className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold bg-rose-50 hover:bg-rose-100 text-rose-700 border border-rose-200/60 transition-colors disabled:opacity-50 cursor-pointer"
            >
              <Trash2 className="w-3.5 h-3.5" />
              <span>Clear</span>
            </button>
          )}
        </div>
      </div>

      {/* Action Feedback Banner */}
      {actionFeedback && (
        <div className="bg-emerald-50 border border-emerald-200 text-emerald-800 text-xs px-4 py-2.5 rounded-xl flex items-center justify-between shadow-xs animate-in fade-in">
          <div className="flex items-center gap-2">
            <CheckCircle2 className="w-4 h-4 text-emerald-600 shrink-0" />
            <span className="font-medium">{actionFeedback}</span>
          </div>
          <button
            onClick={() => setActionFeedback(null)}
            className="text-emerald-600 hover:text-emerald-800 font-bold ml-3"
          >
            ×
          </button>
        </div>
      )}

      {/* Quick Summary Cards (when notifications exist) */}
      {notifications.length > 0 && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="bg-white rounded-xl border border-[#e4e9e5] p-4 shadow-xs">
            <span className="text-[10px] font-bold text-[#71807b] uppercase block">TOTAL NOTIFICATIONS</span>
            <div className="flex items-center justify-between mt-1">
              <span className="text-2xl font-extrabold text-[#202b29]">{notifications.length}</span>
              <Bell className="w-4 h-4 text-amber-600" />
            </div>
            <span className="text-[10px] text-emerald-600 font-semibold flex items-center gap-1 mt-0.5">
              <CheckCircle2 className="w-3 h-3" /> Real-time Synced
            </span>
          </div>

          <div className="bg-white rounded-xl border border-[#e4e9e5] p-4 shadow-xs">
            <span className="text-[10px] font-bold text-[#71807b] uppercase block">MESSAGES & CHATS</span>
            <div className="flex items-center justify-between mt-1">
              <span className="text-2xl font-extrabold text-emerald-700">{messagingCount}</span>
              <MessageSquare className="w-4 h-4 text-emerald-600" />
            </div>
            <span className="text-[10px] text-neutral-400">WhatsApp, SMS, Telegram</span>
          </div>

          <div className="bg-white rounded-xl border border-[#e4e9e5] p-4 shadow-xs">
            <span className="text-[10px] font-bold text-[#71807b] uppercase block">SOCIAL & MEDIA</span>
            <div className="flex items-center justify-between mt-1">
              <span className="text-2xl font-extrabold text-pink-700">{socialCount}</span>
              <Share2 className="w-4 h-4 text-pink-600" />
            </div>
            <span className="text-[10px] text-neutral-400">YouTube, Social Media</span>
          </div>

          <div className="bg-white rounded-xl border border-[#e4e9e5] p-4 shadow-xs">
            <span className="text-[10px] font-bold text-[#71807b] uppercase block">EDUCATION & GAMES</span>
            <div className="flex items-center justify-between mt-1">
              <span className="text-2xl font-extrabold text-blue-700">{eduCount + gameCount}</span>
              <GraduationCap className="w-4 h-4 text-blue-600" />
            </div>
            <span className="text-[10px] text-neutral-400">{eduCount} school, {gameCount} gaming</span>
          </div>
        </div>
      )}

      {/* Main Notifications Card */}
      <div className="bg-white rounded-xl border border-[#e4e9e5] p-5 shadow-xs space-y-4">
        {/* Category Filter Pills & Search */}
        <div className="flex flex-wrap items-center justify-between gap-3 pb-3 border-b border-neutral-100">
          <div className="flex flex-wrap items-center gap-1.5">
            {(
              [
                { id: 'all', label: 'All Alerts', count: notifications.length },
                { id: 'messaging', label: 'Messaging', count: messagingCount },
                { id: 'social', label: 'Social', count: socialCount },
                { id: 'education', label: 'Education', count: eduCount },
                { id: 'game', label: 'Games', count: gameCount },
              ] as const
            ).map((cat) => (
              <button
                key={cat.id}
                onClick={() => setCategoryFilter(cat.id)}
                className={`px-3 py-1.5 rounded-lg text-xs font-semibold capitalize transition-colors cursor-pointer ${
                  categoryFilter === cat.id
                    ? 'bg-amber-100 text-amber-900 border border-amber-300'
                    : 'bg-neutral-50 text-neutral-600 hover:bg-neutral-100 border border-neutral-200'
                }`}
              >
                {cat.label} {cat.count > 0 ? `(${cat.count})` : ''}
              </button>
            ))}
          </div>

          {/* Search Box */}
          <div className="relative">
            <Search className="w-4 h-4 text-neutral-400 absolute left-3 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              placeholder="Search notifications…"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="pl-9 pr-3 py-1.5 rounded-lg text-xs bg-neutral-50 border border-neutral-200 focus:outline-none focus:border-amber-500 w-48 md:w-60"
            />
            {searchTerm && (
              <button
                onClick={() => setSearchTerm('')}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-neutral-400 hover:text-neutral-600"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            )}
          </div>
        </div>

        {/* EMPTY STATE: When no notifications exist in RTDB at /devices/{pairingCode}/notifications */}
        {notifications.length === 0 ? (
          <div className="py-12 px-6 text-center border-2 border-dashed border-neutral-200 rounded-xl bg-neutral-50/50">
            <div className="w-14 h-14 mx-auto mb-3.5 rounded-2xl bg-amber-50 text-amber-600 flex items-center justify-center border border-amber-100 shadow-xs">
              <Bell className="w-7 h-7" />
            </div>

            <h4 className="text-base font-bold text-neutral-900">
              No notifications reported today
            </h4>

            <p className="text-xs text-neutral-500 max-w-md mx-auto mt-1.5 mb-5 leading-relaxed">
              KidGuard is actively listening to real-time notification alerts from Firebase Realtime Database at{' '}
              <span className="font-mono font-medium text-neutral-700 bg-neutral-100 px-1 py-0.5 rounded border border-neutral-200">
                /devices/{pairingCode || 'code'}/notifications
              </span>.
              When messages, push alerts, or app notices arrive on the child device, they will automatically appear here.
            </p>

            <div className="mt-4 flex items-center justify-center gap-1.5 text-[11px] text-neutral-400">
              <CheckCircle2 className="w-3 h-3 text-emerald-500" />
              <span>Real-time listener connected & waiting for background NotificationListenerService</span>
            </div>
          </div>
        ) : filtered.length === 0 ? (
          <div className="py-12 text-center text-neutral-400">
            <Bell className="w-8 h-8 mx-auto mb-2 opacity-50" />
            <p className="text-xs font-semibold text-neutral-600">No notifications match your current filter</p>
            <p className="text-[11px] text-neutral-400 mt-1">Try resetting the search query or category filter.</p>
            <button
              onClick={() => {
                setCategoryFilter('all');
                setSearchTerm('');
              }}
              className="mt-3 text-xs text-amber-700 hover:underline font-semibold"
            >
              Reset filters
            </button>
          </div>
        ) : (
          <div className="divide-y divide-neutral-100">
            {filtered.map((item, idx) => (
              <div 
                key={item.id || `notif_${idx}`} 
                className="py-3.5 flex items-start gap-3.5 hover:bg-neutral-50/70 p-2.5 rounded-xl transition-colors group"
              >
                <div className="w-9 h-9 rounded-xl bg-neutral-100 flex items-center justify-center shrink-0 border border-neutral-200 mt-0.5 shadow-2xs">
                  {getCategoryIcon(item.category)}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-xs font-bold text-neutral-900 flex items-center gap-1.5">
                      {item.appName || 'Application'}
                      {item.packageName && (
                        <span className="text-[10px] font-normal text-neutral-400 font-mono">({item.packageName})</span>
                      )}
                      {item.category && (
                        <span className="text-[9px] font-semibold uppercase px-1.5 py-0.5 rounded bg-neutral-100 text-neutral-600 border border-neutral-200">
                          {item.category}
                        </span>
                      )}
                    </span>
                    <span className="text-[11px] text-neutral-400 shrink-0 flex items-center gap-1">
                      <Clock className="w-3 h-3" />
                      {formatTime(item.timestamp)}
                    </span>
                  </div>
                  {item.title && (
                    <h4 className="text-xs font-semibold text-neutral-800 mt-0.5 leading-snug">
                      {item.title}
                    </h4>
                  )}
                  {item.text && (
                    <p className="text-xs text-neutral-600 mt-0.5 line-clamp-2 leading-relaxed">
                      {item.text}
                    </p>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
