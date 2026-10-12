# KidGuard Parent and Child Apps

The parent and child apps have separate entrypoints. The parent app runs on
Web and Android from the same Flutter application: `lib/main.dart` is the
default parent entrypoint, and `lib/main_parent.dart` is available as an
explicit target. It displays its Email/Password login and registration screen,
then checks `parents/{parentUid}/children`: parents with linked devices go to
the Parent Dashboard, and parents with no linked devices see the Add Child
code entry screen. The child app requires Email/Password authentication before
opening its pairing screen and signs out any existing session on startup. Web
auth uses non-persistent storage, so users must log in again after a restart.

Pairing claims a child device's 4-digit code and links the child at
`parents/{parentUid}/children/{childId}`. Pairing records contain `childId`,
`deviceId`, `childUid`, `pairingCode`, `status`, and `timestamp`; `deviceId`
is the authenticated child UID used for signaling. Once claimed, the parent
also adds `parentUid` to the pairing record so the child can identify the
linked parent. Linked-child records contain `deviceId` and `childUid` so the
parent dashboard can address the paired child. Pairing codes expire five
minutes after their creation timestamp. The child app automatically requests
a fresh code at expiry, and the parent rejects expired codes.

While running, the child updates
`parents/{parentUid}/children/{childId}/presence` with `online`,
`heartbeatAt`, and `lastSeen`. A Realtime Database on-disconnect handler marks
the device offline. It also syncs the non-sensitive `platform` and `appState`
fields under `telemetry`. The parent dashboard treats a heartbeat older than
90 seconds as offline and displays the latest platform and app state. A parent
may link up to five child devices; unlink one from its dashboard card to free a
pairing slot.

The child app does not access camera or microphone until the child chooses
**Start live stream** or the paired parent sends a remote start request. The
child app must be open, and the browser or Android device must grant camera and
microphone permissions. The child can stop sharing locally or the parent can
send a remote stop request. While connected, the parent dashboard can also
switch between front and back cameras and toggle microphone mute. Remote
commands are written to `/devices/{deviceId}/control`; the child listens to
that node and records an acknowledgement so completed commands are not replayed
after reconnecting. The parent dashboard's **Live stream** page also listens
at `/webrtc_signaling/{deviceId}`, receives the child's WebRTC offer and ICE
candidates, writes an answer and its ICE candidates, and renders the received
video. Audio and video are sent peer-to-peer using WebRTC; Realtime Database
carries control commands and signaling only. Browser camera access requires
HTTPS (or localhost). For reliable connections across restrictive NATs and
firewalls, configure an authorized TURN service alongside the default STUN
server in `lib/services/webrtc_service.dart`. Streaming stops when the child
app leaves the foreground.

The child publisher starts at up to 720p/30 fps and samples WebRTC outbound
bandwidth and video packet loss every four seconds. During congestion it lowers
the sender bitrate, frame rate, and encoded resolution; it restores quality
gradually after network conditions improve. Camera exposure and white balance
remain on the camera's automatic settings for supported devices. When a browser
offers multiple labelled cameras on a facing direction, switching prefers a
main or wide sensor over ultra-wide, telephoto, or macro alternatives; Android
uses the platform WebRTC camera selection.

Realtime Database rules must require authenticated access to pairing codes,
allow parents to read and manage only their own child records, and allow a
child account to write only `presence` and `telemetry` for records whose
`childUid` matches `auth.uid`. For WebRTC, allow the child at
`webrtc_signaling/{deviceId}` (where `deviceId == auth.uid`) to publish the
offer and child ICE candidates. Allow only the parent UID recorded on that
paired child record to read that signaling node and write its answer, parent
ICE candidates, viewer status, and the signaling status/timestamp. The child
initializes `deviceId`, `parentUid`, and `childId` on the signaling node so
rules can verify the pairing link at
`parents/{parentUid}/children/{childId}` (including that its `childUid`
matches `{deviceId}`). Allow only the linked parent to write stream commands
at `devices/{deviceId}/control`, and allow the matching child account to read
commands and write their acknowledgement at that path. Verify the command's
`parentUid`, `childId`, and `deviceId` against the paired record. Firebase
Authentication alone does not secure database paths; do not enable
unrestricted database access.

The API key and project ID are fixed in `lib/services/firebase_config.dart`.
Run the parent app with the app ID, sender ID, and Realtime Database URL from
the Firebase project settings:

```sh
flutter run -d chrome --target lib/main_parent.dart \
	--dart-define=FIREBASE_APP_ID=... \
	--dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
	--dart-define=FIREBASE_DATABASE_URL=... \
	--dart-define=FIREBASE_AUTH_DOMAIN=...
```

The same parent app runs on Android, for example:

```sh
flutter run -d <android-device> --target lib/main.dart \
	--dart-define=FIREBASE_APP_ID=... \
	--dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
	--dart-define=FIREBASE_DATABASE_URL=...
```

Use `lib/main_child.dart` to run the child web app with the same Firebase
configuration flags. Enable the Email/Password provider in Firebase
Authentication for both apps. `FIREBASE_AUTH_DOMAIN` is optional. Firebase web
configuration values identify the project and are not server credentials.
