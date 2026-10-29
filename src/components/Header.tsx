import React from 'react';
import { Plus, LogOut, User as UserIcon } from 'lucide-react';
import { ConsoleNavSection } from '../types';

interface HeaderProps {
  currentSection: ConsoleNavSection;
  parentEmail: string | null;
  onSignOut: () => void;
  onOpenAuth: () => void;
  onOpenAddChild: () => void;
  deviceCount: number;
}

const sectionTitles: Record<ConsoleNavSection, { title: string; desc: string }> = {
  devices: {
    title: 'Family Devices',
    desc: 'Manage paired child smartphones and tablets and inspect live presence.',
  },
  camera: {
    title: 'Live Camera Streaming',
    desc: 'View real-time high-definition camera feeds and switch front or back lenses.',
  },
  location: {
    title: 'Live GPS Location',
    desc: 'Track real-time location, accuracy radius, and safe-zone boundaries.',
  },
  mirroring: {
    title: 'Screen Mirroring',
    desc: 'View live screen activity to supervise safe browsing and app usage.',
  },
  notifications: {
    title: 'Synced Notifications',
    desc: 'Review incoming alerts, messages, and social media notifications from child devices.',
  },
  calls: {
    title: 'Call Logs & History',
    desc: 'Inspect incoming, outgoing, and missed phone calls with duration details.',
  },
  usage: {
    title: 'App Usage & Screen Time',
    desc: 'Analyze daily hours spent across entertainment, gaming, social, and education apps.',
  },
};

export const Header: React.FC<HeaderProps> = ({
  currentSection,
  parentEmail,
  onSignOut,
  onOpenAuth,
  onOpenAddChild,
  deviceCount,
}) => {
  const meta = sectionTitles[currentSection] || sectionTitles.devices;

  return (
    <header className="flex flex-col md:flex-row md:items-center justify-between gap-4 pb-6 border-b border-[#e4e9e5] mb-8">
      <div>
        <p className="text-[11px] font-bold text-[#0a9b70] tracking-wider uppercase mb-1">
          PARENT CONSOLE / {currentSection.toUpperCase()}
        </p>
        <h1 className="text-2xl md:text-3xl font-extrabold text-[#202b29] tracking-tight">
          {meta.title}
        </h1>
        <p className="text-sm text-[#71807b] mt-1 max-w-xl">
          {meta.desc}
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-3">
        {/* Add Child Button */}
        <button
          onClick={onOpenAddChild}
          disabled={deviceCount >= 5}
          className={`inline-flex items-center gap-1.5 px-4 py-2 rounded-lg text-xs font-bold transition-all shadow-xs ${
            deviceCount >= 5
              ? 'bg-neutral-200 text-neutral-400 cursor-not-allowed'
              : 'bg-[#0a9b70] hover:bg-[#087957] text-white active:scale-98'
          }`}
        >
          <Plus className="w-4 h-4" />
          Add Child Device ({deviceCount}/5)
        </button>

        {/* Auth / Account indicator */}
        {parentEmail ? (
          <div className="flex items-center gap-2 bg-white px-3 py-1.5 rounded-lg border border-[#e4e9e5] text-xs">
            <div className="w-6 h-6 rounded-full bg-emerald-100 text-emerald-800 flex items-center justify-center font-bold text-[11px]">
              {parentEmail[0].toUpperCase()}
            </div>
            <span className="font-medium text-neutral-700 max-w-[140px] truncate" title={parentEmail}>
              {parentEmail}
            </span>
            <button
              onClick={onSignOut}
              className="p-1 hover:text-rose-600 text-neutral-400 transition-colors"
              title="Sign out of Parent Account"
            >
              <LogOut className="w-3.5 h-3.5" />
            </button>
          </div>
        ) : (
          <button
            onClick={onOpenAuth}
            className="inline-flex items-center gap-1.5 px-3 py-2 rounded-lg text-xs font-semibold bg-white hover:bg-neutral-50 text-neutral-800 border border-[#e4e9e5] transition-colors"
          >
            <UserIcon className="w-3.5 h-3.5 text-neutral-600" />
            Sign In
          </button>
        )}
      </div>
    </header>
  );
};
