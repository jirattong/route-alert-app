import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/incident_report.dart';
import 'push_trigger.dart';

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
  static const String _locksCollection = 'ambulance_locks';

  /// rules ของเซิร์ฟเวอร์ยังไม่อนุญาต ambulance_locks — ข้ามล็อกไปตลอด session นี้
  bool _locksUnavailable = false;
  static const String _localKey = 'local_incident_reports_v2';

  /// ใช้ใน test เท่านั้น: ใส่ Firestore จำลองแทนของจริง แอปไม่เคยตั้งค่านี้
  /// จึงยังใช้ FirebaseFirestore.instance เหมือนเดิมทุกครั้ง
  @visibleForTesting
  static FirebaseFirestore? firestoreOverride;

  FirebaseFirestore get _db => firestoreOverride ?? FirebaseFirestore.instance;

  final StreamController<List<IncidentReport>> _incidentsController =
      StreamController<List<IncidentReport>>.broadcast();

  Stream<List<IncidentReport>> get incidentsStream =>
      _incidentsController.stream;

  StreamSubscription? _firestoreSubscription;

  /// Initialize real-time listening
  Future<void> initialize() async {
    _initFirestoreListener();
  }

  /// เริ่มฟัง Firestore เฉพาะถ้ายังไม่ได้ฟัง — initialize() เดิมยกเลิกแล้วเริ่มใหม่
  /// ทุกครั้ง ส่วนที่ทำงานเบื้องหลัง (เช่นตัวแจ้งเตือนสำรอง) ใช้อันนี้แทน
  Future<void> ensureInitialized() async {
    if (_firestoreSubscription == null) _initFirestoreListener();
  }

  /// หาเคสจาก id — ใช้ cache ในเครื่องก่อน ถ้าไม่เจอ (หรือ [forceRemote]) อ่านจาก
  /// Firestore ตรง เช่นตอนกดแจ้งเตือนเปิดแอปจากสถานะปิดสนิทที่ cache ยังไม่มีเคสนี้
  Future<IncidentReport?> getIncidentById(String id,
      {bool forceRemote = false}) async {
    final local = await getLocalIncidents();
    final cached = local.where((i) => i.id == id).firstOrNull;
    if (cached != null && !forceRemote) return cached;
    try {
      final snap = await _db
          .collection(_collectionName)
          .doc(id)
          .get()
          .timeout(const Duration(seconds: 5));
      final data = snap.data();
      if (data == null) return null;
      return IncidentReport.fromMap({...data, 'id': data['id'] ?? snap.id});
    } catch (e) {
      debugPrint('getIncidentById error: $e');
      return cached;
    }
  }

  /// Ambulance role: ส่ง ETA/ระยะที่เหลือตามถนนขึ้น Firestore ให้ผู้แจ้งเหตุเห็นบน
  /// หน้าล็อก/Dynamic Island — เขียนเฉพาะ Firestore ไม่แตะ cache/stream ในเครื่อง
  /// (หน้ารถพยาบาลฟัง stream แล้วคำนวณเส้นทางใหม่ ถ้าแตะจะวนไม่จบ)
  Future<void> updateAmbulanceEta(
    String id, {
    required int etaMinutes,
    required int distanceMeters,
    required String target,
    String? unitId,
    String? callSign,
  }) async {
    try {
      await _db.collection(_collectionName).doc(id).update({
        'ambulanceEtaMinutes': etaMinutes,
        'ambulanceDistanceMeters': distanceMeters,
        'ambulanceEtaTarget': target,
        'ambulanceEtaUpdatedAt': DateTime.now().toUtc().toIso8601String(),
        if (unitId != null) 'ambulanceEtaUnitId': unitId,
        if (callSign != null) 'ambulanceEtaCallSign': callSign,
      });
    } catch (e) {
      debugPrint('updateAmbulanceEta error: $e');
    }
  }

  /// หน่วยรถนี้มีเคสที่ยังไม่จบค้างอยู่บนเซิร์ฟเวอร์ไหม (null = เช็คไม่ได้)
  Future<bool?> unitHasOpenCase(String unitId) async {
    if (unitId.isEmpty) return false;
    try {
      final coll = _db.collection(_collectionName);
      final results = await Future.wait([
        coll.where('assignedUnitIds', arrayContains: unitId).get(),
        coll.where('assignedAmbulanceId', isEqualTo: unitId).get(), // เคสก่อนรองรับหลายคัน
      ]).timeout(const Duration(seconds: 4));
      return results.expand((s) => s.docs).any((d) {
        final status = d.data()['status'];
        return status != 'resolved' && status != 'cancelled' && d.data()['archived'] != true;
      });
    } catch (_) {
      return null;
    }
  }

  /// Ambulance role: เข้าใกล้จุดเกิดเหตุไม่ถึง 500 ม. — บันทึกครั้งเดียวต่อเคส
  /// เพื่อให้ตัวส่งแจ้งเตือนบอกผู้แจ้งเหตุว่ารถใกล้ถึงแล้ว
  Future<bool> markAmbulanceNearScene(String id, {int? etaMinutes, String? callSign}) async {
    final now = DateTime.now();
    final eta = etaMinutes == null ? null : (etaMinutes < 1 ? 1 : etaMinutes);
    final local = await getLocalIncidents();
    final idx = local.indexWhere((i) => i.id == id);
    if (idx != -1) {
      if (local[idx].ambulanceNearSceneAt != null) return true;
      local[idx] = local[idx].copyWith(
        ambulanceNearSceneAt: now,
        ambulanceNearEtaMinutes: eta,
        ambulanceNearCallSign: callSign,
      );
      await _saveToLocalCache(local);
      if (!_incidentsController.isClosed) _incidentsController.add(local);
    }
    try {
      await _db.collection(_collectionName).doc(id).update({
        'ambulanceNearSceneAt': now.toIso8601String(),
        'ambulanceNearEtaMinutes': eta,
        if (callSign != null) 'ambulanceNearCallSign': callSign,
      });
      notifyIncidentChanged(id);
      return true;
    } catch (e) {
      debugPrint('markAmbulanceNearScene Firestore error: $e');
      return false;
    }
  }

  void _initFirestoreListener() {
    try {
      _firestoreSubscription?.cancel();
      _firestoreSubscription = _db
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

  /// ใช้ใน test เท่านั้น: เริ่มเหมือนเครื่องที่ยังไม่เคยแจ้ง (ไม่มี cooldown ค้าง)
  @visibleForTesting
  void debugResetCooldown() {
    _lastReportSubmissionTime = null;
    _activeCooldownDuration = _defaultCooldown;
  }

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
        await _db
            .collection(_collectionName)
            .doc(id)
            .set(newIncident.toMap());
        notifyIncidentChanged(id);
      } catch (firestoreError) {
        debugPrint('Firestore sync incident error: $firestoreError');
        firestoreSynced = false;
        // ส่งไม่ถึงศูนย์ = ยังไม่นับเป็นการแจ้ง — เดิม cooldown 2 นาทีเริ่มนับไปแล้ว ผู้แจ้งกดส่งใหม่
        // ไม่ได้ทั้งที่ข้อความบอกให้ลองส่งใหม่ (เจอจากสถานการณ์ทดสอบ S04)
        _lastReportSubmissionTime = null;
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
      final original = idx != -1 ? local[idx] : null;
      if (idx != -1) {
        local[idx] = local[idx].copyWith(isErPrepared: isPrepared);
        await _saveToLocalCache(local);
        if (!_incidentsController.isClosed) {
          _incidentsController.add(local);
        }
      }

      try {
        await _db
            .collection(_collectionName)
            .doc(id)
            .update({'isErPrepared': isPrepared});
        return true;
      } catch (e) {
        debugPrint('setErPrepared Firestore error: $e');
        // เขียน Firestore ไม่สำเร็จ ต้อง revert local cache/stream ที่อัปเดต
        // แบบ optimistic ไปแล้วกลับคืน ไม่งั้นฝั่งที่ดู stream นี้อยู่ (เช่นเว็บ
        // Agency dashboard) จะเห็นค่าที่ "ดูเหมือนสำเร็จ" ค้างอยู่ตลอดไปทั้งที่
        // เซิร์ฟเวอร์จริงไม่ได้เปลี่ยนอะไรเลย (เจอจาก code review)
        if (idx != -1 && original != null) {
          local[idx] = original;
          await _saveToLocalCache(local);
          if (!_incidentsController.isClosed) {
            _incidentsController.add(local);
          }
        }
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
      final original = idx != -1 ? local[idx] : null;
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
        await _db
            .collection(_collectionName)
            .doc(id)
            .update({'scenePhotosBase64': updatedPhotos});
        return true;
      } catch (e) {
        debugPrint('addScenePhoto Firestore error: $e');
        // เขียน Firestore ไม่สำเร็จ ต้อง revert local cache/stream ที่อัปเดต
        // แบบ optimistic ไปแล้วกลับคืน (รูปแบบเดียวกับ setErPrepared/
        // dispatchIncidentByHospital ด้านบน — เจอจาก code review) ไม่งั้นรูป
        // ที่เพิ่งถ่ายจะดูเหมือนถูกแนบเข้าเคสสำเร็จแล้วทั้งที่เซิร์ฟเวอร์จริง
        // ไม่มีรูปนี้อยู่เลย
        if (idx != -1 && original != null) {
          local[idx] = original;
          await _saveToLocalCache(local);
          if (!_incidentsController.isClosed) {
            _incidentsController.add(local);
          }
        }
        return false;
      }
    } catch (e) {
      debugPrint('addScenePhoto error: $e');
      return false;
    }
  }

  /// Hospital role: Confirm incident and dispatch ambulance — คืน true/false แบบเดิม
  /// (รายละเอียดว่าทำไมไม่สำเร็จ ใช้ [assignAmbulance])
  Future<bool> dispatchIncidentByHospital({
    required String id,
    required String ambulanceId,
    required String ambulancePlate,
    String? ambulanceCallSign,
    String? callingHospitalId,
    bool selfAccepted = false,
    bool onlyIfUnassigned = false,
  }) async {
    final r = await assignAmbulance(
      id: id,
      ambulanceId: ambulanceId,
      ambulancePlate: ambulancePlate,
      ambulanceCallSign: ambulanceCallSign,
      callingHospitalId: callingHospitalId,
      selfAccepted: selfAccepted,
      onlyIfUnassigned: onlyIfUnassigned,
    );
    return r.ok;
  }

  /// เพิ่มรถ 1 หน่วยเข้าเคส (รพ. สั่งจ่าย หรือรถกดรับ/ร่วมรับเอง) — เคสเดียวรับได้หลายคัน
  ///
  /// ทำใน transaction เดียว อ่านทั้งเอกสารเคสและ "ล็อกของรถ" (ambulance_locks/{ทะเบียน}):
  /// - รถคันเดิมกดซ้ำ → สำเร็จโดยไม่เขียนซ้ำ
  /// - เคสปิดแล้ว / เริ่มนำส่งแล้ว → ไม่รับเพิ่ม
  /// - [onlyIfUnassigned] (รพ. กด "ส่งรถพยาบาล" ครั้งแรก) → ถ้ามีรถรับไปก่อนแล้ว ไม่ส่งซ้อนโดยไม่ตั้งใจ
  /// - รถคันนี้ยังถือเคสอื่นที่ยังไม่จบ → ปฏิเสธ (เดิมล็อกแค่เอกสารเคส รพ. สองแห่งส่งรถ
  ///   คันเดียวกันไปคนละเคสพร้อมกันได้ — เจอจากการทดสอบหลายผู้ใช้)
  ///   ล็อกที่ชี้ไปเคสที่จบ/ถูกปิดไปแล้ว ถือว่าว่าง ไม่ต้องมีใครคอยปลดล็อก
  ///
  /// [callingHospitalId] ใช้แค่ log ถ้าไม่ตรงกับ targetHospitalId ของเคส (ไม่บล็อก — ไม่มี
  /// Firebase Auth ให้บังคับสิทธิ์ และบางครั้งโรงพยาบาลอื่นก็ต้องรับแทนได้) ฟิลด์โรงพยาบาล
  /// ปลายทางที่ตั้งไว้ตอนสร้างเคสไม่ถูกแตะเลย
  Future<DispatchResult> assignAmbulance({
    required String id,
    required String ambulanceId,
    required String ambulancePlate,
    String? ambulanceCallSign,
    String? callingHospitalId,
    bool selfAccepted = false,
    bool onlyIfUnassigned = false,
  }) async {
    final local = await getLocalIncidents();
    final original = local.where((i) => i.id == id).firstOrNull;
    if (original != null &&
        callingHospitalId != null &&
        original.targetHospitalId != null &&
        original.targetHospitalId != callingHospitalId) {
      debugPrint(
          'dispatchIncidentByHospital: เคส $id ถูกระบบเลือกไว้ให้ ${original.targetHospitalId} '
          'แต่ $callingHospitalId เป็นคนมอบหมายรถพยาบาลแทน (ไม่บล็อก แค่แจ้งเตือน)');
    }

    final by = selfAccepted ? 'ambulance' : 'hospital';
    final unit = AssignedUnit(
      unitId: ambulanceId,
      plate: ambulancePlate,
      callSign: ambulanceCallSign ?? 'กู้ชีพ $ambulancePlate',
      assignedBy: by,
      joinedAt: DateTime.now(),
    );
    final ref = _db.collection(_collectionName).doc(id);

    Future<DispatchResult> attempt({required bool useLock}) {
      return _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data();
        if (data == null) return const DispatchResult(DispatchOutcome.notFound);
        final current = IncidentReport.fromMap({...data, 'id': data['id'] ?? snap.id});
        if (current.units.any((u) => u.unitId == ambulanceId)) {
          return DispatchResult(DispatchOutcome.alreadyMine, incident: current);
        }
        if (current.isClosed || current.archived) {
          return DispatchResult(DispatchOutcome.caseClosed, incident: current);
        }
        if (onlyIfUnassigned && current.units.isNotEmpty) {
          return DispatchResult(DispatchOutcome.alreadyHasVehicles, incident: current);
        }
        if (!current.isJoinable) {
          return DispatchResult(DispatchOutcome.notJoinable, incident: current);
        }

        final lockRef = _db.collection(_locksCollection).doc(unit.vehicleKey);
        if (useLock) {
          final lock = (await tx.get(lockRef)).data();
          final otherId = (lock?['openCaseId'] ?? '').toString();
          if (otherId.isNotEmpty && otherId != id) {
            final otherSnap = await tx.get(_db.collection(_collectionName).doc(otherId));
            final od = otherSnap.data();
            if (od != null) {
              final other = IncidentReport.fromMap({...od, 'id': od['id'] ?? otherId});
              if (!other.isClosed &&
                  !other.archived &&
                  other.units.any((u) => u.vehicleKey == unit.vehicleKey)) {
                return DispatchResult(DispatchOutcome.vehicleBusy,
                    incident: current, busyCaseId: otherId);
              }
            }
          }
        }

        final first = current.units.isEmpty;
        final units = [...current.units, unit];
        final changes = <String, dynamic>{
          ...AssignedUnit.fieldsFor(units),
          // คันแรกเป็น "คันหลัก" — ฟิลด์เดิมที่ตัวส่ง push/เว็บ/เคสเก่าใช้อยู่
          if (first) ...{
            'assignedAmbulanceId': ambulanceId,
            'assignedAmbulancePlate': ambulancePlate,
            'assignedAmbulanceCallSign': unit.callSign,
            // ตัวส่ง push ใช้แยกว่าไม่ต้องแจ้งเตือนรถพยาบาลที่กดรับเคสเอง
            'assignedBy': by,
          },
          if (current.status == 'pending') ...{'status': 'assigned', 'statusStep': 1},
        };
        tx.update(ref, changes);
        if (useLock) {
          tx.set(lockRef, {
            'vehicleKey': unit.vehicleKey,
            'plate': ambulancePlate,
            'unitId': ambulanceId,
            'openCaseId': id,
            'updatedAt': DateTime.now().toIso8601String(),
          });
        }
        return DispatchResult(
          first ? DispatchOutcome.assigned : DispatchOutcome.joined,
          incident: IncidentReport.fromMap({...data, ...changes, 'id': current.id}),
        );
      }, timeout: const Duration(seconds: 15));
    }

    try {
      DispatchResult result;
      try {
        result = await attempt(useLock: !_locksUnavailable);
      } on FirebaseException catch (e) {
        // rules บนเซิร์ฟเวอร์ยังไม่เปิด collection ambulance_locks (ยังไม่ได้ deploy rules ใหม่)
        // — ทำงานต่อแบบไม่มีล็อก ดีกว่ารับเคสไม่ได้เลย
        if (e.code != 'permission-denied' || _locksUnavailable) rethrow;
        _locksUnavailable = true;
        debugPrint('ambulance_locks ถูก rules ปฏิเสธ — deploy firestore.rules ใหม่เพื่อกันรถรับสองเคส');
        result = await attempt(useLock: false);
      }
      if (result.incident != null &&
          (result.outcome == DispatchOutcome.assigned || result.outcome == DispatchOutcome.joined)) {
        await _replaceLocalIncident(id, result.incident);
        notifyIncidentChanged(id);
      } else if (result.incident != null) {
        await _replaceLocalIncident(id, result.incident);
      }
      return result;
    } catch (e) {
      debugPrint('dispatchIncidentByHospital Firestore error: $e');
      // อ่านสถานะจริงจากเซิร์ฟเวอร์แล้วแก้เฉพาะเคสนี้ใน cache
      IncidentReport? server;
      try {
        final snap = await ref
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 5));
        final data = snap.data();
        if (data != null) {
          server = IncidentReport.fromMap({...data, 'id': data['id'] ?? snap.id});
        }
      } catch (_) {}
      await _replaceLocalIncident(id, server ?? original);
      // timeout ฝั่งแอปแต่ commit บนเซิร์ฟเวอร์ไปแล้ว — ถือว่าสำเร็จ
      if (server != null && server.units.any((u) => u.unitId == ambulanceId)) {
        notifyIncidentChanged(id);
        return DispatchResult(DispatchOutcome.alreadyMine, incident: server);
      }
      return DispatchResult(DispatchOutcome.failed, incident: server);
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

  Future<void> _replaceLocalIncident(String id, IncidentReport? incident) async {
    if (incident == null) return;
    final fresh = await getLocalIncidents();
    final idx = fresh.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    fresh[idx] = incident;
    await _saveToLocalCache(fresh);
    if (!_incidentsController.isClosed) _incidentsController.add(fresh);
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
      selfAccepted: true,
    );
  }

  /// Ambulance role: Progress through incident stages
  /// step 1: กำลังไปรับเคส, step 2: ถึงจุดเกิดเหตุ, step 3: กำลังไป รพ., step 4: ใกล้ถึง รพ., step 5: ถึง รพ.
  /// [step] ที่ส่งมาไม่ได้ใช้แล้ว — ขั้นคำนวณจาก [status] เสมอ (เดิมหน้ารายละเอียดเขียน
  /// resolved เป็นขั้น 4 แต่หน้าหลักเขียนขั้น 5)
  Future<bool> updateIncidentProgressStep({
    required String id,
    int? step,
    required String status,
  }) async {
    final r = await advanceIncidentStatus(id: id, status: status);
    return r == ProgressOutcome.updated || r == ProgressOutcome.alreadyPast;
  }

  static const Map<String, int> statusRank = {
    'pending': 0,
    'assigned': 1,
    'at_scene': 2,
    'transporting': 3,
    'approaching_er': 4,
    'resolved': 5,
  };

  /// เลื่อนสถานะเคสไปข้างหน้าเท่านั้น ใน transaction:
  /// - เคสถูกปิด/จบไปแล้ว → ไม่เขียน (เดิมเขียนทับตรงๆ ถ้ารถกดเลื่อนสถานะในจังหวะที่
  ///   โรงพยาบาลปิดเคส เคสจะถูกเปิดกลับมา — เจอจากการทดสอบหลายผู้ใช้)
  /// - รถอีกคันในเคสเดียวกันเลื่อนไปถึงขั้นนี้หรือไกลกว่าแล้ว → ถือว่าสำเร็จ ไม่ถอยสถานะกลับ
  Future<ProgressOutcome> advanceIncidentStatus({
    required String id,
    required String status,
  }) async {
    final rank = statusRank[status];
    if (rank == null) return ProgressOutcome.failed;
    final ref = _db.collection(_collectionName).doc(id);
    try {
      IncidentReport? after;
      final outcome = await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data();
        if (data == null) return ProgressOutcome.notFound;
        final current = IncidentReport.fromMap({...data, 'id': data['id'] ?? snap.id});
        after = current;
        if (current.isClosed) return ProgressOutcome.caseClosed;
        final currentRank = statusRank[current.status] ?? current.statusStep;
        if (rank <= currentRank) return ProgressOutcome.alreadyPast;
        tx.update(ref, {'status': status, 'statusStep': rank});
        after = current.copyWith(status: status, statusStep: rank);
        return ProgressOutcome.updated;
      }, timeout: const Duration(seconds: 15));
      await _replaceLocalIncident(id, after);
      if (outcome == ProgressOutcome.updated && status == 'resolved') notifyIncidentChanged(id);
      return outcome;
    } catch (e) {
      debugPrint('updateIncidentProgressStep Firestore error: $e');
      return ProgressOutcome.failed;
    }
  }

  /// Cancel an incident report (Only allowed if status is pending / statusStep == 0)
  /// Hospital role: ปิดเคส (เช่นแจ้งซ้ำ/แจ้งผิด) — ต่างจากผู้แจ้งยกเลิกตรงที่ทำได้ทุกสถานะ
  /// และทุกฝั่งจะไม่เห็นเคสนี้ในรายการอีก (ผู้แจ้งยังเห็นในประวัติว่าถูกยกเลิก)
  Future<bool> closeIncidentByHospital(String incidentId, {String? reason}) async {
    final local = await getLocalIncidents();
    final index = local.indexWhere((i) => i.id == incidentId);
    final original = index != -1 ? local[index] : null;
    if (original != null) {
      local[index] = original.copyWith(status: 'cancelled');
      await _saveToLocalCache(local);
      if (!_incidentsController.isClosed) _incidentsController.add(local);
    }
    try {
      await _db.collection(_collectionName).doc(incidentId).update({
        'status': 'cancelled',
        'cancelledBy': 'hospital',
        if (reason != null && reason.isNotEmpty) 'cancelReason': reason,
        'cancelledAt': DateTime.now().toIso8601String(),
      });
      notifyIncidentChanged(incidentId);
      return true;
    } catch (e) {
      debugPrint('closeIncidentByHospital error: $e');
      await _replaceLocalIncident(incidentId, original);
      return false;
    }
  }

  /// ผู้แจ้งยกเลิกเคส — ทำได้เฉพาะตอนที่เซิร์ฟเวอร์ยังเป็น pending และยังไม่มีรถรับ
  /// เดิมเช็คจาก cache ในเครื่องอย่างเดียวแล้วเขียนทับตรงๆ ถ้ารถกดรับในจังหวะเดียวกัน เคสจะถูก
  /// ยกเลิกทั้งที่มีรถกำลังไป และถ้าเน็ตหลุดก็ยังตอบว่ายกเลิกสำเร็จ (เจอจากสถานการณ์ทดสอบ S18)
  Future<bool> cancelIncident(String incidentId, {String? reason}) async {
    final ref = _db.collection(_collectionName).doc(incidentId);
    try {
      IncidentReport? after;
      final cancelled = await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data();
        if (data == null) return false;
        final current = IncidentReport.fromMap({...data, 'id': data['id'] ?? snap.id});
        after = current;
        if (!current.canBeCancelled || current.units.isNotEmpty) return false;
        final description = reason != null && reason.isNotEmpty
            ? '${current.description} (ยกเลิกโดยผู้แจ้ง: $reason)'
            : '${current.description} (ยกเลิกการแจ้งเหตุ)';
        tx.update(ref, {
          'status': 'cancelled',
          'description': description,
          'cancelledBy': 'reporter',
          if (reason != null) 'cancelReason': reason,
          'cancelledAt': DateTime.now().toIso8601String(),
        });
        after = current.copyWith(status: 'cancelled', description: description);
        return true;
      }, timeout: const Duration(seconds: 15));
      await _replaceLocalIncident(incidentId, after);
      if (!cancelled) return false;

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
        .where((i) => !i.isClosed)
        .expand((i) => i.units.map((u) => u.unitId))
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  /// เหมือน [getBusyAmbulanceIds] แต่นับเป็น "รถ" (ทะเบียน) — อีกบัญชีบนรถคันเดียวกันก็ไม่ว่าง
  Future<Set<String>> getBusyVehicleKeys() async {
    final list = await getLocalIncidents();
    return list.where((i) => !i.isClosed).expand((i) => i.units.map((u) => u.vehicleKey)).toSet();
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

enum DispatchOutcome {
  assigned, // รถคันแรกของเคส
  joined, // รถคันที่ 2, 3, … เข้าร่วม
  alreadyMine, // หน่วยนี้อยู่ในเคสแล้ว (กดซ้ำ)
  alreadyHasVehicles, // onlyIfUnassigned แต่มีรถรับไปก่อนแล้ว
  caseClosed,
  notJoinable, // เริ่มนำส่งแล้ว ไม่รับรถเพิ่ม
  vehicleBusy, // รถคันนี้ยังถือเคสอื่นที่ยังไม่จบ
  notFound,
  failed, // เน็ต/เซิร์ฟเวอร์
}

class DispatchResult {
  const DispatchResult(this.outcome, {this.incident, this.busyCaseId});
  final DispatchOutcome outcome;
  final IncidentReport? incident; // สถานะเคสล่าสุดที่อ่านได้ (null ถ้าอ่านไม่ได้)
  final String? busyCaseId;

  bool get ok =>
      outcome == DispatchOutcome.assigned ||
      outcome == DispatchOutcome.joined ||
      outcome == DispatchOutcome.alreadyMine;
}

enum ProgressOutcome { updated, alreadyPast, caseClosed, notFound, failed }
