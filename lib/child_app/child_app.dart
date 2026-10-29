library child_app;

import 'package:flutter/material.dart';
import 'viewmodels/child_view_model.dart';
import 'views/child_home_screen.dart';

export 'core/services/battery_service.dart';
export 'core/services/camera_stream_service.dart';
export 'core/services/location_service.dart';
export 'core/services/notification_service.dart';
export 'core/services/call_log_service.dart';
export 'core/services/app_usage_service.dart';
export 'core/services/screen_mirror_service.dart';
export 'core/services/audio_stream_service.dart';
export 'core/services/foreground_task_service.dart';
export 'core/services/rtdb_client_service.dart';
export 'data/models/telemetry_payload.dart';
export 'data/models/pairing_state_model.dart';
export 'viewmodels/child_view_model.dart';
export 'views/pairing_display_screen.dart';
export 'views/child_home_screen.dart';

/// Standalone Child Mobile Application Root Widget
class KidGuardChildApp extends StatefulWidget {
  const KidGuardChildApp({Key? key}) : super(key: key);

  @override
  State<KidGuardChildApp> createState() => _KidGuardChildAppState();
}

class _KidGuardChildAppState extends State<KidGuardChildApp> {
  late final ChildViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ChildViewModel();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KidGuard Child Companion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF0A9B70),
        scaffoldBackgroundColor: const Color(0xFFF4F6F4),
        fontFamily: 'Roboto',
      ),
      home: ChildHomeScreen(viewModel: _viewModel),
    );
  }
}
