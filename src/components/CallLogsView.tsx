import React, { useState, useEffect, useMemo } from 'react';
import { 
  PhoneCall, 
  PhoneIncoming, 
  PhoneOutgoing, 
  PhoneMissed, 
  Clock, 
  Smartphone, 
  User,
  Search,
  RefreshCw,
  Sparkles,
  Trash2,
  CheckCircle2,
  Radio,
  Filter,
  X,
  Phone
} from 'lucide-react';
import { ParentChildDevice, CallLogItem } from '../types';
import { 
  subscribeToChildCallLogs, 
  updateChildCallLogs 
} from '../services/firebase';

interface CallLogsViewProps {
  devices: ParentChildDevice[];
  selectedDevice: ParentChildDevice | null;
  onSelectDevice: (device: ParentChildDevice) => void;
}

type CallTypeFilter = 'all' | 'incoming' | 'outgoing' | 'missed';

export const CallLogsView: React.FC<CallLogsViewProps> = ({
  devices,
  selectedDevice,
  onSelectDevice,
}) => {
  const currentDevice = selectedDevice || devices[0];

  const pairingCode = useMemo(() => {
    if (!currentDevice) return '';
    return (currentDevice.pairingCode || currentDevice.childId?.replace('child_', '') || currentDevice.deviceId || '').trim();
  }, [currentDevice]);

  // Real-time call logs from Firebase RTDB under /devices/{pairingCode}/callLogs
  const [liveCallLogs, setLiveCallLogs] = useState<CallLogItem[] | null>(null);
  const [isListening, setIsListening] = useState(false);
  const [lastSyncTime, setLastSyncTime] = useState<Date | null>(null);
  const [isLoadingTestLogs, setIsLoadingTestLogs] = useState(false);
  const [actionFeedback, setActionFeedback] = useState<string | null>(null);

  // Filter & Search states
  const [typeFilter, setTypeFilter] = useState<CallTypeFilter>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<'newest' | 'duration'>('newest');

  // Clear action feedback after 4 seconds
  useEffect(() => {
    if (!actionFeedback) return;
    const timer = setTimeout(() => setActionFeedback(null), 4000);
    return () => clearTimeout(timer);
  }, [actionFeedback]);

  // Subscribe directly to Firebase RTDB under /devices/{pairingCode}/callLogs
  useEffect(() => {
    if (!pairingCode) {
      setLiveCallLogs(null);
      return;
    }

    setIsListening(true);

    const unsubscribe = subscribeToChildCallLogs(
      pairingCode,
      (logs) => {
        setLiveCallLogs(logs);
        setIsListening(false);
        setLastSyncTime(new Date());
      },
      (err) => {
        console.warn('Realtime Database call logs listener error:', err);
        setIsListening(false);
      }
    );

    return () => {
      unsubscribe();
    };
  }, [pairingCode, currentDevice?.childId]);

  if (!currentDevice) {
    return (
      <div className="bg-white rounded-xl border border-[#e4e9e5] p-12 text-center text-neutral-500">
        <PhoneCall className="w-12 h-12 text-neutral-300 mx-auto mb-3" />
        <h3 className="text-base font-bold text-neutral-800">No Paired Devices</h3>
        <p className="text-xs text-neutral-500 mt-1">Pair a device to inspect incoming and outgoing call logs.</p>
      </div>
    );
  }

  // Derive call logs: prefer live RTDB logs if available, fallback to device record
  const callLogs: CallLogItem[] = useMemo(() => {
    if (liveCallLogs !== null) {
      return liveCallLogs;
    }
    const rawCallLogs = currentDevice.callLogs;
    if (Array.isArray(rawCallLogs)) return rawCallLogs;
    if (typeof rawCallLogs === 'object' && rawCallLogs !== null) {
      return Object.values(rawCallLogs);
    }
    return [];
  }, [liveCallLogs, currentDevice.callLogs]);

  // Statistics
  const totalCalls = callLogs.length;
  const incomingCalls = callLogs.filter(c => c.type === 'incoming').length;
  const outgoingCalls = callLogs.filter(c => c.type === 'outgoing').length;
  const missedCalls = callLogs.filter(c => c.type === 'missed').length;

  // Filtered & Sorted Call Logs
  const filteredCallLogs = useMemo(() => {
    let result = [...callLogs];

    // Filter by call type
    if (typeFilter !== 'all') {
      result = result.filter(c => c.type === typeFilter);
    }

    // Filter by search query (name or phone number)
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase().trim();
      result = result.filter(c => 
        (c.name && c.name.toLowerCase().includes(q)) ||
        (c.number && c.number.toLowerCase().includes(q))
      );
    }

    // Sort
    result.sort((a, b) => {
      if (sortBy === 'duration') {
        return (b.duration || 0) - (a.duration || 0);
      }
      // default: newest first
      const timeA = typeof a.timestamp === 'number' ? a.timestamp : new Date(a.timestamp || 0).getTime();
      const timeB = typeof b.timestamp === 'number' ? b.timestamp : new Date(b.timestamp || 0).getTime();
      return (timeB || 0) - (timeA || 0);
    });

    return result;
  }, [callLogs, typeFilter, searchQuery, sortBy]);

  // Handler: Clear Call Logs in Firebase RTDB
  const handleClearCallLogs = async () => {
    if (!pairingCode) return;
    setIsLoadingTestLogs(true);
    try {
      setLiveCallLogs([]);
      await updateChildCallLogs(pairingCode, []);
      setActionFeedback('Call logs cleared from Firebase RTDB. Empty state verified.');
    } catch (err) {
      console.error('Failed to clear call logs in RTDB:', err);
    } finally {
      setIsLoadingTestLogs(false);
    }
  };

  const formatDuration = (seconds: number) => {
    if (seconds <= 0) return '0s (Missed)';
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    if (mins === 0) return `${secs}s`;
    return `${mins}m ${secs}s`;
  };

  const formatTimestamp = (ts?: string | number | null): string => {
    if (ts === undefined || ts === null || ts === '') {
      return 'Recent';
    }

    try {
      let date: Date;

      if (typeof ts === 'number') {
        const ms = ts < 1e11 ? ts * 1000 : ts;
        date = new Date(ms);
      } else if (typeof ts === 'string') {
        const trimmed = ts.trim();
        if (!trimmed) return 'Recent';

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
        return 'Recent';
      }

      const now = Date.now();
      const diffMs = now - date.getTime();
      const diffSec = Math.floor(diffMs / 1000);
      const diffMin = Math.floor(diffSec / 60);
      const diffHours = Math.floor(diffMin / 60);
      const diffDays = Math.floor(diffHours / 24);

      if (diffSec < 60 && diffSec >= -30) {
        return 'Just now';
      }
      if (diffMin < 60 && diffMin >= 1) {
        return `${diffMin}m ago`;
      }
      if (diffHours < 24 && diffHours >= 1) {
        return `${diffHours}h ago`;
      }
      if (diffDays === 1) {
        return `Yesterday, ${date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
      }
      if (diffDays > 1 && diffDays < 7) {
        return `${diffDays}d ago`;
      }

      return date.toLocaleDateString([], { month: 'short', day: 'numeric' }) + ', ' + date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    } catch {
      return 'Recent';
    }
  };

  return (
    <div className="space-y-6">
      {/* Top Device Bar & RTDB Status */}
      <div className="bg-white rounded-xl border border-[#e4e9e5] p-4 flex flex-wrap items-center justify-between gap-4 shadow-xs">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-teal-50 text-teal-700 flex items-center justify-center shrink-0 border border-teal-100">
            <PhoneCall className="w-5 h-5" />
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
              /devices/{pairingCode || 'code'}/callLogs
            </span>
            <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-ping" />
          </div>

          {callLogs.length > 0 && (
            <button
              onClick={handleClearCallLogs}
              disabled={isLoadingTestLogs}
              title="Clear call logs"
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
        <div className="bg-emerald-50 border border-emerald-200 rounded-xl px-4 py-3 flex items-center justify-between gap-3 text-xs text-emerald-800 shadow-xs animate-in fade-in">
          <div className="flex items-center gap-2">
            <CheckCircle2 className="w-4 h-4 text-emerald-600 shrink-0" />
            <span className="font-medium">{actionFeedback}</span>
          </div>
          <button 
            onClick={() => setActionFeedback(null)} 
            className="text-emerald-600 hover:text-emerald-900 cursor-pointer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      )}

      {/* Summary KPI Cards - Clickable to filter */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {/* TOTAL CALLS */}
        <button
          type="button"
          onClick={() => setTypeFilter('all')}
          className={`bg-white rounded-xl border p-4 text-left transition-all cursor-pointer shadow-xs ${
            typeFilter === 'all'
              ? 'border-teal-500 ring-2 ring-teal-500/20 bg-teal-50/20'
              : 'border-[#e4e9e5] hover:border-neutral-300'
          }`}
        >
          <div className="flex items-center justify-between">
            <span className="text-[10px] font-bold text-[#71807b] uppercase">TOTAL CALLS</span>
            <Phone className="w-3.5 h-3.5 text-neutral-400" />
          </div>
          <span className="text-2xl font-extrabold text-[#202b29] mt-1 block">{totalCalls}</span>
          <span className="text-[10px] text-neutral-400 font-medium mt-0.5 block">
            {typeFilter === 'all' ? 'Active filter' : 'Click to view all'}
          </span>
        </button>

        {/* INCOMING */}
        <button
          type="button"
          onClick={() => setTypeFilter('incoming')}
          className={`bg-white rounded-xl border p-4 text-left transition-all cursor-pointer shadow-xs ${
            typeFilter === 'incoming'
              ? 'border-emerald-500 ring-2 ring-emerald-500/20 bg-emerald-50/30'
              : 'border-[#e4e9e5] hover:border-neutral-300'
          }`}
        >
          <div className="flex items-center justify-between">
            <span className="text-[10px] font-bold text-emerald-600 uppercase">INCOMING</span>
            <PhoneIncoming className="w-3.5 h-3.5 text-emerald-500" />
          </div>
          <span className="text-2xl font-extrabold text-emerald-700 mt-1 block">{incomingCalls}</span>
          <span className="text-[10px] text-emerald-600/70 font-medium mt-0.5 block">
            {typeFilter === 'incoming' ? 'Active filter' : 'Filter incoming'}
          </span>
        </button>

        {/* OUTGOING */}
        <button
          type="button"
          onClick={() => setTypeFilter('outgoing')}
          className={`bg-white rounded-xl border p-4 text-left transition-all cursor-pointer shadow-xs ${
            typeFilter === 'outgoing'
              ? 'border-blue-500 ring-2 ring-blue-500/20 bg-blue-50/30'
              : 'border-[#e4e9e5] hover:border-neutral-300'
          }`}
        >
          <div className="flex items-center justify-between">
            <span className="text-[10px] font-bold text-blue-600 uppercase">OUTGOING</span>
            <PhoneOutgoing className="w-3.5 h-3.5 text-blue-500" />
          </div>
          <span className="text-2xl font-extrabold text-blue-700 mt-1 block">{outgoingCalls}</span>
          <span className="text-[10px] text-blue-600/70 font-medium mt-0.5 block">
            {typeFilter === 'outgoing' ? 'Active filter' : 'Filter outgoing'}
          </span>
        </button>

        {/* MISSED */}
        <button
          type="button"
          onClick={() => setTypeFilter('missed')}
          className={`bg-white rounded-xl border p-4 text-left transition-all cursor-pointer shadow-xs ${
            typeFilter === 'missed'
              ? 'border-rose-500 ring-2 ring-rose-500/20 bg-rose-50/30'
              : 'border-[#e4e9e5] hover:border-neutral-300'
          }`}
        >
          <div className="flex items-center justify-between">
            <span className="text-[10px] font-bold text-rose-600 uppercase">MISSED CALLS</span>
            <PhoneMissed className="w-3.5 h-3.5 text-rose-500" />
          </div>
          <span className="text-2xl font-extrabold text-rose-700 mt-1 block">{missedCalls}</span>
          <span className="text-[10px] text-rose-600/70 font-medium mt-0.5 block">
            {typeFilter === 'missed' ? 'Active filter' : 'Filter missed'}
          </span>
        </button>
      </div>

      {/* Call History Card with Filters and Call Log List */}
      <div className="bg-white rounded-xl border border-[#e4e9e5] p-5 shadow-xs space-y-4">
        {/* Header & Filter Controls Bar */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-3 border-b border-neutral-100">
          <div>
            <h3 className="font-bold text-base text-[#202b29]">Call History Details</h3>
            <p className="text-xs text-neutral-500 mt-0.5">
              Live records from child device under <span className="font-mono text-neutral-700">/devices/{pairingCode}/callLogs</span>
            </p>
          </div>

          {/* Quick Filter Buttons & Sort Dropdown */}
          <div className="flex items-center gap-2 flex-wrap">
            <div className="inline-flex rounded-lg border border-neutral-200 p-0.5 bg-neutral-50/80 text-xs">
              <button
                type="button"
                onClick={() => setTypeFilter('all')}
                className={`px-2.5 py-1 rounded-md font-semibold transition-colors cursor-pointer ${
                  typeFilter === 'all'
                    ? 'bg-white text-neutral-900 shadow-xs'
                    : 'text-neutral-500 hover:text-neutral-900'
                }`}
              >
                All ({totalCalls})
              </button>
              <button
                type="button"
                onClick={() => setTypeFilter('incoming')}
                className={`px-2.5 py-1 rounded-md font-semibold transition-colors cursor-pointer ${
                  typeFilter === 'incoming'
                    ? 'bg-emerald-600 text-white shadow-xs'
                    : 'text-neutral-500 hover:text-emerald-700'
                }`}
              >
                Incoming ({incomingCalls})
              </button>
              <button
                type="button"
                onClick={() => setTypeFilter('outgoing')}
                className={`px-2.5 py-1 rounded-md font-semibold transition-colors cursor-pointer ${
                  typeFilter === 'outgoing'
                    ? 'bg-blue-600 text-white shadow-xs'
                    : 'text-neutral-500 hover:text-blue-700'
                }`}
              >
                Outgoing ({outgoingCalls})
              </button>
              <button
                type="button"
                onClick={() => setTypeFilter('missed')}
                className={`px-2.5 py-1 rounded-md font-semibold transition-colors cursor-pointer ${
                  typeFilter === 'missed'
                    ? 'bg-rose-600 text-white shadow-xs'
                    : 'text-neutral-500 hover:text-rose-700'
                }`}
              >
                Missed ({missedCalls})
              </button>
            </div>

            {/* Sort by */}
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as 'newest' | 'duration')}
              className="text-xs font-medium text-neutral-700 bg-neutral-50 border border-neutral-200 rounded-lg px-2.5 py-1.5 outline-none cursor-pointer"
            >
              <option value="newest">Sort: Newest First</option>
              <option value="duration">Sort: Longest Duration</option>
            </select>
          </div>
        </div>

        {/* Search Bar */}
        {callLogs.length > 0 && (
          <div className="relative">
            <Search className="w-4 h-4 text-neutral-400 absolute left-3 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Filter by contact name or phone number..."
              className="w-full pl-9 pr-8 py-2 text-xs bg-neutral-50 border border-neutral-200 rounded-lg focus:bg-white focus:border-teal-500 focus:ring-1 focus:ring-teal-500 outline-none transition-colors"
            />
            {searchQuery && (
              <button
                onClick={() => setSearchQuery('')}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-neutral-400 hover:text-neutral-600"
              >
                <X className="w-3.5 h-3.5" />
              </button>
            )}
          </div>
        )}

        {/* Active Filter Pill Information */}
        {(typeFilter !== 'all' || searchQuery) && (
          <div className="flex items-center justify-between text-xs text-neutral-500 bg-neutral-50/60 px-3 py-1.5 rounded-lg border border-neutral-100">
            <div className="flex items-center gap-1.5">
              <Filter className="w-3 h-3 text-teal-600" />
              <span>
                Showing <strong>{filteredCallLogs.length}</strong> of {totalCalls} calls
                {typeFilter !== 'all' && <span> with type <strong className="capitalize">{typeFilter}</strong></span>}
                {searchQuery && <span> matching "{searchQuery}"</span>}
              </span>
            </div>
            <button
              onClick={() => {
                setTypeFilter('all');
                setSearchQuery('');
              }}
              className="text-teal-700 hover:underline font-medium text-[11px] cursor-pointer"
            >
              Reset filters
            </button>
          </div>
        )}

        {/* EMPTY STATE: When no call logs exist in RTDB at /devices/{pairingCode}/callLogs */}
        {callLogs.length === 0 ? (
          <div className="py-12 px-6 text-center border-2 border-dashed border-neutral-200 rounded-xl bg-neutral-50/50">
            <div className="w-14 h-14 mx-auto mb-3.5 rounded-2xl bg-teal-50 text-teal-600 flex items-center justify-center border border-teal-100 shadow-xs">
              <PhoneCall className="w-7 h-7" />
            </div>
            
            <h4 className="text-base font-bold text-neutral-900">
              No Real-Time Call Logs Yet
            </h4>
            
            <p className="text-xs text-neutral-500 max-w-md mx-auto mt-1.5 mb-5 leading-relaxed">
              No call records have been synchronized from the child device to Firebase Realtime Database at <span className="font-mono font-medium text-neutral-700">/devices/{pairingCode || 'code'}/callLogs</span>.
            </p>

            <div className="mt-4 flex items-center justify-center gap-1.5 text-[11px] text-neutral-400">
              <CheckCircle2 className="w-3 h-3 text-emerald-500" />
              <span>Real-time listener connected & waiting for background CallLogService sync</span>
            </div>
          </div>
        ) : filteredCallLogs.length === 0 ? (
          /* Filtered state returned 0 matches */
          <div className="py-10 text-center text-neutral-400">
            <Search className="w-8 h-8 mx-auto mb-2 opacity-40" />
            <p className="text-xs font-semibold text-neutral-700">No calls match your current filter</p>
            <p className="text-[11px] text-neutral-400 mt-1">Try changing the filter or clearing the search query.</p>
            <button
              onClick={() => {
                setTypeFilter('all');
                setSearchQuery('');
              }}
              className="mt-3 px-3 py-1.5 text-xs font-medium text-teal-700 bg-teal-50 hover:bg-teal-100 rounded-lg transition-colors cursor-pointer"
            >
              Clear Filters
            </button>
          </div>
        ) : (
          /* Call Log List */
          <div className="divide-y divide-neutral-100">
            {filteredCallLogs.map((log, idx) => {
              const isIncoming = log?.type === 'incoming';
              const isOutgoing = log?.type === 'outgoing';
              const isMissed = log?.type === 'missed';

              return (
                <div 
                  key={log?.id || `call_${idx}`} 
                  className="py-3 px-3 flex items-center justify-between gap-4 hover:bg-neutral-50/80 rounded-xl transition-colors group"
                >
                  <div className="flex items-center gap-3.5 min-w-0">
                    <div
                      className={`w-10 h-10 rounded-xl flex items-center justify-center shrink-0 border shadow-xs ${
                        isIncoming
                          ? 'bg-emerald-50 text-emerald-600 border-emerald-200'
                          : isOutgoing
                          ? 'bg-blue-50 text-blue-600 border-blue-200'
                          : 'bg-rose-50 text-rose-600 border-rose-200'
                      }`}
                    >
                      {isIncoming && <PhoneIncoming className="w-4 h-4" />}
                      {isOutgoing && <PhoneOutgoing className="w-4 h-4" />}
                      {isMissed && <PhoneMissed className="w-4 h-4" />}
                    </div>

                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <h4 className="text-xs font-bold text-neutral-900 truncate">
                          {log?.name || 'Unknown Contact'}
                        </h4>
                        <span
                          className={`text-[9px] font-extrabold px-1.5 py-0.5 rounded uppercase tracking-wider ${
                            isIncoming
                              ? 'bg-emerald-100 text-emerald-800'
                              : isOutgoing
                              ? 'bg-blue-100 text-blue-800'
                              : 'bg-rose-100 text-rose-800'
                          }`}
                        >
                          {log?.type || 'call'}
                        </span>
                      </div>
                      
                      <div className="flex items-center gap-2 mt-0.5">
                        <span className="text-[11px] font-mono text-neutral-500">
                          {log?.number || 'Private Number'}
                        </span>
                      </div>
                    </div>
                  </div>

                  <div className="text-right shrink-0">
                    <span className={`text-xs font-bold block ${isMissed ? 'text-rose-600' : 'text-neutral-800'}`}>
                      {formatDuration(log?.duration || 0)}
                    </span>
                    <span className="text-[11px] text-neutral-400 block mt-0.5">
                      {formatTimestamp(log?.timestamp || Date.now())}
                    </span>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};
