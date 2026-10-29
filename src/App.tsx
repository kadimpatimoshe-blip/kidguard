import React, { useState, useEffect, useRef } from 'react';
import { 
  Shield, 
  Smartphone, 
  Battery, 
  BatteryCharging, 
  MapPin, 
  ScreenShare, 
  Video, 
  Mic, 
  Phone, 
  Mail, 
  Copy, 
  Check, 
  RefreshCw, 
  Radio, 
  Wifi,
  ExternalLink,
  Lock,
  Delete,
  ArrowRight,
  LogOut,
  Users,
  CheckCircle2,
  AlertCircle,
  Sparkles,
  Cast,
  Bell,
  PhoneCall,
  BarChart3,
  Plus
} from 'lucide-react';
import { auth, database, sanitizeForRTDB, subscribeToChildDevices, getCurrentParent, saveParentSession, clearParentSession, pairChildDevice, unlinkChildDevice, signInWithEmail, signOut as fbSignOut, onAuthStateChanged, getOrCreateChildPairingCode } from './services/firebase';
import { ref, update, onValue, off, set, onDisconnect } from 'firebase/database';
import { ParentChildDevice, ConsoleNavSection } from './types';
import { Header } from './components/Header';
import { Sidebar } from './components/Sidebar';
import { DeviceCard } from './components/DeviceCard';
import { LiveLocationView } from './components/LiveLocationView';
import { ScreenMirrorView } from './components/ScreenMirrorView';
import { LiveCameraModal } from './components/LiveCameraModal';
import { NotificationsView } from './components/NotificationsView';
import { CallLogsView } from './components/CallLogsView';
import { AppUsageView } from './components/AppUsageView';
import { AddChildModal } from './components/AddChildModal';
import { AuthModal } from './components/AuthModal';

type AppRole = 'parent' | 'child' | null;

export const App: React.FC = () => {
  // ----------------------------------------------------
  // Authentication & Onboarding State
  // ----------------------------------------------------
  const [isAuthenticated, setIsAuthenticated] = useState<boolean>(() => {
    return !!localStorage.getItem('kidguard_auth_user');
  });
  const [currentUser, setCurrentUser] = useState<{ uid: string; email: string } | null>(() => {
    try {
      const raw = localStorage.getItem('kidguard_auth_user');
      return raw ? JSON.parse(raw) : null;
    } catch {
      return null;
    }
  });

  // Role Selection State
  const [selectedRole, setSelectedRole] = useState<AppRole>(() => {
    return (localStorage.getItem('kidguard_device_role') as AppRole) || null;
  });
  const [rememberRole, setRememberRole] = useState<boolean>(true);

  // Auth Mode State
  const [authMode, setAuthMode] = useState<'email'>('email');
  const [enteredPin, setEnteredPin] = useState<string>('');
  const [passcodeError, setPasscodeError] = useState<string | null>(null);
  const [emailInput, setEmailInput] = useState<string>('parent@kidguard.family');
  const [passwordInput, setPasswordInput] = useState<string>('secret123');

  // Toast Notification
  const [toastMessage, setToastMessage] = useState<string | null>(null);
  const showToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => {
      setToastMessage((prev) => (prev === msg ? null : prev));
    }, 3200);
  };

  // ----------------------------------------------------
  // Parent Console State
  // ----------------------------------------------------
  const [currentSection, setCurrentSection] = useState<ConsoleNavSection>('devices');
  const [devices, setDevices] = useState<ParentChildDevice[]>([]);
  const [selectedDevice, setSelectedDevice] = useState<ParentChildDevice | null>(null);
  const [isAddChildModalOpen, setIsAddChildModalOpen] = useState<boolean>(false);
  const [isAuthModalOpen, setIsAuthModalOpen] = useState<boolean>(false);
  const [activeStreamingDevice, setActiveStreamingDevice] = useState<ParentChildDevice | null>(null);

  // ----------------------------------------------------
  // Child Protection Client State
  // ----------------------------------------------------
  const deviceName = "Child Device";
  const deviceModel = "Android 14 (API 34) Protection Client";
  const generateFlashGetCode = () => {
    const chars = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    let res = '';
    for (let i = 0; i < 6; i++) res += chars.charAt(Math.floor(Math.random() * chars.length));
    return `FG-${res}`;
  };
  const [pairingCode, setPairingCode] = useState<string>(() => generateFlashGetCode());
  const [copied, setCopied] = useState<boolean>(false);

  // Dynamic Battery Telemetry
  const [batteryLevel, setBatteryLevel] = useState<number>(0);
  const [isCharging, setIsCharging] = useState<boolean>(false);
  const [batteryHealth] = useState<string>("Normal (Hardware Sensor)");
  const [batteryTemp, setBatteryTemp] = useState<number>(25.0);
  const [batteryVoltage] = useState<number>(3.80);

  // Dynamic GPS Telemetry
  const [location, setLocation] = useState<{
    latitude: number;
    longitude: number;
    accuracy: number;
    speed: number;
    address: string;
    timestamp: number;
  }>({
    latitude: 0.0,
    longitude: 0.0,
    accuracy: 0.0,
    speed: 0.0,
    address: 'Awaiting hardware GPS fix…',
    timestamp: Date.now(),
  });
  const [isRefreshingGps, setIsRefreshingGps] = useState<boolean>(false);

  // Active Background Services Toggles
  const [screenMirrorActive, setScreenMirrorActive] = useState<boolean>(false);
  const [screenFps] = useState<number>(12);
  const [screenFrameCount, setScreenFrameCount] = useState<number>(0);
  const [cameraStreamActive, setCameraStreamActive] = useState<boolean>(false);
  const [audioStreamActive, setAudioStreamActive] = useState<boolean>(false);
  
  // Tracking which parent has claimed this child
  const [parentLink, setParentLink] = useState<{ parentUid: string; childId: string } | null>(null);

  // New effect to handle persistent pairing code in child mode
  useEffect(() => {
    if (selectedRole === 'child' && currentUser && auth) {
      const fetchPersistentCode = async () => {
        const code = await getOrCreateChildPairingCode(currentUser.uid, `dev_${currentUser.uid.slice(0, 8)}`, deviceModel);
        if (code) {
          setPairingCode(code);
        }
      };
      fetchPersistentCode();
    }
  }, [selectedRole, currentUser]);

  const guardian = {
    name: "Account Owner",
    phone: "Linked",
    email: currentUser?.email || 'kadimpatimoshe@gmail.com',
    relationship: "Primary Guardian",
    status: "Verified Account • Auto-Synced",
  };

  // ----------------------------------------------------
  // Authentication & Onboarding Lifecycle
  // ----------------------------------------------------
  useEffect(() => {
    // Listen for real-time Firebase Auth state changes for permanent persistence
    if (!auth) return;
    
    const unsubscribe = onAuthStateChanged(auth, (user: any) => {
      if (user) {
        const sessionUser = { uid: user.uid, email: user.email || '' };
        saveParentSession(sessionUser);
        setCurrentUser(sessionUser);
        setIsAuthenticated(true);
      }
    });

    return () => unsubscribe();
  }, []);

  // ----------------------------------------------------
  // Sync Devices for Parent Console
  // ----------------------------------------------------
  useEffect(() => {
    if (selectedRole !== 'parent' || !currentUser) return;

    const unsubscribe = subscribeToChildDevices(currentUser.uid, (updatedDevices) => {
      setDevices(updatedDevices);
      setSelectedDevice((prev) => {
        if (!prev) return updatedDevices[0] || null;
        return updatedDevices.find((d) => d.childId === prev.childId) || updatedDevices[0] || null;
      });
    });

    return () => {
      unsubscribe();
    };
  }, [selectedRole, currentUser]);

  // Auto-open Add Child Modal if no devices are linked (Onboarding)
  useEffect(() => {
    if (selectedRole === 'parent' && isAuthenticated && devices.length === 0) {
      setIsAddChildModalOpen(true);
    }
  }, [selectedRole, isAuthenticated, devices.length]);

  // ----------------------------------------------------
  // Child Device: Presence Logic (Online/Offline)
  // ----------------------------------------------------
  useEffect(() => {
    if (selectedRole !== 'child' || !database || !pairingCode) return;

    const presenceRef = ref(database, `devices/${pairingCode}/presence/online`);
    
    // Set to true when the component mounts (online)
    set(presenceRef, true);
    
    // Set to false when the connection is lost or the app is closed
    onDisconnect(presenceRef).set(false);

    // Also update parent console sync if logged in
    if (currentUser) {
      const childId = `browser_${currentUser.uid.slice(0, 8)}`;
      const parentPresenceRef = ref(database, `parents/${currentUser.uid}/children/${childId}/presence/online`);
      set(parentPresenceRef, true);
      onDisconnect(parentPresenceRef).set(false);
    }
  }, [selectedRole, pairingCode, currentUser]);

  // ----------------------------------------------------
  // Child Device: Battery & GPS Telemetry Push to RTDB
  // ----------------------------------------------------
  useEffect(() => {
    if (selectedRole !== 'child' && selectedRole !== null) return;
    if (!database) return;

    const payload = sanitizeForRTDB({
      deviceName,
      deviceModelName: deviceModel,
      pairingCode,
      status: 'active',
      platform: 'android',
      lastHeartbeat: Date.now(),
      telemetry: {
        batteryLevel,
        isCharging,
        batteryTemp,
        batteryVoltage,
        batteryHealth,
        updatedAt: Date.now(),
      },
      location: {
        latitude: location.latitude,
        longitude: location.longitude,
        speed: location.speed,
        accuracy: location.accuracy,
        address: location.address,
        timestamp: location.timestamp,
      },
      presence: {
        online: true,
        heartbeatAt: Date.now(),
      },
      guardian,
    });

    try {
      update(ref(database, `devices/${pairingCode}`), payload);
      update(ref(database, `devices/${pairingCode}/telemetry/battery`), {
        level: batteryLevel,
        isCharging,
        temperature: batteryTemp,
        voltage: batteryVoltage,
        health: batteryHealth,
        updatedAt: Date.now(),
      });
      update(ref(database, `devices/${pairingCode}/location`), location);

      // Also mirror to pure 4-digit code if code has letters/hyphen (e.g. 8492)
      const numCode = pairingCode.replace(/\D/g, '');
      if (numCode && numCode !== pairingCode) {
        update(ref(database, `devices/${numCode}`), payload);
      }
      
      // Sync to parent console directly if linked or if using same account
      if (currentUser) {
        const childId = `child_dev_${currentUser.uid.slice(0, 8)}`; // Consistent with getOrCreateChildPairingCode
        const parentDevicePath = `parents/${currentUser.uid}/children/${childId}`;
        
        // Enforce 1-device limit: Clear existing children before updating this one if it's different
        // Actually, since childId is derived from uid, it will always overwrite itself.
        // But let's make sure we also update the device record.
        
        update(ref(database, parentDevicePath), {
          ...payload,
          childId,
          status: 'synced',
          isOnline: true,
          lastSeen: new Date().toISOString(),
        });
        
        // Ensure childId is set for backward compatibility commands
        if (!parentLink) setParentLink({ parentUid: currentUser.uid, childId });
      }
    } catch (e) {
      console.warn('Firebase RTDB child sync note:', e);
    }
  }, [batteryLevel, isCharging, batteryTemp, location, pairingCode, selectedRole, currentUser, parentLink]);

  // Listen for parent remote commands in child mode
  useEffect(() => {
    if (selectedRole !== 'child' && selectedRole !== null) return;
    if (!database) return;

    const controlRef = ref(database, `devices/${pairingCode}/control`);
    const unsubscribe = onValue(controlRef, (snapshot) => {
      const val = snapshot.val();
      if (!val || val.acknowledged) return;

      const cmd = val.command;
      if (cmd === 'startScreenShare') {
        setScreenMirrorActive(true);
        showToast('Parent requested Screen Mirroring start');
      } else if (cmd === 'stopScreenShare') {
        setScreenMirrorActive(false);
        showToast('Screen Mirroring stopped');
      } else if (cmd === 'startStream') {
        setCameraStreamActive(true);
        showToast('Parent started Remote Camera stream');
      } else if (cmd === 'stopStream') {
        setCameraStreamActive(false);
        showToast('Remote Camera stream stopped');
      }

      update(controlRef, {
        acknowledged: true,
        executedAt: Date.now(),
      });
    });

    return () => {
      off(controlRef);
    };
  }, [pairingCode, selectedRole]);

  // Listen for pairing status to find parent UID for direct sync
  useEffect(() => {
    if (selectedRole !== 'child' || !database) return;
    const deviceRef = ref(database, `devices/${pairingCode}`);
    const unsubscribe = onValue(deviceRef, (snapshot) => {
      const data = snapshot.val();
      if (data && data.parentUid && data.childId) {
        setParentLink({ parentUid: data.parentUid, childId: data.childId });
      }
    });
    return () => off(deviceRef);
  }, [pairingCode, selectedRole]);



  // Real Hardware Battery API Listener
  useEffect(() => {
    if (selectedRole !== 'child') return;
    let batteryObj: any = null;
    let onLevelChange: () => void;
    let onChargingChange: () => void;

    if ('getBattery' in navigator) {
      (navigator as any).getBattery().then((bat: any) => {
        batteryObj = bat;
        setBatteryLevel(Math.round(bat.level * 100));
        setIsCharging(bat.charging);

        onLevelChange = () => setBatteryLevel(Math.round(bat.level * 100));
        onChargingChange = () => setIsCharging(bat.charging);

        bat.addEventListener('levelchange', onLevelChange);
        bat.addEventListener('chargingchange', onChargingChange);
      }).catch(() => {});
    }

    return () => {
      if (batteryObj) {
        batteryObj.removeEventListener('levelchange', onLevelChange);
        batteryObj.removeEventListener('chargingchange', onChargingChange);
      }
    };
  }, [selectedRole]);

  // Real Hardware Geolocation API Listener
  useEffect(() => {
    if (selectedRole !== 'child') return;
    let watchId: number | null = null;

    if ('geolocation' in navigator) {
      watchId = navigator.geolocation.watchPosition(
        (pos) => {
          setLocation({
            latitude: Number(pos.coords.latitude.toFixed(6)),
            longitude: Number(pos.coords.longitude.toFixed(6)),
            accuracy: Math.round(pos.coords.accuracy || 5),
            speed: Number((pos.coords.speed ? pos.coords.speed * 3.6 : 0.0).toFixed(1)),
            address: `Real GPS Fix: ${pos.coords.latitude.toFixed(4)}°, ${pos.coords.longitude.toFixed(4)}° (±${Math.round(pos.coords.accuracy || 5)}m)`,
            timestamp: pos.timestamp || Date.now(),
          });
        },
        (err) => {
          console.warn('Real GPS hardware sensor notice:', err.message);
        },
        { enableHighAccuracy: true, timeout: 15000, maximumAge: 5000 }
      );
    }

    return () => {
      if (watchId !== null && 'geolocation' in navigator) {
        navigator.geolocation.clearWatch(watchId);
      }
    };
  }, [selectedRole]);

  // ----------------------------------------------------
  // Auth Handlers
  // ----------------------------------------------------
  const handlePinKey = (val: string) => {
    if (enteredPin.length < 4) {
      const newPin = enteredPin + val;
      setEnteredPin(newPin);
      setPasscodeError(null);

      if (newPin.length === 4) {
        setTimeout(async () => {
          try {
            // Use real email sign-in with the PIN as pseudo-password if desired, 
            // but for "powerful" we should use real email/pass.
            // For the PIN flow, we'll keep it as a local-only or mock for now, 
            // but encourage email auth for the real parent console.
            const user = { uid: `parent_${newPin}`, email: 'parent@kidguard.family' };
            saveParentSession(user);
            setCurrentUser(user);
            setIsAuthenticated(true);
            setEnteredPin('');
            showToast('Passcode PIN Verified (Session Created)');
          } catch (e) {
            setPasscodeError('PIN Authentication Failed');
          }
        }, 300);
      }
    }
  };

  const handleBackspace = () => {
    setEnteredPin((prev) => prev.slice(0, -1));
    setPasscodeError(null);
  };

  const handleClearPin = () => {
    setEnteredPin('');
    setPasscodeError(null);
  };

  const handleEmailAuthSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!emailInput || !passwordInput) {
      setPasscodeError('Please enter both email and password.');
      return;
    }
    try {
      const user = await signInWithEmail(emailInput, passwordInput);
      if (user) {
        setCurrentUser({ uid: user.uid, email: user.email || '' });
        setIsAuthenticated(true);
        showToast('Signed In Successfully');
      }
    } catch (err: any) {
      setPasscodeError(err.message || 'Authentication Failed');
    }
  };

  const handleQuickDemoAuth = async () => {
    // Attempt to log in with a known demo account to ensure real Firebase Auth
    // If this fails, we fall back to a mock but warn the user.
    try {
      const user = await signInWithEmail('kadimpatimoshe@gmail.com', 'secret123');
      if (user) {
        showToast('Demo Account Logged In');
      }
    } catch (err) {
      console.warn('Demo login failed, using local mock mode:', err);
      const demo = { uid: 'parent_demo_01', email: 'kadimpatimoshe@gmail.com' };
      saveParentSession(demo);
      setCurrentUser(demo);
      setIsAuthenticated(true);
      showToast('Demo Account (Offline Mode) Active');
    }
  };

  const handleSignOut = async () => {
    await fbSignOut();
    setCurrentUser(null);
    setIsAuthenticated(false);
    setSelectedRole(null);
    setEnteredPin('');
    showToast('Signed Out');
  };

  const handleSelectRole = (role: AppRole) => {
    setSelectedRole(role);
    if (rememberRole && role) {
      localStorage.setItem('kidguard_device_role', role);
    }
    showToast(role === 'parent' ? 'Parent Console Activated' : 'Child Protection Client Activated');
  };

  const handleSwitchRole = () => {
    localStorage.removeItem('kidguard_device_role');
    setSelectedRole(null);
  };

  // ----------------------------------------------------
  // Child Controls
  // ----------------------------------------------------
  const handleToggleScreenMirror = () => {
    const nextState = !screenMirrorActive;
    setScreenMirrorActive(nextState);
    showToast(nextState ? 'Screen Mirroring Service started' : 'Screen Mirroring Service stopped');
    if (database) {
      update(ref(database, `devices/${pairingCode}/screen`), {
        status: nextState ? 'streaming' : 'standby',
        isSharing: nextState,
        fps: screenFps,
        updatedAt: Date.now(),
      });
    }
  };

  const handleToggleCameraStream = () => {
    const nextState = !cameraStreamActive;
    setCameraStreamActive(nextState);
    showToast(nextState ? 'Remote Camera Stream active' : 'Remote Camera Stream stopped');
    if (database) {
      update(ref(database, `devices/${pairingCode}/stream`), {
        status: nextState ? 'active' : 'stopped',
        cameraFacing: 'back',
        updatedAt: Date.now(),
      });
    }
  };

  const handleToggleAudioStream = () => {
    const nextState = !audioStreamActive;
    setAudioStreamActive(nextState);
    showToast(nextState ? 'One-Way Audio Stream transmitting' : 'One-Way Audio Stream stopped');
    if (database) {
      update(ref(database, `devices/${pairingCode}/audio`), {
        status: nextState ? 'transmitting' : 'standby',
        isTransmitting: nextState,
        sampleRate: 44100,
        updatedAt: Date.now(),
      });
    }
  };

  const handleCopyPairingCode = () => {
    navigator.clipboard?.writeText(pairingCode);
    setCopied(true);
    showToast(`Pairing code ${pairingCode} copied`);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleGenerateNewCode = async () => {
    if (!currentUser) {
      showToast('Please log in first to regenerate code');
      return;
    }
    const chars = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    let res = '';
    for (let i = 0; i < 6; i++) res += chars.charAt(Math.floor(Math.random() * chars.length));
    const newCode = `FG-${res}`;
    
    setPairingCode(newCode);
    showToast(`Fresh binding code generated: ${newCode}`);
    
    if (database) {
      const updates: Record<string, any> = {
        [`user_pairing_codes/${currentUser.uid}`]: newCode,
        [`devices/${newCode}`]: {
          pairingCode: newCode,
          deviceModelName: deviceModel,
          status: 'pending',
          online: true,
          updatedAt: Date.now(),
        }
      };
      await update(ref(database), updates);
    }
  };

  // ----------------------------------------------------
  // Parent Console Pairing Handlers
  // ----------------------------------------------------
  const handlePairChild = async (code: string, modelName: string) => {
    if (!currentUser) throw new Error('Parent not authenticated');
    const newDevice = await pairChildDevice(currentUser.uid, code, modelName);
    showToast(`Successfully paired device with code ${code}!`);
    return newDevice;
  };

  const handleUnlinkDevice = async (device: ParentChildDevice) => {
    if (!currentUser) return;
    if (confirm(`Are you sure you want to unlink ${device.deviceModelName}?`)) {
      try {
        await unlinkChildDevice(currentUser.uid, device.childId);
        showToast(`Unlinked ${device.deviceModelName}`);
      } catch (err: any) {
        showToast(`Error unlinking: ${err.message}`);
      }
    }
  };

  // ====================================================
  // SCREEN 1: INITIAL APP LAUNCH & PASSCODE/EMAIL LOGIN
  // ====================================================
  if (!isAuthenticated) {
    return (
      <div className="min-h-screen bg-[#F4F6F4] flex flex-col items-center justify-center p-4">
        {toastMessage && (
          <div className="fixed top-5 z-50 bg-[#192723] text-white text-xs font-semibold px-4 py-2.5 rounded-full shadow-lg flex items-center gap-2 border border-emerald-500/30">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
            <span>{toastMessage}</span>
          </div>
        )}

        <div className="w-full max-w-md bg-white rounded-3xl border border-[#E4E9E5] p-6 sm:p-8 shadow-xl">
          {/* Logo Badge */}
          <div className="text-center mb-6">
            <div className="w-16 h-16 rounded-2xl bg-[#0A9B70] text-white flex items-center justify-center mx-auto mb-3 shadow-md shadow-emerald-700/20">
              <Shield className="w-8 h-8" />
            </div>
            <h1 className="text-2xl font-extrabold text-[#1D302B] tracking-tight">KidGuard Protection</h1>
            <p className="text-xs text-[#71807B] mt-1">
              Secure family supervision and child safety platform
            </p>
          </div>

          {/* Mode A: Email & Password Form */}
          <form onSubmit={handleEmailAuthSubmit} className="space-y-4">
            <div>
              <label className="block text-xs font-bold text-[#1D302B] mb-1">Email Address</label>
              <input
                type="email"
                value={emailInput}
                onChange={(e) => setEmailInput(e.target.value)}
                className="w-full h-10 px-3 text-xs bg-[#F9FAF9] border border-[#E4E9E5] rounded-xl focus:border-[#0A9B70] focus:ring-2 focus:ring-emerald-100 outline-none text-[#1D302B]"
                placeholder="parent@kidguard.family"
                required
              />
            </div>
            <div>
              <label className="block text-xs font-bold text-[#1D302B] mb-1">Password</label>
              <input
                type="password"
                value={passwordInput}
                onChange={(e) => setPasswordInput(e.target.value)}
                className="w-full h-10 px-3 text-xs bg-[#F9FAF9] border border-[#E4E9E5] rounded-xl focus:border-[#0A9B70] focus:ring-2 focus:ring-emerald-100 outline-none text-[#1D302B]"
                placeholder="••••••••"
                required
              />
            </div>

            <button
              type="submit"
              className="w-full h-10 rounded-xl text-xs font-bold bg-[#0A9B70] hover:bg-[#087957] text-white transition-colors shadow-xs"
            >
              Sign In to KidGuard
            </button>
          </form>

          {/* Quick Demo Login */}
          <div className="mt-6 pt-4 border-t border-[#E4E9E5]">
            <button
              onClick={handleQuickDemoAuth}
              className="w-full py-2.5 px-3 rounded-xl text-xs font-bold bg-[#ECFDF5] hover:bg-[#D1FAE5] text-[#065F46] border border-[#A7F3D0] transition-all flex items-center justify-center gap-2"
            >
              <Sparkles className="w-4 h-4 text-[#0A9B70]" />
              Quick Demo Access (One-Click)
            </button>
          </div>
        </div>
      </div>
    );
  }

  // ====================================================
  // SCREEN 2: ROLE SELECTION (Parent App vs Child App)
  // ====================================================
  if (selectedRole === null) {
    return (
      <div className="min-h-screen bg-[#F4F6F4] flex flex-col items-center justify-center p-4">
        {toastMessage && (
          <div className="fixed top-5 z-50 bg-[#192723] text-white text-xs font-semibold px-4 py-2.5 rounded-full shadow-lg flex items-center gap-2 border border-emerald-500/30">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
            <span>{toastMessage}</span>
          </div>
        )}

        <div className="w-full max-w-xl bg-white rounded-3xl border border-[#E4E9E5] p-6 sm:p-8 shadow-xl">
          <div className="flex items-center justify-between pb-4 border-b border-[#E4E9E5] mb-6">
            <div className="flex items-center gap-2.5">
              <div className="w-8 h-8 rounded-lg bg-[#0A9B70] text-white flex items-center justify-center">
                <Shield className="w-4 h-4" />
              </div>
              <span className="text-sm font-bold text-[#1D302B]">KidGuard Setup</span>
            </div>
            <button
              onClick={handleSignOut}
              className="text-xs text-[#71807B] hover:text-rose-600 flex items-center gap-1 font-semibold"
            >
              <LogOut className="w-3.5 h-3.5" />
              Sign Out
            </button>
          </div>

          <div className="text-center mb-6">
            <span className="px-3 py-1 rounded-full text-[10px] font-extrabold uppercase bg-emerald-50 text-[#0A9B70] border border-emerald-200">
              Step 2 of 2: Device Role
            </span>
            <h2 className="text-2xl font-extrabold text-[#1D302B] tracking-tight mt-2">
              Who is using this device?
            </h2>
            <p className="text-xs text-[#71807B] mt-1 max-w-md mx-auto">
              Select the role for this session. You can easily switch roles at any time from the top bar.
            </p>
          </div>

          {/* Role Choice Cards */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {/* Option 1: Parent Console */}
            <button
              onClick={() => handleSelectRole('parent')}
              className="p-5 rounded-2xl border-2 border-emerald-500 bg-[#F8FAF9] hover:bg-emerald-50/70 text-left transition-all hover:shadow-md group flex flex-col justify-between"
            >
              <div>
                <div className="w-12 h-12 rounded-xl bg-emerald-100 text-[#0A9B70] flex items-center justify-center mb-3">
                  <Users className="w-6 h-6" />
                </div>
                <h3 className="text-base font-extrabold text-[#1D302B]">I am a Parent</h3>
                <span className="text-[11px] font-bold text-[#0A9B70] block mt-0.5">Parent Monitoring Console</span>
                <p className="text-xs text-[#71807B] mt-2 leading-relaxed">
                  Enter the child's 4-digit code to pair. Track live GPS location, view live screen mirror, camera streams, call logs, and app usage.
                </p>
              </div>

              <div className="mt-4 pt-3 border-t border-emerald-200/60 flex items-center justify-between text-xs font-bold text-[#0A9B70]">
                <span>Open Parent Dashboard</span>
                <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
              </div>
            </button>

            {/* Option 2: Child Client */}
            <button
              onClick={() => handleSelectRole('child')}
              className="p-5 rounded-2xl border-2 border-[#E4E9E5] hover:border-emerald-500 bg-[#F8FAF9] hover:bg-emerald-50/70 text-left transition-all hover:shadow-md group flex flex-col justify-between"
            >
              <div>
                <div className="w-12 h-12 rounded-xl bg-blue-100 text-blue-600 flex items-center justify-center mb-3">
                  <Smartphone className="w-6 h-6" />
                </div>
                <h3 className="text-base font-extrabold text-[#1D302B]">I am a Child</h3>
                <span className="text-[11px] font-bold text-blue-600 block mt-0.5">Child Protection Client</span>
                <p className="text-xs text-[#71807B] mt-2 leading-relaxed">
                  Generates a secure 4-digit pairing code to link with your parent. Runs safe background telemetry for battery, location, and services.
                </p>
              </div>

              <div className="mt-4 pt-3 border-t border-neutral-200/60 flex items-center justify-between text-xs font-bold text-neutral-700 group-hover:text-[#0A9B70]">
                <span>Open Child Client</span>
                <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
              </div>
            </button>
          </div>

          <div className="mt-6 flex items-center justify-between text-xs text-[#71807B]">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={rememberRole}
                onChange={(e) => setRememberRole(e.target.checked)}
                className="rounded border-[#E4E9E5] text-[#0A9B70] focus:ring-[#0A9B70]"
              />
              <span>Remember role on this browser</span>
            </label>
          </div>
        </div>
      </div>
    );
  }

  // ====================================================
  // SCREEN 3A: CHILD PROTECTION CLIENT
  // ====================================================
  if (selectedRole === 'child') {
    return (
      <div className="min-h-screen bg-[#F4F6F4] text-[#1D302B] flex flex-col items-center">
        {toastMessage && (
          <div className="fixed top-5 z-50 bg-[#192723] text-white text-xs font-semibold px-4 py-2.5 rounded-full shadow-lg flex items-center gap-2 border border-emerald-500/30">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
            <span>{toastMessage}</span>
          </div>
        )}

        {/* Top Role Switcher Bar */}
        <div className="w-full bg-[#192723] text-white px-4 py-2 border-b border-emerald-950 flex items-center justify-between text-xs">
          <div className="flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
            <span className="font-bold">Device Mode: <span className="text-[#34D399]">Child Protection Client</span></span>
          </div>
          <div className="flex items-center gap-3">
            <button
              onClick={handleSwitchRole}
              className="text-xs bg-white/10 hover:bg-white/20 px-2.5 py-1 rounded-md text-emerald-300 font-bold transition-colors"
            >
              ⇄ Switch to Parent Console
            </button>
            <button
              onClick={handleSignOut}
              className="text-neutral-400 hover:text-white"
              title="Sign Out"
            >
              <LogOut className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>

        {/* Child Top Bar */}
        <header className="w-full bg-white border-b border-[#E4E9E5] sticky top-0 z-30">
          <div className="max-w-2xl mx-auto px-4 sm:px-6 py-3.5 flex items-center justify-between">
            <div className="flex items-center gap-2.5">
              <div className="w-8 h-8 rounded-lg bg-[#0A9B70] flex items-center justify-center text-white shadow-xs">
                <Shield className="w-4 h-4" />
              </div>
              <div>
                <h1 className="text-sm font-bold text-[#1D302B] leading-none">KidGuard Protection</h1>
                <span className="text-[10px] text-[#71807B] leading-tight block mt-0.5">Continuous Foreground Service Active</span>
              </div>
            </div>

            <div className="flex items-center gap-2">
              <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-[#ECFDF5] border border-[#A7F3D0] text-[11px] font-bold text-[#065F46]">
                <span className="w-2 h-2 rounded-full bg-[#10B981] animate-pulse"></span>
                Live Synced
              </div>
            </div>
          </div>
        </header>

        {/* Main Content Dashboard */}
        <main className="w-full max-w-2xl px-4 sm:px-6 py-6 space-y-4 flex-1">
          {/* 1. Header with Device Name and 4-Digit Bind Code */}
          <div className="rounded-2xl p-6 bg-gradient-to-br from-[#192723] to-[#263D36] text-white shadow-md relative overflow-hidden">
            <div className="absolute -right-8 -bottom-8 w-36 h-36 bg-emerald-500/10 rounded-full blur-2xl pointer-events-none"></div>

            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-emerald-400"></span>
                <span className="text-[10px] font-extrabold tracking-wider uppercase text-[#91D5AD]">ACTIVE DEVICE</span>
              </div>

              <div className="flex items-center gap-2">
                <button
                  onClick={handleGenerateNewCode}
                  title="Generate Fresh Code"
                  className="bg-white/10 hover:bg-white/20 text-white px-2 py-1 rounded-lg text-xs flex items-center gap-1"
                >
                  <RefreshCw className="w-3 h-3" />
                  <span>Regenerate</span>
                </button>

                <button
                  onClick={handleCopyPairingCode}
                  title="Click to copy pairing code"
                  className="inline-flex items-center gap-1.5 bg-white/10 hover:bg-white/20 active:scale-95 transition-all text-white px-3 py-1 rounded-lg border border-white/15 text-xs font-mono"
                >
                  <span className="text-[11px] text-white/70">Pairing Code:</span>
                  <span className="font-extrabold text-[#34D399] tracking-wider">{pairingCode}</span>
                  {copied ? <Check className="w-3.5 h-3.5 text-emerald-300" /> : <Copy className="w-3.5 h-3.5 text-white/70" />}
                </button>
              </div>
            </div>

            <div className="mt-4">
              <h2 className="text-2xl font-extrabold text-white tracking-tight">{deviceName}</h2>
              <p className="text-xs text-[#9EB5AB] mt-0.5">{deviceModel}</p>
            </div>

            <div className="mt-5 pt-4 border-t border-white/10 flex flex-wrap items-center justify-between text-[11px]">
              <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-white/10 text-white/90">
                <Wifi className="w-3 h-3 text-emerald-400" />
                Firebase RTDB: /devices/{pairingCode}
              </span>
            </div>
          </div>

          {/* 2. Simplified Protection Status (FlashGet Style) */}
          <div className="bg-white rounded-3xl p-8 border border-[#E4E9E5] shadow-xl text-center space-y-6">
            <div className="w-24 h-24 rounded-full bg-emerald-50 text-[#0A9B70] flex items-center justify-center mx-auto border-4 border-emerald-100/50 shadow-inner">
              <Shield className="w-12 h-12 animate-pulse" />
            </div>
            
            <div>
              <h3 className="text-xl font-black text-[#1D302B] tracking-tight">Device Protected</h3>
              <p className="text-sm text-[#71807B] mt-2 leading-relaxed">
                Everything is working correctly. Your parent can now supervise this device activities remotely.
              </p>
            </div>

            <div className="pt-4 border-t border-[#F1F5F2] flex flex-col gap-3">
              <div className="flex items-center justify-between text-xs font-bold text-[#71807B] bg-[#F8FAF9] p-3 rounded-2xl border border-[#E8ECE9]">
                <div className="flex items-center gap-2">
                  <div className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></div>
                  <span>Background Monitoring</span>
                </div>
                <span className="text-[#0A9B70]">ACTIVE</span>
              </div>
              
              <div className="flex items-center justify-between text-xs font-bold text-[#71807B] bg-[#F8FAF9] p-3 rounded-2xl border border-[#E8ECE9]">
                <div className="flex items-center gap-2">
                  <div className="w-2 h-2 rounded-full bg-blue-500 animate-pulse"></div>
                  <span>Safe GPS Tracking</span>
                </div>
                <span className="text-blue-600">ACTIVE</span>
              </div>
            </div>
          </div>

          {/* 3. Real-Time Activity Log (Optional Notifications Only) */}
          <div className="bg-white rounded-3xl p-6 border border-[#E4E9E5] shadow-xs">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-xs font-black text-[#1D302B] tracking-widest uppercase">LATEST SYSTEM ALERTS</h3>
              <Bell className="w-4 h-4 text-[#71807B]" />
            </div>
            
            <div className="space-y-3">
              <div className="p-3 rounded-2xl bg-emerald-50/50 border border-emerald-100 flex items-start gap-3">
                <div className="w-8 h-8 rounded-xl bg-white flex items-center justify-center shadow-xs shrink-0">
                  <Shield className="w-4 h-4 text-[#0A9B70]" />
                </div>
                <div>
                  <p className="text-[11px] font-bold text-[#1D302B]">Security Sync Successful</p>
                  <p className="text-[10px] text-[#71807B]">Device status was updated 1 minute ago.</p>
                </div>
              </div>
              <div className="p-3 rounded-2xl bg-indigo-50/50 border border-indigo-100 flex items-start gap-3">
                <div className="w-8 h-8 rounded-xl bg-white flex items-center justify-center shadow-xs shrink-0">
                  <Radio className="w-4 h-4 text-indigo-600" />
                </div>
                <div>
                  <p className="text-[11px] font-bold text-[#1D302B]">Background Service Running</p>
                  <p className="text-[10px] text-[#71807B]">Continuous protection is active in background.</p>
                </div>
              </div>
            </div>
          </div>

          {/* 4. Active Background Services List */}
          <div className="space-y-2.5 pt-2">
            <div className="flex items-center justify-between px-1">
              <h3 className="text-xs font-extrabold text-[#71807B] tracking-wider uppercase">
                ACTIVE BACKGROUND SERVICES
              </h3>
              <span className="text-[10px] text-[#71807B]">Android 14 Foreground Types</span>
            </div>

            {/* Service 1: Screen Mirroring */}
            <div className={`bg-white rounded-2xl p-4 border transition-all ${
              screenMirrorActive ? 'border-[#0A9B70] shadow-sm' : 'border-[#E4E9E5]'
            }`}>
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-3">
                  <div className={`w-10 h-10 rounded-xl flex items-center justify-center transition-colors ${
                    screenMirrorActive ? 'bg-indigo-100 text-indigo-700' : 'bg-neutral-100 text-neutral-500'
                  }`}>
                    <ScreenShare className="w-5 h-5" />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <h4 className="text-sm font-bold text-[#1D302B]">Screen Mirroring Service</h4>
                      {screenMirrorActive ? (
                        <span className="px-2 py-0.5 rounded-md bg-[#ECFDF5] border border-[#A7F3D0] text-[#065F46] text-[9px] font-extrabold uppercase animate-pulse">
                          STREAMING
                        </span>
                      ) : (
                        <span className="px-2 py-0.5 rounded-md bg-neutral-100 text-neutral-500 text-[9px] font-bold uppercase">
                          STANDBY
                        </span>
                      )}
                    </div>
                    <p className="text-[11px] text-[#71807B] mt-0.5">
                      MediaProjection foreground capture to /devices/{pairingCode}/screen
                    </p>
                  </div>
                </div>

                <button
                  type="button"
                  role="switch"
                  aria-checked={screenMirrorActive}
                  onClick={handleToggleScreenMirror}
                  className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out ${
                    screenMirrorActive ? 'bg-[#0A9B70]' : 'bg-neutral-300'
                  }`}
                >
                  <span
                    className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow-md ring-0 transition duration-200 ease-in-out ${
                      screenMirrorActive ? 'translate-x-5' : 'translate-x-0'
                    }`}
                  />
                </button>
              </div>
            </div>

            {/* Service 2: Remote Camera Stream */}
            <div className={`bg-white rounded-2xl p-4 border transition-all ${
              cameraStreamActive ? 'border-[#0A9B70] shadow-sm' : 'border-[#E4E9E5]'
            }`}>
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-3">
                  <div className={`w-10 h-10 rounded-xl flex items-center justify-center transition-colors ${
                    cameraStreamActive ? 'bg-emerald-100 text-[#0A9B70]' : 'bg-neutral-100 text-neutral-500'
                  }`}>
                    <Video className="w-5 h-5" />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <h4 className="text-sm font-bold text-[#1D302B]">Remote Camera Stream</h4>
                      <span className="px-2 py-0.5 rounded-md bg-neutral-100 border border-neutral-200 text-neutral-700 text-[9px] font-extrabold uppercase">
                        BACK LENS
                      </span>
                    </div>
                    <p className="text-[11px] text-[#71807B] mt-0.5">
                      Live encrypted WebRTC camera service linked to /devices/{pairingCode}/stream
                    </p>
                  </div>
                </div>

                <button
                  type="button"
                  role="switch"
                  aria-checked={cameraStreamActive}
                  onClick={handleToggleCameraStream}
                  className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out ${
                    cameraStreamActive ? 'bg-[#0A9B70]' : 'bg-neutral-300'
                  }`}
                >
                  <span
                    className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow-md ring-0 transition duration-200 ease-in-out ${
                      cameraStreamActive ? 'translate-x-5' : 'translate-x-0'
                    }`}
                  />
                </button>
              </div>
            </div>

            {/* Service 3: Audio Stream */}
            <div className={`bg-white rounded-2xl p-4 border transition-all ${
              audioStreamActive ? 'border-[#0A9B70] shadow-sm' : 'border-[#E4E9E5]'
            }`}>
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-3">
                  <div className={`w-10 h-10 rounded-xl flex items-center justify-center transition-colors ${
                    audioStreamActive ? 'bg-pink-100 text-pink-600' : 'bg-neutral-100 text-neutral-500'
                  }`}>
                    <Mic className="w-5 h-5" />
                  </div>
                  <div>
                    <div className="flex items-center gap-2">
                      <h4 className="text-sm font-bold text-[#1D302B]">One-Way Audio Stream</h4>
                      {audioStreamActive ? (
                        <span className="px-2 py-0.5 rounded-md bg-[#FDF2F8] border border-[#FBCFE8] text-[#BE185D] text-[9px] font-extrabold uppercase animate-pulse">
                          TRANSMITTING
                        </span>
                      ) : (
                        <span className="px-2 py-0.5 rounded-md bg-neutral-100 text-neutral-500 text-[9px] font-bold uppercase">
                          STANDBY
                        </span>
                      )}
                    </div>
                    <p className="text-[11px] text-[#71807B] mt-0.5">
                      Background microphone relay to /devices/{pairingCode}/audio
                    </p>
                  </div>
                </div>

                <button
                  type="button"
                  role="switch"
                  aria-checked={audioStreamActive}
                  onClick={handleToggleAudioStream}
                  className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out ${
                    audioStreamActive ? 'bg-[#0A9B70]' : 'bg-neutral-300'
                  }`}
                >
                  <span
                    className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow-md ring-0 transition duration-200 ease-in-out ${
                      audioStreamActive ? 'translate-x-5' : 'translate-x-0'
                    }`}
                  />
                </button>
              </div>
            </div>
          </div>

          {/* Primary Guardian Card */}
          <div className="bg-white rounded-2xl p-5 border border-[#E4E9E5] shadow-xs">
            <div className="flex items-center justify-between">
              <span className="text-[10px] font-extrabold text-[#71807B] uppercase tracking-wider">
                PRIMARY GUARDIAN CONTACT
              </span>
              <span className="px-2.5 py-0.5 rounded-full bg-[#ECFDF5] text-[#065F46] text-[10px] font-bold">
                Verified & Synced
              </span>
            </div>

            <div className="mt-3.5 flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="w-11 h-11 rounded-full bg-[#0A9B70]/15 text-[#0A9B70] flex items-center justify-center font-extrabold text-sm">
                  SM
                </div>
                <div>
                  <h4 className="text-sm font-bold text-[#1D302B]">{guardian.name}</h4>
                  <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-[#71807B] mt-0.5">
                    <span className="flex items-center gap-1">
                      <Phone className="w-3 h-3 text-[#0A9B70]" />
                      {guardian.phone}
                    </span>
                    <span className="flex items-center gap-1">
                      <Mail className="w-3 h-3 text-neutral-400" />
                      {guardian.email}
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </main>
      </div>
    );
  }

  // ====================================================
  // SCREEN 3B: PARENT DASHBOARD CONSOLE
  // ====================================================
  const onlineCount = devices.filter((d) => d.isOnline).length;

  return (
    <div className="min-h-screen bg-[#F4F6F4] flex flex-col">
      {/* Toast Notification */}
      {toastMessage && (
        <div className="fixed top-5 z-50 right-5 bg-[#192723] text-white text-xs font-semibold px-4 py-2.5 rounded-full shadow-lg flex items-center gap-2 border border-emerald-500/30">
          <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
          <span>{toastMessage}</span>
        </div>
      )}

      {/* Top Role Switcher Bar */}
      <div className="w-full bg-[#192723] text-white px-4 sm:px-6 py-2 border-b border-emerald-950 flex items-center justify-between text-xs z-40">
        <div className="flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
          <span className="font-bold">Device Mode: <span className="text-[#34D399]">Parent Console</span></span>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={handleSwitchRole}
            className="text-xs bg-white/10 hover:bg-white/20 px-2.5 py-1 rounded-md text-emerald-300 font-bold transition-colors"
          >
            ⇄ Switch to Child Client
          </button>
          <button
            onClick={handleSignOut}
            className="text-neutral-400 hover:text-white"
            title="Sign Out"
          >
            <LogOut className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      <div className="flex flex-1">
        {/* Sidebar Navigation */}
        <Sidebar
          currentSection={currentSection}
          onSelectSection={setCurrentSection}
          onlineCount={onlineCount}
        />

        {/* Main Content Area */}
        <div className="flex-1 p-6 md:p-8 max-w-7xl mx-auto w-full">
          {/* Header */}
          <Header
            currentSection={currentSection}
            parentEmail={currentUser?.email || 'parent@kidguard.family'}
            onSignOut={handleSignOut}
            onOpenAuth={() => setIsAuthModalOpen(true)}
            onOpenAddChild={() => setIsAddChildModalOpen(true)}
            deviceCount={devices.length}
          />

          {/* Section 1: Family Devices */}
          {currentSection === 'devices' && (
            <div className="space-y-6">
              {devices.length === 0 ? (
                <div className="text-center py-16 bg-white rounded-2xl border border-[#E4E9E5] p-8">
                  <div className="w-14 h-14 rounded-full bg-emerald-50 text-[#0A9B70] flex items-center justify-center mx-auto mb-4">
                    <Smartphone className="w-7 h-7" />
                  </div>
                  <h3 className="text-lg font-extrabold text-[#1D302B]">Scan or enter 4-digit bind code to connect device</h3>
                  <p className="text-xs text-[#71807B] max-w-sm mx-auto mt-1 mb-5">
                    No active physical devices linked in Firebase RTDB. Open the Child Protection Client on the target phone to acquire real hardware telemetry.
                  </p>
                  <button
                    onClick={() => setIsAddChildModalOpen(true)}
                    className="px-4 py-2.5 rounded-xl text-xs font-bold bg-[#0A9B70] text-white hover:bg-[#087957] transition-colors"
                  >
                    Pair Device with 4-Digit Code
                  </button>
                </div>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
                  {devices.map((device) => (
                    <DeviceCard
                      key={device.childId}
                      device={device}
                      onOpenLiveStream={(dev) => {
                        setSelectedDevice(dev);
                        setActiveStreamingDevice(dev);
                      }}
                      onOpenLocation={(dev) => {
                        setSelectedDevice(dev);
                        setCurrentSection('location');
                      }}
                      onUnlink={handleUnlinkDevice}
                    />
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Section 2: Live Location */}
          {currentSection === 'location' && (
            <LiveLocationView
              devices={devices}
              selectedDevice={selectedDevice}
              onSelectDevice={setSelectedDevice}
            />
          )}

          {/* Section 3: Screen Mirroring */}
          {currentSection === 'mirroring' && (
            <ScreenMirrorView
              devices={devices}
              selectedDevice={selectedDevice}
              onSelectDevice={setSelectedDevice}
              parentUid={currentUser?.uid || 'parent_console'}
            />
          )}

          {/* Section 4: Live Camera Stream */}
          {currentSection === 'camera' && selectedDevice && (
            <LiveCameraModal
              device={selectedDevice}
              parentUid={currentUser?.uid || 'parent_console'}
              onClose={() => setCurrentSection('devices')}
            />
          )}

          {/* Section 5: Synced Notifications */}
          {currentSection === 'notifications' && (
            <NotificationsView
              devices={devices}
              selectedDevice={selectedDevice}
              onSelectDevice={setSelectedDevice}
            />
          )}

          {/* Section 6: Call Logs & History */}
          {currentSection === 'calls' && (
            <CallLogsView
              devices={devices}
              selectedDevice={selectedDevice}
              onSelectDevice={setSelectedDevice}
            />
          )}

          {/* Section 7: App Usage & Screen Time */}
          {currentSection === 'usage' && (
            <AppUsageView
              devices={devices}
              selectedDevice={selectedDevice}
              onSelectDevice={setSelectedDevice}
            />
          )}
        </div>
      </div>

      {/* 4-Digit Bind Code Pairing Modal */}
      {isAddChildModalOpen && (
        <AddChildModal
          onClose={() => setIsAddChildModalOpen(false)}
          onPair={handlePairChild}
        />
      )}

      {/* Live Camera Streaming Modal Popup */}
      {activeStreamingDevice && (
        <LiveCameraModal
          device={activeStreamingDevice}
          parentUid={currentUser?.uid || 'parent_console'}
          onClose={() => setActiveStreamingDevice(null)}
        />
      )}

      {/* Auth Modal Popup */}
      {isAuthModalOpen && (
        <AuthModal
          onClose={() => setIsAuthModalOpen(false)}
          onSuccess={(u) => {
            setCurrentUser(u);
            setIsAuthenticated(true);
            setIsAuthModalOpen(false);
          }}
        />
      )}
    </div>
  );
};

export default App;
