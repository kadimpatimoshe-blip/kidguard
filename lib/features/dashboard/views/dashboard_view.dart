import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../models/parent_child_device.dart';
import '../services/parent_device_service.dart';
import 'add_child_view.dart';
import 'parent_live_stream_view.dart'
    if (dart.library.js_interop) 'parent_live_stream_view_web.dart';

class DashboardView extends StatelessWidget {
  const DashboardView({
    required this.auth,
    required this.database,
    required this.parentUid,
    super.key,
  });

  final FirebaseAuth auth;
  final FirebaseDatabase database;
  final String parentUid;

  Future<void> _openAddChild(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AddChildView(
          database: database,
          parentUid: parentUid,
          onPaired: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Future<void> _openLiveStream(
    BuildContext context,
    ParentChildDevice device,
  ) async {
    final deviceId = device.deviceId ?? device.childUid;
    if (deviceId == null || deviceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This child device is missing its streaming ID.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ParentLiveStreamView(
          database: database,
          deviceId: deviceId,
          parentUid: parentUid,
          childId: device.childId,
          childName: device.childId.length > 8
              ? 'Child device ${device.childId.substring(0, 8)}'
              : 'Child device ${device.childId}',
        ),
      ),
    );
  }

  Future<void> _unlinkChild(
    BuildContext context,
    ParentChildDevice device,
  ) async {
    final shouldUnlink = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete child device?'),
        content: const Text(
          'This will unlink the device from your parent account. '
          'You can pair it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldUnlink != true || !context.mounted) return;

    try {
      await ParentDeviceService(
        database: database,
        parentUid: parentUid,
      ).unlinkChildDevice(
        device.childId,
        deviceKey: device.deviceKey,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Child device unlinked.')),
      );
    } on FirebaseException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not unlink child device: ${error.message ?? error.code}',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not unlink child device: $error')),
      );
    }
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await auth.signOut();
    } on FirebaseAuthException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not sign out: ${error.message ?? error.code}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: database.ref('/parents/$parentUid/children').onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: _buildAppBar(context),
            body: _DashboardMessage(
              icon: Icons.cloud_off,
              message: 'Could not load child devices: ${snapshot.error}',
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: _buildAppBar(context),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        try {
          final devices = _parseDevices(snapshot.data?.snapshot.value);
          final reachedDeviceLimit = devices.length >= 5;
          return Scaffold(
            appBar: _buildAppBar(context),
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Your child devices',
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: reachedDeviceLimit
                                  ? null
                                  : () => _openAddChild(context),
                              icon: const Icon(Icons.add),
                              label: const Text('Add child'),
                            ),
                          ],
                        ),
                        if (reachedDeviceLimit) ...[
                          const SizedBox(height: 12),
                          Text(
                            'You can pair up to 5 child devices.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Expanded(
                          child: devices.isEmpty
                              ? const _DashboardMessage(
                                  icon: Icons.devices,
                                  message: 'No child devices paired yet.',
                                )
                              : ListView.separated(
                                  itemCount: devices.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) => _DeviceCard(
                                    device: devices[index],
                                    onOpenLiveStream: () => _openLiveStream(
                                      context,
                                      devices[index],
                                    ),
                                    onUnlink: () => _unlinkChild(
                                      context,
                                      devices[index],
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        } on FormatException catch (error) {
          return Scaffold(
            appBar: _buildAppBar(context),
            body: _DashboardMessage(
              icon: Icons.warning_amber,
              message: 'A child device record is invalid: ${error.message}',
            ),
          );
        }
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: const Text('KidGuard Parent Dashboard'),
      actions: [
        IconButton(
          tooltip: 'Sign out',
          onPressed: () => _signOut(context),
          icon: const Icon(Icons.logout),
        ),
      ],
    );
  }

  List<ParentChildDevice> _parseDevices(Object? value) {
    if (value == null) return const [];
    if (value is! Map) {
      throw const FormatException('Expected a device list.');
    }

    final devices = <ParentChildDevice>[];
    for (final entry in value.entries) {
      if (entry.key is! String || (entry.key as String).isEmpty) {
        throw const FormatException('Expected a valid device key.');
      }
      final rawDevice = entry.value;
      if (rawDevice is! Map) {
        throw const FormatException('Expected a device record.');
      }
      if (rawDevice.keys.any((key) => key is! String)) {
        throw const FormatException('Expected string device record keys.');
      }

      final deviceMap = Map<String, dynamic>.from(rawDevice);
      devices.add(
        ParentChildDevice.fromMap(
          deviceMap,
          deviceKey: entry.key as String,
        ),
      );
    }

    devices.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return devices;
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.onOpenLiveStream,
    required this.onUnlink,
  });

  final ParentChildDevice device;
  final VoidCallback onOpenLiveStream;
  final VoidCallback onUnlink;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isPending = device.status == 'pending' || device.status == 'unpaired';
    final name = device.childId.length > 8
        ? 'Child device ${device.childId.substring(0, 8)}'
        : 'Child device ${device.childId}';

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: colors.primaryContainer,
              child: Icon(Icons.phonelink, color: colors.onPrimaryContainer),
            ),
            title: Text(name),
            subtitle: Text(
              [
                'Pairing code ${device.pairingCode}',
                if (device.platform != null)
                  '${device.platform}${device.appState == null ? '' : ' • ${device.appState}'}',
                if (device.lastHeartbeat != null)
                  'Last seen ${device.lastHeartbeat!.toLocal()}',
              ].join('\n'),
            ),
            trailing: Chip(
              backgroundColor: isPending
                  ? colors.secondaryContainer
                  : device.isOnline
                      ? Colors.green.shade100
                      : null,
              avatar: Icon(
                isPending
                    ? Icons.hourglass_top
                    : device.isOnline
                        ? Icons.check_circle
                        : Icons.cloud_off,
                size: 18,
                color: isPending
                    ? colors.onSecondaryContainer
                    : device.isOnline
                        ? Colors.green.shade800
                        : null,
              ),
              label: Text(
                isPending
                    ? 'Pending'
                    : device.isOnline
                        ? 'Online'
                        : 'Offline',
                style: isPending
                    ? TextStyle(color: colors.onSecondaryContainer)
                    : device.isOnline
                        ? TextStyle(color: Colors.green.shade900)
                        : null,
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: isPending ? null : onOpenLiveStream,
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Live stream'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Delete/unlink child device',
                  onPressed: onUnlink,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardMessage extends StatelessWidget {
  const _DashboardMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
