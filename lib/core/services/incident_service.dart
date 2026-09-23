import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/incident_report.dart';

/// เมื่อ true จะยัดเคสตัวอย่าง (demo) ลงใน getLocalIncidents() ตอนที่ cache ว่าง
/// เดิมค่านี้ถูกยัดแบบไม่มีเงื่อนไขเสมอ ทำให้เคสปลอมปนกับข้อมูลจริงในหน้าสถิติ/heatmap/
/// รายการเคส ตอนเพิ่งติดตั้งแอพใหม่หรือเน็ตหลุดชั่วคราว (ก่อน Firestore stream มาแทนที่)
/// ปิดไว้เป็นค่าเริ่มต้นสำหรับ production เปิดเฉพาะตอนต้องการ demo/พรีเซนต์เท่านั้น
const bool kSeedDemoIncidents = false;

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
  Duration _activeCooldownDuration = const Duration(minutes: 2);
  static const Duration _defaultCooldown = Duration(minutes: 2);
  static const Duration _cancelledQuickCooldown = Duration(seconds: 8); // สั้นลงเหลือ 8 วิ หากกดยกเลิกเหตุ

  /// Check remaining cooldown seconds (Anti-Spam)
  int get remainingCooldownSeconds {
    if (_lastReportSubmissionTime == null) return 0;
    final elapsed = DateTime.now().difference(_lastReportSubmissionTime!);
    final remaining = _activeCooldownDuration.inSeconds - elapsed.inSeconds;
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

      _activeCooldownDuration = _defaultCooldown;
      _lastReportSubmissionTime = DateTime.now();

      // 3. Sync with Cloud Firestore — เดิมสลับกินข้อผิดพลาดตรงนี้ทิ้งแล้วรายงาน
      // 'success': true เสมอ ทั้งที่ Firestore คือช่องทางเดียวที่ทำให้ฝั่งรถพยาบาล/
      // agency (คนละเครื่องกัน) เห็นเคสนี้ได้ — ถ้า sync ล้มเหลวจริง (เน็ตหลุด/
      // Firestore ล่ม) เคสจะค้างอยู่แค่ในเครื่องผู้แจ้งเท่านั้น ไม่มีใครรับรู้เลย แต่
      // ผู้แจ้งเห็นข้อความ "ส่งเรียบร้อยแล้ว" ทำให้เข้าใจผิดว่าปลอดภัยแล้ว
      bool firestoreSynced = true;
      try {
        await FirebaseFirestore.instance
            .collection(_collectionName)
            .doc(id)
            .set(newIncident.toMap());
      } catch (firestoreError) {
        debugPrint('Firestore sync incident error: $firestoreError');
        firestoreSynced = false;
      }

      return {
        'success': firestoreSynced,
        'message': firestoreSynced
            ? 'ส่งรายงานเหตุฉุกเฉินเรียบร้อยแล้ว'
            : '⚠️ บันทึกในเครื่องแล้ว แต่ส่งไปยังศูนย์ไม่สำเร็จ (เช็คสัญญาณอินเทอร์เน็ต) '
                'เคสนี้จะยังไม่ถูกส่งต่อจนกว่าจะลองส่งใหม่ หากเร่งด่วนกรุณาโทร 1669',
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
        return true;
      } catch (e) {
        debugPrint('setErPrepared Firestore error: $e');
        return false;
      }
    } catch (e) {
      debugPrint('setErPrepared error: $e');
      return false;
    }
  }

  /// Ambulance role: Appends a real scene photo (base64) taken by the crew on-site
  Future<bool> addScenePhoto(String id, String photoBase64) async {
    try {
      final local = await getLocalIncidents();
      final idx = local.indexWhere((i) => i.id == id);
      List<String> updatedPhotos = [photoBase64];
      if (idx != -1) {
        updatedPhotos = [...local[idx].scenePhotosBase64, photoBase64];
        local[idx] = local[idx].copyWith(scenePhotosBase64: updatedPhotos);
        await _saveToLocalCache(local);
        if (!_incidentsController.isClosed) {
          _incidentsController.add(local);
        }
      }

      try {
        await FirebaseFirestore.instance
            .collection(_collectionName)
            .doc(id)
            .update({'scenePhotosBase64': updatedPhotos});
        return true;
      } catch (e) {
        debugPrint('addScenePhoto Firestore error: $e');
        return false;
      }
    } catch (e) {
      debugPrint('addScenePhoto error: $e');
      return false;
    }
  }

  /// Hospital role: Confirm incident and dispatch ambulance with pinned hospital location
  Future<bool> dispatchIncidentByHospital({
    required String id,
    required String ambulanceId,
    required String ambulancePlate,
    String? ambulanceCallSign,
    String? hospitalName,
    double? hospitalLatitude,
    double? hospitalLongitude,
  }) async {
    try {
      final local = await getLocalIncidents();
      final idx = local.indexWhere((i) => i.id == id);
      if (idx != -1) {
        local[idx] = local[idx].copyWith(
          status: 'assigned',
          statusStep: 1, // 1: กำลังเดินทางไปรับเคส
          assignedAmbulanceId: ambulanceId,
          assignedAmbulancePlate: ambulancePlate,
          assignedAmbulanceCallSign: ambulanceCallSign ?? 'กู้ชีพ $ambulancePlate',
          hospitalName: hospitalName,
          hospitalLatitude: hospitalLatitude,
          hospitalLongitude: hospitalLongitude,
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
          'assignedAmbulanceId': ambulanceId,
          'assignedAmbulancePlate': ambulancePlate,
          'assignedAmbulanceCallSign': ambulanceCallSign ?? 'กู้ชีพ $ambulancePlate',
          if (hospitalName != null) 'hospitalName': hospitalName,
          if (hospitalLatitude != null) 'hospitalLatitude': hospitalLatitude,
          if (hospitalLongitude != null) 'hospitalLongitude': hospitalLongitude,
        });
        return true;
      } catch (e) {
        debugPrint('dispatchIncidentByHospital Firestore error: $e');
        return false;
      }
    } catch (e) {
      debugPrint('dispatchIncidentByHospital error: $e');
      return false;
    }
  }

  /// Ambulance role: Arrived at incident scene (Step 2)
  Future<bool> reportAmbulanceAtScene(String id) async {
    return updateIncidentProgressStep(
      id: id,
      step: 2,
      status: 'at_scene',
    );
  }

  /// Ambulance role: Transporting patient to hospital (Step 3)
  Future<bool> reportAmbulanceTransporting(String id) async {
    return updateIncidentProgressStep(
      id: id,
      step: 3,
      status: 'transporting',
    );
  }

  /// Ambulance role: Approaching hospital ER (Step 4 - < 1.5 km alert)
  Future<bool> reportAmbulanceApproachingHospital(String id) async {
    return updateIncidentProgressStep(
      id: id,
      step: 4,
      status: 'approaching_er',
    );
  }

  /// Ambulance role: Submit Medical Tele-Report (Vital Signs & Condition)
  /// Ambulance / Hospital role: Mission completed (Step 5 - Resolved)
  Future<bool> resolveIncident(String id) async {
    return updateIncidentProgressStep(
      id: id,
      step: 5,
      status: 'resolved',
    );
  }

  /// Ambulance role: Accept incident dispatch (compatible helper)
  Future<bool> acceptIncidentByAmbulance({
    required String id,
    required String ambulancePlate,
    required String ambulanceId,
  }) async {
    return dispatchIncidentByHospital(
      id: id,
      ambulanceId: ambulanceId,
      ambulancePlate: ambulancePlate,
    );
  }

  /// Ambulance role: Progress through incident stages
  /// step 1: กำลังไปรับเคส, step 2: ถึงจุดเกิดเหตุ, step 3: กำลังไป รพ., step 4: ใกล้ถึง รพ., step 5: ถึง รพ.
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
        return true;
      } catch (e) {
        debugPrint('updateIncidentProgressStep Firestore error: $e');
        return false;
      }
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

      // เมื่อผู้ใช้กดยกเลิกเหตุ ให้ลดเวลา Cooldown จาก 2 นาที เหลือเพียง 8 วินาที เพื่อให้สามารถกดแจ้งเหตุใหม่ที่ถูกต้องได้ทันที
      _activeCooldownDuration = _cancelledQuickCooldown;
      _lastReportSubmissionTime = DateTime.now();

      return true;
    } catch (e) {
      debugPrint('cancelIncident error: $e');
      return false;
    }
  }

  /// คืนชุด ID รถพยาบาลที่กำลังมีเคส active อยู่ (ยังไม่ resolved/cancelled) —
  /// ใช้กันไม่ให้รถพยาบาลคันเดียวรับ 2 เคสพร้อมกันได้ ทั้งฝั่ง agency (auto-dispatch)
  /// และฝั่งรถพยาบาลเอง (self-accept) เรียกจุดนี้จุดเดียว ไม่ต้องเปิด stream ใหม่
  /// เพราะ local cache นี้ sync ตาม Firestore อยู่แล้วทุกครั้งที่มีการเปลี่ยนแปลง
  Future<Set<String>> getBusyAmbulanceIds() async {
    final list = await getLocalIncidents();
    return list
        .where((i) => i.status != 'resolved' && i.status != 'cancelled')
        .map((i) => i.assignedAmbulanceId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  /// Get incidents from local cache
  Future<List<IncidentReport>> getLocalIncidents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_localKey);
      if (jsonStr == null || jsonStr.isEmpty) {
        return kSeedDemoIncidents ? _getDefaultInitialCases() : [];
      }

      final List<dynamic> raw = json.decode(jsonStr);
      final list = raw.map((e) => IncidentReport.fromMap(e)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      return kSeedDemoIncidents ? _getDefaultInitialCases() : [];
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
