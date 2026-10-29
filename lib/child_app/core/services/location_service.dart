import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/models/telemetry_payload.dart';
import 'rtdb_client_service.dart';

/// Real Hardware GPS Location Tracking Service using `geolocator`
/// Strict production implementation: zero static coordinates, waits for real satellite fixes.
class LocationService {
  final RtdbClientService _rtdbClient;

  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _fallbackSyncTimer;
  bool _isRunning = false;
  String _currentPairingCode = '';
  LocationPayload? _lastLocation;
  String? _lastError;

  void Function(LocationPayload payload)? onLocationUpdated;
  void Function(Map<String, dynamic> data)? onUpdateToParent;
  void Function(String error)? onError;

  LocationService({RtdbClientService? rtdbClient})
      : _rtdbClient = rtdbClient ?? RtdbClientService();

  bool get isRunning => _isRunning;
  LocationPayload? get lastLocation => _lastLocation;
  String? get lastError => _lastError;
  bool get hasValidFix => _lastLocation != null && (_lastLocation!.latitude != 0.0 || _lastLocation!.longitude != 0.0);

  /// Verifies and requests runtime location permissions for Android 14 (API 34)
  Future<bool> checkAndRequestPermissions() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _lastError = 'Hardware location service (GPS) is turned off on this device.';
        onError?.call(_lastError!);
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _lastError = 'Location permission denied by user.';
          onError?.call(_lastError!);
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _lastError = 'Location permission is permanently denied in Android settings.';
        onError?.call(_lastError!);
        return false;
      }

      if (await Permission.locationAlways.isDenied) {
        await Permission.locationAlways.request();
      }

      _lastError = null;
      return true;
    } catch (e) {
      _lastError = 'Permission check failed: $e';
      onError?.call(_lastError!);
      return false;
    }
  }

  /// Starts real-time hardware GPS tracking and continuous RTDB sync
  Future<bool> startTracking({
    required String pairingCode,
    this.onUpdateToParent,
    Duration interval = const Duration(seconds: 15),
  }) async {
    final cleanCode = pairingCode.trim();
    if (cleanCode.isEmpty) return false;
    _currentPairingCode = cleanCode;

    final hasPermission = await checkAndRequestPermissions();
    if (!hasPermission) return false;

    _isRunning = true;

    // 1. Immediately request initial real GPS fix from hardware
    try {
      final initialPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      await _handlePositionUpdate(initialPosition);
    } catch (e) {
      // If immediate fix times out, check last known hardware position without mock fallback
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          await _handlePositionUpdate(lastKnown);
        }
      } catch (_) {}
    }

    // 2. Listen to continuous live GPS position stream from physical device
    _positionStreamSubscription?.cancel();
    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      forceLocationManager: false,
      intervalDuration: const Duration(seconds: 10),
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) async {
        await _handlePositionUpdate(position);
      },
      onError: (err) {
        _lastError = 'GPS hardware stream error: $err';
        onError?.call(_lastError!);
      },
    );

    // 3. Periodic fallback sync to maintain freshness
    _fallbackSyncTimer?.cancel();
    _fallbackSyncTimer = Timer.periodic(interval, (_) async {
      if (!_isRunning) return;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 10),
        );
        await _handlePositionUpdate(pos);
      } catch (_) {}
    });

    return true;
  }

  /// Converts hardware Position into typed LocationPayload and writes to RTDB
  Future<void> _handlePositionUpdate(Position position) async {
    final speedKmH = (position.speed >= 0 ? position.speed * 3.6 : 0.0);
    final formattedAddress = 'GPS Fix: ${position.latitude.toStringAsFixed(5)}°, ${position.longitude.toStringAsFixed(5)}° (±${position.accuracy.toStringAsFixed(1)}m)';

    final payload = LocationPayload(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      address: formattedAddress,
      speed: double.parse(speedKmH.toStringAsFixed(1)),
      timestamp: position.timestamp.millisecondsSinceEpoch,
    );

    _lastLocation = payload;
    _lastError = null;
    onLocationUpdated?.call(payload);

    if (_currentPairingCode.isNotEmpty) {
      await _rtdbClient.updatePath(
        'devices/$_currentPairingCode/location',
        payload.toJson(),
      );
      onUpdateToParent?.call(payload.toJson());
    }
  }

  /// Explicit sync method requested remotely by parent
  Future<bool> syncCurrentLocation(String pairingCode) async {
    _currentPairingCode = pairingCode.trim();
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      await _handlePositionUpdate(pos);
      return true;
    } catch (e) {
      _lastError = 'Failed to get current GPS location: $e';
      onError?.call(_lastError!);
      return false;
    }
  }

  void stopTracking() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _fallbackSyncTimer?.cancel();
    _fallbackSyncTimer = null;
    _isRunning = false;
  }

  void dispose() {
    stopTracking();
  }
}
