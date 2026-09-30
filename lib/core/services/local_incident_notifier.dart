import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth_face_login/data/services/face_auth_repository.dart';
import '../models/incident_report.dart';
import 'ambulance_storage_service.dart';
import 'incident_notification_presenter.dart';
import 'incident_service.dart';
import 'notification_intent.dart';

@immutable
class LocalNotifierUser {
  final String email;
  final String role;
  final String? hospitalId;
  final String? ambulanceUnitId;

  const LocalNotifierUser({
    required this.email,
    required this.role,
    this.hospitalId,
    this.ambulanceUnitId,
  });
}

@immutable
class LocalPlanResult {
  final List<Map<String, String>> notifications;
  final Map<String, dynamic> nextLog;
  final bool changed;

  const LocalPlanResult(this.notifications, this.nextLog, this.changed);
}

/// ตัวแจ้งเตือนสำรองในเครื่อง — ใช้เมื่อเครื่องนี้รับ push จากเซิร์ฟเวอร์ไม่ได้ (เช่น
/// iPhone ที่ใช้บัญชี Apple ฟรี) หรือยังไม่ได้ตั้งค่าตัวส่ง push: ดูการเปลี่ยนแปลงของ
/// เคสจาก Firestore ตลอดที่แอปยังทำงานอยู่ แล้วแสดงแจ้งเตือนแบบเดียวกับเซิร์ฟเวอร์
/// ตรรกะต้องตรงกับ planNotifications() ใน push-worker/src/index.js
class LocalIncidentNotifier {
  static final LocalIncidentNotifier instance = LocalIncidentNotifier._();
  LocalIncidentNotifier._();

  static const _freshWindow = Duration(minutes: 15);
  static const _maxLogEntries = 300;

  StreamSubscription<List<IncidentReport>>? _sub;
  String? _email;
  LocalNotifierUser? _user;
  Map<String, Map<String, dynamic>> _log = {};
  Future<void> _queue = Future.value();

  bool get isRunning => _sub != null;

  Future<void> start(String email) async {
    final clean = email.trim().toLowerCase();
    if (_email == clean && _sub != null) return;
    await stop();
    _email = clean;

    // ตอนเพิ่งล็อกอิน session อาจยังบันทึกไม่เสร็จ รอสั้นๆ ก่อนยอมแพ้
    var user = await FaceAuthRepository.getCurrentUser();
    for (var i = 0; i < 3 && (user == null || user.email.trim().toLowerCase() != clean); i++) {
      await Future.delayed(const Duration(seconds: 1));
      user = await FaceAuthRepository.getCurrentUser();
    }
    if (_email != clean || user == null || user.email.trim().toLowerCase() != clean) {
      if (_email == clean) _email = null;
      return;
    }

    String? unit;
    if (user.role == 'ambulance') {
      unit = AmbulanceStorageService.profileNotifier.value['ambulanceId'];
      if (unit == null || unit.isEmpty) {
        unit = (await AmbulanceStorageService.loadProfile())['ambulanceId'];
      }
    }
    _user = LocalNotifierUser(
      email: clean,
      role: user.role,
      hospitalId: user.hospitalId,
      ambulanceUnitId: unit,
    );
    _log = await _loadLog(clean);
    if (_email != clean) return;

    await IncidentService().ensureInitialized();
    _enqueue(await IncidentService().getLocalIncidents());
    _sub = IncidentService().incidentsStream.listen(_enqueue);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _email = null;
    _user = null;
    _log = {};
  }

  void _enqueue(List<IncidentReport> incidents) {
    _queue = _queue.then((_) => _process(incidents)).catchError((Object e) {
      debugPrint('LocalIncidentNotifier error: $e');
    });
  }

  Future<void> _process(List<IncidentReport> incidents) async {
    final email = _email;
    var user = _user;
    if (email == null || user == null) return;

    // หน่วยรถอาจถูกแก้ในหน้าโปรไฟล์ระหว่างใช้งาน
    if (user.role == 'ambulance') {
      final unit = AmbulanceStorageService.profileNotifier.value['ambulanceId'];
      if (unit != null && unit.isNotEmpty && unit != user.ambulanceUnitId) {
        user = _user = LocalNotifierUser(
            email: user.email, role: user.role, hospitalId: user.hospitalId, ambulanceUnitId: unit);
      }
    }

    var dirty = false;
    for (final incident in incidents) {
      final result = plan(incident, _log[incident.id] ?? const {}, user, DateTime.now());
      if (!result.changed) continue;
      _log.remove(incident.id);
      _log[incident.id] = result.nextLog;
      dirty = true;
      for (final data in result.notifications) {
        if (_email != email) return;
        await IncidentNotificationPresenter.present(data);
      }
    }
    if (dirty && _email == email) {
      await _saveLog(email, incidents.map((i) => i.id).toSet());
    }
  }

  static String _logKey(String email) => 'local_push_log_v1_$email';

  Future<Map<String, Map<String, dynamic>>> _loadLog(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_logKey(email));
      if (raw == null) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
    } catch (_) {
      return {};
    }
  }

  // ตัดทิ้งเฉพาะเคสที่ไม่อยู่ในรายการแล้ว (ถูกลบ) — ถ้าตัดเคสที่ยังอยู่ รอบถัดไป
  // จะวางแผนใหม่จาก log ว่างแล้วแจ้งเตือนเคสที่ยังใหม่ซ้ำอีกครั้ง
  Future<void> _saveLog(String email, Set<String> presentIds) async {
    final removable = _log.keys.where((id) => !presentIds.contains(id)).toList();
    for (final id in removable) {
      if (_log.length <= _maxLogEntries) break;
      _log.remove(id);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_logKey(email), jsonEncode(_log));
    } catch (_) {}
  }

  /// ตัดสินใจว่าเครื่องนี้ (ของ [user]) ต้องแจ้งเตือนอะไรบ้างจากสถานะปัจจุบันของเคส
  static LocalPlanResult plan(
    IncidentReport incident,
    Map<String, dynamic> log,
    LocalNotifierUser user,
    DateTime now,
  ) {
    final next = Map<String, dynamic>.from(log);
    final out = <Map<String, String>>[];
    final age = now.difference(incident.createdAt);
    final fresh = age >= const Duration(seconds: -60) && age <= _freshWindow;
    final silent = incident.archived || (log['created'] != true && !fresh);
    final closed = incident.status == 'resolved' || incident.status == 'cancelled';
    final myEmail = user.email.trim().toLowerCase();
    final isReporter =
        myEmail.isNotEmpty && incident.reporterEmail.trim().toLowerCase() == myEmail;

    void add(String kind, String audience, String title, String body) => out.add({
          'incidentId': incident.id,
          'kind': kind,
          'audience': audience,
          'title': title,
          'body': body,
        });

    final type = incident.type.isNotEmpty ? incident.type : 'เหตุฉุกเฉิน';
    final place = incident.address.isNotEmpty
        ? incident.address
        : (incident.province.isNotEmpty ? incident.province : 'ไม่ระบุตำแหน่ง');
    final unit = [incident.assignedAmbulanceCallSign, incident.assignedAmbulancePlate]
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => 'หน่วยกู้ชีพ')!;
    final nearUnit = (incident.ambulanceNearCallSign ?? '').isNotEmpty
        ? incident.ambulanceNearCallSign!
        : unit;

    if (log['created'] != true) {
      next['created'] = true;
      if (!silent && incident.status == 'pending') {
        final target = incident.targetHospitalId;
        final mine = user.hospitalId;
        if (user.role == 'agency' &&
            (target == null || target.isEmpty || mine == null || mine.isEmpty || mine == target)) {
          final severity = incident.severity.isNotEmpty ? '${incident.severity} · ' : '';
          add(PushKind.newIncident, PushAudience.agency, '🚨 เคสใหม่: $type', '$severity$place');
        } else if (user.role == 'ambulance') {
          add(PushKind.newIncident, PushAudience.ambulance, '🚑 มีเคสใหม่รอรับ', '$type · $place');
        }
      }
    }

    // เคสเดียวรับได้หลายคัน — แจ้งทีละหน่วยที่เพิ่งเข้าเคส (log เดิมมีแค่ assignedTo คันแรก)
    final units = incident.units;
    final notified = <String>{
      if (log['assignedTo'] != null) '${log['assignedTo']}',
      ...((log['assignedUnits'] as List?) ?? const []).map((e) => '$e'),
    };
    final newUnits = units.where((u) => !notified.contains(u.unitId)).toList();
    if (newUnits.isNotEmpty) {
      final firstAssignment = notified.isEmpty;
      final prevVehicles = (log['vehicleCount'] as num?)?.toInt() ?? (firstAssignment ? 0 : 1);
      next['assignedTo'] = log['assignedTo'] ?? units.first.unitId;
      next['assignedUnits'] = [...notified, ...newUnits.map((u) => u.unitId)];
      next['vehicleCount'] = incident.vehicleCount;
      if (!silent && !closed) {
        if (user.role == 'ambulance') {
          final mine = user.ambulanceUnitId;
          final assignedToMe = mine != null &&
              newUnits.any((u) => u.unitId == mine && u.assignedBy != 'ambulance');
          if (assignedToMe) {
            add(PushKind.assignedToYou, PushAudience.ambulance, '🚑 ได้รับมอบหมายเคสใหม่',
                '$type · $place');
          } else if (firstAssignment) {
            add(PushKind.caseTaken, PushAudience.ambulance, '', '');
          }
        }
        if (isReporter) {
          if (firstAssignment) {
            add(PushKind.ambulanceOnTheWay, PushAudience.reporter,
                '🚑 รถพยาบาลกำลังเดินทางไปหาคุณ', '$unit รับเคสของคุณแล้ว');
          } else if (incident.vehicleCount > prevVehicles) {
            add(PushKind.ambulanceOnTheWay, PushAudience.reporter,
                '🚑 มีรถพยาบาลมาเพิ่ม',
                'ตอนนี้มี ${incident.vehicleCount} คันกำลังไปหาคุณ (${incident.vehiclesLabel})');
          }
        }
      }
    }

    if (incident.ambulanceNearSceneAt != null && log['nearScene'] != true) {
      next['nearScene'] = true;
      if (!silent && !closed && isReporter) {
        final eta = incident.ambulanceNearEtaMinutes;
        final etaText = (eta != null && eta > 0) ? ' (อีกราว $eta นาที)' : '';
        add(PushKind.ambulanceNear, PushAudience.reporter, '📍 รถพยาบาลใกล้ถึงแล้ว',
            '$nearUnit อยู่ห่างไม่ถึง 500 ม.$etaText เตรียมตัวรอที่จุดเกิดเหตุ');
      }
    }

    if (incident.status == 'resolved' && log['resolved'] != true) {
      next['resolved'] = true;
      if (!silent && isReporter) {
        final hospital = incident.hospitalName;
        add(
          PushKind.resolved,
          PushAudience.reporter,
          '✅ เคสของคุณเสร็จสิ้นแล้ว',
          (hospital != null && hospital.isNotEmpty)
              ? 'ผู้ป่วยถึง $hospital เรียบร้อยแล้ว'
              : 'ทีมกู้ชีพดำเนินการเสร็จสิ้นแล้ว ขอบคุณที่แจ้งเหตุ',
        );
      }
    }

    final changed = ['created', 'assignedTo', 'nearScene', 'resolved', 'vehicleCount']
            .any((k) => next[k] != log[k]) ||
        '${next['assignedUnits']}' != '${log['assignedUnits']}';
    return LocalPlanResult(out, next, changed);
  }
}
