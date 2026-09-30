import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'critical_notification_service.dart';
import 'notification_intent.dart';

/// หน้าตาแจ้งเตือนของเคส 1 รายการ (แยกเป็น pure data ไว้ทดสอบได้)
@immutable
class IncidentNotificationSpec {
  final int id;
  final bool cancelOnly;
  final String title;
  final String body;
  final bool emergency;
  final String? category;
  final String payload;
  final String threadId;
  final Color color;

  const IncidentNotificationSpec({
    required this.id,
    required this.cancelOnly,
    required this.title,
    required this.body,
    required this.emergency,
    required this.category,
    required this.payload,
    required this.threadId,
    required this.color,
  });
}

/// แปลงข้อมูลแจ้งเตือนเคส (จาก FCM data หรือจากตัวแจ้งเตือนสำรองในเครื่อง) เป็น
/// แจ้งเตือนจริง ใช้ได้ทั้งใน isolate หลักและ isolate เบื้องหลังของ FCM
class IncidentNotificationPresenter {
  static const _red = Color(0xFFDC2626);
  static const _teal = Color(0xFF00A896);
  static const _green = Color(0xFF10B981);

  static IncidentNotificationSpec? specFor(Map<String, dynamic> data) {
    final intent = NotificationIntent.fromData(data);
    if (intent == null) return null;
    final id = notificationIdForIncident(intent.incidentId);
    final title = data['title']?.toString() ?? '';
    final body = data['body']?.toString() ?? '';

    IncidentNotificationSpec spec({
      bool cancelOnly = false,
      bool emergency = false,
      String? category,
      Color color = _teal,
    }) =>
        IncidentNotificationSpec(
          id: id,
          cancelOnly: cancelOnly,
          title: title,
          body: body,
          emergency: emergency,
          category: category,
          payload: intent.toPayload(),
          threadId: intent.incidentId,
          color: color,
        );

    if (intent.kind == PushKind.caseTaken) return spec(cancelOnly: true);
    if (title.isEmpty) return null;

    switch (intent.kind) {
      case PushKind.newIncident:
        final category = switch (intent.audience) {
          PushAudience.agency => CriticalNotificationService.categoryNewAgency,
          PushAudience.ambulance =>
            CriticalNotificationService.categoryNewAmbulance,
          _ => null,
        };
        return spec(emergency: true, category: category, color: _red);
      case PushKind.assignedToYou:
        return spec(emergency: true, color: _red);
      case PushKind.resolved:
        return spec(color: _green);
      default:
        return spec();
    }
  }

  static Future<void> present(Map<String, dynamic> data,
      {bool inBackgroundIsolate = false}) async {
    final spec = specFor(data);
    if (spec == null) return;
    final service = CriticalNotificationService();
    await service.initialize(requestPermissions: !inBackgroundIsolate);
    if (spec.cancelOnly) {
      await service.cancelNotification(spec.id);
      return;
    }
    await service.showIncidentNotification(
      id: spec.id,
      title: spec.title,
      body: spec.body,
      emergency: spec.emergency,
      payload: spec.payload,
      threadId: spec.threadId,
      color: spec.color,
      category: spec.category,
    );
  }
}
