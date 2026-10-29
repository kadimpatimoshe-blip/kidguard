import { database, sendRemoteCommand, regenerateChildPairingCode } from './firebase';
import { ref, set, update, onValue, off, get, remove, push } from 'firebase/database';

export { regenerateChildPairingCode };

export const peerConfiguration: RTCConfiguration = {
  iceServers: [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun1.l.google.com:19302' },
    { urls: 'stun:stun2.l.google.com:19302' },
    { urls: 'stun:stun3.l.google.com:19302' }
  ],
  bundlePolicy: 'max-bundle',
  rtcpMuxPolicy: 'require',
  iceCandidatePoolSize: 2,
};

export interface PairingCodeValidationResult {
  isValid: boolean;
  isRegenerated: boolean;
  newPairingCode?: string;
  previousPairingCode?: string;
  message?: string;
}

/**
 * Actively checks Firebase RTDB to verify if the child pairing code is still valid,
 * or if the child device has generated a new pairing code (e.g., 9334).
 */
export const checkChildPairingCodeValidity = async (
  pairingCode: string,
  deviceId?: string,
  childId?: string
): Promise<PairingCodeValidationResult> => {
  const cleanCode = (pairingCode || '').trim();
  if (!cleanCode) {
    return { isValid: false, isRegenerated: false, message: 'Missing pairing code' };
  }

  // 1. Fast local check (from cross-tab or test events)
  try {
    const regCode = localStorage.getItem(`kidguard_regenerated_code_${cleanCode}`) ||
      (deviceId ? localStorage.getItem(`kidguard_regenerated_code_${deviceId}`) : null);
    if (regCode && regCode !== cleanCode) {
      return {
        isValid: false,
        isRegenerated: true,
        newPairingCode: regCode,
        previousPairingCode: cleanCode,
        message: `Child device regenerated pairing code. Please re-link using code ${regCode}`,
      };
    }
  } catch {}

  if (!database) {
    return { isValid: true, isRegenerated: false };
  }

  try {
    // 2. Query /devices/{cleanCode} in RTDB
    const devSnap = await get(ref(database, `devices/${cleanCode}`));
    if (devSnap.exists()) {
      const data = devSnap.val();
      if (data?.newPairingCode && String(data.newPairingCode).trim() !== cleanCode) {
        const newCode = String(data.newPairingCode).trim().padStart(4, '0');
        return {
          isValid: false,
          isRegenerated: true,
          newPairingCode: newCode,
          previousPairingCode: cleanCode,
          message: `Child device regenerated pairing code. Please re-link using code ${newCode}`,
        };
      }
      if (data?.status === 'regenerated' || data?.status === 'expired') {
        const newCode = data?.newPairingCode ? String(data.newPairingCode).trim().padStart(4, '0') : undefined;
        return {
          isValid: false,
          isRegenerated: !!newCode,
          newPairingCode: newCode,
          previousPairingCode: cleanCode,
          message: newCode
            ? `Child device regenerated pairing code. Please re-link using code ${newCode}`
            : 'Child pairing code is no longer valid',
        };
      }
    }

    // 3. Query /pairings/{cleanCode} in RTDB
    const pairingSnap = await get(ref(database, `pairings/${cleanCode}`));
    if (pairingSnap.exists()) {
      const data = pairingSnap.val();
      if (data?.newPairingCode && String(data.newPairingCode).trim() !== cleanCode) {
        const newCode = String(data.newPairingCode).trim().padStart(4, '0');
        return {
          isValid: false,
          isRegenerated: true,
          newPairingCode: newCode,
          previousPairingCode: cleanCode,
          message: `Child device regenerated pairing code. Please re-link using code ${newCode}`,
        };
      }
    }

    // 4. Query /pairing_codes/{deviceId} and /devices/{deviceId}
    const targetDevId = deviceId || (devSnap.exists() ? devSnap.val()?.deviceId : null);
    if (targetDevId) {
      const pcSnap = await get(ref(database, `pairing_codes/${targetDevId}`));
      if (pcSnap.exists()) {
        const pcData = pcSnap.val();
        if (pcData?.pairingCode && String(pcData.pairingCode).trim().padStart(4, '0') !== cleanCode) {
          const newCode = String(pcData.pairingCode).trim().padStart(4, '0');
          return {
            isValid: false,
            isRegenerated: true,
            newPairingCode: newCode,
            previousPairingCode: cleanCode,
            message: `Child device regenerated pairing code. Please re-link using code ${newCode}`,
          };
        }
      }

      const devIdSnap = await get(ref(database, `devices/${targetDevId}`));
      if (devIdSnap.exists()) {
        const devData = devIdSnap.val();
        if (devData?.pairingCode && String(devData.pairingCode).trim().padStart(4, '0') !== cleanCode) {
          const newCode = String(devData.pairingCode).trim().padStart(4, '0');
          return {
            isValid: false,
            isRegenerated: true,
            newPairingCode: newCode,
            previousPairingCode: cleanCode,
            message: `Child device regenerated pairing code. Please re-link using code ${newCode}`,
          };
        }
      }
    }

    // 5. Query /pairing_codes collection to match deviceId or childId
    if (targetDevId || childId) {
      const allCodesSnap = await get(ref(database, 'pairing_codes'));
      if (allCodesSnap.exists()) {
        const all = allCodesSnap.val();
        for (const key of Object.keys(all)) {
          const item = all[key];
          if (
            item &&
            (item.deviceId === targetDevId || item.childId === childId || key === targetDevId) &&
            item.pairingCode &&
            String(item.pairingCode).trim().padStart(4, '0') !== cleanCode
          ) {
            const newCode = String(item.pairingCode).trim().padStart(4, '0');
            return {
              isValid: false,
              isRegenerated: true,
              newPairingCode: newCode,
              previousPairingCode: cleanCode,
              message: `Child device regenerated pairing code. Please re-link using code ${newCode}`,
            };
          }
        }
      }
    }

    return { isValid: true, isRegenerated: false };
  } catch (e) {
    console.warn('Error checking child pairing code validity:', e);
    return { isValid: true, isRegenerated: false };
  }
};

/**
 * Actively listens in real-time to Firebase RTDB to detect if the child pairing code
 * is still valid or if the child device has generated a new pairing code (e.g., 9334).
 */
export const subscribeToChildPairingCodeValidity = (
  pairingCode: string,
  deviceId: string | undefined,
  childId: string | undefined,
  onStatusChange: (result: PairingCodeValidationResult) => void
): (() => void) => {
  const cleanCode = (pairingCode || '').trim();
  let isSubscribed = true;
  const unsubs: (() => void)[] = [];

  const notifyNewCode = (newCode: string) => {
    if (!isSubscribed) return;
    const formatted = newCode.trim().padStart(4, '0');
    if (formatted && formatted !== cleanCode) {
      onStatusChange({
        isValid: false,
        isRegenerated: true,
        newPairingCode: formatted,
        previousPairingCode: cleanCode,
        message: `Child device regenerated pairing code. Please re-link using code ${formatted}`,
      });
    }
  };

  // Perform immediate async check
  checkChildPairingCodeValidity(cleanCode, deviceId, childId).then((res) => {
    if (!isSubscribed) return;
    if (!res.isValid) {
      onStatusChange(res);
    }
  });

  // Local window event listener for instant response
  const handleRegenEvent = (e: any) => {
    const detail = e.detail || {};
    if (
      (detail.previousCode === cleanCode || detail.deviceId === deviceId) &&
      detail.newPairingCode &&
      detail.newPairingCode !== cleanCode
    ) {
      notifyNewCode(detail.newPairingCode);
    }
  };
  window.addEventListener('kidguard_pairing_code_regenerated', handleRegenEvent);
  unsubs.push(() => window.removeEventListener('kidguard_pairing_code_regenerated', handleRegenEvent));

  if (database && cleanCode) {
    const db = database;

    // 1. Listen to /devices/{cleanCode}
    const devRef = ref(db, `devices/${cleanCode}`);
    const unsubDev = onValue(devRef, (snap) => {
      if (!isSubscribed || !snap.exists()) return;
      const data = snap.val();
      if (data?.newPairingCode && String(data.newPairingCode).trim() !== cleanCode) {
        notifyNewCode(String(data.newPairingCode));
      } else if (data?.status === 'regenerated' || data?.status === 'expired') {
        const newCode = data?.newPairingCode ? String(data.newPairingCode).trim().padStart(4, '0') : undefined;
        onStatusChange({
          isValid: false,
          isRegenerated: !!newCode,
          newPairingCode: newCode,
          previousPairingCode: cleanCode,
          message: newCode
            ? `Child device regenerated pairing code. Please re-link using code ${newCode}`
            : 'Child pairing code is no longer valid',
        });
      }
    });
    unsubs.push(() => off(devRef, 'value', unsubDev));

    // 2. Listen to /pairings/{cleanCode}
    const pairingRef = ref(db, `pairings/${cleanCode}`);
    const unsubPairing = onValue(pairingRef, (snap) => {
      if (!isSubscribed || !snap.exists()) return;
      const data = snap.val();
      if (data?.newPairingCode && String(data.newPairingCode).trim() !== cleanCode) {
        notifyNewCode(String(data.newPairingCode));
      }
    });
    unsubs.push(() => off(pairingRef, 'value', unsubPairing));

    // 3. Listen to /pairing_codes/{deviceId} if deviceId is known
    if (deviceId) {
      const pcRef = ref(db, `pairing_codes/${deviceId}`);
      const unsubPc = onValue(pcRef, (snap) => {
        if (!isSubscribed || !snap.exists()) return;
        const data = snap.val();
        if (data?.pairingCode && String(data.pairingCode).trim().padStart(4, '0') !== cleanCode) {
          notifyNewCode(String(data.pairingCode));
        }
      });
      unsubs.push(() => off(pcRef, 'value', unsubPc));

      // 4. Also listen to /devices/{deviceId}
      const devIdRef = ref(db, `devices/${deviceId}`);
      const unsubDevId = onValue(devIdRef, (snap) => {
        if (!isSubscribed || !snap.exists()) return;
        const data = snap.val();
        if (data?.pairingCode && String(data.pairingCode).trim().padStart(4, '0') !== cleanCode) {
          notifyNewCode(String(data.pairingCode));
        }
      });
      unsubs.push(() => off(devIdRef, 'value', unsubDevId));
    }
  }

  // Active polling check every 3 seconds to guarantee prompt triggers even without push notifications
  const pollTimer = setInterval(async () => {
    if (!isSubscribed) return;
    const res = await checkChildPairingCodeValidity(cleanCode, deviceId, childId);
    if (!isSubscribed) return;
    if (res.isRegenerated && res.newPairingCode) {
      notifyNewCode(res.newPairingCode);
    }
  }, 3000);
  unsubs.push(() => clearInterval(pollTimer));

  return () => {
    isSubscribed = false;
    unsubs.forEach((u) => {
      try {
        u();
      } catch {}
    });
  };
};

export interface WebRTCSignalingOptions {
  cameraFacing?: 'front' | 'back';
  pairingCode?: string;
  onStream: (stream: MediaStream) => void;
  onStatusChange?: (status: string) => void;
  onError?: (err: Error) => void;
  onConnectionStateChange?: (state: RTCPeerConnectionState) => void;
  onPairingCodeInvalidated?: (newPairingCode?: string) => void;
}

export interface WebRTCSignalingSession {
  peerConnection: RTCPeerConnection | null;
  reconnect: () => Promise<void>;
  cleanup: () => void;
  switchCamera: (facing: 'front' | 'back') => Promise<void>;
  checkCodeValidity?: () => Promise<PairingCodeValidationResult>;
}

/**
 * Initializes a parent WebRTC signaling session over Firebase RTDB at /devices/{deviceId}/signaling
 */
export const startParentWebRTCSession = async (
  deviceId: string,
  parentUid: string,
  childId: string,
  options: WebRTCSignalingOptions
): Promise<WebRTCSignalingSession> => {
  let pc: RTCPeerConnection | null = null;
  let answerUnsub: (() => void) | null = null;
  let candidatesUnsub: (() => void) | null = null;
  let validityUnsub: (() => void) | null = null;
  let isCleanedUp = false;
  let currentFacing = options.cameraFacing || 'front';

  // Actively check and listen if child pairing code is still valid in Firebase RTDB
  const activePairingCode = options.pairingCode || (deviceId.startsWith('dev_') ? deviceId.replace('dev_', '') : deviceId);
  if (activePairingCode) {
    validityUnsub = subscribeToChildPairingCodeValidity(
      activePairingCode,
      deviceId,
      childId,
      (result) => {
        if (!result.isValid && result.isRegenerated && result.newPairingCode) {
          const msg = `Child device regenerated pairing code. Please re-link using code ${result.newPairingCode}`;
          options.onStatusChange?.(msg);
          options.onPairingCodeInvalidated?.(result.newPairingCode);
        }
      }
    );
  }

  const cleanupListeners = () => {
    if (answerUnsub) {
      answerUnsub();
      answerUnsub = null;
    }
    if (candidatesUnsub) {
      candidatesUnsub();
      candidatesUnsub = null;
    }
  };

  const initConnection = async () => {
    cleanupListeners();
    if (pc) {
      try {
        pc.close();
      } catch (e) {
        // ignore
      }
      pc = null;
    }

    if (isCleanedUp) return;

    try {
      options.onStatusChange?.('Initializing WebRTC peer connection…');
      pc = new RTCPeerConnection(peerConfiguration);

      // Listen for remote tracks (incoming video/audio from child)
      pc.ontrack = (event) => {
        if (event.streams && event.streams[0]) {
          options.onStream(event.streams[0]);
        } else if (event.track) {
          const inboundStream = new MediaStream([event.track]);
          options.onStream(inboundStream);
        }
      };

      pc.onconnectionstatechange = () => {
        if (pc) {
          options.onConnectionStateChange?.(pc.connectionState);
          if (pc.connectionState === 'connected') {
            options.onStatusChange?.('Live child camera stream connected');
          } else if (pc.connectionState === 'failed' || pc.connectionState === 'disconnected') {
            options.onStatusChange?.(`WebRTC connection ${pc.connectionState}`);
          }
        }
      };

      // Set transceivers to receive video and audio from child device
      try {
        pc.addTransceiver('video', { direction: 'recvonly' });
        pc.addTransceiver('audio', { direction: 'recvonly' });
      } catch (err) {
        console.warn('Could not add transceivers directly, creating offer with receive options:', err);
      }

      // Gather local ICE candidates and post to Firebase RTDB
      pc.onicecandidate = async (event) => {
        if (event.candidate && database && !isCleanedUp) {
          try {
            const candJson = event.candidate.toJSON();
            const candRef = push(ref(database, `devices/${deviceId}/signaling/parentCandidates`));
            await set(candRef, candJson);

            // Also post to devices/${deviceId}/stream/ice for KidGuardSignaling compatibility
            const streamIceRef = push(ref(database, `devices/${deviceId}/stream/ice`));
            await set(streamIceRef, {
              candidate: event.candidate.candidate,
              sdpMid: event.candidate.sdpMid,
              sdpMLineIndex: event.candidate.sdpMLineIndex,
              from: 'parent',
              createdAt: Date.now(),
            });
          } catch (e) {
            console.warn('Error saving parent ICE candidate to Firebase RTDB:', e);
          }
        }
      };

      // Create WebRTC Offer
      const offer = await pc.createOffer({
        offerToReceiveVideo: true,
        offerToReceiveAudio: true,
      });
      await pc.setLocalDescription(offer);

      // If Firebase RTDB is active, publish offer and listen for child answer
      if (database) {
        const signalingRef = ref(database, `devices/${deviceId}/signaling`);
        const offerPayload = {
          type: offer.type,
          sdp: offer.sdp,
          facing: currentFacing,
          timestamp: Date.now(),
          initiator: parentUid,
          from: 'parent',
          createdAt: Date.now(),
        };
        
        // Reset old signaling artifacts and post new offer
        await update(signalingRef, {
          offer: offerPayload,
          answer: null,
          childCandidates: null,
          state: 'offer_created',
        });

        // Also update devices/${deviceId}/stream node for KidGuardSignaling compatibility
        const streamRef = ref(database, `devices/${deviceId}/stream`);
        await update(streamRef, {
          offer: offerPayload,
          answer: null,
          status: 'offer_created',
        });

        // Listen for child SDP Answer on signaling/answer
        const answerRef = ref(database, `devices/${deviceId}/signaling/answer`);
        const unsubAns = onValue(answerRef, async (snapshot) => {
          if (!snapshot.exists() || !pc || isCleanedUp) return;
          const answerData = snapshot.val();
          if (answerData && answerData.sdp && pc.signalingState === 'have-local-offer') {
            try {
              options.onStatusChange?.('Received child camera answer, establishing P2P link…');
              await pc.setRemoteDescription(new RTCSessionDescription({
                type: 'answer',
                sdp: answerData.sdp,
              }));
            } catch (err: any) {
              console.warn('Failed setting remote description answer:', err);
            }
          }
        });

        // Also listen for child SDP Answer on stream/answer
        const streamAnswerRef = ref(database, `devices/${deviceId}/stream/answer`);
        const unsubStreamAns = onValue(streamAnswerRef, async (snapshot) => {
          if (!snapshot.exists() || !pc || isCleanedUp) return;
          const answerData = snapshot.val();
          if (answerData && answerData.sdp && pc.signalingState === 'have-local-offer') {
            try {
              options.onStatusChange?.('Received child camera answer, establishing P2P link…');
              await pc.setRemoteDescription(new RTCSessionDescription({
                type: 'answer',
                sdp: answerData.sdp,
              }));
            } catch (err: any) {
              console.warn('Failed setting remote description answer:', err);
            }
          }
        });
        answerUnsub = () => {
          off(answerRef, 'value', unsubAns);
          off(streamAnswerRef, 'value', unsubStreamAns);
        };

        // Listen for child ICE Candidates on signaling/childCandidates
        const childCandRef = ref(database, `devices/${deviceId}/signaling/childCandidates`);
        const unsubCand = onValue(childCandRef, async (snapshot) => {
          if (!snapshot.exists() || !pc || isCleanedUp) return;
          const candidatesObj = snapshot.val();
          if (candidatesObj && typeof candidatesObj === 'object') {
            const candidatesList = Object.values(candidatesObj) as any[];
            for (const cand of candidatesList) {
              if (cand && cand.candidate) {
                try {
                  await pc.addIceCandidate(new RTCIceCandidate(cand));
                } catch {
                  // candidate may be added already
                }
              }
            }
          }
        });

        // Also listen for child ICE Candidates on stream/ice
        const streamIceRef = ref(database, `devices/${deviceId}/stream/ice`);
        const unsubStreamIce = onValue(streamIceRef, async (snapshot) => {
          if (!snapshot.exists() || !pc || isCleanedUp) return;
          const candidatesObj = snapshot.val();
          if (candidatesObj && typeof candidatesObj === 'object') {
            const candidatesList = Object.values(candidatesObj) as any[];
            for (const cand of candidatesList) {
              if (cand && cand.candidate && cand.from !== 'parent') {
                try {
                  await pc.addIceCandidate(new RTCIceCandidate({
                    candidate: cand.candidate,
                    sdpMid: cand.sdpMid,
                    sdpMLineIndex: cand.sdpMLineIndex,
                  }));
                } catch {}
              }
            }
          }
        });

        candidatesUnsub = () => {
          off(childCandRef, 'value', unsubCand);
          off(streamIceRef, 'value', unsubStreamIce);
        };
      }

      // Signal child to turn on camera and answer WebRTC signaling
      await sendRemoteCommand(deviceId, parentUid, childId, 'startStream', {
        cameraFacing: currentFacing,
        timestamp: Date.now(),
      });

      options.onStatusChange?.('Signaling offer dispatched. Waiting for child device…');
    } catch (err: any) {
      console.warn('WebRTC signaling initialization error:', err);
      options.onError?.(err);
    }
  };

  // Launch initial connection
  await initConnection();

  return {
    get peerConnection() {
      return pc;
    },
    reconnect: async () => {
      options.onStatusChange?.('Re-initializing WebRTC signaling via Firebase RTDB…');
      await initConnection();
    },
    switchCamera: async (facing: 'front' | 'back') => {
      currentFacing = facing;
      await sendRemoteCommand(deviceId, parentUid, childId, 'switchCamera', {
        cameraFacing: facing,
      });
      if (database) {
        try {
          await update(ref(database, `devices/${deviceId}/signaling`), {
            'offer/facing': facing,
          });
        } catch {
          // ignore
        }
      }
    },
    checkCodeValidity: async () => {
      return checkChildPairingCodeValidity(activePairingCode, deviceId, childId);
    },
    cleanup: () => {
      isCleanedUp = true;
      cleanupListeners();
      if (validityUnsub) {
        validityUnsub();
        validityUnsub = null;
      }
      if (pc) {
        try {
          pc.close();
        } catch {}
        pc = null;
      }
      if (database) {
        try {
          update(ref(database, `devices/${deviceId}/signaling`), {
            state: 'closed',
            closedAt: Date.now(),
          }).catch(() => {});
        } catch {}
      }
      sendRemoteCommand(deviceId, parentUid, childId, 'stopStream').catch(() => {});
    },
  };
};



export interface ScreenFrameData {
  frame?: string; // base64 data URL e.g. "data:image/jpeg;base64,..." or URL
  activeApp?: string; // e.g. "YouTube", "Chrome", "Roblox", "Minecraft", "WhatsApp"
  timestamp?: number;
  fps?: number;
  orientation?: 'portrait' | 'landscape';
  battery?: number;
  status?: 'streaming' | 'paused' | 'standby' | 'mirroring' | 'stopped';
  deviceModel?: string;
  source?: 'rtdb_frame' | 'webrtc_stream' | 'simulated';
  isSharing?: boolean;
  command?: string;
  commandId?: string;
  commandAcknowledged?: boolean;
}

/**
 * Listens to live screen frame feeds from Firebase RTDB under /devices/{pairingCode}/screen
 */
export const subscribeToDeviceScreen = (
  pairingCodeOrDeviceId: string,
  onScreenFrame: (screenData: ScreenFrameData) => void,
  onError?: (err: Error) => void
): (() => void) => {
  if (!database) {
    return () => {};
  }

  const cleanKey = String(pairingCodeOrDeviceId || '').trim();
  if (!cleanKey) return () => {};

  let isSubscribed = true;
  const screenRef = ref(database, `devices/${cleanKey}/screen`);

  const handleValue = (snapshot: any) => {
    if (!isSubscribed) return;
    try {
      if (snapshot.exists()) {
        const val = snapshot.val();
        if (val && typeof val === 'object') {
          onScreenFrame({
            ...val,
            source: 'rtdb_frame',
          });
        }
      }
    } catch (err: any) {
      console.warn(`Error parsing screen data for ${cleanKey}:`, err);
      onError?.(err);
    }
  };

  onValue(screenRef, handleValue, (err) => {
    console.warn(`Screen frame listener error for /devices/${cleanKey}/screen:`, err);
    onError?.(err);
  });

  return () => {
    isSubscribed = false;
    off(screenRef, 'value', handleValue);
  };
};

/**
 * Updates or broadcasts live screen frame feed in Firebase RTDB under /devices/{pairingCode}/screen
 */
export const updateDeviceScreen = async (
  pairingCodeOrDeviceId: string,
  screenData: Partial<ScreenFrameData>
): Promise<void> => {
  if (!database) return;
  const cleanKey = String(pairingCodeOrDeviceId || '').trim();
  if (!cleanKey) return;

  const screenRef = ref(database, `devices/${cleanKey}/screen`);
  await update(screenRef, {
    ...screenData,
    timestamp: Date.now(),
  });
};

export interface ScreenSignalingOptions {
  onStream: (stream: MediaStream) => void;
  onFrameData?: (data: ScreenFrameData) => void;
  onStatusChange?: (status: string) => void;
  onError?: (err: Error) => void;
  onConnectionStateChange?: (state: RTCPeerConnectionState) => void;
}

/**
 * Initializes a parent WebRTC screen sharing session over Firebase RTDB at /devices/{deviceId}/screenSignaling
 */
export const startParentScreenShareSession = async (
  deviceId: string,
  parentUid: string,
  childId: string,
  options: ScreenSignalingOptions
): Promise<WebRTCSignalingSession> => {
  let pc: RTCPeerConnection | null = null;
  let answerUnsub: (() => void) | null = null;
  let candidatesUnsub: (() => void) | null = null;
  let isCleanedUp = false;

  const cleanupListeners = () => {
    if (answerUnsub) {
      answerUnsub();
      answerUnsub = null;
    }
    if (candidatesUnsub) {
      candidatesUnsub();
      candidatesUnsub = null;
    }
  };

  const initConnection = async () => {
    cleanupListeners();
    if (pc) {
      try {
        pc.close();
      } catch {}
      pc = null;
    }

    if (isCleanedUp) return;

    try {
      options.onStatusChange?.('Initializing WebRTC screen peer connection…');
      pc = new RTCPeerConnection(peerConfiguration);

      pc.ontrack = (event) => {
        if (event.streams && event.streams[0]) {
          options.onStream(event.streams[0]);
        } else if (event.track) {
          const inboundStream = new MediaStream([event.track]);
          options.onStream(inboundStream);
        }
      };

      pc.onconnectionstatechange = () => {
        if (pc) {
          options.onConnectionStateChange?.(pc.connectionState);
          if (pc.connectionState === 'connected') {
            options.onStatusChange?.('Live child screen stream connected (WebRTC)');
          } else if (pc.connectionState === 'failed' || pc.connectionState === 'disconnected') {
            options.onStatusChange?.(`WebRTC screen connection ${pc.connectionState}`);
          }
        }
      };

      try {
        pc.addTransceiver('video', { direction: 'recvonly' });
      } catch (err) {
        console.warn('Could not add video transceiver for screen stream:', err);
      }

      pc.onicecandidate = async (event) => {
        if (event.candidate && database && !isCleanedUp) {
          try {
            const candRef = push(ref(database, `devices/${deviceId}/screenSignaling/parentCandidates`));
            await set(candRef, event.candidate.toJSON());
          } catch (e) {
            console.warn('Error saving parent screen ICE candidate:', e);
          }
        }
      };

      const offer = await pc.createOffer({
        offerToReceiveVideo: true,
      });
      await pc.setLocalDescription(offer);

      if (database) {
        const signalingRef = ref(database, `devices/${deviceId}/screenSignaling`);
        await update(signalingRef, {
          offer: {
            type: offer.type,
            sdp: offer.sdp,
            mediaType: 'screen',
            timestamp: Date.now(),
            initiator: parentUid,
          },
          answer: null,
          childCandidates: null,
          state: 'offer_created',
        });

        // Listen for child screen answer
        const answerRef = ref(database, `devices/${deviceId}/screenSignaling/answer`);
        const unsubAns = onValue(answerRef, async (snapshot) => {
          if (!snapshot.exists() || !pc || isCleanedUp) return;
          const answerData = snapshot.val();
          if (answerData && answerData.sdp && pc.signalingState === 'have-local-offer') {
            try {
              options.onStatusChange?.('Received child screen answer, establishing P2P screen stream…');
              await pc.setRemoteDescription(new RTCSessionDescription({
                type: 'answer',
                sdp: answerData.sdp,
              }));
            } catch (err: any) {
              console.warn('Failed setting remote description for screen answer:', err);
            }
          }
        });
        answerUnsub = () => off(answerRef, 'value', unsubAns);

        // Listen for child screen ICE candidates
        const childCandRef = ref(database, `devices/${deviceId}/screenSignaling/childCandidates`);
        const unsubCand = onValue(childCandRef, async (snapshot) => {
          if (!snapshot.exists() || !pc || isCleanedUp) return;
          const candidatesObj = snapshot.val();
          if (candidatesObj && typeof candidatesObj === 'object') {
            const candidatesList = Object.values(candidatesObj) as any[];
            for (const cand of candidatesList) {
              if (cand && cand.candidate) {
                try {
                  await pc.addIceCandidate(new RTCIceCandidate(cand));
                } catch {}
              }
            }
          }
        });
        candidatesUnsub = () => off(childCandRef, 'value', unsubCand);
      }

      // Signal child device to start screen stream
      await sendRemoteCommand(deviceId, parentUid, childId, 'startScreenShare', {
        timestamp: Date.now(),
      });

      options.onStatusChange?.('Screen mirror request dispatched. Waiting for child device…');
    } catch (err: any) {
      console.warn('WebRTC screen signaling error:', err);
      options.onError?.(err);
    }
  };

  await initConnection();

  return {
    get peerConnection() {
      return pc;
    },
    reconnect: async () => {
      options.onStatusChange?.('Re-initializing WebRTC screen signaling via Firebase RTDB…');
      await initConnection();
    },
    switchCamera: async () => {},
    cleanup: () => {
      isCleanedUp = true;
      cleanupListeners();
      if (pc) {
        try {
          pc.close();
        } catch {}
        pc = null;
      }
      if (database) {
        try {
          update(ref(database, `devices/${deviceId}/screenSignaling`), {
            state: 'closed',
            closedAt: Date.now(),
          }).catch(() => {});
        } catch {}
      }
      sendRemoteCommand(deviceId, parentUid, childId, 'stopScreenShare').catch(() => {});
    },
  };
};


