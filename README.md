# KidGuard Parent Web App

The app initializes Firebase from build-time configuration and first displays
an Email/Password login and registration screen. After authentication, it
checks `parents/{parentUid}/children`: parents with linked devices go directly
to the Parent Dashboard; parents with no linked devices see the Add Child code
entry screen. Pairing claims a child device's 4- or 6-digit code, links the
child under
`parents/{parentUid}/children/{childId}`, and deletes the used pairing-code
record. Pairing-code and linked-child records use the same exact fields:
`childId`, `pairingCode`, `status`, and `timestamp`. The child creates a
pairing-code record with `status: waiting`; the parent claim changes the status
to `paired` and refreshes `timestamp`. The parent UID is represented by the
path and is not duplicated in either record. Pairing codes expire five minutes
after their creation timestamp. The child app automatically requests a fresh
code at expiry, and the parent rejects expired codes. On a valid claim, the
parent uses one multi-location database update to link the child and remove the
pairing code. This makes the writes atomic but does not prevent simultaneous
claims from both succeeding.

The child pairing screen is available at the `/child` named route and through
the **Go to Child Mode** buttons on the login and Parent Dashboard screens. The
child route requires a non-anonymous Firebase Email/Password account; users can
register or log in from the child route before generating a pairing code.
Anonymous authentication is not used for pairing. Realtime Database rules must
also require authenticated access to pairing codes and parent-child records;
Firebase Authentication alone does not secure database paths.

Run the web app with values from your Firebase project's web app settings and
Realtime Database page:

```sh
flutter run -d chrome \
	--dart-define=FIREBASE_API_KEY=... \
	--dart-define=FIREBASE_APP_ID=... \
	--dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
	--dart-define=FIREBASE_PROJECT_ID=... \
	--dart-define=FIREBASE_DATABASE_URL=... \
	--dart-define=FIREBASE_AUTH_DOMAIN=...
```

Enable the Email/Password provider in Firebase Authentication before using the
login or registration screens. `FIREBASE_AUTH_DOMAIN` is optional. Configure
Realtime Database rules for authenticated access to `pairing_codes` and
authenticated parent access to that parent's
`parents/{parentUid}/children` records. Do not enable unrestricted database
access. Firebase web configuration values identify the project and are not
server credentials.
