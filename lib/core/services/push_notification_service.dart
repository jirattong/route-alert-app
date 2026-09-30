import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../../features/auth_face_login/data/services/face_auth_repository.dart';
import 'ambulance_storage_service.dart';
import 'critical_notification_service.dart';
import 'incident_notification_presenter.dart';
import 'live_tracking_service.dart';
import 'local_incident_notifier.dart';
import 'notification_intent.dart';
import 'push_trigger.dart';

/// จัดการ push notification (Firebase Cloud Messaging) ฝั่งแอป — ขอสิทธิ์, เก็บ
/// token ผูกกับบัญชี, แสดงแจ้งเตือนเคส และส่งต่อการกดแจ้งเตือนไปยังตัวนำทาง
/// ถ้าเครื่องนี้รับ push ไม่ได้ (เช่น iPhone บัญชี Apple ฟรี) จะเปิดตัวแจ้งเตือน
/// สำรองในเครื่อง (LocalIncidentNotifier) แทน
class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  String? _email;
  bool _listenersAttached = false;
  static bool _openHandlersAttached = false;

  /// true เมื่อเครื่องนี้ได้ token และบันทึกลงบัญชีแล้ว (รับ push จากเซิร์ฟเวอร์ได้)
  final ValueNotifier<bool> pushAvailable = ValueNotifier(false);

  /// เรียกทุกครั้งที่รู้ว่าบัญชีไหนล็อกอินอยู่ (cold-start ที่มี session ค้าง,
  /// ล็อกอิน/สมัครสำเร็จ) — เรียกซ้ำด้วยบัญชีเดิมจะไม่ทำอะไร แต่ถ้าสลับบัญชี
  /// บนเครื่องเดิมจะย้าย token ไปผูกกับบัญชีใหม่
  Future<void> initialize(String email) async {
    final clean = email.trim().toLowerCase();
    if (_email == clean) return;
    _email = clean;

    // หน้าล็อก/Dynamic Island ไม่พึ่ง FCM — เริ่มก่อน ไม่ต้องรอขั้นตอน FCM ซึ่งบน iPhone
    // บัญชีฟรีอาจค้าง/ล้ม
    unawaited(LiveTrackingService.instance.start(clean));
    // หน่วยรถต้องตรงกับบัญชีเร็วที่สุด (ก่อนหน้ารถพยาบาลใช้รหัสหน่วยตัดสินว่าเคสไหนเป็นของตัวเอง)
    unawaited(syncAmbulanceUnitId());

    // ขอสิทธิ์แจ้งเตือนของเครื่องเอง (local) หลังล็อกอิน — ไม่พึ่ง FCM ซึ่งบน iPhone บัญชีฟรีใช้ไม่ได้
    await CriticalNotificationService().initialize();

    var tokenSaved = false;
    try {
      // cold-start: AppLoadingScreen อาจเรียกมาก่อน Firebase.initializeApp ใน main.dart เสร็จ
      for (var i = 0; i < 24 && Firebase.apps.isEmpty; i++) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
      if (Firebase.apps.isEmpty) {
        throw StateError('Firebase ยังไม่พร้อม');
      }
      final messaging = FirebaseMessaging.instance;
      await messaging
          .requestPermission(alert: true, badge: true, sound: true)
          .timeout(const Duration(seconds: 20));

      final token =
          await messaging.getToken().timeout(const Duration(seconds: 10));
      if (token != null && _email == clean) {
        await FaceAuthRepository.updateFcmToken(clean, token);
        tokenSaved = true;
      }

      if (!_listenersAttached) {
        _listenersAttached = true;
        messaging.onTokenRefresh.listen((newToken) {
          final current = _email;
          if (current != null) {
            FaceAuthRepository.updateFcmToken(current, newToken);
          }
        });

        // ตอนแอปเปิดอยู่ ระบบไม่โชว์แจ้งเตือนให้เอง (Android ได้แบบ data-only,
        // iOS ถูกปิดไว้ตอน foreground) — แสดงเองแบบเดียวกับตอนอยู่เบื้องหลัง
        FirebaseMessaging.onMessage.listen((message) {
          IncidentNotificationPresenter.present(message.data);
        });
      }
    } catch (e) {
      // เปิดทางให้เรียก initialize() ใหม่ได้ภายหลัง (เช่น Firebase init เสร็จช้า
      // กว่า AppLoadingScreen ตอน cold-start)
      if (_email == clean) _email = null;
      debugPrint('PushNotificationService.initialize error: $e');
    }

    pushAvailable.value = tokenSaved;
    if (tokenSaved && serverPushConfigured) {
      await LocalIncidentNotifier.instance.stop();
    } else {
      await LocalIncidentNotifier.instance.start(clean);
    }
  }

  /// ผูกการกดแจ้งเตือนที่ระบบ (iOS) แสดงให้จาก FCM — เรียกตอนเปิดแอป ไม่ขึ้นกับการล็อกอิน
  static Future<void> initOpenHandlers() async {
    if (_openHandlersAttached || Firebase.apps.isEmpty) return;
    _openHandlersAttached = true;
    try {
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        NotificationIntentHub.dispatch(NotificationIntent.fromData(message.data));
      });
      // iOS + UIScene: firebase_messaging อาจไม่เคยได้ตั้งค่าตัวเอง getInitialMessage จะไม่ตอบ
      final initial = await FirebaseMessaging.instance
          .getInitialMessage()
          .timeout(const Duration(seconds: 5), onTimeout: () => null);
      if (initial != null) {
        NotificationIntentHub.dispatch(NotificationIntent.fromData(initial.data));
      }
    } catch (e) {
      debugPrint('PushNotificationService.initOpenHandlers error: $e');
    }
  }

  /// ผูกหน่วยรถพยาบาลของเครื่องนี้กับบัญชี (เฉพาะ role ambulance)
  Future<void> syncAmbulanceUnitId() async {
    try {
      final user = await FaceAuthRepository.getCurrentUser();
      if (user == null || user.role != 'ambulance') return;
      await AmbulanceStorageService.syncWithAccount(user.email);
    } catch (e) {
      debugPrint('PushNotificationService.syncAmbulanceUnitId error: $e');
    }
  }

  /// เรียกตอน logout — เอา token เครื่องนี้ออกจากบัญชีเดิม ไม่งั้นบัญชีเดิมจะ
  /// ยังได้รับแจ้งเตือนเข้าเครื่องนี้ต่อไปแม้คนอื่นล็อกอินแทนแล้ว
  Future<void> detach(String email) async {
    _email = null;
    pushAvailable.value = false;
    await LocalIncidentNotifier.instance.stop();
    await LiveTrackingService.instance.stop();
    try {
      if (Firebase.apps.isEmpty) return;
      final token = await FirebaseMessaging.instance
          .getToken()
          .timeout(const Duration(seconds: 3));
      if (token != null) {
        await FaceAuthRepository.clearFcmTokenIfMatches(email, token);
      }
    } catch (e) {
      debugPrint('PushNotificationService.detach error: $e');
    }
  }
}

/// firebase_messaging บังคับให้เป็น top-level function — Android ได้ข้อความแบบ
/// data-only แม้แอปถูกปัดปิด จึงต้องวาดแจ้งเตือนเองตรงนี้ (มีปุ่ม/ทับอันเดิมได้)
/// ส่วน iOS ที่มี alert ระบบโชว์ให้เองแล้ว ข้ามไป
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.notification != null) return;
  DartPluginRegistrant.ensureInitialized();
  await IncidentNotificationPresenter.present(message.data,
      inBackgroundIsolate: true);
}
