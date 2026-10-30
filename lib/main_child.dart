import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'child_app/child_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase (Required for RTDB telemetry)
  await Firebase.initializeApp();
  
  runApp(const KidGuardChildApp());
}
