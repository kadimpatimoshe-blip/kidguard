import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/child_device.dart';
import '../viewmodels/parent_view_model.dart';
import 'pair_device_screen.dart';

/// Complete Parent Console Dashboard Screen
/// Directly synchronized with physical child devices over Firebase RTDB and WebRTC.
class ParentDashboardScreen extends StatefulWidget {
  final ParentViewModel viewModel;
  final VoidCallback onSwitchRole;
  final VoidCallback onSignOut;

  const ParentDashboardScreen({
    Key? key,
    required this.viewModel,
    required this.onSwitchRole,
    required this.onSignOut,
  }) : super(key: key);

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  int _activeActivityTab = 0; // 0: Notifications, 1: Call Logs, 2: App Usage
  bool _showCameraView = false;
  bool _showScreenView = false;

  @override
  void initState() {
    super.initState();
    // Renderer initialization for flutter_webrtc
    widget.viewModel.webRtc.initializeRenderers();
  }

  void _openPairDevice() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PairDeviceScreen(
          viewModel: widget.viewModel,
          onDevicePaired: (device) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Successfully paired ${device.deviceModelName}!'),
                backgroundColor: const Color(0xFF0A9B70),
              ),
            );
          },
        ),
      ),
    );
  }

  void _confirmUnpair(ChildDevice device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair Device?'),
        content: Text(
          'Are you sure you want to unlink ${device.deviceModelName} (${device.pairingCode})? Real-time telemetry and streaming will stop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.viewModel.unpairDevice(device.pairingCode);
            },
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final devices = widget.viewModel.devices;
        final selected = widget.viewModel.selectedDevice ??
            (devices.isNotEmpty ? devices.first : null);

        return Scaffold(
          backgroundColor: const Color(0xFFF4F6F4),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0.5,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A9B70),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KidGuard Parent Console',
                      style: TextStyle(
                        color: Color(0xFF1D302B),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Firebase RTDB & WebRTC Connected',
                      style: TextStyle(
                        color: Color(0xFF71807B),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF71807B)),
                tooltip: 'Refresh Telemetry',
                onPressed: () => widget.viewModel.refreshSelectedDevice(),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF0A9B70)),
                tooltip: 'Pair Device with 4-Digit Code',
                onPressed: _openPairDevice,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF71807B)),
                onSelected: (val) {
                  if (val == 'switch_role') {
                    widget.onSwitchRole();
                  } else if (val == 'sign_out') {
                    widget.onSignOut();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'switch_role',
                    child: Row(
                      children: [
                        Icon(Icons.swap_horiz_rounded, size: 18, color: Color(0xFF0A9B70)),
                        SizedBox(width: 8),
                        Text('Switch to Child Role'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'sign_out',
                    child: Row(
                      children: [
                        Icon(Icons.logout_rounded, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Sign Out'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: devices.isEmpty
              ? _buildEmptyState()
              : SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Active Devices Carousel / Selector
                      _buildDeviceSelector(devices, selected),
                      const SizedBox(height: 16),

                      if (selected != null) ...[
                        // 1. Device Header Card (Presence, status, node)
                        _buildDeviceHeroCard(selected),
                        const SizedBox(height: 16),

                        // 2. Telemetry Cards: Real Hardware Battery & Real GPS Location
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildBatteryCard(selected)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildLocationCard(selected)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // 3. WebRTC Live Media Streaming Views & Controls
                        _buildWebRtcStreamingSection(selected),
                        const SizedBox(height: 16),

                        // 4. Remote Quick Actions (Siren, GPS Refresh, Audio)
                        _buildQuickActionControls(selected),
                        const SizedBox(height: 16),

                        // 5. Real-Time Activity Logs, Calls & App Usage
                        _buildActivityAndLogsSection(selected),
                      ],
                    ],
                  ),
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openPairDevice,
            backgroundColor: const Color(0xFF0A9B70),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Pair Device', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  // ========================================================================
  // EMPTY STATE (No Simulated Fallback)
  // ========================================================================

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF0A9B70).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.phonelink_setup_rounded, size: 40, color: Color(0xFF0A9B70)),
            ),
            const SizedBox(height: 20),
            const Text(
              'Scan or enter 4-digit bind code to connect device',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1D302B)),
            ),
            const SizedBox(height: 8),
            const Text(
              'No active child device found in Firebase RTDB. Open the KidGuard Child Protection app on the child phone to generate a real-time 4-digit code.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF71807B), height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openPairDevice,
              icon: const Icon(Icons.link_rounded),
              label: const Text('Enter 4-Digit Code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A9B70),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // DEVICE SELECTOR BAR
  // ========================================================================

  Widget _buildDeviceSelector(List<ChildDevice> devices, ChildDevice? selected) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: devices.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == devices.length) {
            return ActionChip(
              avatar: const Icon(Icons.add, size: 16, color: Color(0xFF0A9B70)),
              label: const Text('Pair Device', style: TextStyle(color: Color(0xFF0A9B70), fontWeight: FontWeight.bold)),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF0A9B70)),
              onPressed: _openPairDevice,
            );
          }

          final dev = devices[index];
          final isSelected = dev.pairingCode == selected?.pairingCode;

          return FilterChip(
            selected: isSelected,
            showCheckmark: false,
            avatar: Icon(
              Icons.smartphone_rounded,
              size: 16,
              color: isSelected ? Colors.white : const Color(0xFF71807B),
            ),
            label: Text(
              '${dev.deviceModelName} (${dev.pairingCode})',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isSelected ? Colors.white : const Color(0xFF1D302B),
              ),
            ),
            selectedColor: const Color(0xFF0A9B70),
            backgroundColor: Colors.white,
            side: BorderSide(
              color: isSelected ? const Color(0xFF0A9B70) : const Color(0xFFE4E9E5),
            ),
            onSelected: (_) => widget.viewModel.selectDevice(dev),
          );
        },
      ),
    );
  }

  // ========================================================================
  // 1. DEVICE HERO CARD (Presence & Status)
  // ========================================================================

  Widget _buildDeviceHeroCard(ChildDevice device) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF192723), Color(0xFF263D36)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: device.isOnline ? const Color(0xFF34D399) : Colors.amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    device.isOnline ? 'ONLINE & SYNCED' : 'STANDBY / OFFLINE',
                    style: TextStyle(
                      color: device.isOnline ? const Color(0xFF91D5AD) : const Color(0xFFFDE68A),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Code: ${device.pairingCode}',
                      style: const TextStyle(
                        color: Color(0xFF34D399),
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70, size: 18),
                    tooltip: 'Unpair Device',
                    onPressed: () => _confirmUnpair(device),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            device.deviceModelName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'RTDB Path: /devices/${device.pairingCode} • ${device.platform.toUpperCase()}',
            style: const TextStyle(color: Color(0xFF9EB5AB), fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // 2. REAL-TIME BATTERY TELEMETRY CARD
  // ========================================================================

  Widget _buildBatteryCard(ChildDevice device) {
    final isCharging = device.isCharging;
    final stateLabel = isCharging
        ? 'Charging'
        : (device.batteryState.isNotEmpty ? device.batteryState : 'Discharging');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E9E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                isCharging ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
                color: const Color(0xFF0A9B70),
                size: 20,
              ),
              Text(
                '${device.batteryLevel}%',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0A9B70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (device.batteryLevel / 100).clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFE5E7EB),
              color: const Color(0xFF0A9B70),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            stateLabel,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1D302B)),
          ),
          const SizedBox(height: 4),
          Text(
            '${device.batteryVoltage.toStringAsFixed(2)}V • ${device.batteryTemp.toStringAsFixed(1)}°C',
            style: const TextStyle(fontSize: 10, color: Color(0xFF71807B), fontFamily: 'monospace'),
          ),
          if (device.powerSaveMode) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Power Save Active',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ========================================================================
  // 3. REAL-TIME LIVE GPS LOCATION CARD
  // ========================================================================

  Widget _buildLocationCard(ChildDevice device) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E9E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.location_on_rounded, color: Color(0xFF2563EB), size: 20),
              InkWell(
                onTap: () => widget.viewModel.refreshGpsLocation(device.pairingCode),
                child: const Row(
                  children: [
                    Icon(Icons.refresh, size: 12, color: Color(0xFF2563EB)),
                    SizedBox(width: 2),
                    Text(
                      'GPS Live',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (device.hasValidGps) ...[
            Text(
              '${device.latitude.toStringAsFixed(4)}°, ${device.longitude.toStringAsFixed(4)}°',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
                color: Color(0xFF1D302B),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              device.speed > 0
                  ? 'Speed: ${device.speed.toStringAsFixed(1)} km/h • ±${device.accuracy.toStringAsFixed(0)}m'
                  : 'Stationary • ±${device.accuracy.toStringAsFixed(0)}m',
              style: const TextStyle(fontSize: 10, color: Color(0xFF71807B)),
            ),
            const SizedBox(height: 2),
            Text(
              device.address.isNotEmpty ? device.address : 'GPS coordinates reported',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Color(0xFF71807B)),
            ),
          ] else ...[
            const Text(
              'Awaiting GPS fix…',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF71807B)),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => widget.viewModel.refreshGpsLocation(device.pairingCode),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
              child: const Text('Request Location Fix', style: TextStyle(fontSize: 10, color: Color(0xFF2563EB))),
            ),
          ],
        ],
      ),
    );
  }

  // ========================================================================
  // 4. REAL WEBRTC STREAMING SECTION (RTCVideoRenderer & Controls)
  // ========================================================================

  Widget _buildWebRtcStreamingSection(ChildDevice device) {
    final webRtc = widget.viewModel.webRtc;
    final isCamActive = webRtc.isCameraConnected || webRtc.isCameraConnecting || _showCameraView;
    final isScreenActive = webRtc.isScreenConnected || webRtc.isScreenConnecting || _showScreenView;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E9E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'REAL WEBRTC STREAMING CONTROLS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF71807B),
                  letterSpacing: 1.0,
                ),
              ),
              if (webRtc.isCameraConnected || webRtc.isScreenConnected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Color(0xFF10B981), size: 6),
                      SizedBox(width: 4),
                      Text(
                        'P2P CONNECTED',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Control Action Buttons
          Row(
            children: [
              // Remote Camera Button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (webRtc.isCameraConnected || webRtc.isCameraConnecting) {
                      await widget.viewModel.stopCameraStream(device.pairingCode);
                      setState(() => _showCameraView = false);
                    } else {
                      setState(() {
                        _showCameraView = true;
                        _showScreenView = false;
                      });
                      await widget.viewModel.startCameraStream(device.pairingCode);
                    }
                  },
                  icon: Icon(
                    Icons.videocam_rounded,
                    size: 16,
                    color: (webRtc.isCameraConnected || webRtc.isCameraConnecting)
                        ? const Color(0xFF0A9B70)
                        : const Color(0xFF1D302B),
                  ),
                  label: Text(
                    webRtc.isCameraConnected
                        ? 'Stop Cam'
                        : webRtc.isCameraConnecting
                            ? 'Connecting…'
                            : 'Live Camera',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: (webRtc.isCameraConnected || webRtc.isCameraConnecting)
                          ? const Color(0xFF0A9B70)
                          : const Color(0xFF1D302B),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: (webRtc.isCameraConnected || webRtc.isCameraConnecting)
                          ? const Color(0xFF0A9B70)
                          : const Color(0xFFE4E9E5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Screen Mirror Button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (webRtc.isScreenConnected || webRtc.isScreenConnecting) {
                      await widget.viewModel.stopScreenMirror(device.pairingCode);
                      setState(() => _showScreenView = false);
                    } else {
                      setState(() {
                        _showScreenView = true;
                        _showCameraView = false;
                      });
                      await widget.viewModel.startScreenMirror(device.pairingCode);
                    }
                  },
                  icon: Icon(
                    Icons.screen_share_rounded,
                    size: 16,
                    color: (webRtc.isScreenConnected || webRtc.isScreenConnecting)
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF1D302B),
                  ),
                  label: Text(
                    webRtc.isScreenConnected
                        ? 'Stop Mirror'
                        : webRtc.isScreenConnecting
                            ? 'Connecting…'
                            : 'Live Screen',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: (webRtc.isScreenConnected || webRtc.isScreenConnecting)
                          ? const Color(0xFF2563EB)
                          : const Color(0xFF1D302B),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: (webRtc.isScreenConnected || webRtc.isScreenConnecting)
                          ? const Color(0xFF2563EB)
                          : const Color(0xFFE4E9E5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),

          // Live Camera Stream Video Renderer View
          if (isCamActive) ...[
            const SizedBox(height: 12),
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF0A9B70), width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: webRtc.isCameraConnected
                        ? RTCVideoView(
                            webRtc.cameraRenderer,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                          )
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0A9B70)),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Waiting for real remote camera track from child device…',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Signaling over RTDB: /devices/${device.pairingCode}/stream',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  // Overlay controls & lens switcher
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.circle, color: Colors.red, size: 8),
                          const SizedBox(width: 6),
                          Text(
                            'LIVE CAM • ${webRtc.currentCameraFacing.toUpperCase()}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 20),
                          tooltip: 'Switch Camera Lens',
                          style: IconButton.styleFrom(backgroundColor: Colors.black54),
                          onPressed: () => widget.viewModel.switchCameraLens(device.pairingCode),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                          tooltip: 'Close Stream',
                          style: IconButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.8)),
                          onPressed: () async {
                            await widget.viewModel.stopCameraStream(device.pairingCode);
                            setState(() => _showCameraView = false);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Live Screen Mirror Video Renderer View
          if (isScreenActive) ...[
            const SizedBox(height: 12),
            Container(
              height: 260,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: webRtc.isScreenConnected
                        ? RTCVideoView(
                            webRtc.screenRenderer,
                            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                          )
                        : (device.screenFrameBase64 != null
                            ? _buildBase64FrameFallback(device.screenFrameBase64!)
                            : Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Waiting for remote display media stream from child phone…',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Signaling over RTDB: /devices/${device.pairingCode}/screen',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'APP: ${device.screenActiveApp} (${device.screenFps} FPS)',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                      tooltip: 'Stop Screen Mirror',
                      style: IconButton.styleFrom(backgroundColor: Colors.red.withOpacity(0.8)),
                      onPressed: () async {
                        await widget.viewModel.stopScreenMirror(device.pairingCode);
                        setState(() => _showScreenView = false);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBase64FrameFallback(String base64String) {
    try {
      final clean = base64String.contains(',') ? base64String.split(',').last : base64String;
      final bytes = base64Decode(clean);
      return Image.memory(bytes, fit: BoxFit.contain);
    } catch (_) {
      return const Center(child: Text('Awaiting screen frames…', style: TextStyle(color: Colors.white54)));
    }
  }

  // ========================================================================
  // 5. QUICK ACTIONS (Audio Listen & Remote Siren)
  // ========================================================================

  Widget _buildQuickActionControls(ChildDevice device) {
    final webRtc = widget.viewModel.webRtc;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E9E5)),
      ),
      child: Row(
        children: [
          // Listen In (One-way Audio)
          Expanded(
            child: TextButton.icon(
              onPressed: () async {
                if (webRtc.isAudioConnected || webRtc.isAudioConnecting) {
                  await widget.viewModel.stopAudioStream(device.pairingCode);
                } else {
                  await widget.viewModel.startAudioStream(device.pairingCode);
                }
              },
              icon: Icon(
                webRtc.isAudioConnected ? Icons.mic_rounded : Icons.mic_none_rounded,
                size: 16,
                color: webRtc.isAudioConnected ? const Color(0xFF0A9B70) : const Color(0xFF1D302B),
              ),
              label: Text(
                webRtc.isAudioConnected ? 'Listening Live' : 'Listen In (Mic)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: webRtc.isAudioConnected ? const Color(0xFF0A9B70) : const Color(0xFF1D302B),
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: webRtc.isAudioConnected ? const Color(0xFFECFDF5) : const Color(0xFFF8FAF9),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Sound Alarm Siren
          Expanded(
            child: TextButton.icon(
              onPressed: () async {
                final ok = await widget.viewModel.playSirenOnChildDevice(device.pairingCode);
                if (mounted && ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Dispatched siren alert to child device')),
                  );
                }
              },
              icon: const Icon(Icons.volume_up_rounded, size: 16, color: Color(0xFFE11D48)),
              label: const Text(
                'Play Siren',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFE11D48)),
              ),
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFFFF1F2),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================================================
  // 6. REAL-TIME ACTIVITY LOGS, CALLS & APP USAGE (No Mock Lists)
  // ========================================================================

  Widget _buildActivityAndLogsSection(ChildDevice device) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E9E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Tabs
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _buildTabButton(0, 'Alerts (${device.notifications.length})', Icons.notifications_rounded),
                const SizedBox(width: 6),
                _buildTabButton(1, 'Calls (${device.callLogs.length})', Icons.phone_rounded),
                const SizedBox(width: 6),
                _buildTabButton(2, 'Apps (${device.appUsage.length})', Icons.apps_rounded),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE4E9E5)),

          // Tab Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: _buildActiveTabContent(device),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isSelected = _activeActivityTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeActivityTab = index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0A9B70).withOpacity(0.12) : const Color(0xFFF9FAF9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFF0A9B70) : const Color(0xFFE4E9E5),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isSelected ? const Color(0xFF0A9B70) : const Color(0xFF71807B)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? const Color(0xFF0A9B70) : const Color(0xFF71807B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent(ChildDevice device) {
    switch (_activeActivityTab) {
      case 0:
        return _buildNotificationsList(device.notifications);
      case 1:
        return _buildCallLogsList(device.callLogs);
      case 2:
        return _buildAppUsageList(device.appUsage);
      default:
        return const SizedBox();
    }
  }

  Widget _buildNotificationsList(List notifications) {
    if (notifications.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No notifications received yet from child device.',
            style: TextStyle(fontSize: 12, color: Color(0xFF71807B)),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: notifications.length.clamp(0, 15),
      separatorBuilder: (_, __) => const Divider(height: 14, color: Color(0xFFF3F4F6)),
      itemBuilder: (context, index) {
        final notif = notifications[index];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF0A9B70).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.notifications_active_rounded, size: 14, color: Color(0xFF0A9B70)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        notif.appName,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1D302B)),
                      ),
                      Text(
                        _formatRelativeTime(notif.timestamp),
                        style: const TextStyle(fontSize: 9, color: Color(0xFF71807B)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (notif.title.isNotEmpty)
                    Text(
                      notif.title,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                    ),
                  Text(
                    notif.text,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF71807B)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCallLogsList(List callLogs) {
    if (callLogs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No call logs synchronized from device.',
            style: TextStyle(fontSize: 12, color: Color(0xFF71807B)),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: callLogs.length.clamp(0, 15),
      separatorBuilder: (_, __) => const Divider(height: 14, color: Color(0xFFF3F4F6)),
      itemBuilder: (context, index) {
        final call = callLogs[index];
        final isMissed = call.type == 'missed';
        final isIncoming = call.type == 'incoming';

        return Row(
          children: [
            Icon(
              isMissed
                  ? Icons.call_missed_rounded
                  : (isIncoming ? Icons.call_received_rounded : Icons.call_made_rounded),
              size: 16,
              color: isMissed ? Colors.red : (isIncoming ? const Color(0xFF0A9B70) : Colors.blue),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    call.name,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1D302B)),
                  ),
                  Text(
                    call.number,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF71807B)),
                  ),
                ],
              ),
            ),
            Text(
              '${call.duration}s',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF71807B)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAppUsageList(List appUsage) {
    if (appUsage.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No app usage statistics recorded yet.',
            style: TextStyle(fontSize: 12, color: Color(0xFF71807B)),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: appUsage.length.clamp(0, 15),
      separatorBuilder: (_, __) => const Divider(height: 14, color: Color(0xFFF3F4F6)),
      itemBuilder: (context, index) {
        final app = appUsage[index];
        return Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.android_rounded, size: 16, color: Color(0xFF2563EB)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.appName,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1D302B)),
                  ),
                  Text(
                    app.category,
                    style: const TextStyle(fontSize: 9, color: Color(0xFF71807B)),
                  ),
                ],
              ),
            ),
            Text(
              app.durationText,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF1D302B)),
            ),
          ],
        );
      },
    );
  }

  String _formatRelativeTime(int timestamp) {
    final diff = DateTime.now().millisecondsSinceEpoch - timestamp;
    final mins = diff ~/ (60 * 1000);
    if (mins < 1) return 'Just now';
    if (mins < 60) return '${mins}m ago';
    final hours = mins ~/ 60;
    if (hours < 24) return '${hours}h ago';
    return '${hours ~/ 24}d ago';
  }
}
