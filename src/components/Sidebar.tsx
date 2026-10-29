import React from 'react';
import { 
  Smartphone, 
  Video, 
  MapPin, 
  Cast, 
  Bell, 
  PhoneCall, 
  BarChart3, 
  ShieldCheck
} from 'lucide-react';
import { ConsoleNavSection } from '../types';

interface SidebarProps {
  currentSection: ConsoleNavSection;
  onSelectSection: (section: ConsoleNavSection) => void;
  onlineCount: number;
}

export const Sidebar: React.FC<SidebarProps> = ({
  currentSection,
  onSelectSection,
  onlineCount,
}) => {
  const navItems: { id: ConsoleNavSection; label: string; icon: React.ReactNode; symbol: string }[] = [
    { id: 'devices', label: 'Family Devices', icon: <Smartphone className="w-4 h-4" />, symbol: '▣' },
    { id: 'camera', label: 'Live Camera', icon: <Video className="w-4 h-4" />, symbol: '◉' },
    { id: 'location', label: 'Live Location', icon: <MapPin className="w-4 h-4" />, symbol: '⌖' },
    { id: 'mirroring', label: 'Screen Mirroring', icon: <Cast className="w-4 h-4" />, symbol: '▣' },
    { id: 'notifications', label: 'Notifications', icon: <Bell className="w-4 h-4" />, symbol: '●' },
    { id: 'calls', label: 'Call Logs', icon: <PhoneCall className="w-4 h-4" />, symbol: '☎' },
    { id: 'usage', label: 'App Usage', icon: <BarChart3 className="w-4 h-4" />, symbol: '▤' },
  ];

  return (
    <aside className="w-64 bg-[#1d302b] text-[#f6fbf8] flex flex-col p-6 min-h-screen border-r border-emerald-950/40 select-none">
      {/* Brand */}
      <div className="flex items-center gap-3 px-2 mb-8">
        <div className="w-9 h-9 rounded-xl bg-[#b9efce] text-[#113c2d] flex items-center justify-center font-bold text-lg shadow-sm">
          <ShieldCheck className="w-5 h-5" />
        </div>
        <div>
          <span className="font-extrabold text-lg tracking-tight">Kid<span className="text-[#91d5ad]">Guard</span></span>
          <span className="block text-[10px] text-emerald-300/70 font-semibold uppercase tracking-wider">Parent Console</span>
        </div>
      </div>

      {/* Nav Labels */}
      <p className="text-[10px] font-bold text-[#9aafa6] tracking-wider uppercase px-2 mb-3">
        MONITORING SUITE
      </p>

      {/* Nav links */}
      <nav className="flex flex-col gap-1.5 flex-1">
        {navItems.map((item) => {
          const isActive = currentSection === item.id;
          return (
            <button
              key={item.id}
              onClick={() => onSelectSection(item.id)}
              className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-xs font-medium transition-all text-left cursor-pointer ${
                isActive
                  ? 'bg-[#2d4840] text-white shadow-xs font-semibold'
                  : 'text-[#d9e4df] hover:bg-emerald-900/30 hover:text-white'
              }`}
            >
              <span className={`w-5 h-5 rounded flex items-center justify-center text-xs ${isActive ? 'text-emerald-300' : 'text-emerald-400/70'}`}>
                {item.icon}
              </span>
              <span className="flex-1">{item.label}</span>
              {item.id === 'devices' && onlineCount > 0 && (
                <span className="px-1.5 py-0.5 rounded-full text-[10px] bg-emerald-500/20 text-emerald-300 font-bold border border-emerald-500/30">
                  {onlineCount} live
                </span>
              )}
            </button>
          );
        })}
      </nav>

      {/* Footer Info */}
      <div className="pt-4 border-t border-emerald-900/60 text-xs text-[#bfd0c8]/80 leading-relaxed px-1">
        <div className="flex items-center gap-2 mb-1">
          <span className="w-2 h-2 rounded-full bg-[#7ce0a6] animate-pulse"></span>
          <span className="font-semibold text-emerald-200">Realtime device sync</span>
        </div>
        <p className="text-[11px] text-emerald-400/60">Encrypted WebRTC & RTDB connection</p>
      </div>
    </aside>
  );
};
