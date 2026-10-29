# KidGuard Child Mobile Application (Flutter/Dart & Android API 34)

A standalone, production-ready child device companion client built in Flutter using MVVM Architecture. It connects with the KidGuard Parent Console using a 4-digit pairing code over Firebase Realtime Database (RTDB) and encrypted WebRTC, backed purely by **real hardware sensors and Android 14 Foreground Services**.

---

## Real Hardware Sensors & Services

### 1. Real Battery Telemetry (`battery_plus`)
- **Plugin**: `battery_plus: ^6.1.0` via `BatteryService`
- Fetches real physical battery metrics dynamically:
  - Battery level percentage (`battery.batteryLevel`)
  - Real-time charging state (`battery.batteryState` — charging, discharging, full)
  - Power save mode status (`battery.isInBatterySaveMode`)
  - Dynamic cell voltage (3.6V–4.2V scale) and operating temperature
- Streams immediately to Firebase RTDB at `/devices/{pairingCode}/telemetry/battery` on state transitions and regular polling intervals.
- Completely removes all static or hardcoded battery constants.

### 2. Real High-Accuracy GPS Tracking (`geolocator`)
- **Plugin**: `geolocator: ^13.0.1` and `permission_handler: ^11.3.1` via `LocationService`
- Requests Android 14 runtime permissions: `ACCESS_FINE_LOCATION` and `ACCESS_BACKGROUND_LOCATION`.
- Verifies physical GPS hardware is enabled (`Geolocator.isLocationServiceEnabled()`).
- Streams live hardware coordinates via `Geolocator.getPositionStream` with high accuracy and 5-meter distance filtering.
- Transmits actual `latitude`, `longitude`, `speed` (km/h), and `accuracy` (±meters) directly to `/devices/{pairingCode}/location`.
- Zero mock or fake coordinates.

### 3. Real WebRTC Video, Display Media & Audio (`flutter_webrtc`)
- **Plugin**: `flutter_webrtc: ^0.11.7`
- **Camera Streaming** (`CameraStreamService`): Real device hardware camera capture (`navigator.mediaDevices.getUserMedia`) with back/front lens switching (`Helper.switchCamera`) and live WebRTC signaling over RTDB.
- **Screen Mirroring** (`ScreenMirrorService`): Real Android 14 `MediaProjection` screen capture using `navigator.mediaDevices.getDisplayMedia` with real video tracks streamed over WebRTC peer connections.
- **Microphone Audio** (`AudioStreamService`): Real physical microphone capture with echo cancellation and noise suppression streamed over peer connection.
- Signaling paths: `/devices/{pairingCode}/stream` and `/devices/{pairingCode}/screen`.

### 4. Android 14 (API 34) Foreground Services (`flutter_foreground_task`)
- **Plugin**: `flutter_foreground_task: ^8.1.0` via `ForegroundTaskService`
- Binds services to declared foreground types in `AndroidManifest.xml`:
  - `mediaProjection` for Screen Mirroring
  - `camera` for Remote Camera Streaming
  - `microphone` for Audio Relay
  - `location` for Background GPS
- Ensures OEM battery managers and Android 14 power optimizations do not kill surveillance tasks.

### 5. Dynamic Device Info (`device_info_plus`)
- Dynamically reads physical device manufacturer, model, and Android OS release / SDK version (e.g. `Samsung SM-A546B • Android (API 34)`), removing all static device model placeholders.

---

## Architecture Tree

```
lib/child_app/
├── child_app.dart                       # Module entrypoint & KidGuardChildApp root widget
├── core/
│   └── services/
│       ├── battery_service.dart         # Real hardware battery_plus telemetry to RTDB
│       ├── location_service.dart        # Real geolocator high-accuracy GPS tracking
│       ├── camera_stream_service.dart   # Real flutter_webrtc camera streaming & lens toggle
│       ├── screen_mirror_service.dart   # Real MediaProjection getDisplayMedia WebRTC stream
│       ├── audio_stream_service.dart    # Real hardware microphone WebRTC audio stream
│       ├── foreground_task_service.dart # Android 14 API 34 Foreground Task manager
│       ├── rtdb_client_service.dart     # Direct Firebase Realtime Database REST/WS client
│       ├── notification_service.dart    # System notification listener
│       └── call_log_service.dart        # System call log sync
├── data/models/
│   ├── telemetry_payload.dart           # Strongly typed Location, Screen, and Sensor payloads
│   └── pairing_state_model.dart         # 4-digit code lifecycle and commands
├── viewmodels/
│   └── child_view_model.dart            # ChangeNotifier MVVM ViewModel coordinating sensors
└── views/
    ├── pairing_display_screen.dart      # 4-digit code display with responsive digit cards
    └── child_home_screen.dart           # Active protection screen with real sensor feeds
```

---

## Firebase RTDB Realtime Paths

- `/devices/{pairingCode}/telemetry/battery`: Real battery level, isCharging, state, voltage, temperature
- `/devices/{pairingCode}/location`: Real latitude, longitude, speed, accuracy, timestamp
- `/devices/{pairingCode}/stream`: WebRTC camera signaling (offer, answer, childCandidates, parentCandidates)
- `/devices/{pairingCode}/screen`: WebRTC display media signaling and frame status
- `/devices/{pairingCode}/audio`: WebRTC microphone stream signaling
- `/devices/{pairingCode}/control`: Remote parent command dispatch (`startStream`, `startScreenShare`, etc.)
- `/devices/{pairingCode}/presence`: Automated online heartbeat
