import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'features/auth_face_login/presentation/face_login_screen.dart';

import 'dart:async';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Launch Flutter UI IMMEDIATELY!
  // Eliminates white-screen freeze completely by rendering on frame 1 (~50ms)
  runApp(const RouteAlertApp());

  // 2. Initialize background services asynchronously (non-blocking)
  unawaited(_initBackgroundServices());
}

Future<void> _initBackgroundServices() async {
  // Load .env with fast local disk read
  try {
    await dotenv.load(fileName: ".env").timeout(const Duration(seconds: 1));
  } catch (e) {
    debugPrint('DotEnv load notice: $e');
  }

  // Initialize Firebase asynchronously with a strict 3-second timeout
  // to avoid network socket stalls on iOS
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 3));
    }
  } catch (e) {
    debugPrint('Firebase init notice: $e');
  }
}

class RouteAlertApp extends StatelessWidget {
  const RouteAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RouteAlert',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00A896)),
        useMaterial3: true,
      ),
      home: const FaceLoginScreen(),
    );
  }
}