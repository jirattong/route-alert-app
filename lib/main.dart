import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'core/services/critical_notification_service.dart';
import 'core/services/notification_intent.dart';
import 'core/services/push_notification_service.dart';
import 'features/auth_face_login/presentation/app_loading_screen.dart';

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

  // ต้องพร้อมก่อนผู้ใช้กดแจ้งเตือน และต้องเช็คว่าแอปถูกเปิดจากการกดแจ้งเตือนหรือเปล่า
  // (ยังไม่ขอสิทธิ์ตรงนี้ ไม่งั้น Firebase ต้องรอจนผู้ใช้ตอบกล่องขอสิทธิ์)
  await CriticalNotificationService().initialize(requestPermissions: false);
  await CriticalNotificationService().consumeLaunchDetails();

  // Initialize Firebase asynchronously with a strict 3-second timeout
  // to avoid network socket stalls on iOS
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 3));
    }
    // ต้องลงทะเบียน background handler ให้เร็วที่สุดหลัง Firebase พร้อมใช้งาน
    // (เพิ่มตอนทำระบบแจ้งเตือนเบื้องหลัง) — ตัว handler เองต้องเป็น top-level
    // function เท่านั้นตามข้อกำหนดของ firebase_messaging (ดู
    // push_notification_service.dart)
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await PushNotificationService.initOpenHandlers();
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
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00A896)),
        useMaterial3: true,
      ),
      // AppLoadingScreen เช็ค session ที่ค้างอยู่ (ดูหัวข้อ 17 ใน CHANGES_SUMMARY.md)
      // แล้วพาไปหน้าล็อกอินหรือหน้าหลักของ role ที่ถูกต้องเอง พร้อมอนิเมชันมือ
      // การ์ตูนที่วาดเอง (นิ้วกาง/งอ) แทนหน้าขาวเปล่าๆ — โหลดเร็วมาก ไม่กระทบ
      // "เปิดแอปทันที" ตามที่ตั้งใจไว้ด้านบน (Onboarding เช็คแยกอีกทีหลังล็อกอินแล้ว
      // ดูหัวข้อ 16)
      home: const AppLoadingScreen(),
    );
  }
}
