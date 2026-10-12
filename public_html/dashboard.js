const firebaseConfig = {
  apiKey: 'AIzaSyCn_0mbkQNSlOIvUA3Tv9QKFn8skyZL0vg',
  appId: '1:897177192961:web:286e429b79dabe05938e00',
  authDomain: 'kidguard-3b499.firebaseapp.com',
  databaseURL: 'https://kidguard-3b499-default-rtdb.asia-southeast1.firebasedatabase.app',
  messagingSenderId: '897177192961',
  projectId: 'kidguard-3b499',
  storageBucket: 'kidguard-3b499.firebasestorage.app',
  measurementId: 'G-KT3LSRH7W9',
};

const firebaseApp = firebase.initializeApp(firebaseConfig);
const auth = firebase.auth(firebaseApp);
const database = firebase.database(firebaseApp);
const statusElement = document.getElementById('status');
const startButton = document.getElementById('start-stream');
const pairButton = document.getElementById('pair-device');
const pairingCodeInput = document.getElementById('pairing-code');
const childDevicesList = document.getElementById('child-devices');
const deviceCountElement = document.getElementById('device-count');
const onlineCountElement = document.getElementById('online-count');
const connectionStateElement = document.getElementById('connection-state');
const appShell = document.querySelector('.app-shell');
const liveView = document.getElementById('live-view');
const liveDeviceTitle = document.getElementById('live-device-title');
const liveDeviceId = document.getElementById('live-device-id');
const liveConnection = document.getElementById('live-connection');
const liveStatus = document.getElementById('live-status');
const livePlaceholder = document.getElementById('live-placeholder');
const livePlaceholderTitle = livePlaceholder.querySelector('strong');
const livePlaceholderMessage = livePlaceholder.querySelector('span');
const backToDevicesButton = document.getElementById('back-to-devices');
const frontCameraButton = document.getElementById('front-camera');
const backCameraButton = document.getElementById('back-camera');
const toggleAudioButton = document.getElementById('toggle-audio');
const playbackVolume = document.getElementById('playback-volume');
const remoteVideo = document.getElementById('remoteVideo');
const peerConfiguration = {
  iceServers: [{ urls: 'stun:stun.l.google.com:19302' }],
  bundlePolicy: 'max-bundle',
  rtcpMuxPolicy: 'require',
  iceCandidatePoolSize: 2,
};

let activePeerConnection;
let activeSignalReference;
let streamRequestActive = false;
let childrenReference;
let childrenValueListener;
let presenceRefreshTimer;
let currentParentUid;
let activeParentUid;
let activeChildIdentity;
let liveViewRequestId = 0;
let currentCameraFacing = 'front';
const connectionReference = database.ref('.info/connected');
const connectionValueListener = (snapshot) => {
  const connected = snapshot.val() === true;
  connectionStateElement.textContent = connected ? 'Live' : 'Offline';
  connectionStateElement.style.color = connected ? '#0a9b70' : '#c34e48';
};
const childDevices = new Map();

pairingCodeInput.addEventListener('input', () => {
  pairingCodeInput.value = pairingCodeInput.value.replace(/\D/g, '').slice(0, 6);
});

function setStatus(message, color = '#ff9800') {
  statusElement.textContent = message;
  statusElement.style.color = color;
}

document.querySelector('.sidebar-nav').addEventListener('click', (event) => {
  const link = event.target.closest('a[data-nav-section]');
  if (!link) return;
  event.preventDefault();

  const devicesSection = document.getElementById('devices');
  if (link.dataset.navSection === 'devices') {
    document.querySelectorAll('.sidebar-nav .nav-link').forEach((navLink) => {
      const isActive = navLink === link;
      navLink.classList.toggle('active', isActive);
      if (isActive) {
        navLink.setAttribute('aria-current', 'page');
      } else {
        navLink.removeAttribute('aria-current');
      }
    });
    devicesSection.scrollIntoView({ behavior: 'smooth' });
    devicesSection.focus();
    return;
  }

  devicesSection.scrollIntoView({ behavior: 'smooth' });
  if (link.dataset.navSection === 'camera') {
    setStatus('Select a device below to open Live Camera.');
    devicesSection.focus();
    return;
  }

  setStatus(`${link.textContent.trim()} is not available yet.`);
});

function setLiveStatus(message, state = 'connecting') {
  liveStatus.textContent = message;
  liveStatus.classList.toggle('error', state === 'error');
  liveConnection.classList.toggle('connected', state === 'connected');
  liveConnection.textContent = state === 'connected'
    ? 'Connected'
    : state === 'error' ? 'Connection issue' : 'Connecting';
}

function updateCameraSelection() {
  frontCameraButton.setAttribute(
    'aria-pressed',
    String(currentCameraFacing === 'front'),
  );
  backCameraButton.setAttribute(
    'aria-pressed',
    String(currentCameraFacing === 'back'),
  );
}

function updateAudioControl() {
  toggleAudioButton.textContent = remoteVideo.muted
    ? 'Unmute audio'
    : 'Mute audio';
  toggleAudioButton.setAttribute('aria-pressed', String(!remoteVideo.muted));
}

function showLiveView(identity, modelName) {
  appShell.hidden = true;
  liveView.hidden = false;
  liveView.setAttribute('aria-hidden', 'false');
  liveDeviceTitle.textContent = modelName;
  liveDeviceId.textContent = `Device ID: ${identity.deviceId}`;
  livePlaceholderTitle.textContent = 'Connecting to the child device';
  livePlaceholderMessage.textContent = 'The child app must be open and online.';
  livePlaceholder.hidden = false;
  remoteVideo.srcObject = null;
  remoteVideo.muted = true;
  remoteVideo.volume = Number(playbackVolume.value);
  updateAudioControl();
  currentCameraFacing = 'front';
  updateCameraSelection();
  frontCameraButton.disabled = true;
  backCameraButton.disabled = true;
  setLiveStatus('Requesting camera stream…');
  document.body.style.overflow = 'hidden';
  liveView.focus();
}

async function signInParent() {
  const email = document.getElementById('email').value.trim();
  const password = document.getElementById('password').value;
  if (!email || !password) throw new Error('Enter your parent email and password.');
  await auth.setPersistence(firebase.auth.Auth.Persistence.LOCAL);
  return auth.signInWithEmailAndPassword(email, password);
}

function renderChildDevices() {
  childDevicesList.replaceChildren();
  deviceCountElement.textContent = String(childDevices.size);
  onlineCountElement.textContent = String(
    [...childDevices.values()].filter(isDeviceOnline).length,
  );
  if (!currentParentUid) {
    const signedOutItem = document.createElement('div');
    signedOutItem.className = 'empty-state';
    signedOutItem.textContent = 'Sign in to load paired devices.';
    childDevicesList.appendChild(signedOutItem);
    return;
  }
  if (childDevices.size === 0) {
    const emptyItem = document.createElement('div');
    emptyItem.className = 'empty-state';
    emptyItem.textContent = 'No child devices paired yet.';
    childDevicesList.appendChild(emptyItem);
    return;
  }

  childDevices.forEach((device, childId) => {
    const card = document.createElement('article');
    card.className = 'device-card';

    const cardTop = document.createElement('div');
    cardTop.className = 'device-card-top';
    const heading = document.createElement('div');
    heading.className = 'device-heading';
    const icon = document.createElement('span');
    icon.className = 'device-icon';
    icon.setAttribute('aria-hidden', 'true');
    const titleBlock = document.createElement('div');
    const modelLabel = document.createElement('span');
    modelLabel.className = 'device-kicker';
    modelLabel.textContent = 'DEVICE MODEL NAME';
    const modelName = getDeviceModelName(device.record);
    const title = document.createElement('h3');
    title.className = 'device-model';
    title.textContent = modelName;
    titleBlock.append(modelLabel, title);
    heading.append(icon, titleBlock);

    const online = isDeviceOnline(device);
    const badge = document.createElement('span');
    badge.className = `status-badge ${online ? 'online' : 'offline'}`;
    badge.textContent = online ? '🟢 Online' : '🔴 Offline';
    cardTop.append(heading, badge);

    const details = document.createElement('div');
    details.className = 'device-details';
    const idBlock = document.createElement('div');
    const idLabel = document.createElement('span');
    idLabel.className = 'detail-label';
    idLabel.textContent = 'DEVICE ID';
    const idValue = document.createElement('span');
    idValue.className = 'detail-value device-id';
    idValue.textContent = device.record.deviceId || device.record.childUid || childId;
    idBlock.append(idLabel, idValue);
    details.appendChild(idBlock);

    const openButton = document.createElement('button');
    openButton.className = 'device-open';
    openButton.type = 'button';
    openButton.append(cardTop, details);
    openButton.setAttribute('aria-label', `Open Live View for ${modelName}`);
    openButton.addEventListener('click', () => openSavedDevice(childId));

    const actions = document.createElement('div');
    actions.className = 'device-actions';
    const removeButton = document.createElement('button');
    removeButton.className = 'remove-button';
    removeButton.type = 'button';
    removeButton.textContent = 'Remove Device';
    removeButton.setAttribute('aria-label', `Remove Device ${modelName}`);
    removeButton.addEventListener('click', () => {
      removeChildDevice(childId, modelName, removeButton);
    });
    actions.appendChild(removeButton);

    card.append(openButton, actions);
    childDevicesList.appendChild(card);
  });
}

function getDeviceModelName(record) {
  const telemetry = record.telemetry || {};
  const modelName = record.deviceModelName || record.modelName ||
    record.deviceModel || telemetry.deviceModelName || telemetry.modelName ||
    telemetry.deviceModel;
  return typeof modelName === 'string' && modelName.trim()
    ? modelName.trim()
    : 'Model name not reported';
}

function isDeviceOnline(device) {
  const presence = device.presence;
  const heartbeat = presence?.heartbeatAt ?? presence?.lastSeen;
  const heartbeatAt = typeof heartbeat === 'number'
    ? (heartbeat < 100000000000 ? heartbeat * 1000 : heartbeat)
    : Date.parse(heartbeat);
  return presence?.online === true && Number.isFinite(heartbeatAt) &&
    Date.now() - heartbeatAt <= 90000;
}

async function removeChildDevice(childId, modelName, button) {
  if (!currentParentUid || !window.confirm(
    `Remove ${modelName} from your family devices? It will be unpaired.`,
  )) return;

  button.disabled = true;
  try {
    await database.ref(`parents/${currentParentUid}/children/${childId}`).remove();
    setStatus('Device removed and unpaired.', '#0a9b70');
  } catch (error) {
    setStatus(`Could not remove device: ${error.message}`, '#c34e48');
    console.error(`Could not unlink child device ${childId}:`, error);
    button.disabled = false;
  }
}

function removeChildDeviceListeners() {
  childDevices.forEach((device) => {
    device.reference.off('value', device.listener);
  });
  childDevices.clear();
  if (childrenReference && childrenValueListener) {
    childrenReference.off('value', childrenValueListener);
  }
  childrenReference = null;
  childrenValueListener = null;
}

function watchChildDevices(parentUid) {
  removeChildDeviceListeners();
  childDevicesList.replaceChildren();
  childDevicesList.setAttribute('aria-busy', 'true');
  const loadingItem = document.createElement('div');
  loadingItem.className = 'empty-state';
  loadingItem.textContent = 'Loading paired devices…';
  childDevicesList.appendChild(loadingItem);
  childrenReference = database.ref(`parents/${parentUid}/children`);
  childrenValueListener = (snapshot) => {
    const linkedDevices = new Map();
    snapshot.forEach((childSnapshot) => {
      const record = childSnapshot.val();
      if (record?.status === 'paired') {
        linkedDevices.set(childSnapshot.key, record);
      }
    });

    childDevices.forEach((device, childId) => {
      if (!linkedDevices.has(childId)) {
        device.reference.off('value', device.listener);
        childDevices.delete(childId);
      }
    });

    linkedDevices.forEach((record, childId) => {
      const existingDevice = childDevices.get(childId);
      if (existingDevice) {
        existingDevice.record = record;
        return;
      }
      const device = {
        record,
        presence: null,
        reference: database.ref(`parents/${parentUid}/children/${childId}/presence`),
        listener: null,
      };
      device.listener = (presenceSnapshot) => {
        device.presence = presenceSnapshot.val();
        renderChildDevices();
      };
      childDevices.set(childId, device);
      device.reference.on('value', device.listener, (error) => {
        console.error(`Could not read presence for child ${childId}:`, error);
        renderChildDevices();
      });
    });
    childDevicesList.setAttribute('aria-busy', 'false');
    renderChildDevices();
  };
  childrenReference.on('value', childrenValueListener, (error) => {
    setStatus(`Could not load paired child devices: ${error.message}`, '#f44336');
    childDevicesList.replaceChildren();
  });
}

auth.onAuthStateChanged((user) => {
  currentParentUid = user?.uid;
  if (user) {
    watchChildDevices(user.uid);
  } else {
    removeChildDeviceListeners();
    renderChildDevices();
  }
});

connectionReference.on('value', connectionValueListener);
presenceRefreshTimer = setInterval(renderChildDevices, 15000);

function isValidDatabaseKey(value) {
  return typeof value === 'string' &&
    value.length > 0 &&
    !/[.#$\[\]/]/.test(value);
}

function getPairingTimestamp(record) {
  const value = record.createdAt ?? record.timestamp;
  if (typeof value === 'number') {
    return new Date(value < 100000000000 ? value * 1000 : value);
  }
  return new Date(value);
}

function validatePairingRecord(record, code) {
  if (!record || typeof record !== 'object' ||
      String(record.pairingCode ?? '').padStart(4, '0') !== code) {
    throw new Error('Pairing code is invalid or expired.');
  }
  if (!['pending', 'waiting'].includes(record.status)) {
    throw new Error('Pairing code is invalid, expired, or already claimed.');
  }
  const createdAt = getPairingTimestamp(record);
  if (!Number.isFinite(createdAt.getTime()) ||
      Date.now() - createdAt.getTime() >= 5 * 60 * 1000) {
    throw new Error('Pairing code has expired. Generate a new code on the child device.');
  }
}

function getDeviceIdentity(record, fallbackDeviceId) {
  const deviceId = record.deviceId ?? record.childUid ?? fallbackDeviceId;
  const childId = record.childId ?? deviceId;
  if (!isValidDatabaseKey(deviceId) || !isValidDatabaseKey(childId)) {
    throw new Error('The pairing record has an invalid child device identity.');
  }
  if (record.childUid != null &&
      (typeof record.childUid !== 'string' || record.childUid.length === 0)) {
    throw new Error('The pairing record has an invalid child account ID.');
  }
  return { deviceId, childId, childUid: record.childUid };
}

async function findAlreadyLinkedDevice(parentUid, code) {
  const snapshot = await database.ref(`parents/${parentUid}/children`).once('value');
  let linkedDevice;
  snapshot.forEach((childSnapshot) => {
    const record = childSnapshot.val();
    if (record?.status === 'paired' &&
        String(record.pairingCode ?? '').padStart(4, '0') === code) {
      linkedDevice = getDeviceIdentity(record, childSnapshot.key);
      return true;
    }
    return false;
  });
  return linkedDevice;
}

async function claimPairingCode(parentUid, code) {
  const alreadyLinked = await findAlreadyLinkedDevice(parentUid, code);
  if (alreadyLinked) return alreadyLinked;

  const matches = await database.ref('pairing_codes')
    .orderByChild('pairingCode')
    .equalTo(code)
    .once('value');
  const records = [];
  matches.forEach((snapshot) => {
    records.push(snapshot);
  });
  if (records.length > 1) {
    throw new Error('Pairing code is ambiguous. Generate a new code on the child device.');
  }

  let pairingSnapshot = records[0];
  if (!pairingSnapshot) {
    pairingSnapshot = await database.ref(`pairing_codes/${code}`).once('value');
  }
  const pairingRecord = pairingSnapshot.val();
  validatePairingRecord(pairingRecord, code);
  const identity = getDeviceIdentity(pairingRecord, pairingSnapshot.key);
  const pairedAt = new Date().toISOString();
  const childPath = `parents/${parentUid}/children/${identity.childId}`;

  await database.ref().update({
    [childPath]: {
      childId: identity.childId,
      pairingCode: code,
      status: 'paired',
      timestamp: pairedAt,
      deviceId: identity.deviceId,
      ...(identity.childUid ? { childUid: identity.childUid } : {}),
    },
    [`pairing_codes/${pairingSnapshot.key}`]: {
      deviceId: pairingSnapshot.key ?? identity.deviceId,
      childId: identity.childId,
      ...(identity.childUid ? { childUid: identity.childUid } : {}),
      pairingCode: code,
      parentUid,
      status: 'paired',
      createdAt: pairingRecord.createdAt ?? pairingRecord.timestamp,
      lastSeen: pairedAt,
      timestamp: pairingRecord.timestamp,
    },
  });
  return identity;
}

function waitForCommandAcknowledgement(controlReference, commandId) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      controlReference.off('value', onValue);
      reject(new Error('The child did not acknowledge the request. Make sure its app is online and open.'));
    }, 30000);

    function onValue(snapshot) {
      const acknowledgement = snapshot.val()?.acknowledgement;
      if (acknowledgement?.commandId !== commandId) return;
      clearTimeout(timeout);
      controlReference.off('value', onValue);
      if (acknowledgement.status !== 'completed') {
        reject(new Error(acknowledgement.message || 'The child could not start its camera stream.'));
        return;
      }
      resolve();
    }

    controlReference.on('value', onValue, (error) => {
      clearTimeout(timeout);
      controlReference.off('value', onValue);
      reject(error);
    });
  });
}

async function requestChildStream(parentUid, identity, requestId) {
  const signalReference = database.ref(`webrtc_signaling/${identity.deviceId}`);
  activeSignalReference = signalReference;
  await signalReference.child('viewerStatus').onDisconnect().set('stopped');

  const controlReference = database.ref(`devices/${identity.deviceId}/control`);
  const commandId = `${Date.now()}_${parentUid}`;
  if (requestId !== liveViewRequestId) return;
  await controlReference.update({
    deviceId: identity.deviceId,
    parentUid,
    childId: identity.childId,
    commandId,
    command: 'startStream',
    requestedBy: parentUid,
    requestedAt: firebase.database.ServerValue.TIMESTAMP,
  });
  await waitForCommandAcknowledgement(controlReference, commandId);
  if (requestId !== liveViewRequestId) {
    await signalReference.child('viewerStatus').set('stopped');
    return;
  }

  const signalSnapshot = await signalReference.once('value');
  if (requestId !== liveViewRequestId) return;
  const signal = signalSnapshot.val();
  if (signal?.deviceId !== identity.deviceId ||
      signal?.parentUid !== parentUid ||
      signal?.childId !== identity.childId ||
      signal?.status !== 'offered' ||
      typeof signal?.sessionId !== 'string' ||
      typeof signal?.offer?.sdp !== 'string' ||
      typeof signal?.offer?.type !== 'string') {
    throw new Error('The child acknowledged the request but did not provide a WebRTC offer.');
  }

  await connectToOffer(signal, signalReference, requestId);
}

async function connectToOffer(signal, signalReference, requestId) {
  const peerConnection = new RTCPeerConnection(peerConfiguration);
  activePeerConnection = peerConnection;
  const sessionId = signal.sessionId;
  let remoteDescriptionSet = false;

  peerConnection.ontrack = (event) => {
    if (requestId === liveViewRequestId && event.streams.length > 0) {
      if (remoteVideo.srcObject !== event.streams[0]) {
        remoteVideo.muted = true;
        remoteVideo.srcObject = event.streams[0];
      }
      livePlaceholder.hidden = true;
      updateAudioControl();
      remoteVideo.play().catch((error) => {
        setLiveStatus(`Tap play to start video: ${error.message}`, 'error');
      });
    }
  };
  peerConnection.onconnectionstatechange = () => {
    if (activePeerConnection !== peerConnection) return;
    if (peerConnection.connectionState === 'connected') {
      setLiveStatus('Live video and audio connected.', 'connected');
      frontCameraButton.disabled = false;
      backCameraButton.disabled = false;
    } else if (peerConnection.connectionState === 'failed') {
      setLiveStatus(`WebRTC connection ${peerConnection.connectionState}.`, 'error');
      frontCameraButton.disabled = true;
      backCameraButton.disabled = true;
      signalReference.child('viewerStatus').set('stopped').catch((error) => {
        console.error('Could not stop the failed WebRTC viewer:', error);
      });
      signalReference.child('childCandidates').off();
      remoteVideo.srcObject = null;
      livePlaceholderTitle.textContent = 'Live connection lost';
      livePlaceholderMessage.textContent = 'Return to the device list and try again.';
      livePlaceholder.hidden = false;
      activePeerConnection?.close();
      activePeerConnection = null;
    }
  };
  peerConnection.onicecandidate = (event) => {
    if (!event.candidate || requestId !== liveViewRequestId) return;
    signalReference.child('parentCandidates').push({
      candidate: event.candidate.candidate,
      sdpMid: event.candidate.sdpMid,
      sdpMLineIndex: event.candidate.sdpMLineIndex,
      sessionId,
    }).catch((error) => setStatus(`Could not send ICE candidate: ${error.message}`, '#f44336'));
  };

  await peerConnection.setRemoteDescription(
    new RTCSessionDescription(signal.offer),
  );
  if (requestId !== liveViewRequestId) {
    signalReference.child('childCandidates').off();
    peerConnection.close();
    return;
  }
  remoteDescriptionSet = true;
  const addCandidate = async (value) => {
    if (requestId !== liveViewRequestId || !value || value.sessionId !== sessionId ||
        typeof value.candidate !== 'string') return;
    const candidate = new RTCIceCandidate({
      candidate: value.candidate,
      sdpMid: value.sdpMid ?? null,
      sdpMLineIndex: value.sdpMLineIndex ?? null,
    });
    if (!remoteDescriptionSet) return;
    await peerConnection.addIceCandidate(candidate);
  };
  signalReference.child('childCandidates').on('child_added', (snapshot) => {
    addCandidate(snapshot.val()).catch((error) => {
      setLiveStatus(`Could not add child ICE candidate: ${error.message}`, 'error');
    });
  });
  const answer = await peerConnection.createAnswer();
  if (requestId !== liveViewRequestId) {
    signalReference.child('childCandidates').off();
    peerConnection.close();
    return;
  }
  await peerConnection.setLocalDescription(answer);
  if (requestId !== liveViewRequestId) {
    signalReference.child('childCandidates').off();
    peerConnection.close();
    return;
  }
  await signalReference.child('answer').set({
    type: answer.type,
    sdp: answer.sdp,
    sessionId,
  });
  if (requestId !== liveViewRequestId) {
    signalReference.child('childCandidates').off();
    peerConnection.close();
    await signalReference.child('viewerStatus').set('stopped');
    return;
  }
  await signalReference.update({
    status: 'answered',
    viewerStatus: 'viewing',
    updatedAt: firebase.database.ServerValue.TIMESTAMP,
  });
  if (requestId !== liveViewRequestId) {
    signalReference.child('childCandidates').off();
    await signalReference.child('viewerStatus').set('stopped');
    peerConnection.close();
    return;
  }
  setLiveStatus('Waiting for video and audio…');
}

async function launchLiveView(parentUid, identity, modelName) {
  if (streamRequestActive) return;
  streamRequestActive = true;
  startButton.disabled = true;
  activeParentUid = parentUid;
  activeChildIdentity = identity;
  const requestId = ++liveViewRequestId;
  showLiveView(identity, modelName);
  try {
    await requestChildStream(parentUid, identity, requestId);
  } catch (error) {
    if (requestId !== liveViewRequestId) return;
    setLiveStatus(error.message || 'Could not start the live stream.', 'error');
    livePlaceholderTitle.textContent = 'Could not connect';
    livePlaceholderMessage.textContent = error.message || 'Check that the child app is online.';
    console.error('Could not start Firebase/WebRTC live stream:', error);
    if (activeSignalReference) {
      try {
        await activeSignalReference.child('viewerStatus').set('stopped');
      } catch (cleanupError) {
        console.error('Could not stop the failed WebRTC viewer:', cleanupError);
        setLiveStatus(`${error.message}; cleanup failed: ${cleanupError.message}`, 'error');
      }
      activeSignalReference.child('childCandidates').off();
    }
    activePeerConnection?.close();
    activePeerConnection = null;
    remoteVideo.srcObject = null;
  } finally {
    if (requestId === liveViewRequestId) {
      streamRequestActive = false;
      startButton.disabled = false;
    }
  }
}

async function openSavedDevice(childId) {
  const device = childDevices.get(childId);
  if (!device) return;
  try {
    const parentUid = currentParentUid || auth.currentUser?.uid;
    if (!parentUid) throw new Error('Sign in to open this child device.');
    const identity = getDeviceIdentity(
      { ...device.record, childId: device.record.childId || childId },
      childId,
    );
    await launchLiveView(parentUid, identity, getDeviceModelName(device.record));
  } catch (error) {
    setStatus(error.message || 'Could not open this child device.', '#c34e48');
    console.error(`Could not open child device ${childId}:`, error);
  }
}

async function startStream() {
  startButton.disabled = true;
  setStatus('Signing in and checking pairing code…');
  try {
    const code = pairingCodeInput.value.trim();
    if (!/^(?:\d{4}|\d{6})$/.test(code)) {
      throw new Error('Enter a 4- or 6-digit pairing code.');
    }
    const credential = await signInParent();
    const identity = await claimPairingCode(credential.user.uid, code);
    const device = childDevices.get(identity.childId);
    await launchLiveView(
      credential.user.uid,
      identity,
      device ? getDeviceModelName(device.record) : 'Child device',
    );
  } catch (error) {
    setStatus(error.message || 'Could not start the live stream.', '#c34e48');
    console.error('Could not start Firebase/WebRTC live stream:', error);
    startButton.disabled = false;
  }
}

async function sendChildCommand(command, fields = {}) {
  if (!activeParentUid || !activeChildIdentity) {
    throw new Error('No child device is selected.');
  }
  const controlReference = database.ref(
    `devices/${activeChildIdentity.deviceId}/control`,
  );
  const commandId = `${Date.now()}_${activeParentUid}`;
  await controlReference.update({
    deviceId: activeChildIdentity.deviceId,
    parentUid: activeParentUid,
    childId: activeChildIdentity.childId,
    commandId,
    command,
    ...fields,
    requestedBy: activeParentUid,
    requestedAt: firebase.database.ServerValue.TIMESTAMP,
  });
  await waitForCommandAcknowledgement(controlReference, commandId);
}

async function selectCamera(facing) {
  if (!activePeerConnection || activePeerConnection.connectionState !== 'connected') {
    return;
  }
  frontCameraButton.disabled = true;
  backCameraButton.disabled = true;
  liveStatus.textContent = `Switching to the ${facing} camera…`;
  liveStatus.classList.remove('error');
  try {
    await sendChildCommand('switchCamera', { cameraFacing: facing });
    currentCameraFacing = facing;
    updateCameraSelection();
    setLiveStatus(`${facing === 'front' ? 'Front' : 'Back'} camera active.`, 'connected');
  } catch (error) {
    setLiveStatus(error.message || 'Could not switch camera.', 'error');
  } finally {
    const connected = activePeerConnection?.connectionState === 'connected';
    frontCameraButton.disabled = !connected;
    backCameraButton.disabled = !connected;
  }
}

function closeLiveView() {
  liveViewRequestId += 1;
  streamRequestActive = false;
  startButton.disabled = false;
  const signalReference = activeSignalReference;
  activeSignalReference = null;
  if (signalReference) {
    signalReference.child('viewerStatus').set('stopped').catch((error) => {
      console.error('Could not stop the Live View:', error);
    });
    signalReference.child('childCandidates').off();
  }
  activePeerConnection?.close();
  activePeerConnection = null;
  remoteVideo.pause();
  remoteVideo.srcObject?.getTracks().forEach((track) => track.stop());
  remoteVideo.srcObject = null;
  activeParentUid = null;
  activeChildIdentity = null;
  frontCameraButton.disabled = true;
  backCameraButton.disabled = true;
  liveView.hidden = true;
  liveView.setAttribute('aria-hidden', 'true');
  appShell.hidden = false;
  document.body.style.overflow = '';
  setStatus('Live View closed.', '#0a9b70');
  const devicesSection = document.getElementById('devices');
  devicesSection.scrollIntoView({ behavior: 'smooth' });
  devicesSection.focus();
}

toggleAudioButton.addEventListener('click', () => {
  remoteVideo.muted = !remoteVideo.muted;
  updateAudioControl();
  if (!remoteVideo.muted) {
    remoteVideo.play().catch((error) => {
      setLiveStatus(`Audio playback needs interaction: ${error.message}`, 'error');
    });
  }
});
playbackVolume.addEventListener('input', () => {
  remoteVideo.volume = Number(playbackVolume.value);
});
frontCameraButton.addEventListener('click', () => selectCamera('front'));
backCameraButton.addEventListener('click', () => selectCamera('back'));
backToDevicesButton.addEventListener('click', closeLiveView);
window.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !liveView.hidden) closeLiveView();
});

async function pairDevice() {
  pairButton.disabled = true;
  setStatus('Signing in and pairing child device…');
  try {
    const code = pairingCodeInput.value.trim();
    if (!/^(?:\d{4}|\d{6})$/.test(code)) {
      throw new Error('Enter a 4- or 6-digit pairing code.');
    }
    const credential = await signInParent();
    await claimPairingCode(credential.user.uid, code);
    setStatus('Child device paired successfully.', '#4CAF50');
  } catch (error) {
    setStatus(error.message || 'Could not pair child device.', '#f44336');
    console.error('Could not pair child device:', error);
  } finally {
    pairButton.disabled = false;
  }
}

pairButton.addEventListener('click', pairDevice);
startButton.addEventListener('click', startStream);

window.addEventListener('pagehide', () => {
  liveViewRequestId += 1;
  clearInterval(presenceRefreshTimer);
  removeChildDeviceListeners();
  connectionReference.off('value', connectionValueListener);
  if (activeSignalReference) {
    activeSignalReference.child('viewerStatus').set('stopped');
    activeSignalReference.child('childCandidates').off();
  }
  activePeerConnection?.close();
  remoteVideo.srcObject?.getTracks().forEach((track) => track.stop());
  remoteVideo.srcObject = null;
});
