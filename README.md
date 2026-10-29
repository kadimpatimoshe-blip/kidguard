# KidGuard Kid Pro 🛡️ — Professional Parental Control Suite

KidGuard Kid Pro is a professional-grade parental control and child protection suite built with **Flutter / Dart** for native mobile companions (Android 14 API 34+) and a high-performance **React + TypeScript** web dashboard. It features real-time Firebase Realtime Database synchronization, peer-to-peer WebRTC streaming, continuous telemetry, and secure 4-digit bind code pairing.

### 🚀 Powerful Features (FlashGet Kids Parity):
- **Continuous Background Protection**: Android 14 API 34 compliant foreground services.
- **Real-Time Screen Mirroring**: High-performance frame capture with low latency.
- **WebRTC Camera & Audio**: Encrypted, peer-to-peer environmental monitoring.
- **Enterprise-Grade Security**: Real Firebase Authentication (Email/Google) and secure data sync.
- **Offline Persistence**: Database persistence enabled for reliable tracking in poor connectivity.

---

## Complete Onboarding & Pairing Architecture

### 1. Initial App Launch & Authentication
- **Initial Auth Check**: On startup, KidGuard checks for existing authenticated sessions or configured passcodes.
- **Passcode (PIN) Lock**: Clean 4-digit PIN screen with visual dots and an on-screen numeric keypad for rapid, secure device locking.
- **Email & Password Login / Register**: Full credentials authentication with validation, password visibility toggle, and instant one-tap demo access.
- Implemented in Flutter (`lib/auth/screens/auth_screen.dart`, `lib/auth/auth_service.dart`) and Web (`src/App.tsx`, `src/components/AuthModal.tsx`).

### 2. Device Role Selection (Parent vs. Child)
- After authentication, users configure the device role with intuitive visual selection:
  - **"I am a Parent" (Parent Console)**: Supervises family devices, views live GPS on maps, mirrors screens, streams remote cameras, inspects notifications, call logs, and screen-time analytics.
  - **"I am a Child" (Child Protection Client)**: Runs continuous Android 14 API 34 foreground telemetry, broadcasts live GPS and battery health to `/devices/{pairingCode}`, and generates a 4-digit bind code.
- "Remember this choice" setting persists the device role, with seamless top-bar role switching available at any time.
- Implemented in Flutter (`lib/role_selection/screens/role_selection_screen.dart`) and Web (`src/App.tsx`).

### 3. 4-Digit Bind Code Generation & Validation
- **Child Device Code Generation**:
  - Automatically generates a 4-digit / alphanumeric pairing code (e.g., `FG-8492` or dynamic 4-digit numeric code like `3819`).
  - Publishes and updates the device presence under Firebase Realtime Database at `/devices/{pairingCode}` and `/pairings/{pairingCode}`.
  - Includes a 300-second countdown timer and instant regeneration.
- **Parent Device Code Validation**:
  - The Parent Console provides a dedicated "Pair Device" input screen / modal.
  - As the parent enters the 4-digit code, it actively queries Firebase RTDB at `/devices/{pairingCode}`.
  - Previews verified child hardware info (Device Model, Battery Level, RTDB Node).
  - Once confirmed, marks status as `paired`, records `parentUid`, and establishes real-time bi-directional telemetry and remote command streaming (`startStream`, `stopStream`, `startScreenShare`, `stopScreenShare`).
- Implemented in Flutter (`lib/parent_app/views/pair_device_screen.dart`, `lib/parent_app/viewmodels/parent_view_model.dart`, `lib/child_app/views/pairing_display_screen.dart`, `lib/child_app/viewmodels/child_view_model.dart`) and Web (`src/components/AddChildModal.tsx`, `src/services/firebase.ts`, `src/App.tsx`).

---

## Flutter Architecture (`lib/`)

```
lib/
├── main.dart                               # App entrypoint coordinating Auth, Role, and Apps
├── auth/
│   ├── auth_service.dart                   # Auth state, PIN passcode & email credential manager
│   └── screens/
│       └── auth_screen.dart                # Passcode PIN keypad & Email/Password form
├── role_selection/
│   └── screens/
│       └── role_selection_screen.dart      # Role chooser: Parent Console vs Child Companion
├── parent_app/
│   ├── parent_app.dart                     # Parent module export
│   ├── models/
│   │   └── child_device.dart               # ChildDevice model with battery, location, presence
│   ├── viewmodels/
│   │   └── parent_view_model.dart          # RTDB polling, pairing validation & remote commands
│   └── views/
│       ├── pair_device_screen.dart         # 4-digit bind code input & RTDB verification
│       └── parent_dashboard_screen.dart    # Full Parent Dashboard with telemetry & streaming
└── child_app/
    ├── child_app.dart                      # Child module export
    ├── core/services/
    │   ├── rtdb_client_service.dart        # Direct Firebase RTDB REST & WebSocket client
    │   ├── camera_stream_service.dart      # WebRTC camera streaming
    │   ├── location_service.dart           # Background GPS streaming
    │   ├── screen_mirror_service.dart      # Android 14 MediaProjection capture
    │   ├── notification_service.dart       # Notification sync
    │   └── call_log_service.dart           # Call history sync
    ├── data/models/
    │   ├── pairing_state_model.dart        # 4-digit code lifecycle
    │   └── telemetry_payload.dart          # Typed telemetry payloads
    ├── viewmodels/
    │   └── child_view_model.dart           # MVVM ViewModel publishing to /devices/{code}
    └── views/
        ├── pairing_display_screen.dart     # Responsive 4-digit code cards with countdown
        └── child_home_screen.dart          # Active protection & background service toggles
```

---

## Web Architecture (`src/`)

- **Interactive Role Switcher**: Test both Parent Console and Child Client directly in the browser.
- **Firebase Realtime Database**: Synchronized paths:
  - `/devices/{pairingCode}`: Telemetry, battery, location, presence, control
  - `/devices/{pairingCode}/control`: Parent commands (`startStream`, `startScreenShare`, etc.)
  - `/devices/{pairingCode}/screen`: Frame buffer & mirroring state
  - `/parents/{parentUid}/children`: Linked family devices

---

## Development

```bash
# Web preview & build
npm install
npm run build
npm run dev

# Standalone Flutter mobile app
flutter pub get
flutter run
```
