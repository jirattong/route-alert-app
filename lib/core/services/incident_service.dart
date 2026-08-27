import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/incident_report.dart';

class IncidentService {
  static final IncidentService _instance = IncidentService._internal();
  factory IncidentService() => _instance;
  IncidentService._internal();

  static const String _collectionName = 'incident_reports';
  static const String _localKey = 'local_incident_reports_v2';

  final StreamController<List<IncidentReport>> _incidentsController =
      StreamController<List<IncidentReport>>.broadcast();

  Stream<List<IncidentReport>> get incidentsStream =>
      _incidentsController.stream;

  StreamSubscription? _firestoreSubscription;

  /// Initialize real-time listening
  Future<void> initialize() async {
    _initFirestoreListener();
  }

  void _initFirestoreListener() {
    try {
      _firestoreSubscription?.cancel();
      _firestoreSubscription = FirebaseFirestore.instance
          .collection(_collectionName)
          .snapshots()
          .listen((snapshot) async {
        final List<IncidentReport> list = [];
        for (var doc in snapshot.docs) {
          try {
            final data = doc.data();
            list.add(IncidentReport.fromMap(data));
          } catch (e) {
            debugPrint('Error parsing incident doc ${doc.id}: $e');
          }
        }

        // Sort latest first
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        // Save to local cache
        await _saveToLocalCache(list);
        if (!_incidentsController.isClosed) {
          _incidentsController.add(list);
        }
      }, onError: (err) async {
        debugPrint('Firestore incident stream error: $err');
        final local = await getLocalIncidents();
        if (!_incidentsController.isClosed) {
          _incidentsController.add(local);
        }
      });
    } catch (e) {
      debugPrint('IncidentService init error: $e');
    }
  }

  // Anti-Spam & Sybil Attack Protection State
  DateTime? _lastReportSubmissionTime;
  static const Duration _antiSpamCooldown = Duration(minutes: 2);

  /// Check remaining cooldown seconds (Anti-Spam)
  int get remainingCooldownSeconds {
    if (_lastReportSubmissionTime == null) return 0;
    final elapsed = DateTime.now().difference(_lastReportSubmissionTime!);
    final remaining = _antiSpamCooldown.inSeconds - elapsed.inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Create a new incident report (Driver role with Anti-Spam Defense)
  Future<Map<String, dynamic>> createIncident(IncidentReport incident) async {
    try {
      // 1. Anti-Spam Rate Limit Check
      if (remainingCooldownSeconds > 0) {
        return {
          'success': false,
          'message':
              '⚠️ ป้องกันสแปมแจ้งเหตุ: กรุณารอสักครู่ (เหลือ Cooldown $remainingCooldownSeconds วินาที) หากมีเหตุเร่งด่วนกรุณาโทร 1669',
        };
      }

      final id = incident.id.isNotEmpty
          ? incident.id
          : 'INC-${DateTime.now().millisecondsSinceEpoch}';

      final newIncident = incident.copyWith(id: id);

      // 2. Save to local cache first
      final local = await getLocalIncidents();
      local.removeWhere((i) => i.id == id);
      local.insert(0, newIncident);
      await _saveToLocalCache(local);
      if (!_incidentsController.isClosed) {
        _incidentsController.add(local);
      }

      _lastReportSubmissionTime = DateTime.now();

      // 3. Sync with Cloud Firestore
      try {
        await FirebaseFirestore.instance
            .collection(_collectionName)
            .doc(id)
            .set(newIncident.toMap());
      } catch (firestoreError) {
        debugPrint('Firestore sync incident error: $firestoreError');
      }

      return {
        'success': true,
        'message': 'ส่งรายงานเหตุฉุกเฉินเรียบร้อยแล้ว',
      };
    } catch (e) {
      debugPrint('createIncident error: $e');
      return {
        'success': false,
        'message': 'เกิดข้อผิดพลาดในการส่งข้อมูล: $e',
      };
    }
  }

  /// Agency role: Sets ER preparation status (Hospital ER ready)
  Future<bool> setErPrepared(String id, bool isPrepared) async {
    try {
      final local = await getLocalIncidents();
      final idx = local.indexWhere((i) => i.id == id);
      if (idx != -1) {
        local[idx] = local[idx].copyWith(isErPrepared: isPrepared);
        await _saveToLocalCache(local);
        if (!_incidentsController.isClosed) {
          _incidentsController.add(local);
        }
      }

      try {
        await FirebaseFirestore.instance
            .collection(_collectionName)
            .doc(id)
            .update({'isErPrepared': isPrepared});
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('setErPrepared error: $e');
      return false;
    }
  }

  /// Ambulance role: Accept incident dispatch
  Future<bool> acceptIncidentByAmbulance({
    required String id,
    required String ambulancePlate,
    required String ambulanceId,
  }) async {
    try {
      final local = await getLocalIncidents();
      final idx = local.indexWhere((i) => i.id == id);
      if (idx != -1) {
        local[idx] = local[idx].copyWith(
          status: 'assigned',
          statusStep: 1, // กำลังเดินทางไปรับเคส
          assignedAmbulancePlate: ambulancePlate,
          assignedAmbulanceId: ambulanceId,
        );
        await _saveToLocalCache(local);
        if (!_incidentsController.isClosed) {
          _incidentsController.add(local);
        }
      }

      try {
        await FirebaseFirestore.instance
            .collection(_collectionName)
            .doc(id)
            .update({
          'status': 'assigned',
          'statusStep': 1,
          'assignedAmbulancePlate': ambulancePlate,
          'assignedAmbulanceId': ambulanceId,
        });
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('acceptIncidentByAmbulance error: $e');
      return false;
    }
  }

  /// Ambulance role: Progress through incident stages
  /// step 1: กำลังไปรับเคส, step 2: ถึงจุดเกิดเหตุ, step 3: กำลังไป รพ., step 4: ถึง รพ. (Resolved)
  Future<bool> updateIncidentProgressStep({
    required String id,
    required int step,
    required String status,
  }) async {
    try {
      final local = await getLocalIncidents();
      final idx = local.indexWhere((i) => i.id == id);
      if (idx != -1) {
        local[idx] = local[idx].copyWith(
          status: status,
          statusStep: step,
        );
        await _saveToLocalCache(local);
        if (!_incidentsController.isClosed) {
          _incidentsController.add(local);
        }
      }

      try {
        await FirebaseFirestore.instance
            .collection(_collectionName)
            .doc(id)
            .update({
          'status': status,
          'statusStep': step,
        });
      } catch (_) {}

      return true;
    } catch (e) {
      debugPrint('updateIncidentProgressStep error: $e');
      return false;
    }
  }

  /// Cancel an incident report (Only allowed if status is pending / statusStep == 0)
  Future<bool> cancelIncident(String incidentId, {String? reason}) async {
    try {
      final local = await getLocalIncidents();
      final index = local.indexWhere((i) => i.id == incidentId);
      if (index != -1) {
        final existing = local[index];
        if (!existing.canBeCancelled) {
          debugPrint('Cannot cancel: Incident is already assigned/in progress');
          return false;
        }

        final updated = existing.copyWith(
          status: 'cancelled',
          description: reason != null && reason.isNotEmpty
              ? '${existing.description} (ยกเลิกโดยผู้แจ้ง: $reason)'
              : '${existing.description} (ยกเลิกการแจ้งเหตุ)',
        );
        local[index] = updated;
        await _saveToLocalCache(local);
        if (!_incidentsController.isClosed) {
          _incidentsController.add(local);
        }
      }

      // Sync Firestore
      try {
        await FirebaseFirestore.instance
            .collection(_collectionName)
            .doc(incidentId)
            .update({
          'status': 'cancelled',
          if (reason != null) 'cancelReason': reason,
          'cancelledAt': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('Firestore cancel error: $e');
      }

      return true;
    } catch (e) {
      debugPrint('cancelIncident error: $e');
      return false;
    }
  }

  /// Get incidents from local cache
  Future<List<IncidentReport>> getLocalIncidents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_localKey);
      if (jsonStr == null || jsonStr.isEmpty) {
        return _getDefaultInitialCases();
      }

      final List<dynamic> raw = json.decode(jsonStr);
      final list = raw.map((e) => IncidentReport.fromMap(e)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      return _getDefaultInitialCases();
    }
  }

  Future<void> _saveToLocalCache(List<IncidentReport> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = list.map((e) => e.toMap()).toList();
      await prefs.setString(_localKey, json.encode(raw));
    } catch (_) {}
  }

  List<IncidentReport> _getDefaultInitialCases() {
    final now = DateTime.now();
    return [
      IncidentReport(
        id: 'Case #AVCB00021',
        type: 'อุบัติเหตุทางรถยนต์',
        severity: 'วิกฤต (Code Red - หมดสติ / บาดเจ็บสาหัส)',
        description: 'รถยนต์เฉี่ยวชนกับรถจักรยานยนต์ มีผู้ได้รับบาดเจ็บ 2 ราย',
        latitude: 19.0400,
        longitude: 99.8962,
        province: 'เชียงใหม่',
        address: 'อ.ฝาง จ.เชียงใหม่ บริเวณหน้าตลาดสด',
        reporterName: 'พลเมืองดี',
        reporterEmail: 'citizen@gmail.com',
        reporterPhone: '0812345678',
        status: 'pending',
        statusStep: 0,
        isErPrepared: false,
        eta: '4 นาที',
        assignedAmbulancePlate: 'กขค123',
        createdAt: now.subtract(const Duration(minutes: 15)),
      ),
      IncidentReport(
        id: 'Case #SIXSEVEN67',
        type: 'การจราจรติดขัดรุนแรง',
        severity: 'ปานกลาง (Medium - บาดเจ็บแต่รู้สึกตัว)',
        description: 'ต้นไม้ล้มกีดขวางช่องทางจราจร การจราจรเคลื่อนตัวช้า',
        latitude: 19.0320,
        longitude: 99.8850,
        province: 'เชียงใหม่',
        address: 'อ.เมือง จ.เชียงใหม่ ถ.สุเทพ',
        reporterName: 'ผู้ใช้ทางหลวง',
        reporterEmail: 'driver@gmail.com',
        status: 'in_progress',
        statusStep: 1,
        isErPrepared: true,
        eta: '8 นาที',
        assignedAmbulancePlate: 'ขก4567',
        createdAt: now.subtract(const Duration(hours: 1, minutes: 20)),
      ),
    ];
  }

  void dispose() {
    _firestoreSubscription?.cancel();
    _incidentsController.close();
  }
}
