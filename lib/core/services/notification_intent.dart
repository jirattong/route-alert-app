import 'dart:convert';

import 'package:flutter/widgets.dart';

/// รูปแบบข้อมูลแจ้งเตือนเคส — ค่าเหล่านี้ต้องตรงกับที่ push-worker/src/index.js
/// และ functions/index.js ส่งมาใน FCM data (incidentId, kind, audience, title, body)
class PushKind {
  static const newIncident = 'new_incident';
  static const assignedToYou = 'assigned_to_you';
  static const ambulanceOnTheWay = 'ambulance_on_the_way';
  static const ambulanceNear = 'ambulance_near';
  static const resolved = 'resolved';
  // ไม่แสดงอะไร — สั่งลบแจ้งเตือน "มีเคสใหม่รอรับ" ที่ค้างอยู่เมื่อเคสมีรถรับแล้ว
  static const caseTaken = 'case_taken';
}

class PushAudience {
  static const agency = 'agency';
  static const ambulance = 'ambulance';
  static const reporter = 'reporter';
}

/// สิ่งที่ผู้ใช้กดบนแจ้งเตือน — 'tap' คือกดตัวแจ้งเตือน ที่เหลือคือ id ของปุ่ม
class PushAction {
  static const tap = 'tap';
  static const view = 'view';
  static const accept = 'accept';
  static const dispatch = 'dispatch';
}

/// ใช้นำทางจากนอก widget tree (เช่นตอนกดแจ้งเตือน) — ผูกกับ MaterialApp ใน main.dart
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// id แจ้งเตือนคงที่ต่อเคส — แสดงซ้ำด้วย id เดิมจะทับอันเก่า (สถานะใหม่แทนที่
/// สถานะเก่า ไม่ต่อแถวยาว) อยู่ในช่วง [2^30, 2^31) ไม่ชนกับ id ตายตัว 911/1669
/// ของแจ้งเตือนเรดาร์ ใช้ hash เองแทน String.hashCode ให้ได้ค่าเดิมทุก isolate/ทุกรุ่น
int notificationIdForIncident(String incidentId) =>
    0x40000000 + (_incidentHash(incidentId) % 0x3fffffff);

int _incidentHash(String incidentId) {
  var h = 0;
  for (final unit in utf8.encode(incidentId)) {
    h = (h * 31 + unit) % 2147483647;
  }
  return h;
}

/// id ของแจ้งเตือนค้างติดตามรถ (Android) — ช่วง [2^29, 2^30) ไม่ซ้อนกับแจ้งเตือนเคส
int trackingNotificationIdForIncident(String incidentId) =>
    0x20000000 + (_incidentHash(incidentId) % 0x1fffffff);

@immutable
class NotificationIntent {
  final String incidentId;
  final String kind;
  final String audience;
  final String action;

  const NotificationIntent({
    required this.incidentId,
    required this.kind,
    required this.audience,
    this.action = PushAction.tap,
  });

  static NotificationIntent? fromData(Map<String, dynamic> data,
      {String action = PushAction.tap}) {
    final id = data['incidentId']?.toString() ?? '';
    if (id.isEmpty) return null;
    return NotificationIntent(
      incidentId: id,
      kind: data['kind']?.toString() ?? '',
      audience: data['audience']?.toString() ?? '',
      action: action,
    );
  }

  /// [actionId] ว่าง/null = กดตัวแจ้งเตือน ไม่ได้กดปุ่ม
  static NotificationIntent? fromPayload(String? payload, {String? actionId}) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      return fromData(
        Map<String, dynamic>.from(decoded),
        action: (actionId == null || actionId.isEmpty) ? PushAction.tap : actionId,
      );
    } catch (_) {
      return null;
    }
  }

  String toPayload() =>
      jsonEncode({'incidentId': incidentId, 'kind': kind, 'audience': audience});

  bool sameAs(NotificationIntent other) =>
      other.incidentId == incidentId &&
      other.kind == kind &&
      other.audience == audience &&
      other.action == action;

  @override
  String toString() => 'NotificationIntent($incidentId, $kind, $audience, $action)';
}

/// จุดกลางส่งต่อ "ผู้ใช้กดแจ้งเตือน" จากแหล่งต่างๆ (local notification, FCM, เปิด
/// แอปจากแจ้งเตือน) ไปยังตัวนำทาง — กดก่อนตัวนำทางพร้อม (เช่นเปิดแอปจากสถานะปิด
/// สนิท) จะเก็บไว้ก่อนแล้วส่งให้ทันทีที่ตัวนำทางลงทะเบียน
class NotificationIntentHub {
  static void Function(NotificationIntent intent)? _handler;
  static final List<NotificationIntent> _pending = [];

  static void dispatch(NotificationIntent? intent) {
    if (intent == null) return;
    final handler = _handler;
    if (handler != null) {
      handler(intent);
    } else {
      _pending.add(intent);
    }
  }

  static void setHandler(void Function(NotificationIntent intent) handler) {
    _handler = handler;
    final queued = List.of(_pending);
    _pending.clear();
    queued.forEach(handler);
  }
}
