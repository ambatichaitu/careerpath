import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'core/auth_gate.dart';
import 'firebase_options.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!DefaultFirebaseOptions.isConfigured) {
    debugPrint(
      '[FIREBASE CONFIG NOTICE] CareerPath is running with placeholder Firebase options. '
      'Run "flutterfire configure --project=careerpath-26fa0" to connect genuine cloud authentication.',
    );
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization notice: $e');
  }

  // Probe and resolve the fastest reachable backend URL (Physical phone / LAN / Emulator)
  try {
    await AppConfig.resolveBackendBaseUrl();
  } catch (_) {}

  runApp(const CareerPathApp());
}

/// CareerPath root application widget.
/// Configures Material 3 light theme and routes to the central Firebase AuthGate.
/// Accepts an optional [home] widget for test environments without live Firebase channels.
class CareerPathApp extends StatelessWidget {
  final Widget? home;

  const CareerPathApp({super.key, this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: home ?? const AuthGate(),
    );
  }
}
