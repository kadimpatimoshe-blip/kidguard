import React, { useState, useEffect } from 'react';
import { 
  X, 
  Smartphone, 
  CheckCircle2, 
  AlertCircle, 
  Loader2, 
  Database, 
  Wifi, 
  ShieldCheck,
  ArrowRight,
  Search,
  Check
} from 'lucide-react';
import { ParentChildDevice } from '../types';
import { searchAndVerifyChildDevice, DeviceVerificationResult } from '../services/firebase';

interface AddChildModalProps {
  onClose: () => void;
  onPair: (code: string, modelName: string) => Promise<ParentChildDevice>;
}

export const AddChildModal: React.FC<AddChildModalProps> = ({ onClose, onPair }) => {
  const [code, setCode] = useState('');
  const [modelName, setModelName] = useState('');
  const [isSearching, setIsSearching] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [searchResult, setSearchResult] = useState<DeviceVerificationResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pairedDevice, setPairedDevice] = useState<ParentChildDevice | null>(null);

  // Auto-search when a full code (e.g. FG-XXXXXX or 6 digits) is entered
  useEffect(() => {
    const clean = code.trim().toUpperCase();
    if (clean.length >= 6) {
      handleSearch(clean);
    } else {
      setSearchResult(null);
      setError(null);
    }
  }, [code]);

  const handleSearch = async (cleanCode: string) => {
    setIsSearching(true);
    setError(null);
    try {
      const result = await searchAndVerifyChildDevice(cleanCode);
      setSearchResult(result);
      if (!modelName) {
        setModelName(result.deviceModelName);
      }
    } catch (err: any) {
      setError(err.message || 'Error searching /devices/' + cleanCode);
      setSearchResult(null);
    } finally {
      setIsSearching(false);
    }
  };

  const handleLink = async (e: React.FormEvent) => {
    e.preventDefault();
    const cleanCode = code.trim().toUpperCase();
    if (!cleanCode || cleanCode.length < 6) {
      setError('Please enter a valid binding code (e.g. FG-XXXXXX).');
      return;
    }

    setIsSubmitting(true);
    setError(null);

    try {
      const finalModelName = modelName.trim() || searchResult?.deviceModelName || `Android Device (${cleanCode})`;
      const device = await onPair(cleanCode, finalModelName);
      setPairedDevice(device);
    } catch (err: any) {
      setError(err.message || 'Could not verify or link device in Firebase RTDB.');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-xs animate-in fade-in">
      <div className="bg-white rounded-2xl border border-[#e4e9e5] p-6 max-w-md w-full shadow-2xl relative">
        <button
          onClick={onClose}
          className="absolute top-4 right-4 p-1.5 rounded-lg text-neutral-400 hover:text-neutral-600 hover:bg-neutral-100 transition-colors"
        >
          <X className="w-5 h-5" />
        </button>

        {pairedDevice ? (
          <div className="text-center py-2 space-y-4">
            <div className="w-14 h-14 rounded-full bg-emerald-100 text-emerald-600 flex items-center justify-center mx-auto shadow-sm">
              <CheckCircle2 className="w-8 h-8" />
            </div>

            <div>
              <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-bold bg-emerald-100 text-emerald-800 border border-emerald-300 mb-2">
                <span className="w-2 h-2 rounded-full bg-emerald-600 animate-pulse"></span>
                Status: Online / Synced
              </span>
              <h3 className="text-xl font-extrabold text-neutral-900">
                {pairedDevice.deviceModelName || 'Child Device'}
              </h3>
              <p className="text-xs text-neutral-500 mt-1">
                Verified via <code className="text-neutral-700 font-semibold bg-neutral-100 px-1 py-0.5 rounded">/devices/{pairedDevice.pairingCode}</code> and linked to Parent Console.
              </p>
            </div>

            <div className="bg-neutral-50 rounded-xl p-3 border border-neutral-200 text-left text-xs space-y-2">
              <div className="flex justify-between items-center">
                <span className="text-neutral-500 font-medium">Child Device ID:</span>
                <span className="font-mono font-bold text-neutral-800">{pairedDevice.childId}</span>
              </div>
              <div className="flex justify-between items-center">
                <span className="text-neutral-500 font-medium">Firebase RTDB Node:</span>
                <span className="font-mono text-emerald-700 bg-emerald-50 px-1.5 py-0.5 rounded border border-emerald-200 font-bold">
                  /devices/{pairedDevice.pairingCode}
                </span>
              </div>
              <div className="flex justify-between items-center">
                <span className="text-neutral-500 font-medium">Realtime Presence:</span>
                <span className="font-semibold text-emerald-600 flex items-center gap-1">
                  <Wifi className="w-3 h-3" />
                  Live Synced
                </span>
              </div>
            </div>

            <button
              onClick={onClose}
              className="w-full py-2.5 rounded-xl font-bold text-xs bg-[#0a9b70] hover:bg-[#087957] text-white transition-colors shadow-xs flex items-center justify-center gap-2"
            >
              Done & Open in Parent Console
              <ArrowRight className="w-4 h-4" />
            </button>
          </div>
        ) : (
          <form onSubmit={handleLink} className="space-y-4">
            <div className="text-center mb-4">
              <div className="w-12 h-12 rounded-xl bg-emerald-50 text-emerald-700 flex items-center justify-center mx-auto mb-2 border border-emerald-100 shadow-xs">
                <Smartphone className="w-6 h-6" />
              </div>
              <h3 className="text-xl font-extrabold text-[#202b29]">Add Child Device</h3>
              <p className="text-xs text-[#71807b] mt-1">
                Enter the binding code (e.g. <strong>FG-XXXXXX</strong>) displayed on your child's device. 
                <span className="block mt-1 font-bold text-amber-600">Note: This will replace your current linked device.</span>
              </p>
            </div>

            {error && (
              <div className="p-3 rounded-lg bg-rose-50 border border-rose-200 text-xs text-rose-700 flex items-center gap-2">
                <AlertCircle className="w-4 h-4 shrink-0 text-rose-600" />
                <span>{error}</span>
              </div>
            )}

            <div>
              <div className="flex items-center justify-between mb-1">
                <label className="text-xs font-bold text-neutral-700">
                  Child Binding Code (ID)
                </label>
                <span className="text-[11px] text-neutral-400">
                  Example: FG-ABCDEF
                </span>
              </div>

              <div className="flex items-center gap-2">
                <div className="relative flex-1">
                  <input
                    type="text"
                    maxLength={12}
                    autoFocus
                    placeholder="FG-ABCDEF"
                    value={code}
                    onChange={(e) => setCode(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter' && code.length >= 6) {
                        e.preventDefault();
                        handleSearch(code.trim().toUpperCase());
                      }
                    }}
                    className="w-full h-12 text-center font-mono font-bold text-xl tracking-[0.1em] bg-neutral-50 border border-[#e4e9e5] rounded-xl focus:border-[#0a9b70] focus:ring-2 focus:ring-emerald-100 outline-none text-neutral-900"
                  />
                  {isSearching && (
                    <div className="absolute right-3 top-1/2 -translate-y-1/2 text-emerald-600 flex items-center gap-1 text-xs">
                      <Loader2 className="w-4 h-4 animate-spin" />
                    </div>
                  )}
                </div>

                <button
                  type="button"
                  onClick={() => code.length >= 4 && handleSearch(code.trim().replace(/\D/g, ''))}
                  disabled={isSearching || code.length < 4}
                  className="h-12 px-4 rounded-xl border border-neutral-300 bg-neutral-100 hover:bg-neutral-200 text-neutral-700 font-bold text-xs flex items-center gap-1.5 transition-colors disabled:opacity-40 shrink-0"
                  title="Search Firebase RTDB /devices/{pairingCode}"
                >
                  <Search className="w-3.5 h-3.5 text-neutral-500" />
                  Search RTDB
                </button>
              </div>
            </div>

            {/* Active RTDB Search Result Card */}
            {searchResult && (
              <div className="p-3.5 bg-emerald-50/90 rounded-xl border border-emerald-200 text-xs space-y-2 animate-in fade-in">
                <div className="flex items-center justify-between">
                  <span className="font-bold text-emerald-900 flex items-center gap-1.5">
                    <Database className="w-4 h-4 text-emerald-700 shrink-0" />
                    Verified: {searchResult.rtdbPath}
                  </span>
                  <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-200 text-emerald-900 flex items-center gap-1">
                    <span className="w-1.5 h-1.5 rounded-full bg-emerald-600 animate-pulse"></span>
                    Ready to Sync
                  </span>
                </div>
                <div className="text-neutral-700 space-y-1 pt-1 border-t border-emerald-200/60 text-[11px]">
                  <div className="flex justify-between">
                    <span className="text-neutral-500">Device Model:</span>
                    <span className="font-bold text-neutral-900">{searchResult.deviceModelName}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-neutral-500">Firebase Node:</span>
                    <span className="font-mono text-emerald-800 font-semibold">{searchResult.rtdbPath}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-neutral-500">Pairing Status:</span>
                    <span className="capitalize font-semibold text-emerald-700">Online & Ready to Link</span>
                  </div>
                </div>
              </div>
            )}

            <div>
              <label className="block text-xs font-bold text-neutral-700 mb-1">
                Custom Child Label (Optional)
              </label>
              <input
                type="text"
                placeholder={searchResult?.deviceModelName || "e.g. Liam's Phone"}
                value={modelName}
                onChange={(e) => setModelName(e.target.value)}
                className="w-full h-10 px-3 text-xs bg-neutral-50 border border-[#e4e9e5] rounded-xl focus:border-[#0a9b70] focus:ring-2 focus:ring-emerald-100 outline-none text-neutral-900"
              />
            </div>

            <div className="pt-2">
              <button
                type="submit"
                disabled={isSubmitting || !code || code.length < 4}
                className="w-full h-11 rounded-xl text-xs font-bold bg-[#0a9b70] hover:bg-[#087957] text-white flex items-center justify-center gap-2 transition-colors disabled:opacity-50 shadow-xs"
              >
                {isSubmitting ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin" />
                    Linking /devices/{code} to Console…
                  </>
                ) : (
                  <>
                    <ShieldCheck className="w-4 h-4" />
                    Verify & Link Device {code ? `(${code})` : ''}
                  </>
                )}
              </button>
            </div>

            <div className="pt-2 border-t border-neutral-100 text-[11px] text-neutral-400 text-center leading-normal">
              Queries Firebase RTDB <code className="text-neutral-600 bg-neutral-100 px-1 rounded">/devices/{code || '3819'}</code>, verifies child presence, and updates status to <strong>Online/Synced</strong>.
            </div>
          </form>
        )}
      </div>
    </div>
  );
};
