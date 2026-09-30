import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/agency/presentation/agency_incident_detail_screen.dart';
import '../../features/ambulance/presentation/ambulance_case_actions.dart';
import '../../features/ambulance/presentation/ambulance_incident_detail_screen.dart';
import '../../features/auth_face_login/data/services/face_auth_repository.dart';
import '../../features/driver_radar/presentation/incident_detail_screen.dart';
import '../utils/slide_from_right_route.dart';
import 'incident_service.dart';
import 'notification_intent.dart';

/// พาผู้ใช้ไปหน้าเคสที่ถูกต้องเมื่อกดแจ้งเตือน/กดปุ่มบนแจ้งเตือน — รอจนหน้าหลักของ
/// role แสดงแล้วค่อยนำทาง (กดตอนแอปปิดสนิท แอปต้องผ่านหน้าโหลด/ล็อกอินก่อน)
class NotificationRouter {
  static final NotificationRouter instance = NotificationRouter._();
  NotificationRouter._();

  final List<NotificationIntent> _queue = [];
  bool _attached = false;
  int _homesShown = 0;
  bool get _homeShown => _homesShown > 0;
  bool _processing = false;
  NotificationIntent? _lastHandled;
  DateTime? _lastHandledAt;

  void attach() {
    if (_attached) return;
    _attached = true;
    NotificationIntentHub.setHandler(_onIntent);
  }

  // นับจำนวน เพราะตอนสลับหน้า หน้าหลักใหม่อาจแสดงก่อนหน้าเก่าถูก dispose
  void onHomeShown() {
    attach();
    _homesShown++;
    _drain();
  }

  void onHomeHidden() {
    if (_homesShown > 0) _homesShown--;
  }

  void _onIntent(NotificationIntent intent) {
    // กดครั้งเดียวอาจมาถึงจากสองทาง (เช่น launch details + response callback)
    final last = _lastHandled;
    if (last != null &&
        last.sameAs(intent) &&
        DateTime.now().difference(_lastHandledAt!) < const Duration(seconds: 5)) {
      return;
    }
    if (_queue.any((q) => q.sameAs(intent))) return;
    _lastHandled = intent;
    _lastHandledAt = DateTime.now();
    _queue.add(intent);
    _drain();
  }

  Future<void> _drain() async {
    if (_processing || !_homeShown) return;
    _processing = true;
    try {
      while (_queue.isNotEmpty && _homeShown) {
        final handled = await _handle(_queue.first);
        if (!handled) break; // ยังไม่มีผู้ใช้ล็อกอิน เก็บไว้รอรอบหน้า
        _queue.removeAt(0);
      }
    } finally {
      _processing = false;
    }
  }

  /// เจ้าของแจ้งเตือนต้องตรงกับผู้ใช้ที่ล็อกอินอยู่ — กันเปิดหน้าเคสผิดบทบาท
  /// (เช่นแจ้งเตือนของบัญชีเก่าที่ค้างในเครื่องหลังสลับบัญชี)
  static bool isAllowed({
    required String audience,
    required String userRole,
    required String userEmail,
    required String reporterEmail,
  }) {
    switch (audience) {
      case PushAudience.agency:
        return userRole == 'agency';
      case PushAudience.ambulance:
        return userRole == 'ambulance';
      case PushAudience.reporter:
        final me = userEmail.trim().toLowerCase();
        return me.isNotEmpty && reporterEmail.trim().toLowerCase() == me;
      default:
        return true;
    }
  }

  /// คืน false ถ้ายังจัดการไม่ได้ตอนนี้ (ให้ลองใหม่ภายหลัง)
  Future<bool> _handle(NotificationIntent intent) async {
    final user = await FaceAuthRepository.getCurrentUser();
    if (user == null) return false;

    final needsFresh = intent.action == PushAction.accept ||
        intent.action == PushAction.dispatch;
    final incident = await IncidentService()
        .getIncidentById(intent.incidentId, forceRemote: needsFresh);
    final navigator = appNavigatorKey.currentState;
    final context = appNavigatorKey.currentContext;
    if (navigator == null || context == null || !context.mounted) return false;

    if (incident == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่พบเคสนี้ อาจถูกลบไปแล้ว')),
      );
      return true;
    }
    if (!isAllowed(
      audience: intent.audience,
      userRole: user.role,
      userEmail: user.email,
      reporterEmail: incident.reporterEmail,
    )) {
      debugPrint('NotificationRouter: ข้าม $intent (ไม่ใช่ของบัญชี ${user.email})');
      return true;
    }

    // audience ว่าง (ข้อมูลรุ่นเก่า) → เลือกหน้าตาม role ของผู้ใช้
    final audience = intent.audience.isNotEmpty
        ? intent.audience
        : switch (user.role) {
            'agency' => PushAudience.agency,
            'ambulance' => PushAudience.ambulance,
            _ => PushAudience.reporter,
          };

    switch (audience) {
      case PushAudience.agency:
        unawaited(navigator.push(slideFromRightRoute(AgencyIncidentDetailScreen(
          incident: incident,
          autoDispatch: intent.action == PushAction.dispatch,
        ))));
      case PushAudience.ambulance:
        var latest = incident;
        if (intent.action == PushAction.accept) {
          latest = await AmbulanceCaseActions.acceptCase(context, incident) ?? incident;
        }
        final nav = appNavigatorKey.currentState;
        if (nav == null) return true;
        unawaited(nav.push(
            slideFromRightRoute(AmbulanceIncidentDetailScreen(incident: latest))));
      default:
        unawaited(navigator.push(
            slideFromRightRoute(IncidentDetailScreen(incident: incident))));
    }
    return true;
  }
}
