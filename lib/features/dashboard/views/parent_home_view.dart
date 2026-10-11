import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'add_child_view.dart';
import 'dashboard_view.dart';

class ParentHomeView extends StatefulWidget {
  const ParentHomeView({
    required this.auth,
    required this.database,
    required this.parentUid,
    super.key,
  });

  final FirebaseAuth auth;
  final FirebaseDatabase database;
  final String parentUid;

  @override
  State<ParentHomeView> createState() => _ParentHomeViewState();
}

class _ParentHomeViewState extends State<ParentHomeView> {
  bool _hasPairedDevice = false;

  @override
  void didUpdateWidget(covariant ParentHomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parentUid != widget.parentUid) {
      _hasPairedDevice = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final childrenReference =
        widget.database.ref('/parents/${widget.parentUid}/children');

    return StreamBuilder<DatabaseEvent>(
      stream: childrenReference.onValue,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SelectableText(
                  'Could not check linked child devices: ${snapshot.error}',
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final value = snapshot.data!.snapshot.value;
        if (value is Map && value.isNotEmpty) {
          _hasPairedDevice = true;
        }

        if (_hasPairedDevice) {
          return DashboardView(
            auth: widget.auth,
            database: widget.database,
            parentUid: widget.parentUid,
          );
        }

        return AddChildView(
          database: widget.database,
          parentUid: widget.parentUid,
        );
      },
    );
  }
}
