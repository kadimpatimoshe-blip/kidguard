export interface PresenceData {
  online: boolean;
  heartbeatAt?: number | string;
  lastSeen?: number | string;
}

export interface TelemetryData {
  platform?: string;
  appState?: string;
  deviceModel?: string;
  deviceManufacturer?: string;
  deviceModelName?: string;
  batteryLevel?: number;
  isCharging?: boolean;
  updatedAt?: number | string;
}

export interface LocationData {
  latitude: number;
  longitude: number;
  accuracy: number;
  address?: string;
  timestamp: number | string;
  speed?: number;
  lat?: number;
  lon?: number;
  updatedAt?: number | string;
}

export interface CallLogItem {
  id: string;
  name: string;
  number: string;
  type: 'incoming' | 'outgoing' | 'missed';
  duration: number; // in seconds
  timestamp: string | number;
}

export interface NotificationItem {
  id: string;
  appName: string;
  packageName: string;
  title: string;
  text: string;
  timestamp: string | number;
  category?: string;
}

export interface AppUsageItem {
  id?: string;
  appName: string;
  packageName?: string;
  hoursUsed?: number;
  duration?: number | string;
  durationText?: string;
  category?: string;
  icon?: string;
  color?: string;
  lastTimeUsed?: number | string;
}

export interface DeviceTelemetryData {
  pairingCode: string;
  status: string;
  isOnline: boolean;
  location: LocationData | null;
  callLogs: CallLogItem[];
  appUsage: AppUsageItem[];
  notifications: NotificationItem[];
  telemetry?: TelemetryData;
  presence?: PresenceData;
  lastHeartbeat?: string | number | Date;
  lastSeen?: string | number | Date;
  deviceModelName?: string;
  platform?: string;
  appState?: string;
}

export interface ParentChildDevice {
  childId: string;
  pairingCode: string;
  status: 'pending' | 'paired' | 'unpaired' | 'expired' | 'waiting' | 'online' | 'offline' | 'regenerated' | string;
  timestamp: string;
  deviceId?: string;
  childUid?: string;
  isOnline: boolean;
  lastHeartbeat?: string | Date;
  lastSeen?: string | Date;
  platform?: string;
  appState?: string;
  deviceKey?: string;
  deviceModelName?: string;
  deviceManufacturer?: string;
  presence?: PresenceData;
  telemetry?: TelemetryData;
  location?: LocationData;
  callLogs?: CallLogItem[];
  notifications?: NotificationItem[];
  appUsage?: AppUsageItem[];
  monitoringSettings?: {
    locationEnabled: boolean;
    callLogsEnabled: boolean;
    appUsageEnabled: boolean;
    notificationsEnabled: boolean;
  };
}

export interface PairingRecord {
  deviceId: string;
  childId: string;
  childUid?: string;
  pairingCode: string;
  status: 'pending' | 'waiting' | 'paired' | 'expired';
  createdAt: string;
  lastSeen?: string;
  timestamp: string;
  parentUid?: string;
}

export interface RemoteCommandAcknowledgement {
  commandId: string;
  status: 'completed' | 'failed';
  message?: string;
  completedAt: number;
}

export interface RemoteCommand {
  deviceId: string;
  parentUid: string;
  childId: string;
  commandId: string;
  command: 'startStream' | 'stopStream' | 'switchCamera' | 'toggleAudioMute' | 'startScreenShare' | 'stopScreenShare' | 'syncLocation';
  cameraFacing?: 'front' | 'back';
  requestedBy: string;
  requestedAt: number;
  acknowledgement?: RemoteCommandAcknowledgement;
}

export interface WebRTCSignalingRecord {
  deviceId: string;
  parentUid: string;
  childId: string;
  sessionId?: string;
  status?: 'offered' | 'answered' | 'stopped';
  viewerStatus?: 'viewing' | 'stopped';
  offer?: {
    type: string;
    sdp: string;
  };
  answer?: {
    type: string;
    sdp: string;
    sessionId?: string;
  };
  parentCandidates?: Record<string, { candidate: string; sdpMid?: string | null; sdpMLineIndex?: number | null; sessionId?: string }>;
  childCandidates?: Record<string, { candidate: string; sdpMid?: string | null; sdpMLineIndex?: number | null; sessionId?: string }>;
  updatedAt?: number;
}

export type ConsoleNavSection = 
  | 'devices' 
  | 'camera' 
  | 'location' 
  | 'mirroring' 
  | 'notifications' 
  | 'calls' 
  | 'usage';

export interface UserProfile {
  uid: string;
  email: string;
  displayName?: string;
}
