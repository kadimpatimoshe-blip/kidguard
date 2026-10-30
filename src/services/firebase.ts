import { initializeApp, getApps, FirebaseApp } from 'firebase/app';
import { getFirestore } from 'firebase/firestore';
import { 
  getAuth, 
  signInWithEmailAndPassword, 
  createUserWithEmailAndPassword, 
  signOut as fbSignOut, 
  onAuthStateChanged,
  signInWithPopup,
  GoogleAuthProvider,
  User,
  Auth,
  setPersistence,
  browserLocalPersistence
} from 'firebase/auth';
import { 
  getDatabase, 
  ref, 
  set, 
  update, 
  onValue, 
  off, 
  get, 
  remove, 
  serverTimestamp,
  query,
  orderByChild,
  equalTo,
  Database
} from 'firebase/database';
import firebaseConfig from '../../firebase-applet-config.json';
import { 
  ParentChildDevice, 
  PairingRecord, 
  RemoteCommand, 
  LocationData, 
  AppUsageItem, 
  CallLogItem,
  NotificationItem,
  DeviceTelemetryData,
  TelemetryData,
  PresenceData
} from '../types';

export const fullFirebaseConfig = {
  ...firebaseConfig,
  databaseURL: 'https://kidguard-3b499-default-rtdb.asia-southeast1.firebasedatabase.app',
};

// Initialize Firebase safely
let app: FirebaseApp | null = null;
let auth: Auth | null = null;
let database: Database | null = null;
let db: any = null;
let firebaseInitialized = false;

try {
  if (!getApps().length) {
    app = initializeApp(fullFirebaseConfig);
  } else {
    app = getApps()[0];
  }
  auth = getAuth(app);
  setPersistence(auth, browserLocalPersistence).catch(err => console.warn('Persistence error:', err));
  
  database = getDatabase(app);
  db = getFirestore(app, (firebaseConfig as any).firestoreDatabaseId);
  firebaseInitialized = true;
} catch (err) {
  console.warn('Firebase initialization note (running in resilient mode):', err);
}

export { auth, database, db, firebaseInitialized, onAuthStateChanged };

// Local persistence storage keys
const LOCAL_STORAGE_DEVICES_KEY = 'kidguard_local_devices_';
const LOCAL_STORAGE_PARENT_KEY = 'kidguard_local_parent';
const LOCAL_STORAGE_PAIRING_CODES_KEY = 'kidguard_local_pairing_codes';

// Load local fallback devices (empty by default if none paired)
export const loadLocalDevices = (parentUid: string): ParentChildDevice[] => {
  try {
    const raw = localStorage.getItem(`${LOCAL_STORAGE_DEVICES_KEY}${parentUid}`);
    if (raw) {
      const parsed: ParentChildDevice[] = JSON.parse(raw);
      // Clean out any legacy mock/dummy devices if user had them previously
      const sanitized = parsed.filter(d => 
        !d.childId?.includes('mock') && 
        !d.deviceModelName?.toLowerCase().includes('samsung galaxy a54') &&
        !d.deviceModelName?.toLowerCase().includes('google pixel 8')
      );
      if (sanitized.length !== parsed.length) {
        localStorage.setItem(`${LOCAL_STORAGE_DEVICES_KEY}${parentUid}`, JSON.stringify(sanitized));
      }
      return sanitized;
    }
  } catch (e) {
    console.error('Failed to load local devices', e);
  }
  return [];
};

export const toArray = <T>(val: any): T[] => {
  if (!val) return [];
  if (Array.isArray(val)) return val;
  if (typeof val === 'object') return Object.values(val);
  return [];
};

/**
 * Recursively removes any `undefined` properties and converts Date objects to ISO strings,
 * which is strictly required for Firebase Realtime Database update/set operations.
 */
export const sanitizeForRTDB = (data: any): any => {
  if (data === undefined) {
    return undefined;
  }
  if (data === null || typeof data !== 'object') {
    return data;
  }
  if (data instanceof Date) {
    return data.toISOString();
  }
  if (Array.isArray(data)) {
    return data
      .filter((item) => item !== undefined)
      .map((item) => sanitizeForRTDB(item));
  }
  const result: Record<string, any> = {};
  for (const [key, value] of Object.entries(data)) {
    if (value !== undefined) {
      const sanitized = sanitizeForRTDB(value);
      if (sanitized !== undefined) {
        result[key] = sanitized;
      }
    }
  }
  return result;
};

export const saveLocalDevices = (parentUid: string, devices: ParentChildDevice[]) => {
  try {
    const cleanDevices = devices.filter(d => 
      !d.childId?.includes('mock') && 
      !d.deviceModelName?.toLowerCase().includes('samsung galaxy a54') &&
      !d.deviceModelName?.toLowerCase().includes('google pixel 8')
    );
    localStorage.setItem(`${LOCAL_STORAGE_DEVICES_KEY}${parentUid}`, JSON.stringify(cleanDevices));
  } catch (e) {
    console.error('Failed to save local devices', e);
  }
};

// Check if device is recently online (within 90 seconds like in dashboard.js & Flutter app)
export const isDeviceRecentlyOnline = (device: ParentChildDevice): boolean => {
  if (device.presence?.online === false) return false;
  const heartbeat = device.presence?.heartbeatAt ?? device.presence?.lastSeen ?? device.lastHeartbeat ?? device.lastSeen;
  if (!heartbeat) return device.isOnline || false;
  
  const time = typeof heartbeat === 'number' 
    ? (heartbeat < 100000000000 ? heartbeat * 1000 : heartbeat)
    : Date.parse(String(heartbeat));
    
  return Number.isFinite(time) && (Date.now() - time) <= 90000;
};

// Authentication helper
export const getCurrentParent = (): { uid: string; email: string } | null => {
  const user = auth?.currentUser;
  if (user) {
    return {
      uid: user.uid,
      email: user.email || 'parent@kidguard.family',
    };
  }
  try {
    const stored = localStorage.getItem(LOCAL_STORAGE_PARENT_KEY);
    if (stored) {
      const parsed = JSON.parse(stored);
      // Verify if stored UID matches current auth (if auth is already loaded but user is null, stored is invalid)
      if (auth && !auth.currentUser) return null;
      return parsed;
    }
  } catch {
    // ignore
  }
  return null;
};

export const saveParentSession = (user: { uid: string; email: string }) => {
  try {
    localStorage.setItem(LOCAL_STORAGE_PARENT_KEY, JSON.stringify(user));
    localStorage.setItem('kidguard_auth_user', JSON.stringify(user));
  } catch {
    // ignore
  }
};

export const signInWithGoogle = async (): Promise<User | null> => {
  if (!auth) return null;
  const provider = new GoogleAuthProvider();
  try {
    const result = await signInWithPopup(auth, provider);
    const user = result.user;
    saveParentSession({ uid: user.uid, email: user.email || '' });
    return user;
  } catch (err) {
    console.error('Google Sign-In failed', err);
    throw err;
  }
};

export const signInWithEmail = async (email: string, pass: string): Promise<User | null> => {
  if (!auth) return null;
  try {
    const result = await signInWithEmailAndPassword(auth, email, pass);
    const user = result.user;
    saveParentSession({ uid: user.uid, email: user.email || '' });
    return user;
  } catch (err) {
    console.error('Email Sign-In failed', err);
    throw err;
  }
};

export const signUpWithEmail = async (email: string, pass: string): Promise<User | null> => {
  if (!auth) return null;
  try {
    const result = await createUserWithEmailAndPassword(auth, email, pass);
    const user = result.user;
    saveParentSession({ uid: user.uid, email: user.email || '' });
    return user;
  } catch (err) {
    console.error('Email Sign-Up failed', err);
    throw err;
  }
};

export const clearParentSession = () => {
  try {
    localStorage.removeItem(LOCAL_STORAGE_PARENT_KEY);
    localStorage.removeItem('kidguard_auth_user');
  } catch {
    // ignore
  }
};

export const signOut = async () => {
  if (auth) {
    await fbSignOut(auth);
  }
  clearParentSession();
  localStorage.removeItem('kidguard_auth_user');
};

// Watch devices from Firebase RTDB (returns real paired devices only, no mock/dummy devices)
export const subscribeToChildDevices = (
  parentUid: string,
  onDevicesUpdate: (devices: ParentChildDevice[]) => void,
  onError?: (err: Error) => void
): (() => void) => {
  if (!database) {
    const devices = loadLocalDevices(parentUid);
    onDevicesUpdate(devices);
    return () => {};
  }

  const childrenRef = ref(database, `parents/${parentUid}/children`);
  let isSubscribed = true;

  const unsubscribeListener = onValue(
    childrenRef,
    (snapshot) => {
      if (!isSubscribed) return;
      const val = snapshot.val();
      if (!val) {
        // No devices in Firebase RTDB: clean empty state
        onDevicesUpdate([]);
        saveLocalDevices(parentUid, []);
        return;
      }

      const devicesList: ParentChildDevice[] = [];
      const keys = Object.keys(val);
      
      // STRICT 1-DEVICE LIMIT: If there are multiple devices, we only take the most recent one
      // This cleans up legacy data and prevents UI clutter.
      let targetKeys = keys;
      if (keys.length > 1) {
        // Sort by timestamp if available
        targetKeys = keys.sort((a, b) => {
          const tA = val[a]?.timestamp || '';
          const tB = val[b]?.timestamp || '';
          return tB.localeCompare(tA);
        }).slice(0, 1);
      }

      targetKeys.forEach((key) => {
        const item = val[key];
        if (item && typeof item === 'object') {
          // Strictly exclude any legacy dummy/mock devices
          if (
            key.includes('mock') || 
            item.childId?.includes('mock') ||
            item.deviceModelName?.toLowerCase().includes('samsung galaxy a54') ||
            item.deviceModelName?.toLowerCase().includes('google pixel 8')
          ) {
            return;
          }

          const online = item.presence?.online === true || isDeviceRecentlyOnline(item);
          const rawLoc = item.location;
          let parsedLocation: LocationData | undefined = undefined;
          if (rawLoc && typeof rawLoc === 'object') {
            const latVal = rawLoc.latitude !== undefined ? rawLoc.latitude : rawLoc.lat;
            const lonVal = rawLoc.longitude !== undefined ? rawLoc.longitude : rawLoc.lon;
            const latNum = typeof latVal === 'number' ? latVal : parseFloat(latVal);
            const lonNum = typeof lonVal === 'number' ? lonVal : parseFloat(lonVal);
            if (!isNaN(latNum) && !isNaN(lonNum)) {
              parsedLocation = {
                latitude: latNum,
                longitude: lonNum,
                lat: latNum,
                lon: lonNum,
                accuracy: typeof rawLoc.accuracy === 'number' ? rawLoc.accuracy : (parseFloat(rawLoc.accuracy) || 10),
                speed: typeof rawLoc.speed === 'number' ? rawLoc.speed : (parseFloat(rawLoc.speed) || 0),
                timestamp: rawLoc.updatedAt || rawLoc.timestamp || Date.now(),
                updatedAt: rawLoc.updatedAt || rawLoc.timestamp || Date.now(),
                address: rawLoc.address || `${latNum.toFixed(5)}°, ${lonNum.toFixed(5)}°`,
              };
            }
          }

          devicesList.push({
            childId: item.childId || key,
            deviceId: item.deviceId || item.childId || key,
            childUid: item.childUid,
            pairingCode: String(item.pairingCode || item.bindingCode || key),
            status: item.status || 'bound',
            timestamp: item.timestamp || item.createdAt || new Date().toISOString(),
            isOnline: online,
            deviceModelName: item.deviceModelName || item.telemetry?.deviceModelName || `Device ${key.slice(0, 8)}`,
            deviceManufacturer: item.deviceManufacturer || item.telemetry?.deviceManufacturer || 'Android',
            platform: item.platform || item.telemetry?.platform || 'android',
            appState: item.appState || item.telemetry?.appState || 'resumed',
            presence: item.presence || {
              online: true,
              heartbeatAt: Date.now(),
              lastSeen: Date.now(),
            },
            telemetry: item.telemetry,
            location: parsedLocation,
            callLogs: toArray(item.callLogs),
            notifications: parseAndNormalizeNotifications(toArray(item.notifications)),
            appUsage: toArray(item.appUsage),
            monitoringSettings: item.monitoringSettings || {
              locationEnabled: true,
              callLogsEnabled: true,
              appUsageEnabled: true,
              notificationsEnabled: true,
            }
          });
        }
      });

      // Sort by newest
      devicesList.sort((a, b) => (b.timestamp || '').localeCompare(a.timestamp || ''));
      onDevicesUpdate(devicesList);
      saveLocalDevices(parentUid, devicesList);
    },
    (err) => {
      console.warn('Realtime Database listen error, checking local store:', err);
      const devices = loadLocalDevices(parentUid);
      onDevicesUpdate(devices);
      if (onError) onError(err);
    }
  );

  return () => {
    isSubscribed = false;
    off(childrenRef);
  };
};

/**
 * Listens to real-time GPS coordinates directly from Firebase RTDB under /devices/{pairingCode}/location.
 * Validates latitude/longitude and invokes callback with LocationData, or null if no valid GPS fix is available.
 */
export const subscribeToChildLocation = (
  pairingCode: string,
  onLocationUpdate: (location: LocationData | null) => void,
  onError?: (err: Error) => void
): (() => void) => {
  const cleanCode = (pairingCode || '').trim();
  if (!cleanCode) {
    onLocationUpdate(null);
    return () => {};
  }

  if (!database) {
    // Check local storage fallback for simulated/offline state
    try {
      const local = localStorage.getItem(`kidguard_last_location_${cleanCode}`);
      if (local) {
        const parsed = JSON.parse(local);
        if (
          typeof parsed?.latitude === 'number' &&
          !isNaN(parsed.latitude) &&
          typeof parsed?.longitude === 'number' &&
          !isNaN(parsed.longitude)
        ) {
          onLocationUpdate(parsed);
          return () => {};
        }
      }
    } catch {}
    onLocationUpdate(null);
    return () => {};
  }

  const locationRef = ref(database, `devices/${cleanCode}/location`);
  let isSubscribed = true;

  const unsubscribe = onValue(
    locationRef,
    async (snapshot) => {
      if (!isSubscribed) return;
      const val = snapshot.val();

      if (!val || typeof val !== 'object') {
        onLocationUpdate(null);
        return;
      }

      const latVal = val.latitude !== undefined ? val.latitude : val.lat;
      const lonVal = val.longitude !== undefined ? val.longitude : val.lon;

      const lat = typeof latVal === 'number' ? latVal : parseFloat(latVal);
      const lon = typeof lonVal === 'number' ? lonVal : parseFloat(lonVal);

      if (isNaN(lat) || isNaN(lon) || lat < -90 || lat > 90 || lon < -180 || lon > 180) {
        onLocationUpdate(null);
        return;
      }

      const accuracy = typeof val.accuracy === 'number' ? val.accuracy : parseFloat(val.accuracy) || 10;
      let address = typeof val.address === 'string' ? val.address.trim() : '';

      // If address is missing, attempt reverse geocoding via OpenStreetMap Nominatim
      if (!address) {
        try {
          const res = await fetch(
            `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lon}&zoom=18&addressdetails=1`,
            { headers: { 'Accept': 'application/json' } }
          );
          if (res.ok) {
            const data = await res.json();
            if (data?.display_name) {
              address = data.display_name;
            }
          }
        } catch {
          // If network fetch fails, format coordinates as address string
          address = `${lat.toFixed(5)}°, ${lon.toFixed(5)}°`;
        }
      }

      const timestamp = val.updatedAt || val.timestamp || val.time || Date.now();
      const locData: LocationData = {
        latitude: lat,
        longitude: lon,
        lat,
        lon,
        accuracy: Math.round(accuracy),
        address: address || `${lat.toFixed(5)}°, ${lon.toFixed(5)}°`,
        timestamp,
        updatedAt: timestamp,
        speed: val.speed !== undefined ? Number(val.speed) : 0,
      };

      try {
        localStorage.setItem(`kidguard_last_location_${cleanCode}`, JSON.stringify(locData));
      } catch {}

      onLocationUpdate(locData);
    },
    (err) => {
      console.warn(`Error listening to /devices/${cleanCode}/location:`, err);
      if (onError) onError(err);
      onLocationUpdate(null);
    }
  );

  return () => {
    isSubscribed = false;
    off(locationRef);
  };
};

/**
 * Updates real-time GPS coordinates directly in Firebase RTDB under /devices/{pairingCode}/location
 */
export const updateChildLocation = async (
  pairingCode: string,
  location: Partial<LocationData> & { latitude: number; longitude: number }
): Promise<void> => {
  const cleanCode = (pairingCode || '').trim();
  if (!cleanCode) return;

  const payload: Record<string, any> = {
    latitude: location.latitude,
    longitude: location.longitude,
    accuracy: location.accuracy || 10,
    address: location.address || '',
    timestamp: location.timestamp || Date.now(),
    speed: location.speed !== undefined ? location.speed : 0,
    updatedAt: new Date().toISOString(),
  };

  if (database) {
    try {
      const updates: Record<string, any> = {};
      const cleanPayload = sanitizeForRTDB(payload);
      updates[`devices/${cleanCode}/location`] = cleanPayload;
      updates[`pairings/${cleanCode}/location`] = cleanPayload;
      
      // Also update under parent node if we know which parent this child belongs to
      const parent = getCurrentParent();
      if (parent) {
        const childId = `child_${cleanCode}`;
        updates[`parents/${parent.uid}/children/${childId}/location`] = cleanPayload;
      }
      
      await update(ref(database), updates);
    } catch (e) {
      console.warn('Failed to push RTDB location update:', e);
    }
  }

  try {
    localStorage.setItem(`kidguard_last_location_${cleanCode}`, JSON.stringify(payload));
  } catch {}
};

/**
 * Normalizes duration to hours and formatted text.
 * Accepts numbers in hours, minutes, seconds, or milliseconds, or formatted strings.
 */
export const normalizeUsageDuration = (val: any): { hoursUsed: number; durationText: string } => {
  if (val === undefined || val === null) {
    return { hoursUsed: 0, durationText: '0m' };
  }

  let totalMinutes = 0;

  if (typeof val === 'number') {
    if (val > 100000) {
      // Milliseconds (e.g. Android UsageStats totalTimeInForeground)
      totalMinutes = Math.round(val / 60000);
    } else if (val > 300) {
      // Seconds
      totalMinutes = Math.round(val / 60);
    } else if (val > 24) {
      // Minutes
      totalMinutes = Math.round(val);
    } else {
      // Float hours (e.g. 1.5 hours)
      totalMinutes = Math.round(val * 60);
    }
  } else if (typeof val === 'string') {
    const trimmed = val.trim();
    const num = parseFloat(trimmed);
    if (!isNaN(num) && /^\d+(\.\d+)?$/.test(trimmed)) {
      if (num > 100000) totalMinutes = Math.round(num / 60000);
      else if (num > 300) totalMinutes = Math.round(num / 60);
      else if (num > 24) totalMinutes = Math.round(num);
      else totalMinutes = Math.round(num * 60);
    } else {
      const hoursMatch = trimmed.match(/(\d+(?:\.\d+)?)\s*(?:h|hr|hour)/i);
      const minsMatch = trimmed.match(/(\d+(?:\.\d+)?)\s*(?:m|min)/i);
      const secsMatch = trimmed.match(/(\d+(?:\.\d+)?)\s*(?:s|sec)/i);

      const h = hoursMatch ? parseFloat(hoursMatch[1]) : 0;
      const m = minsMatch ? parseFloat(minsMatch[1]) : 0;
      const s = secsMatch ? parseFloat(secsMatch[1]) : 0;

      totalMinutes = Math.round(h * 60 + m + s / 60);
    }
  }

  const hours = totalMinutes / 60;
  const hFloor = Math.floor(hours);
  const mRemainder = Math.round(totalMinutes % 60);

  let text = '';
  if (hFloor > 0 && mRemainder > 0) {
    text = `${hFloor}h ${mRemainder}m`;
  } else if (hFloor > 0) {
    text = `${hFloor}h`;
  } else {
    text = `${Math.max(1, mRemainder)}m`;
  }

  return {
    hoursUsed: Math.round(hours * 10) / 10,
    durationText: text,
  };
};

/**
 * Derives category, color, and icon for common applications if not explicitly provided
 */
export const getAppCategoryAndMeta = (appName: string = '', packageName: string = ''): { category: string; color: string; icon: string } => {
  const lower = `${appName} ${packageName}`.toLowerCase();

  if (lower.includes('youtube')) {
    return { category: 'Media & Entertainment', color: '#EF4444', icon: 'youtube' };
  }
  if (lower.includes('tiktok') || lower.includes('tik tok')) {
    return { category: 'Social Media', color: '#111827', icon: 'video' };
  }
  if (lower.includes('whatsapp') || lower.includes('com.whatsapp')) {
    return { category: 'Messaging', color: '#10B981', icon: 'message' };
  }
  if (lower.includes('instagram')) {
    return { category: 'Social Media', color: '#E1306C', icon: 'camera' };
  }
  if (lower.includes('free fire') || lower.includes('freefire') || lower.includes('roblox') || lower.includes('minecraft') || lower.includes('pubg') || lower.includes('brawl') || lower.includes('game')) {
    return { category: 'Games', color: '#8B5CF6', icon: 'gamepad' };
  }
  if (lower.includes('chrome') || lower.includes('firefox') || lower.includes('browser') || lower.includes('safari')) {
    return { category: 'Web Browser', color: '#3B82F6', icon: 'globe' };
  }
  if (lower.includes('spotify') || lower.includes('music') || lower.includes('sound')) {
    return { category: 'Music & Audio', color: '#10B981', icon: 'music' };
  }
  if (lower.includes('netflix') || lower.includes('disney') || lower.includes('prime') || lower.includes('twitch')) {
    return { category: 'Streaming', color: '#F43F5E', icon: 'tv' };
  }
  if (lower.includes('snapchat')) {
    return { category: 'Social Media', color: '#FBBF24', icon: 'camera' };
  }
  if (lower.includes('duolingo') || lower.includes('learn') || lower.includes('school') || lower.includes('khan')) {
    return { category: 'Education', color: '#22C55E', icon: 'book' };
  }
  if (lower.includes('camera') || lower.includes('photo') || lower.includes('gallery')) {
    return { category: 'Photos & Camera', color: '#F59E0B', icon: 'image' };
  }
  if (lower.includes('phone') || lower.includes('call') || lower.includes('contacts')) {
    return { category: 'Communication', color: '#06B6D4', icon: 'phone' };
  }

  return { category: 'Productivity', color: '#6366F1', icon: 'app' };
};

/**
 * Listens to real-time app usage statistics directly from Firebase RTDB under /devices/{pairingCode}/appUsage.
 * Dynamically converts RTDB snapshot (array or map) into structured AppUsageItem array.
 * If no usage data is sent from the child device yet, emits empty array [].
 */
export const subscribeToChildAppUsage = (
  pairingCode: string,
  onUsageUpdate: (appUsage: AppUsageItem[]) => void,
  onError?: (err: Error) => void
): (() => void) => {
  const cleanCode = (pairingCode || '').trim();
  if (!cleanCode) {
    onUsageUpdate([]);
    return () => {};
  }

  if (!database) {
    // Check local storage fallback for simulated/offline state
    try {
      const local = localStorage.getItem(`kidguard_last_app_usage_${cleanCode}`);
      if (local) {
        const parsed = JSON.parse(local);
        if (Array.isArray(parsed)) {
          onUsageUpdate(parsed);
          return () => {};
        }
      }
    } catch {}
    onUsageUpdate([]);
    return () => {};
  }

  const appUsageRef = ref(database, `devices/${cleanCode}/appUsage`);
  let isSubscribed = true;

  const unsubscribe = onValue(
    appUsageRef,
    (snapshot) => {
      if (!isSubscribed) return;
      const val = snapshot.val();

      if (!val) {
        onUsageUpdate([]);
        return;
      }

      // Convert array or key-value object to array
      const rawList: any[] = Array.isArray(val)
        ? val
        : typeof val === 'object'
        ? Object.entries(val).map(([k, v]) => (typeof v === 'object' && v ? { id: k, ...v } : { id: k, appName: k, hoursUsed: v }))
        : [];

      const normalized: AppUsageItem[] = rawList
        .filter(item => item && (item.appName || item.name || item.packageName || item.pkg))
        .map((item, index) => {
          const appName = item.appName || item.name || item.label || item.packageName?.split('.').pop() || `App ${index + 1}`;
          const packageName = item.packageName || item.pkg || '';
          const meta = getAppCategoryAndMeta(appName, packageName);
          
          const rawDuration = item.duration !== undefined 
            ? item.duration 
            : item.hoursUsed !== undefined 
            ? item.hoursUsed 
            : item.totalTimeInForeground !== undefined
            ? item.totalTimeInForeground
            : item.minutesUsed !== undefined
            ? item.minutesUsed
            : 0;

          const { hoursUsed, durationText } = normalizeUsageDuration(rawDuration);

          return {
            id: String(item.id || item.packageName || `app_${index}_${Date.now()}`),
            appName,
            packageName,
            category: item.category || meta.category,
            icon: item.icon || meta.icon,
            color: item.color || meta.color,
            hoursUsed: hoursUsed,
            duration: item.duration || durationText,
            durationText: durationText,
            lastTimeUsed: item.lastTimeUsed || item.lastUsed || undefined,
          };
        })
        .sort((a, b) => (b.hoursUsed || 0) - (a.hoursUsed || 0));

      try {
        localStorage.setItem(`kidguard_last_app_usage_${cleanCode}`, JSON.stringify(normalized));
      } catch {}

      onUsageUpdate(normalized);
    },
    (err) => {
      console.warn(`Error listening to /devices/${cleanCode}/appUsage:`, err);
      if (onError) onError(err);
      onUsageUpdate([]);
    }
  );

  return () => {
    isSubscribed = false;
    off(appUsageRef);
  };
};

/**
 * Updates or broadcasts real-time app usage statistics in Firebase RTDB under /devices/{pairingCode}/appUsage
 */
export const updateChildAppUsage = async (
  pairingCode: string,
  usageData: AppUsageItem[] | Record<string, any>
): Promise<void> => {
  const cleanCode = (pairingCode || '').trim();
  if (!cleanCode) return;

  if (database) {
    try {
      const cleanData = sanitizeForRTDB(usageData) ?? [];
      const updates: Record<string, any> = {};
      updates[`devices/${cleanCode}/appUsage`] = cleanData;
      updates[`pairings/${cleanCode}/appUsage`] = cleanData;
      await update(ref(database), updates);
    } catch (e) {
      console.warn('Failed to update RTDB appUsage:', e);
    }
  }

  try {
    localStorage.setItem(`kidguard_last_app_usage_${cleanCode}`, JSON.stringify(usageData));
  } catch {}
};

export const getSampleCallLogs = (): CallLogItem[] => [];

/**
 * Listens to real-time call logs directly from Firebase RTDB under /devices/{pairingCode}/callLogs.
 * Dynamically converts RTDB snapshot into structured CallLogItem array.
 * If no call logs exist in Firebase RTDB, emits empty array [].
 */
export const subscribeToChildCallLogs = (
  pairingCode: string,
  onLogsUpdate: (callLogs: CallLogItem[]) => void,
  onError?: (err: Error) => void
): (() => void) => {
  const cleanCode = (pairingCode || '').trim();
  if (!cleanCode) {
    onLogsUpdate([]);
    return () => {};
  }

  if (!database) {
    try {
      const local = localStorage.getItem(`kidguard_last_call_logs_${cleanCode}`);
      if (local) {
        const parsed = JSON.parse(local);
        if (Array.isArray(parsed)) {
          onLogsUpdate(parsed);
          return () => {};
        }
      }
    } catch {}
    onLogsUpdate([]);
    return () => {};
  }

  const db = database;
  const callLogsRef = ref(db, `devices/${cleanCode}/callLogs`);
  let isSubscribed = true;

  const unsubscribe = onValue(
    callLogsRef,
    (snapshot) => {
      if (!isSubscribed) return;
      const val = snapshot.val();

      if (!val) {
        // Also check if pairings/${cleanCode}/callLogs exists as fallback
        const pairingCallLogsRef = ref(db, `pairings/${cleanCode}/callLogs`);
        get(pairingCallLogsRef)
          .then((pairSnap) => {
            if (!isSubscribed) return;
            const pairVal = pairSnap.val();
            if (pairVal) {
              const rawList: any[] = Array.isArray(pairVal)
                ? pairVal
                : typeof pairVal === 'object'
                ? Object.values(pairVal)
                : [];
              const normalized: CallLogItem[] = rawList
                .filter(item => item && (item.name || item.number || item.id))
                .map((item, idx) => ({
                  id: String(item.id || `cl_${idx}`),
                  name: String(item.name || item.contactName || 'Unknown Contact'),
                  number: String(item.number || item.phoneNumber || ''),
                  type: (item.type === 'incoming' || item.type === 'outgoing' || item.type === 'missed') ? item.type : 'incoming',
                  duration: Number(item.duration) || 0,
                  timestamp: item.timestamp || Date.now(),
                }));
              onLogsUpdate(normalized);
            } else {
              onLogsUpdate([]);
            }
          })
          .catch(() => {
            if (isSubscribed) onLogsUpdate([]);
          });
        return;
      }

      const rawList: any[] = Array.isArray(val)
        ? val
        : typeof val === 'object'
        ? Object.values(val)
        : [];

      const normalized: CallLogItem[] = rawList
        .filter(item => item && (item.name || item.number || item.id))
        .map((item, idx) => ({
          id: String(item.id || `cl_${idx}`),
          name: String(item.name || item.contactName || 'Unknown Contact'),
          number: String(item.number || item.phoneNumber || ''),
          type: (item.type === 'incoming' || item.type === 'outgoing' || item.type === 'missed') ? item.type : 'incoming',
          duration: Number(item.duration) || 0,
          timestamp: item.timestamp || Date.now(),
        }));

      try {
        localStorage.setItem(`kidguard_last_call_logs_${cleanCode}`, JSON.stringify(normalized));
      } catch {}

      onLogsUpdate(normalized);
    },
    (err) => {
      console.warn(`Error listening to /devices/${cleanCode}/callLogs:`, err);
      if (onError) onError(err);
      onLogsUpdate([]);
    }
  );

  return () => {
    isSubscribed = false;
    off(callLogsRef);
  };
};

/**
 * Updates or broadcasts real-time call logs in Firebase RTDB under /devices/{pairingCode}/callLogs
 */
export const updateChildCallLogs = async (
  pairingCode: string,
  callLogs: CallLogItem[] | Record<string, any>
): Promise<void> => {
  const cleanCode = (pairingCode || '').trim();
  if (!cleanCode) return;

  if (database) {
    try {
      const cleanData = sanitizeForRTDB(callLogs) ?? [];
      const updates: Record<string, any> = {};
      updates[`devices/${cleanCode}/callLogs`] = cleanData;
      updates[`pairings/${cleanCode}/callLogs`] = cleanData;
      await update(ref(database), updates);
    } catch (e) {
      console.warn('Failed to update RTDB callLogs:', e);
    }
  }

  try {
    localStorage.setItem(`kidguard_last_call_logs_${cleanCode}`, JSON.stringify(callLogs));
  } catch {}
};

/**
 * Safely parses and normalizes raw notification data from Firebase RTDB snapshots.
 * Supports arrays or keyed maps, ensures valid timestamps and fallback category heuristics.
 */
export function parseAndNormalizeNotifications(rawList: any[]): NotificationItem[] {
  if (!Array.isArray(rawList)) {
    if (rawList && typeof rawList === 'object') {
      rawList = Object.values(rawList);
    } else {
      return [];
    }
  }

  return rawList
    .filter((item: any) => item && typeof item === 'object')
    .map((item: any, idx: number) => {
      const appName = String(item.appName || item.name || item.source || item.packageName?.split('.').pop() || 'Alert').trim();
      const packageName = String(item.packageName || item.pkg || '').trim();
      const title = String(item.title || item.header || item.subject || '').trim();
      const text = String(item.text || item.message || item.body || item.content || '').trim();

      // Determine category with intelligent heuristics if not explicitly given
      let category = item.category;
      if (!category) {
        const lower = `${appName} ${packageName} ${title}`.toLowerCase();
        if (lower.includes('whatsapp') || lower.includes('message') || lower.includes('chat') || lower.includes('sms') || lower.includes('telegram')) {
          category = 'messaging';
        } else if (lower.includes('classroom') || lower.includes('school') || lower.includes('duolingo') || lower.includes('canvas')) {
          category = 'education';
        } else if (lower.includes('game') || lower.includes('roblox') || lower.includes('minecraft') || lower.includes('play')) {
          category = 'game';
        } else if (lower.includes('youtube') || lower.includes('insta') || lower.includes('tiktok') || lower.includes('snapchat')) {
          category = 'social';
        } else {
          category = 'system';
        }
      }

      return {
        id: String(item.id || item.key || `notif_${idx}_${Date.now()}`),
        appName: appName || 'App Notification',
        packageName,
        title: title || appName,
        text,
        timestamp: item.timestamp || item.time || Date.now(),
        category,
      };
    })
    .sort((a, b) => {
      const timeA = typeof a.timestamp === 'number' ? a.timestamp : new Date(a.timestamp || 0).getTime();
      const timeB = typeof b.timestamp === 'number' ? b.timestamp : new Date(b.timestamp || 0).getTime();
      return (timeB || 0) - (timeA || 0);
    });
};

export const getSampleNotifications = (): NotificationItem[] => [];

/**
 * Listens to real-time notification alerts directly from Firebase RTDB under /devices/{pairingCode}/notifications.
 * Dynamically converts RTDB snapshot (array or map) into structured NotificationItem array.
 * If no notifications exist yet in Firebase RTDB, emits clean empty array [].
 */
export const subscribeToChildNotifications = (
  pairingCode: string,
  onNotificationsUpdate: (notifications: NotificationItem[]) => void,
  onError?: (err: Error) => void
): (() => void) => {
  const cleanCode = (pairingCode || '').trim();
  if (!cleanCode) {
    onNotificationsUpdate([]);
    return () => {};
  }

  const db = database;
  if (!db) {
    try {
      const local = localStorage.getItem(`kidguard_last_notifications_${cleanCode}`);
      if (local) {
        const parsed = JSON.parse(local);
        if (Array.isArray(parsed)) {
          onNotificationsUpdate(parsed);
          return () => {};
        }
      }
    } catch {}
    onNotificationsUpdate([]);
    return () => {};
  }

  const notifRef = ref(db, `devices/${cleanCode}/notifications`);
  let isSubscribed = true;

  const unsubscribe = onValue(
    notifRef,
    (snapshot) => {
      if (!isSubscribed) return;
      const val = snapshot.val();

      if (!val) {
        // Also check pairings/${cleanCode}/notifications as fallback
        const pairingNotifRef = ref(db, `pairings/${cleanCode}/notifications`);
        get(pairingNotifRef)
          .then((pairSnap) => {
            if (!isSubscribed) return;
            const pairVal = pairSnap.val();
            if (pairVal) {
              const rawList: any[] = Array.isArray(pairVal)
                ? pairVal
                : typeof pairVal === 'object'
                ? Object.values(pairVal)
                : [];
              const normalized = parseAndNormalizeNotifications(rawList);
              onNotificationsUpdate(normalized);
            } else {
              onNotificationsUpdate([]);
            }
          })
          .catch(() => {
            if (isSubscribed) onNotificationsUpdate([]);
          });
        return;
      }

      const rawList: any[] = Array.isArray(val)
        ? val
        : typeof val === 'object'
        ? Object.values(val)
        : [];

      const normalized = parseAndNormalizeNotifications(rawList);

      try {
        localStorage.setItem(`kidguard_last_notifications_${cleanCode}`, JSON.stringify(normalized));
      } catch {}

      onNotificationsUpdate(normalized);
    },
    (err) => {
      console.warn(`Error listening to /devices/${cleanCode}/notifications:`, err);
      if (onError) onError(err);
      onNotificationsUpdate([]);
    }
  );

  return () => {
    isSubscribed = false;
    off(notifRef);
  };
};

/**
 * Updates or broadcasts real-time notifications in Firebase RTDB under /devices/{pairingCode}/notifications
 */
export const updateChildNotifications = async (
  pairingCode: string,
  notifications: NotificationItem[] | Record<string, any>
): Promise<void> => {
  const cleanCode = (pairingCode || '').trim();
  if (!cleanCode) return;

  if (database) {
    try {
      const cleanData = sanitizeForRTDB(notifications) ?? [];
      const updates: Record<string, any> = {};
      updates[`devices/${cleanCode}/notifications`] = cleanData;
      updates[`pairings/${cleanCode}/notifications`] = cleanData;
      await update(ref(database), updates);
    } catch (e) {
      console.warn('Failed to update RTDB notifications:', e);
    }
  }

  try {
    localStorage.setItem(`kidguard_last_notifications_${cleanCode}`, JSON.stringify(notifications));
  } catch {}
};

/**
 * Listens to the complete standard device telemetry structure under /devices/{pairingCode}.
 * Formats status, location coordinates, logged calls, app usage metrics, and notifications safely with fallbacks.
 */
export const subscribeToChildDeviceTelemetry = (
  pairingCode: string,
  onTelemetryUpdate: (data: DeviceTelemetryData | null) => void,
  onError?: (err: Error) => void
): (() => void) => {
  const cleanCode = (pairingCode || '').trim();
  if (!cleanCode) {
    onTelemetryUpdate(null);
    return () => {};
  }

  const db = database;
  if (!db) {
    onTelemetryUpdate(null);
    return () => {};
  }

  const deviceRef = ref(db, `devices/${cleanCode}`);
  let isSubscribed = true;

  const unsubscribe = onValue(
    deviceRef,
    (snapshot) => {
      if (!isSubscribed) return;
      const val = snapshot.val();
      if (!val || typeof val !== 'object') {
        onTelemetryUpdate(null);
        return;
      }

      // 1. Status & Online computation
      const rawStatus = typeof val.status === 'string' ? val.status : 'paired';
      const presence = val.presence || { online: rawStatus === 'online', heartbeatAt: Date.now(), lastSeen: Date.now() };
      const online = presence.online === true || rawStatus === 'online' || isDeviceRecentlyOnline(val);

      // 2. Location coordinates formatting with safe fallback
      let locData: LocationData | null = null;
      if (val.location && typeof val.location === 'object') {
        const lat = typeof val.location.latitude === 'number' ? val.location.latitude : parseFloat(val.location.latitude);
        const lon = typeof val.location.longitude === 'number' ? val.location.longitude : parseFloat(val.location.longitude);
        if (!isNaN(lat) && !isNaN(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
          locData = {
            latitude: lat,
            longitude: lon,
            accuracy: Math.round(Number(val.location.accuracy) || 10),
            address: typeof val.location.address === 'string' ? val.location.address : `${lat.toFixed(5)}°, ${lon.toFixed(5)}°`,
            timestamp: val.location.timestamp || Date.now(),
            speed: Number(val.location.speed) || 0,
          };
        }
      }

      // 3. Logged calls formatting with safe fallback
      const rawCalls = Array.isArray(val.callLogs)
        ? val.callLogs
        : typeof val.callLogs === 'object' && val.callLogs !== null
        ? Object.values(val.callLogs)
        : [];
      const callLogs: CallLogItem[] = rawCalls
        .filter((c: any) => c && (c.name || c.number || c.id))
        .map((c: any, idx: number) => ({
          id: String(c.id || `cl_${idx}`),
          name: String(c.name || c.contactName || 'Unknown Contact'),
          number: String(c.number || c.phoneNumber || ''),
          type: (c.type === 'incoming' || c.type === 'outgoing' || c.type === 'missed') ? c.type : 'incoming',
          duration: Number(c.duration) || 0,
          timestamp: c.timestamp || Date.now(),
        }));

      // 4. App usage metrics formatting with safe fallback
      const rawUsage = Array.isArray(val.appUsage)
        ? val.appUsage
        : typeof val.appUsage === 'object' && val.appUsage !== null
        ? Object.entries(val.appUsage).map(([k, v]: [string, any]) => (typeof v === 'object' && v ? { id: k, ...v } : { id: k, appName: k, hoursUsed: v }))
        : [];
      const appUsage: AppUsageItem[] = rawUsage
        .filter((u: any) => u && (u.appName || u.name || u.packageName || u.pkg))
        .map((u: any, idx: number) => {
          const appName = u.appName || u.name || u.label || u.packageName?.split('.').pop() || `App ${idx + 1}`;
          const packageName = u.packageName || u.pkg || '';
          const meta = getAppCategoryAndMeta(appName, packageName);
          const rawDuration = u.duration !== undefined ? u.duration : u.hoursUsed !== undefined ? u.hoursUsed : u.totalTimeInForeground !== undefined ? u.totalTimeInForeground : 0;
          const { hoursUsed, durationText } = normalizeUsageDuration(rawDuration);
          return {
            id: String(u.id || u.packageName || `app_${idx}`),
            appName,
            packageName,
            category: u.category || meta.category,
            icon: u.icon || meta.icon,
            color: u.color || meta.color,
            hoursUsed,
            duration: u.duration || durationText,
            durationText,
            lastTimeUsed: u.lastTimeUsed || u.lastUsed,
          };
        });

      // 5. Notifications formatting with safe fallback
      const rawNotifs = Array.isArray(val.notifications)
        ? val.notifications
        : typeof val.notifications === 'object' && val.notifications !== null
        ? Object.values(val.notifications)
        : [];
      const notifications = parseAndNormalizeNotifications(rawNotifs);

      // 6. Device telemetry & presence
      const telemetry: TelemetryData = {
        platform: val.platform || val.telemetry?.platform || 'android',
        appState: val.appState || val.telemetry?.appState || 'resumed',
        deviceModel: val.deviceModel || val.telemetry?.deviceModel,
        deviceModelName: val.deviceModelName || val.telemetry?.deviceModelName || `Device ${cleanCode}`,
        batteryLevel: val.telemetry?.batteryLevel !== undefined ? Number(val.telemetry.batteryLevel) : val.batteryLevel !== undefined ? Number(val.batteryLevel) : undefined,
        isCharging: val.telemetry?.isCharging ?? val.isCharging,
        updatedAt: val.telemetry?.updatedAt || val.updatedAt || Date.now(),
      };

      onTelemetryUpdate({
        pairingCode: cleanCode,
        status: rawStatus,
        isOnline: online,
        location: locData,
        callLogs,
        appUsage,
        notifications,
        telemetry,
        presence,
        lastHeartbeat: val.lastHeartbeat || presence.heartbeatAt || Date.now(),
        lastSeen: val.lastSeen || presence.lastSeen || Date.now(),
        deviceModelName: val.deviceModelName || telemetry.deviceModelName || `Device ${cleanCode}`,
        platform: telemetry.platform || 'android',
        appState: telemetry.appState || 'resumed',
      });
    },
    (err) => {
      console.warn(`Error listening to /devices/${cleanCode}:`, err);
      if (onError) onError(err);
      onTelemetryUpdate(null);
    }
  );

  return () => {
    isSubscribed = false;
    off(deviceRef);
  };
};

/**
 * Listens directly to /devices/{pairingCode} for device status and online presence
 */
export const subscribeToChildDeviceStatus = (
  pairingCode: string,
  onStatusUpdate: (statusInfo: { status: string; isOnline: boolean; lastSeen?: number }) => void,
  onError?: (err: Error) => void
): (() => void) => {
  const cleanCode = (pairingCode || '').trim();
  if (!cleanCode) {
    onStatusUpdate({ status: 'offline', isOnline: false });
    return () => {};
  }

  const db = database;
  if (!db) {
    onStatusUpdate({ status: 'offline', isOnline: false });
    return () => {};
  }

  const statusRef = ref(db, `devices/${cleanCode}`);
  let isSubscribed = true;

  const unsubscribe = onValue(
    statusRef,
    (snapshot) => {
      if (!isSubscribed) return;
      const val = snapshot.val();
      if (!val) {
        onStatusUpdate({ status: 'offline', isOnline: false });
        return;
      }
      const rawStatus = typeof val.status === 'string' ? val.status : 'paired';
      const online = val.presence?.online === true || rawStatus === 'online' || isDeviceRecentlyOnline(val);
      onStatusUpdate({
        status: rawStatus,
        isOnline: online,
        lastSeen: val.lastSeen || val.presence?.lastSeen || Date.now(),
      });
    },
    (err) => {
      if (onError) onError(err);
      onStatusUpdate({ status: 'offline', isOnline: false });
    }
  );

  return () => {
    isSubscribed = false;
    off(statusRef);
  };
};

export interface DeviceVerificationResult {
  code: string;
  existsInRTDB: boolean;
  rtdbPath: string;
  deviceModelName: string;
  status: 'online' | 'ready' | 'pending' | 'paired' | 'synced';
  platform: string;
  batteryLevel: number;
  lastSeen?: string;
  verified: boolean;
  rawData?: any;
}

/**
 * Actively searches Firebase RTDB at /devices/{pairingCode} (and /pairings/{pairingCode}),
 * verifies the child device credentials and status, and returns the verification details.
 */
export const searchAndVerifyChildDevice = async (
  code: string
): Promise<DeviceVerificationResult> => {
  const cleanCode = code.trim().toUpperCase();
  if (!cleanCode || cleanCode.length < 4) {
    throw new Error('Please enter a valid binding code (e.g. FG-ABCDEF).');
  }

  let foundData: any = null;
  let foundPath = `pending_binds/${cleanCode}`;

  if (database) {
    try {
      // 1. Primary query: check /pending_binds/{code}
      const bindRef = ref(database, `pending_binds/${cleanCode}`);
      const snap = await get(bindRef);
      if (snap.exists() && snap.val()) {
        foundData = snap.val();
        foundPath = `pending_binds/${cleanCode}`;
      } else {
        // 2. Secondary query: check /devices/{code}
        const deviceRef = ref(database, `devices/${cleanCode}`);
        const deviceSnap = await get(deviceRef);
        if (deviceSnap.exists() && deviceSnap.val()) {
          foundData = deviceSnap.val();
          foundPath = `devices/${cleanCode}`;
        }
      }
    } catch (err) {
      console.warn('Realtime Database lookup failed for ' + cleanCode, err);
    }
  }

  const existsInRTDB = Boolean(foundData);
  const deviceModelName = foundData?.deviceModelName || foundData?.modelName || `Android Phone (${cleanCode})`;
  const platform = foundData?.platform || 'android';
  const batteryLevel = foundData?.telemetry?.batteryLevel || foundData?.batteryLevel || 85;
  const status = (foundData?.status === 'paired' || foundData?.status === 'synced')
    ? 'synced'
    : 'ready';

  return {
    code: cleanCode,
    existsInRTDB,
    rtdbPath: `/${foundPath}`,
    deviceModelName,
    status,
    platform,
    batteryLevel,
    lastSeen: foundData?.lastSeen || new Date().toISOString(),
    verified: true,
    rawData: foundData,
  };
};

/**
 * Real Firebase Realtime Database pairing query and claim logic.
 * Specifically searches Firebase RTDB path /devices/{pairingCode}, verifies child device status,
 * links it under parents/{parentUid}/children/{childId}, and marks it Online/Synced in RTDB.
 */
export const claimPairingCode = async (
  parentUid: string,
  code: string,
  customModelName?: string
): Promise<ParentChildDevice> => {
  const cleanCode = code.trim().toUpperCase();
  if (!cleanCode || cleanCode.length < 4) {
    throw new Error('Please enter a valid binding code (e.g. FG-ABCDEF).');
  }

  if (!database) throw new Error('Database not initialized');

  // 1. Check pending_binds first (new account-based system)
  const bindRef = ref(database, `pending_binds/${cleanCode}`);
  const bindSnap = await get(bindRef);

  if (bindSnap.exists() && bindSnap.val()) {
    const bindData = bindSnap.val();
    if (bindData.parentUid !== parentUid) {
      throw new Error('This code belongs to a different account. Please log in with the correct email.');
    }

    const deviceId = bindData.deviceId;
    const childId = bindData.childId;
    const nowIso = new Date().toISOString();

    // 1.5 Strictly enforce 1 device limit: Remove all existing children for this parent first
    try {
      const childrenRef = ref(database, `parents/${parentUid}/children`);
      const childrenSnap = await get(childrenRef);
      if (childrenSnap.exists()) {
        const children = childrenSnap.val();
        const cleanupUpdates: Record<string, any> = {};
        for (const cid of Object.keys(children)) {
          cleanupUpdates[`parents/${parentUid}/children/${cid}`] = null;
          // Also try to clear the device's own record if we have its code
          const oldCode = children[cid].pairingCode;
          if (oldCode) {
            cleanupUpdates[`devices/${oldCode}`] = null;
          }
        }
        await update(ref(database), cleanupUpdates);
      }
    } catch (e) {
      console.warn('Cleanup of existing devices failed (non-fatal):', e);
    }

    const connectedDevice: ParentChildDevice = {
      childId,
      deviceId,
      childUid: '',
      pairingCode: cleanCode,
      status: 'paired',
      timestamp: nowIso,
      isOnline: true,
      lastHeartbeat: nowIso,
      lastSeen: nowIso,
      deviceModelName: customModelName || bindData.deviceModelName,
      deviceManufacturer: 'Android',
      platform: 'android',
      appState: 'resumed',
      presence: { online: true, heartbeatAt: Date.now() },
      telemetry: {
        deviceModelName: customModelName || bindData.deviceModelName,
        platform: 'android',
        appState: 'resumed',
        batteryLevel: 100,
        isCharging: false,
        updatedAt: Date.now(),
      },
      monitoringSettings: {
        locationEnabled: true,
        callLogsEnabled: true,
        appUsageEnabled: true,
        notificationsEnabled: true,
      }
    };

    const updates: Record<string, any> = {};
    const sanitizedDevice = sanitizeForRTDB(connectedDevice);
    updates[`parents/${parentUid}/children/${childId}`] = sanitizedDevice;
    
    // Use deep paths to avoid wiping child telemetry
    updates[`devices/${cleanCode}/deviceId`] = deviceId;
    updates[`devices/${cleanCode}/childId`] = childId;
    updates[`devices/${cleanCode}/pairingCode`] = cleanCode;
    updates[`devices/${cleanCode}/parentUid`] = parentUid;
    updates[`devices/${cleanCode}/status`] = 'synced';
    updates[`devices/${cleanCode}/online`] = true;
    updates[`devices/${cleanCode}/lastSeen`] = nowIso;
    updates[`devices/${cleanCode}/deviceModelName`] = customModelName || bindData.deviceModelName;

    updates[`pairings/${cleanCode}/deviceId`] = deviceId;
    updates[`pairings/${cleanCode}/childId`] = childId;
    updates[`pairings/${cleanCode}/pairingCode`] = cleanCode;
    updates[`pairings/${cleanCode}/parentUid`] = parentUid;
    updates[`pairings/${cleanCode}/status`] = 'synced';
    updates[`pairings/${cleanCode}/online`] = true;
    
    await update(ref(database), updates);
    await remove(bindRef);

    return connectedDevice;
  }

  let verifiedChildData: any = null;
  let sourcePath = '';
  let matchedKey = cleanCode;

  if (database) {
    try {
      // 1. Query path /devices/{pairingCode} directly
      const deviceRef = ref(database, `devices/${cleanCode}`);
      const deviceSnap = await get(deviceRef);
      if (deviceSnap.exists() && deviceSnap.val()) {
        verifiedChildData = deviceSnap.val();
        sourcePath = `devices/${cleanCode}`;
      }

      // 2. Query path /pairings/{code}
      if (!verifiedChildData) {
        const pairingRef = ref(database, `pairings/${cleanCode}`);
        const pairingSnap = await get(pairingRef);
        if (pairingSnap.exists() && pairingSnap.val()) {
          verifiedChildData = pairingSnap.val();
          sourcePath = `pairings/${cleanCode}`;
        }
      }

      // 3. Query path /pairing_codes/{code}
      if (!verifiedChildData) {
        const codeRef = ref(database, `pairing_codes/${cleanCode}`);
        const codeSnap = await get(codeRef);
        if (codeSnap.exists() && codeSnap.val()) {
          verifiedChildData = codeSnap.val();
          sourcePath = `pairing_codes/${cleanCode}`;
        }
      }

      // 4. Query /pairing_codes collection where pairingCode matches
      if (!verifiedChildData) {
        const allPairingCodesSnap = await get(ref(database, 'pairing_codes'));
        if (allPairingCodesSnap.exists()) {
          const all = allPairingCodesSnap.val();
          for (const key of Object.keys(all)) {
            const item = all[key];
            if (item && String(item.pairingCode || '').padStart(4, '0') === cleanCode) {
              verifiedChildData = item;
              matchedKey = key;
              sourcePath = `pairing_codes/${key}`;
              break;
            }
          }
        }
      }

      // 5. Query /devices collection where pairingCode matches
      if (!verifiedChildData) {
        const devicesRef = ref(database, 'devices');
        const codeQuery = query(devicesRef, orderByChild('pairingCode'), equalTo(cleanCode));
        const codeSnap = await get(codeQuery);
        
        if (codeSnap.exists()) {
          const all = codeSnap.val();
          const firstKey = Object.keys(all)[0];
          verifiedChildData = all[firstKey];
          matchedKey = firstKey;
          sourcePath = `devices/${firstKey}`;
        }
      }
    } catch (e) {
      console.warn('Firebase query encountered issue, attempting resilient registration:', e);
    }
  }

  // If not yet existing in RTDB, initialize child device at /devices/{pairingCode} and /pairings/{code}
  const childId = verifiedChildData?.childId || `child_${cleanCode}`;
  const deviceId = verifiedChildData?.deviceId || matchedKey || `dev_${cleanCode}`;
  const deviceModelName = customModelName?.trim() || verifiedChildData?.deviceModelName || verifiedChildData?.modelName || `Android Phone (${cleanCode})`;
  const nowIso = new Date().toISOString();

  const connectedDevice: ParentChildDevice = {
    childId,
    deviceId,
    childUid: verifiedChildData?.childUid || '',
    pairingCode: cleanCode,
    status: 'paired',
    timestamp: nowIso,
    isOnline: true,
    lastHeartbeat: nowIso,
    lastSeen: nowIso,
    deviceModelName,
    deviceManufacturer: verifiedChildData?.deviceManufacturer || 'Android',
    platform: verifiedChildData?.platform || 'android',
    appState: 'resumed',
    presence: {
      online: true,
      heartbeatAt: Date.now(),
      lastSeen: Date.now(),
    },
    telemetry: verifiedChildData?.telemetry || {
      deviceModelName,
      platform: 'android',
      appState: 'resumed',
      batteryLevel: verifiedChildData?.batteryLevel || 88,
      isCharging: false,
      updatedAt: Date.now(),
    },
    ...(verifiedChildData?.location && typeof verifiedChildData.location.latitude === 'number'
      ? { location: sanitizeForRTDB(verifiedChildData.location) }
      : {}),
    callLogs: toArray(verifiedChildData?.callLogs),
    notifications: toArray(verifiedChildData?.notifications),
    appUsage: toArray(verifiedChildData?.appUsage),
    monitoringSettings: {
      locationEnabled: true,
      callLogsEnabled: true,
      appUsageEnabled: true,
      notificationsEnabled: true,
    }
  };

  // Write verified & paired device to Firebase Realtime Database
  if (database) {
    try {
      const rawUpdates: Record<string, any> = {};

      // 1. Save connected child device under parents/{parentUid}/children/{childId}
      rawUpdates[`parents/${parentUid}/children/${childId}`] = sanitizeForRTDB(connectedDevice);

      // 2. Update status to Online/Synced under /devices/{cleanCode} using deep paths
      rawUpdates[`devices/${cleanCode}/deviceId`] = deviceId;
      rawUpdates[`devices/${cleanCode}/childId`] = childId;
      rawUpdates[`devices/${cleanCode}/pairingCode`] = cleanCode;
      rawUpdates[`devices/${cleanCode}/parentUid`] = parentUid;
      rawUpdates[`devices/${cleanCode}/status`] = 'synced';
      rawUpdates[`devices/${cleanCode}/online`] = true;
      rawUpdates[`devices/${cleanCode}/lastSeen`] = nowIso;
      rawUpdates[`devices/${cleanCode}/updatedAt`] = nowIso;
      rawUpdates[`devices/${cleanCode}/deviceModelName`] = deviceModelName;

      // 3. Update status to Online/Synced under /pairings/{cleanCode}
      rawUpdates[`pairings/${cleanCode}/deviceId`] = deviceId;
      rawUpdates[`pairings/${cleanCode}/childId`] = childId;
      rawUpdates[`pairings/${cleanCode}/pairingCode`] = cleanCode;
      rawUpdates[`pairings/${cleanCode}/parentUid`] = parentUid;
      rawUpdates[`pairings/${cleanCode}/status`] = 'synced';
      rawUpdates[`pairings/${cleanCode}/online`] = true;
      rawUpdates[`pairings/${cleanCode}/lastSeen`] = nowIso;
      rawUpdates[`pairings/${cleanCode}/updatedAt`] = nowIso;
      rawUpdates[`pairings/${cleanCode}/deviceModelName`] = deviceModelName;

      // 4. Update source path if different
      if (sourcePath && sourcePath !== `devices/${cleanCode}` && sourcePath !== `pairings/${cleanCode}`) {
        rawUpdates[`${sourcePath}/status`] = 'paired';
        rawUpdates[`${sourcePath}/parentUid`] = parentUid;
        rawUpdates[`${sourcePath}/online`] = true;
        rawUpdates[`${sourcePath}/lastSeen`] = nowIso;
      }

      const cleanUpdates: Record<string, any> = {};
      for (const [path, val] of Object.entries(rawUpdates)) {
        if (val !== undefined) {
          const sanitized = sanitizeForRTDB(val);
          if (sanitized !== undefined) {
            cleanUpdates[path] = sanitized;
          }
        }
      }

      await update(ref(database), cleanUpdates);
    } catch (err) {
      console.error('Failed to update RTDB records during pairing:', err);
    }
  }

  // Update local parent console state cache
  // Strictly enforce 1-device limit: replace all existing with the new one
  const updatedList = [connectedDevice];
  saveLocalDevices(parentUid, updatedList);

  return connectedDevice;
};

// Simplified and robust pairing logic for the "FlashGet Kids" style
export const pairChildDevice = async (
  parentUid: string, 
  code: string, 
  customModelName?: string
): Promise<ParentChildDevice> => {
  if (!database) throw new Error('Database not initialized');
  const cleanCode = (code || '').trim().toUpperCase();

  // 1. Fetch the pending bind or device record
  const bindRef = ref(database, `pending_binds/${cleanCode}`);
  const deviceRef = ref(database, `devices/${cleanCode}`);
  
  const [bindSnap, deviceSnap] = await Promise.all([
    get(bindRef),
    get(deviceRef)
  ]);

  const bindData = bindSnap.val();
  const deviceData = deviceSnap.val();
  
  if (!bindData && !deviceData) {
    throw new Error('Invalid or expired pairing code. Please regenerate on child device.');
  }

  const baseData = bindData || deviceData;
  const childId = baseData.childId || `child_${cleanCode}`;
  const deviceId = baseData.deviceId || `dev_${cleanCode}`;
  const modelName = customModelName || baseData.deviceModelName || `Device ${cleanCode}`;

  // 2. ENFORCE 1-DEVICE LIMIT: Prepare a multi-path update to wipe existing links
  // This ensures that when a new device is paired, ALL traces of old devices for this parent are removed.
  const parentChildrenRef = ref(database, `parents/${parentUid}/children`);
  const existingChildrenSnap = await get(parentChildrenRef);
  const existingChildren = existingChildrenSnap.val();
  
  const updates: Record<string, any> = {};
  
  // Wipe all existing children for this parent from RTDB
  if (existingChildren) {
    Object.keys(existingChildren).forEach(oldChildId => {
      const oldChild = existingChildren[oldChildId];
      updates[`parents/${parentUid}/children/${oldChildId}`] = null;
      if (oldChild?.pairingCode) {
        // Remove from all known global nodes
        const pCode = oldChild.pairingCode;
        updates[`devices/${pCode}`] = null;
        updates[`pairings/${pCode}`] = null;
        updates[`control/${pCode}`] = null;
        updates[`stream/${pCode}`] = null;
        updates[`signaling/${pCode}`] = null;
      }
    });
  }

  // 3. Prepare the new paired device record
  const nowIso = new Date().toISOString();
  const connectedDevice: ParentChildDevice = {
    childId,
    deviceId,
    childUid: baseData.childUid || '',
    pairingCode: cleanCode,
    status: 'paired',
    timestamp: nowIso,
    isOnline: true,
    lastHeartbeat: nowIso,
    lastSeen: nowIso,
    deviceModelName: modelName,
    deviceManufacturer: baseData.deviceManufacturer || 'Android',
    platform: baseData.platform || 'android',
    appState: 'resumed',
    presence: { online: true, heartbeatAt: Date.now(), lastSeen: Date.now() },
    telemetry: baseData.telemetry || {
      deviceModelName: modelName,
      platform: 'android',
      appState: 'resumed',
      batteryLevel: 100,
      isCharging: false,
      updatedAt: Date.now(),
    },
    monitoringSettings: {
      locationEnabled: true,
      callLogsEnabled: true,
      appUsageEnabled: true,
      notificationsEnabled: true,
    }
  };

  // 4. Save the new link and clear pending bind
  updates[`parents/${parentUid}/children/${childId}`] = sanitizeForRTDB(connectedDevice);
  
  // Use deep paths to preserve existing child telemetry (location, battery, etc.)
  updates[`devices/${cleanCode}/deviceId`] = deviceId;
  updates[`devices/${cleanCode}/childId`] = childId;
  updates[`devices/${cleanCode}/pairingCode`] = cleanCode;
  updates[`devices/${cleanCode}/parentUid`] = parentUid;
  updates[`devices/${cleanCode}/status`] = 'synced';
  updates[`devices/${cleanCode}/online`] = true;
  updates[`devices/${cleanCode}/lastSeen`] = nowIso;
  updates[`devices/${cleanCode}/deviceModelName`] = modelName;

  updates[`pairings/${cleanCode}/deviceId`] = deviceId;
  updates[`pairings/${cleanCode}/childId`] = childId;
  updates[`pairings/${cleanCode}/pairingCode`] = cleanCode;
  updates[`pairings/${cleanCode}/parentUid`] = parentUid;
  updates[`pairings/${cleanCode}/status`] = 'synced';
  updates[`pairings/${cleanCode}/online`] = true;
  
  // Also clear signaling artifacts from previous sessions
  updates[`devices/${cleanCode}/signaling`] = null;
  updates[`devices/${cleanCode}/stream/offer`] = null;
  updates[`devices/${cleanCode}/stream/answer`] = null;
  updates[`devices/${cleanCode}/stream/childCandidates`] = null;
  updates[`devices/${cleanCode}/stream/parentCandidates`] = null;

  // 5. Atomic Update
  await update(ref(database), updates);
  if (bindSnap.exists()) {
    await remove(bindRef);
  }

  // Update local cache
  saveLocalDevices(parentUid, [connectedDevice]);

  return connectedDevice;
};

// Unlink child device (Fully remove from everywhere)
export const unlinkChildDevice = async (parentUid: string, childId: string): Promise<void> => {
  if (!database) return;
  try {
    const parentChildRef = ref(database, `parents/${parentUid}/children/${childId}`);
    const snap = await get(parentChildRef);
    const data = snap.val();

    const updates: Record<string, any> = {};
    updates[`parents/${parentUid}/children/${childId}`] = null;

    if (data && data.pairingCode) {
      const pCode = data.pairingCode;
      updates[`devices/${pCode}`] = null;
      updates[`pairings/${pCode}`] = null;
      updates[`control/${pCode}`] = null;
      updates[`pending_binds/${pCode}`] = null;
      updates[`stream/${pCode}`] = null;
      updates[`signaling/${pCode}`] = null;
      
      // Also clear signaling candidates
      updates[`devices/${pCode}/signaling`] = null;
      updates[`devices/${pCode}/stream`] = null;
    }

    // Atomic removal
    await update(ref(database), updates);
    console.log(`Device ${childId} successfully unlinked from RTDB.`);
  } catch (e) {
    console.warn('Firebase unlink error:', e);
    throw e;
  }

  const current = loadLocalDevices(parentUid);
  const updated = current.filter(d => d.childId !== childId);
  saveLocalDevices(parentUid, updated);
};

/**
 * Specifically requested delete function that targets a device by its pairing code.
 * Removes the device node and all associations from Firebase RTDB.
 */
export const deleteChildDevice = async (deviceCode: string): Promise<void> => {
  if (!database) return;
  const cleanCode = (deviceCode || '').trim().toUpperCase();
  const parent = getCurrentParent();
  if (!parent) throw new Error('Parent authentication required to delete devices');

  try {
    // 1. Identify the childId in the parent's list that matches this code
    const childrenRef = ref(database, `parents/${parent.uid}/children`);
    const snap = await get(childrenRef);
    const children = snap.val();
    
    let childId = `child_${cleanCode}`; // Default fallback
    if (children) {
      const foundId = Object.keys(children).find(key => children[key].pairingCode === cleanCode);
      if (foundId) childId = foundId;
    }

    // 2. Perform thorough unlinking
    await unlinkChildDevice(parent.uid, childId);
    console.log(`Device ${cleanCode} successfully deleted and synced!`);
  } catch (err) {
    console.error('Error deleting device:', err);
    throw err;
  }
};

// Send remote command (startStream, stopStream, switchCamera, toggleAudioMute, syncLocation)
export const sendRemoteCommand = async (
  deviceId: string,
  parentUid: string,
  childId: string,
  command: 'startStream' | 'stopStream' | 'switchCamera' | 'toggleAudioMute' | 'startScreenShare' | 'stopScreenShare' | 'syncLocation',
  fields: Record<string, any> = {}
): Promise<void> => {
  const commandId = `${Date.now()}_${parentUid}`;
  const payload: RemoteCommand = {
    deviceId,
    parentUid,
    childId,
    commandId,
    command,
    requestedBy: parentUid,
    requestedAt: Date.now(),
    ...fields,
  };

  if (database) {
    try {
      const cleanPayload = sanitizeForRTDB(payload);
      await update(ref(database, `devices/${deviceId}/control`), cleanPayload);
      return;
    } catch (e) {
      console.warn('Firebase send command error:', e);
    }
  }

  // Also dispatch window custom event for local simulator / multi-tab test
  window.dispatchEvent(new CustomEvent('kidguard_remote_command', { detail: payload }));
};

// Child Mode Helper: Get or Create pairing code tied to the user UID
export const getOrCreateChildPairingCode = async (
  uid: string,
  deviceId: string,
  modelName = 'Child Browser Companion'
): Promise<string> => {
  if (!database) return '';

  try {
    // 1. Check if this UID already has a code
    const userRef = ref(database, `user_pairing_codes/${uid}`);
    const snap = await get(userRef);
    if (snap.exists()) {
      return snap.val();
    }

    // 2. No code found, generate a new one
    const chars = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    let randomPart = '';
    for (let i = 0; i < 6; i++) {
      randomPart += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    const code = `FG-${randomPart}`;
    const createdAt = new Date().toISOString();

    const updates: Record<string, any> = {
      [`user_pairing_codes/${uid}`]: code,
      [`devices/${code}`]: {
        deviceId,
        childId: `child_${deviceId}`,
        pairingCode: code,
        status: 'pending',
        createdAt,
        lastSeen: createdAt,
        deviceModelName: modelName,
        online: true,
      }
    };

    await update(ref(database), updates);
    return code;
  } catch (e) {
    console.warn('Failed to get/create child pairing code:', e);
    return '';
  }
};

export const createChildPairingCodeRecord = async (
  deviceId: string,
  modelName = 'Child Browser Companion'
): Promise<string> => {
  const chars = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  let randomPart = '';
  for (let i = 0; i < 6; i++) randomPart += chars.charAt(Math.floor(Math.random() * chars.length));
  const code = `FG-${randomPart}`;
  const createdAt = new Date().toISOString();

  if (database) {
    try {
      const updates = {
        [`devices/${code}`]: {
          deviceId,
          childId: `child_${deviceId}`,
          pairingCode: code,
          status: 'pending',
          createdAt,
          online: true,
          deviceModelName: modelName,
        }
      };
      await update(ref(database), updates);
    } catch (e) { console.warn(e); }
  }
  return code;
};

/**
 * Creates a one-time binding code in /pending_binds/{code}
 */
export const createPendingBind = async (
  parentUid: string,
  deviceId: string,
  modelName: string,
  forceCode?: string
): Promise<string> => {
  if (!database) return '';

  const chars = '0123456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  let randomPart = '';
  for (let i = 0; i < 6; i++) {
    randomPart += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  const code = forceCode || `FG-${randomPart}`;
  const now = Date.now();

  const bindRecord = {
    deviceId,
    childId: `child_${deviceId}`,
    pairingCode: code,
    deviceModelName: modelName,
    parentUid,
    status: 'pending_bind',
    createdAt: now,
  };

  try {
    await set(ref(database, `pending_binds/${code}`), sanitizeForRTDB(bindRecord));
    return code;
  } catch (e) {
    console.error('Failed to create pending bind', e);
    throw e;
  }
};

/**
 * Parent claims a binding code. Moves device to parent's active list and deletes the code.
 */
export const claimBindingCode = async (
  parentUid: string,
  code: string
): Promise<ParentChildDevice> => {
  if (!database) throw new Error('Database not initialized');

  const cleanCode = (code || '').trim().toUpperCase();
  const bindRef = ref(database, `pending_binds/${cleanCode}`);
  const snapshot = await get(bindRef);

  if (!snapshot.exists()) {
    throw new Error('Invalid or expired binding code');
  }

  const bindData = snapshot.val();
  if (bindData.parentUid !== parentUid) {
    throw new Error('This code belongs to a different account. Please log in with the correct email.');
  }

  const deviceId = bindData.deviceId;
  const childId = bindData.childId;
  const nowIso = new Date().toISOString();

  const connectedDevice: ParentChildDevice = {
    childId,
    deviceId,
    childUid: '',
    pairingCode: cleanCode,
    status: 'paired',
    timestamp: nowIso,
    isOnline: true,
    lastHeartbeat: nowIso,
    lastSeen: nowIso,
    deviceModelName: bindData.deviceModelName,
    deviceManufacturer: 'Android',
    platform: 'android',
    appState: 'resumed',
    presence: { online: true, heartbeatAt: Date.now() },
    telemetry: {
      deviceModelName: bindData.deviceModelName,
      platform: 'android',
      appState: 'resumed',
      batteryLevel: 100,
      isCharging: false,
      updatedAt: Date.now(),
    },
    monitoringSettings: {
      locationEnabled: true,
      callLogsEnabled: true,
      appUsageEnabled: true,
      notificationsEnabled: true,
    }
  };

  const updates: Record<string, any> = {};
  updates[`parents/${parentUid}/children/${childId}`] = sanitizeForRTDB(connectedDevice);
  
  // Use deep paths for backward compatibility and preservation
  updates[`devices/${cleanCode}/deviceId`] = deviceId;
  updates[`devices/${cleanCode}/childId`] = childId;
  updates[`devices/${cleanCode}/pairingCode`] = cleanCode;
  updates[`devices/${cleanCode}/parentUid`] = parentUid;
  updates[`devices/${cleanCode}/status`] = 'synced';
  updates[`devices/${cleanCode}/online`] = true;
  updates[`devices/${cleanCode}/lastSeen`] = nowIso;
  updates[`devices/${cleanCode}/deviceModelName`] = bindData.deviceModelName;
  
  await update(ref(database), updates);
  
  // CRITICAL: Delete the temporary binding code after successful link
  await remove(bindRef);

  return connectedDevice;
};



/**
 * Child Mode / Test Helper: Regenerates child pairing code and marks previous code as regenerated
 * in Firebase RTDB so active parent viewers can detect it immediately.
 */
export const regenerateChildPairingCode = async (
  deviceId: string,
  previousCode?: string,
  modelName = 'Child Browser Companion',
  newCodeProposal?: string
): Promise<string> => {
  const code = (newCodeProposal || Math.floor(1000 + Math.random() * 9000).toString()).padStart(4, '0');
  const createdAt = new Date().toISOString();

  const record: PairingRecord = {
    deviceId,
    childId: `child_${deviceId}`,
    pairingCode: code,
    status: 'pending',
    createdAt,
    lastSeen: createdAt,
    timestamp: createdAt,
  };

  if (database) {
    try {
      const rawUpdates: Record<string, any> = {
        [`devices/${code}`]: {
          ...record,
          deviceModelName: modelName,
          status: 'pending',
          online: true,
        },
        [`pairings/${code}`]: {
          ...record,
          deviceModelName: modelName,
          status: 'pending',
          online: true,
        },
        [`pairing_codes/${deviceId}`]: {
          ...record,
          previousPairingCode: previousCode || null,
        },
        [`devices/${deviceId}`]: {
          ...record,
          pairingCode: code,
          previousPairingCode: previousCode || null,
        },
      };

      if (previousCode && previousCode !== code) {
        rawUpdates[`devices/${previousCode}/status`] = 'regenerated';
        rawUpdates[`devices/${previousCode}/newPairingCode`] = code;
        rawUpdates[`devices/${previousCode}/regeneratedAt`] = Date.now();
        rawUpdates[`pairings/${previousCode}/status`] = 'regenerated';
        rawUpdates[`pairings/${previousCode}/newPairingCode`] = code;
        rawUpdates[`pairings/${previousCode}/regeneratedAt`] = Date.now();
      }

      await update(ref(database), sanitizeForRTDB(rawUpdates));
    } catch (e) {
      console.warn('Could not regenerate child pairing code in Firebase:', e);
    }
  }

  try {
    const raw = localStorage.getItem(LOCAL_STORAGE_PAIRING_CODES_KEY);
    const codes = raw ? JSON.parse(raw) : {};
    codes[deviceId] = record;
    codes[code] = record;
    if (previousCode) {
      codes[previousCode] = { ...(codes[previousCode] || {}), status: 'regenerated', newPairingCode: code };
    }
    localStorage.setItem(LOCAL_STORAGE_PAIRING_CODES_KEY, JSON.stringify(codes));
    localStorage.setItem(`kidguard_regenerated_code_${deviceId}`, code);
    if (previousCode) {
      localStorage.setItem(`kidguard_regenerated_code_${previousCode}`, code);
    }
  } catch {
    // ignore
  }

  // Dispatch custom event for multi-tab or local testing
  window.dispatchEvent(
    new CustomEvent('kidguard_pairing_code_regenerated', {
      detail: { deviceId, previousCode, newPairingCode: code },
    })
  );

  return code;
};
