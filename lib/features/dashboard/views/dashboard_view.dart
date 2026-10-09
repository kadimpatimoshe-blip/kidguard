import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../models/parent_child_device.dart';
import 'add_child_view.dart';

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
        ),
      ),
    );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('KidGuard Parent Dashboard'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pushNamed('/child'),
            icon: const Icon(Icons.phonelink_lock),
            label: const Text('Go to Child Mode'),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
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
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _openAddChild(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add child'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: StreamBuilder<DatabaseEvent>(
                      stream:
                          database.ref('/parents/$parentUid/children').onValue,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return _DashboardMessage(
                            icon: Icons.cloud_off,
                            message:
                                'Could not load child devices: ${snapshot.error}',
                          );
                        }
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        try {
                          final devices = _parseDevices(
                            snapshot.data?.snapshot.value,
                          );
                          if (devices.isEmpty) {
                            return const _DashboardMessage(
                              icon: Icons.devices,
                              message:
                                  'No child devices paired yet. Add a child device to get started.',
                            );
                          }
                          return ListView.separated(
                            itemCount: devices.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) =>
                                _DeviceCard(device: devices[index]),
                          );
                        } on FormatException catch (error) {
                          return _DashboardMessage(
                            icon: Icons.warning_amber,
                            message:
                                'A child device record is invalid: ${error.message}',
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<ParentChildDevice> _parseDevices(Object? value) {
    if (value == null) return const [];
    if (value is! Map) {
      throw const FormatException('Expected a device list.');
    }

    return value.values.map((rawDevice) {
      if (rawDevice is! Map) {
        throw const FormatException('Expected a device record.');
      }
      return ParentChildDevice.fromMap(rawDevice);
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final ParentChildDevice device;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = device.childId.length > 8
        ? 'Child device ${device.childId.substring(0, 8)}'
        : 'Child device ${device.childId}';

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colors.primaryContainer,
          child: Icon(Icons.phonelink, color: colors.onPrimaryContainer),
        ),
        title: Text(name),
        subtitle: Text('Pairing code ${device.pairingCode}'),
        trailing: Chip(
          avatar: Icon(
            device.status == 'paired' ? Icons.check_circle : Icons.info,
            size: 18,
          ),
          label: Text(device.status),
        ),
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
