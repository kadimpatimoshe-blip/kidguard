import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'add_child_view.dart';
import 'dashboard_view.dart';

class ParentHomeView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final childrenReference =
        database.ref('/parents/$parentUid/children');

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
          return DashboardView(
            auth: auth,
            database: database,
            parentUid: parentUid,
          );
        }

        return AddChildView(
          database: database,
          parentUid: parentUid,
        );
      },
    );
  }
}
