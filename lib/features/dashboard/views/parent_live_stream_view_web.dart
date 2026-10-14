import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class ParentLiveStreamView extends StatelessWidget {
  const ParentLiveStreamView({
    required this.database,
    required this.deviceId,
    required this.parentUid,
    required this.childId,
    required this.childName,
    super.key,
  });

  final FirebaseDatabase database;
  final String deviceId;
  final String parentUid;
  final String childId;
  final String childName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(childName)),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Live streaming is not available in the web parent app. '
            'Use the mobile parent app to view a child device.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
