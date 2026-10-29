# KidGuard Production Architecture: Complete Mock Purge & Real RTDB/WebRTC Binding

Comprehensive documentation of the full audit and elimination of all mock simulators, hardcoded fallback lists, local test arrays, and simulated device states across both the Parent Console and Child Protection Client.

## 1. Zero Tolerance For Mocks: Audit & Purge Summary

### A. Child Protection Client (`lib/child_app/` & React Child View)
1. **Battery Telemetry (`battery_service.dart`)**:
   - Removed artificial fallbacks (`if (_batteryLevel == 0) _batteryLevel = 100;`).
   - Propagates real hardware battery percentage, voltage, charging state, temperature, and power-save status from `battery_plus` directly to `/devices/{pairingCode}/telemetry/battery`.
   - Defaults to 0% and reports genuine sensor states instead of mock 100%.

2. **GPS Geolocation (`location_service.dart` & `LiveLocationView.tsx`)**:
   - Stripped out all hardcoded city coordinates (San Francisco `37.7749`, New York, Los Angeles, London).
   - Removed `sampleLocations` arrays.
   - Requires real satellite fix from `geolocator` / browser Geolocation API (`accuracy`, `speed`, `latitude`, `longitude`).
   - Default waiting state: `latitude: 0.0, longitude: 0.0, "Awaiting hardware GPS fix…"`.

3. **Sensor & System Telemetry Services**:
   - `CallLogService`: Removed `seedSampleCallLogs()`. Binds 1:1 to real telephony call logs.
   - `NotificationService`: Removed `seedSampleNotifications()`. Binds 1:1 to Android `NotificationListenerService`.
   - `AppUsageService`: Removed `seedSampleAppUsage()`. Binds 1:1 to Android `UsageStatsManager`.
   - `ChildViewModel`: Starts strictly unpaired (`_isPaired = false`), generates random 4-digit code (no static `FG-8492`), and binds to authorized guardian.

### B. Parent App & Web Console (`lib/parent_app/` & `src/`)
1. **Elimination of Simulated Device Fallbacks**:
   - Removed `addSampleDevice()` and hardcoded child phone lists in `ParentViewModel`.
   - Removed fallback sample device in `src/App.tsx` (`sample: ParentChildDevice`).
   - Displays exact required empty state: **"Scan or enter 4-digit bind code to connect device"** when no physical child device is linked under `/devices/{pairingCode}` in Firebase RTDB.

2. **WebRTC Video/Audio Streaming**:
   - Purged `createSimulatedStream`, `createSimulatedScreenStream`, `generateSimulatedScreenBase64`, and "Simulate Feed" buttons in `webrtc.ts`, `LiveCameraModal.tsx`, and `ScreenMirrorView.tsx`.
   - Video renderers (`RTCVideoRenderer` in Flutter and HTML5 `<video>` in Web) only activate when remote WebRTC tracks arrive from the child device or valid Base64 frame payloads arrive via `/devices/{pairingCode}/screen`.
   - Displays real connection timeout ("Waiting for child device screen stream...") with manual retry handshake.

3. **Real Remote Control & Telemetry Sync**:
   - Replaced all "Simulate" test buttons with production remote commands (`sendRemoteCommand` targeting `/devices/{pairingCode}/control`).
   - Replaced "Simulate Child GPS Fix to RTDB" with **"Request Real GPS Fix from Child Device"** (`syncLocation` command).
   - Real-time listeners for `/devices/{pairingCode}/telemetry/battery`, `/devices/{pairingCode}/location`, `/devices/{pairingCode}/notifications`, and `/devices/{pairingCode}/appUsage`.

---

## 2. Real-Time Firebase RTDB Schema

```
/devices/{pairingCode}/
  ├── status: 'active' | 'synced' | 'pending'
  ├── online: boolean
  ├── lastHeartbeat: timestamp
  ├── deviceModelName: string
  ├── telemetry/
  │     └── battery/
  │           ├── level: int (0-100)
  │           ├── isCharging: boolean
  │           ├── temperature: float
  │           ├── voltage: float
  │           └── health: string
  ├── location/
  │     ├── latitude: double
  │     ├── longitude: double
  │     ├── accuracy: float
  │     ├── speed: float
  │     └── timestamp: timestamp
  ├── screen/
  │     ├── status: 'streaming' | 'standby'
  │     ├── isSharing: boolean
  │     ├── frame: base64 (JPEG/PNG)
  │     └── activeApp: string
  ├── stream/ (WebRTC Camera Signaling)
  │     ├── offer: { sdp, type }
  │     ├── answer: { sdp, type }
  │     └── candidates/
  ├── control/
  │     ├── command: 'startStream' | 'stopStream' | 'switchCamera' | 'toggleAudioMute' | 'syncLocation'
  │     ├── requestedAt: timestamp
  │     └── acknowledged: boolean
  ├── callLogs/
  ├── notifications/
  └── appUsage/
```

---

## 3. Verification & Code Quality

- **TypeScript Compilation**: `tsc -b && vite build` runs with 0 errors.
- **Codebase Audit**: `grep -rn "seedSample\|addSampleDevice\|createSimulated\|generateSimulated\|37.7749\|FG-8492"` verified to return 0 occurrences across `lib/` and `src/`.
- **Flutter Model Validation**: `ChildDevice`, `ParentWebRtcService`, `ParentViewModel`, and `ParentDashboardScreen` use real `flutter_webrtc` rendering with no simulated streams.

---

## 4. Android 14 (API 34) Native Architecture Alignment (`com.kidguard.child`)

- **Manifest Declaration (`/android/app/src/main/AndroidManifest.xml`)**:
  - Package: `com.kidguard.child`
  - Application class: `KidGuardApplication` with automatic creation of persistent system notification channels (`CHANNEL_LOCATION`, `CHANNEL_MEDIA_PROJECTION`, `CHANNEL_AUDIO`, `CHANNEL_PROTECTION`).
  - Permissions: Declares explicit foreground service types (`FOREGROUND_SERVICE_LOCATION`, `FOREGROUND_SERVICE_MEDIA_PROJECTION`, `FOREGROUND_SERVICE_MICROPHONE`, `FOREGROUND_SERVICE_CAMERA`, `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`).
- **Broadcast Receiver (`boot.BootCompletedReceiver`)**:
  - Registered for `BOOT_COMPLETED` and `LOCKED_BOOT_COMPLETED`.
  - Directly triggers `ServiceStarter.startAll(context)` upon device reboot.
- **Service Starter Utility (`util.ServiceStarter`)**:
  - Centralizes start/stop operations across all background services with Android 14 API 34 compliance via `ContextCompat.startForegroundService`.
- **Foreground Services**:
  - `service.LocationForegroundService`: API 34 `location` foreground service bound to real hardware `LocationManager` GPS/Network providers.
  - `service.MediaProjectionForegroundService`: API 34 `mediaProjection` foreground service managing real `MediaProjection` token and display capture.
  - `service.AudioCaptureService`: API 34 `microphone` foreground service capturing hardware PCM audio streams via `AudioRecord`.
  - `service.ChildNotificationListenerService`: Android notification listener capturing incoming third-party push notifications.
  - `MainActivity`: FlutterActivity bridge handling method calls to control native foreground services.

