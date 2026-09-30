import 'dart:convert';
import 'package:flutter/material.dart';

/// รถ/บัญชีรถพยาบาล 1 หน่วยที่รับเคส — เคสเดียวรับได้หลายคัน
/// นับจำนวนรถตาม "ทะเบียน" ([vehicleKey]) ไม่ใช่ตามบัญชี เพราะรถคันเดียวอาจมีเจ้าหน้าที่
/// หลายคนล็อกอินคนละบัญชี (หลาย unitId แต่ทะเบียนเดียวกัน = 1 คัน)
class AssignedUnit {
  final String unitId;
  final String plate;
  final String callSign;
  final String assignedBy; // 'hospital' | 'ambulance'
  final DateTime? joinedAt;

  const AssignedUnit({
    required this.unitId,
    required this.plate,
    required this.callSign,
    this.assignedBy = 'hospital',
    this.joinedAt,
  });

  static const String unsetPlate = 'ยังไม่ระบุทะเบียน';

  /// กุญแจของ "รถ 1 คัน": ทะเบียนที่ตัดช่องว่าง/ขีด/จุดออก (กข 1234 = กข-1234)
  /// ถ้ายังไม่ได้ตั้งทะเบียน ใช้รหัสหน่วยแทน (ไม่งั้นรถที่ยังไม่ตั้งทะเบียนทุกคันจะนับเป็นคันเดียว)
  static String vehicleKeyFor(String? plate, String unitId) {
    final p = (plate ?? '').toLowerCase().replaceAll(RegExp(r'[\s\-./_#]'), '');
    if (p.isEmpty || p == unsetPlate) return 'unit_$unitId';
    return 'plate_$p';
  }

  String get vehicleKey => vehicleKeyFor(plate, unitId);

  bool get hasPlate => vehicleKey.startsWith('plate_');

  /// ป้ายที่แสดงให้คนอ่าน: ทะเบียน ถ้าไม่มีใช้ชื่อเรียกขาน
  String get label => hasPlate ? plate : (callSign.isNotEmpty ? callSign : unitId);

  Map<String, dynamic> toMap() => {
        'unitId': unitId,
        'plate': plate,
        'callSign': callSign,
        'vehicleKey': vehicleKey,
        'assignedBy': assignedBy,
        'joinedAt': joinedAt?.toIso8601String(),
      };

  factory AssignedUnit.fromMap(Map<dynamic, dynamic> map) => AssignedUnit(
        unitId: (map['unitId'] ?? '').toString(),
        plate: (map['plate'] ?? '').toString(),
        callSign: (map['callSign'] ?? '').toString(),
        assignedBy: (map['assignedBy'] ?? 'hospital').toString(),
        joinedAt: map['joinedAt'] != null ? DateTime.tryParse(map['joinedAt'].toString()) : null,
      );

  /// ฟิลด์ในเอกสารเคสที่คำนวณจากรายชื่อหน่วย — เขียนพร้อมกันทุกครั้ง
  /// (assignedUnitIds ใช้ค้นแบบ array-contains, assignedVehicleCount ให้เว็บ/ตัวส่ง push อ่านง่าย)
  static Map<String, dynamic> fieldsFor(List<AssignedUnit> units) {
    final keys = <String>[];
    for (final u in units) {
      if (!keys.contains(u.vehicleKey)) keys.add(u.vehicleKey);
    }
    return {
      'assignedUnits': units.map((u) => u.toMap()).toList(),
      'assignedUnitIds': units.map((u) => u.unitId).toList(),
      'assignedVehicleKeys': keys,
      'assignedVehicleCount': keys.length,
    };
  }
}

class IncidentReport {
  final String id;
  final String type;
  final String severity;
  final String description;
  final double latitude;
  final double longitude;
  final String province;
  final String address;
  final String? photoBase64;
  final List<String> photosBase64;
  final List<String> scenePhotosBase64; // รูปที่ทีมรถพยาบาลถ่ายหน้างานจริง
  final String reporterName;
  final String reporterEmail;
  final String reporterPhone;
  final String status; // 'pending' | 'assigned' | 'at_scene' | 'transporting' | 'approaching_er' | 'resolved' | 'cancelled'
  final int statusStep; // 0: รอยืนยัน, 1: กำลังไปรับเคส, 2: ถึงจุดเกิดเหตุ, 3: กำลังไป รพ., 4: ใกล้ถึง รพ., 5: ถึง รพ. เรียบร้อย
  final bool isErPrepared; // โรงพยาบาลเตรียมห้องฉุกเฉินแล้วหรือไม่
  final String eta; // e.g. "4 นาที"
  final String? assignedAmbulanceId;
  final String? assignedAmbulancePlate;
  final String? assignedAmbulanceCallSign;
  // ทุกหน่วยที่รับเคสนี้ (คันแรก = assignedAmbulance* ด้านบน เก็บไว้ให้โค้ด/ข้อมูลเก่าใช้ต่อได้)
  final List<AssignedUnit> assignedUnits;
  final String? targetHospitalId; // ID ของ รพ. ที่ใกล้ที่สุดที่ได้รับเคส
  final String? hospitalName;
  final double? hospitalLatitude;
  final double? hospitalLongitude;
  final double? hospitalDistanceKm; // ระยะทางจากจุดเกิดเหตุถึง รพ. (กม.)
  // 'hospital' | 'ambulance' — ใครเป็นคนมอบหมายรถ (รถกดรับเคสเองไม่ต้องแจ้งเตือนตัวเอง)
  final String? assignedBy;
  // เวลาที่รถพยาบาลเข้าใกล้จุดเกิดเหตุ (< 500 ม.) — ใช้แจ้งเตือนผู้แจ้งเหตุครั้งเดียว
  final DateTime? ambulanceNearSceneAt;
  final int? ambulanceNearEtaMinutes;
  final String? ambulanceNearCallSign; // คันที่เข้าใกล้จุดเกิดเหตุก่อน (มีหลายคัน)
  // ETA/ระยะตามถนนที่รถพยาบาลคำนวณเองแล้วส่งขึ้นมาเรื่อยๆ — ใช้แสดงบนหน้าล็อก/Dynamic Island
  // ของผู้แจ้งเหตุ target = 'scene' (กำลังไปจุดเกิดเหตุ) | 'hospital' (กำลังนำส่ง)
  final int? ambulanceEtaMinutes;
  final int? ambulanceDistanceMeters;
  final String? ambulanceEtaTarget;
  final DateTime? ambulanceEtaUpdatedAt;
  // คันที่ส่ง ETA ล่าสุด — มีหลายคันจะแสดง ETA ของคันที่ใกล้ที่สุด (ดู shouldPublishEta)
  final String? ambulanceEtaUnitId;
  final String? ambulanceEtaCallSign;
  final DateTime createdAt;
  // เก็บเข้าคลังแบบนุ่มนวล (soft-delete) จากเว็บ "Data" เครื่องมือแอดมิน —
  // ต่างจากการลบถาวรจริง (deleteDoc) ตรงที่ยังอยู่ครบใน Firestore กู้คืนได้
  // เสมอ แค่ซ่อนจาก heatmap/สถิติของฝั่ง agency เท่านั้น
  final bool archived;

  IncidentReport({
    required this.id,
    required this.type,
    required this.severity,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.province,
    required this.address,
    this.photoBase64,
    this.photosBase64 = const [],
    this.scenePhotosBase64 = const [],
    required this.reporterName,
    required this.reporterEmail,
    this.reporterPhone = '',
    this.status = 'pending',
    this.statusStep = 0,
    this.isErPrepared = false,
    this.eta = '5 นาที',
    this.assignedAmbulanceId,
    this.assignedAmbulancePlate,
    this.assignedAmbulanceCallSign,
    this.assignedUnits = const [],
    this.targetHospitalId,
    this.hospitalName,
    this.hospitalLatitude,
    this.hospitalLongitude,
    this.hospitalDistanceKm,
    this.assignedBy,
    this.ambulanceNearSceneAt,
    this.ambulanceNearEtaMinutes,
    this.ambulanceNearCallSign,
    this.ambulanceEtaMinutes,
    this.ambulanceDistanceMeters,
    this.ambulanceEtaTarget,
    this.ambulanceEtaUpdatedAt,
    this.ambulanceEtaUnitId,
    this.ambulanceEtaCallSign,
    required this.createdAt,
    this.archived = false,
  });

  bool get canBeCancelled => status == 'pending' && statusStep == 0;

  bool get isClosed => status == 'resolved' || status == 'cancelled';

  /// รถคันอื่นยังเข้าร่วมเคสได้: ยังไม่เริ่มนำส่ง (รอรับ/กำลังไป/ถึงจุดเกิดเหตุ)
  bool get isJoinable =>
      !archived && (status == 'pending' || status == 'assigned' || status == 'at_scene');

  /// ทุกหน่วยที่รับเคส — เคสเก่าก่อนรองรับหลายคันมีแค่ assignedAmbulanceId
  List<AssignedUnit> get units {
    if (assignedUnits.isNotEmpty) return assignedUnits;
    final id = assignedAmbulanceId ?? '';
    if (id.isEmpty) return const [];
    return [
      AssignedUnit(
        unitId: id,
        plate: assignedAmbulancePlate ?? '',
        callSign: assignedAmbulanceCallSign ?? '',
        assignedBy: assignedBy ?? 'hospital',
      ),
    ];
  }

  /// รถที่กำลังดำเนินเคส นับตามทะเบียน (1 ทะเบียน = 1 คัน ไม่ว่ามีกี่บัญชี)
  List<AssignedUnit> get vehicles {
    final seen = <String>{};
    return units.where((u) => seen.add(u.vehicleKey)).toList();
  }

  int get vehicleCount => vehicles.length;

  /// "กข 1234, ขค 5678"
  String get vehiclesLabel => vehicles.map((v) => v.label).join(', ');

  /// ชื่อรถที่ผู้แจ้งเห็น (หน้าติดตาม/หน้าล็อก/Dynamic Island): คันที่ส่ง ETA ล่าสุด
  /// (= คันที่ใกล้ที่สุด) หรือคันแรก ต่อท้ายจำนวนคันที่เหลือถ้ามีหลายคัน
  String get reporterUnitLabel {
    final main = [ambulanceEtaCallSign, assignedAmbulanceCallSign, assignedAmbulancePlate]
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => 'หน่วยกู้ชีพ')!;
    final n = vehicleCount;
    return n > 1 ? '$main (+${n - 1} คัน)' : main;
  }

  /// หน่วยนี้ (หรือรถคันเดียวกัน = ทะเบียนเดียวกันแต่คนละบัญชี) อยู่ในเคสนี้ไหม
  bool hasUnit(String? unitId, {String? plate}) {
    if (unitId == null || unitId.isEmpty) return false;
    final key = AssignedUnit.vehicleKeyFor(plate, unitId);
    return units.any((u) => u.unitId == unitId || u.vehicleKey == key);
  }

  /// หลายคันส่ง ETA เข้าเคสเดียวกัน — ผู้แจ้งควรเห็นคันที่ใกล้ที่สุด ไม่ใช่สลับไปมา
  /// เขียนทับได้เมื่อ: เป็นคันเดิม, ยังไม่มีใคร, ของเดิมเก่าเกิน 90 วิ (คันนั้นหยุดส่งแล้ว),
  /// เปลี่ยนช่วงทาง (ไปจุดเกิดเหตุ → ไป รพ.) หรือคันนี้ถึงเร็วกว่า/เท่ากัน
  bool shouldPublishEta({
    required String unitId,
    required int etaMinutes,
    required String target,
    required DateTime now,
  }) {
    final owner = ambulanceEtaUnitId ?? '';
    if (owner.isEmpty || owner == unitId) return true;
    final at = ambulanceEtaUpdatedAt;
    if (at == null || now.difference(at) > const Duration(seconds: 90)) return true;
    if (ambulanceEtaTarget != target) return true;
    return etaMinutes <= (ambulanceEtaMinutes ?? 1 << 30);
  }

  Color get statusColor {
    switch (status) {
      case 'cancelled':
        return const Color(0xFF94A3B8); // Slate Grey
      case 'resolved':
        return const Color(0xFF10B981); // Emerald
      case 'approaching_er':
        return const Color(0xFFDC2626); // Crimson Red (Critical Alert)
      case 'transporting':
      case 'at_scene':
      case 'in_progress':
        return const Color(0xFFF59E0B); // Amber
      case 'assigned':
        return const Color(0xFF5B9EE1); // Blue
      case 'pending':
      default:
        return const Color(0xFFEB5757); // Red
    }
  }

  String get statusText {
    switch (status) {
      case 'cancelled':
        return 'ยกเลิกการแจ้งเหตุ';
      case 'resolved':
        return 'ช่วยเหลือเสร็จสิ้น (ถึง รพ. แล้ว)';
      case 'approaching_er':
        return '🚨 รถพยาบาลใกล้ถึง รพ. ใน 3 นาที (เตรียม ER)';
      case 'transporting':
        return 'กำลังนำส่งผู้ป่วยกลับโรงพยาบาล';
      case 'at_scene':
        return 'รถพยาบาลถึงจุดเกิดเหตุแล้ว';
      case 'in_progress':
        return 'กำลังดำเนินการช่วยเหลือ';
      case 'assigned':
        return 'กำลังเดินทางไปยังที่เกิดเหตุ';
      case 'pending':
      default:
        return 'รอยืนยันจากโรงพยาบาล';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'severity': severity,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'province': province,
      'address': address,
      'photoBase64': photoBase64 ?? (photosBase64.isNotEmpty ? photosBase64.first : null),
      'photosBase64': photosBase64,
      'scenePhotosBase64': scenePhotosBase64,
      'reporterName': reporterName,
      'reporterEmail': reporterEmail,
      'reporterPhone': reporterPhone,
      'status': status,
      'statusStep': statusStep,
      'isErPrepared': isErPrepared,
      'eta': eta,
      'assignedAmbulanceId': assignedAmbulanceId,
      'assignedAmbulancePlate': assignedAmbulancePlate,
      'assignedAmbulanceCallSign': assignedAmbulanceCallSign,
      ...AssignedUnit.fieldsFor(assignedUnits),
      'targetHospitalId': targetHospitalId,
      'hospitalName': hospitalName,
      'hospitalLatitude': hospitalLatitude,
      'hospitalLongitude': hospitalLongitude,
      'hospitalDistanceKm': hospitalDistanceKm,
      'assignedBy': assignedBy,
      'ambulanceNearSceneAt': ambulanceNearSceneAt?.toIso8601String(),
      'ambulanceNearEtaMinutes': ambulanceNearEtaMinutes,
      'ambulanceNearCallSign': ambulanceNearCallSign,
      'ambulanceEtaMinutes': ambulanceEtaMinutes,
      'ambulanceDistanceMeters': ambulanceDistanceMeters,
      'ambulanceEtaTarget': ambulanceEtaTarget,
      'ambulanceEtaUpdatedAt': ambulanceEtaUpdatedAt?.toIso8601String(),
      'ambulanceEtaUnitId': ambulanceEtaUnitId,
      'ambulanceEtaCallSign': ambulanceEtaCallSign,
      'createdAt': createdAt.toIso8601String(),
      'archived': archived,
    };
  }

  factory IncidentReport.fromMap(Map<String, dynamic> map) {
    final rawPhotos = map['photosBase64'] as List<dynamic>?;
    final List<String> parsedPhotos = rawPhotos != null
        ? rawPhotos.map((e) => e.toString()).toList()
        : (map['photoBase64'] != null ? [map['photoBase64'].toString()] : const []);

    return IncidentReport(
      id: map['id'] ?? '',
      type: map['type'] ?? 'อุบัติเหตุทางรถยนต์',
      severity: map['severity'] ?? 'วิกฤต (Code Red)',
      description: map['description'] ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 19.0284,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 99.8962,
      province: map['province'] ?? 'เชียงใหม่',
      address: map['address'] ?? '',
      photoBase64: map['photoBase64'] ?? (parsedPhotos.isNotEmpty ? parsedPhotos.first : null),
      photosBase64: parsedPhotos,
      scenePhotosBase64: (map['scenePhotosBase64'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      reporterName: map['reporterName'] ?? 'ผู้ใช้งาน RouteAlert',
      reporterEmail: map['reporterEmail'] ?? '',
      reporterPhone: map['reporterPhone'] ?? '',
      status: map['status'] ?? 'pending',
      statusStep: (map['statusStep'] as num?)?.toInt() ?? 0,
      isErPrepared: map['isErPrepared'] == true,
      eta: map['eta'] ?? '5 นาที',
      assignedAmbulanceId: map['assignedAmbulanceId'],
      assignedAmbulancePlate: map['assignedAmbulancePlate'],
      assignedAmbulanceCallSign: map['assignedAmbulanceCallSign'],
      assignedUnits: (map['assignedUnits'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(AssignedUnit.fromMap)
              .where((u) => u.unitId.isNotEmpty)
              .toList() ??
          const [],
      targetHospitalId: map['targetHospitalId'],
      hospitalName: map['hospitalName'],
      hospitalLatitude: (map['hospitalLatitude'] as num?)?.toDouble(),
      hospitalLongitude: (map['hospitalLongitude'] as num?)?.toDouble(),
      hospitalDistanceKm: (map['hospitalDistanceKm'] as num?)?.toDouble(),
      assignedBy: map['assignedBy']?.toString(),
      ambulanceNearSceneAt: map['ambulanceNearSceneAt'] != null
          ? DateTime.tryParse(map['ambulanceNearSceneAt'].toString())
          : null,
      ambulanceNearEtaMinutes: (map['ambulanceNearEtaMinutes'] as num?)?.toInt(),
      ambulanceNearCallSign: map['ambulanceNearCallSign']?.toString(),
      ambulanceEtaMinutes: (map['ambulanceEtaMinutes'] as num?)?.toInt(),
      ambulanceDistanceMeters: (map['ambulanceDistanceMeters'] as num?)?.toInt(),
      ambulanceEtaTarget: map['ambulanceEtaTarget']?.toString(),
      ambulanceEtaUpdatedAt: map['ambulanceEtaUpdatedAt'] != null
          ? DateTime.tryParse(map['ambulanceEtaUpdatedAt'].toString())
          : null,
      ambulanceEtaUnitId: map['ambulanceEtaUnitId']?.toString(),
      ambulanceEtaCallSign: map['ambulanceEtaCallSign']?.toString(),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      archived: map['archived'] == true,
    );
  }

  String toJson() => json.encode(toMap());
  factory IncidentReport.fromJson(String str) =>
      IncidentReport.fromMap(json.decode(str));

  IncidentReport copyWith({
    String? id,
    String? type,
    String? severity,
    String? description,
    double? latitude,
    double? longitude,
    String? province,
    String? address,
    String? photoBase64,
    List<String>? photosBase64,
    List<String>? scenePhotosBase64,
    String? reporterName,
    String? reporterEmail,
    String? reporterPhone,
    String? status,
    int? statusStep,
    bool? isErPrepared,
    String? eta,
    String? assignedAmbulanceId,
    String? assignedAmbulancePlate,
    String? assignedAmbulanceCallSign,
    List<AssignedUnit>? assignedUnits,
    String? targetHospitalId,
    String? hospitalName,
    double? hospitalLatitude,
    double? hospitalLongitude,
    double? hospitalDistanceKm,
    String? assignedBy,
    DateTime? ambulanceNearSceneAt,
    int? ambulanceNearEtaMinutes,
    String? ambulanceNearCallSign,
    int? ambulanceEtaMinutes,
    int? ambulanceDistanceMeters,
    String? ambulanceEtaTarget,
    DateTime? ambulanceEtaUpdatedAt,
    String? ambulanceEtaUnitId,
    String? ambulanceEtaCallSign,
    DateTime? createdAt,
    bool? archived,
  }) {
    return IncidentReport(
      id: id ?? this.id,
      type: type ?? this.type,
      severity: severity ?? this.severity,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      province: province ?? this.province,
      address: address ?? this.address,
      photoBase64: photoBase64 ?? this.photoBase64,
      photosBase64: photosBase64 ?? this.photosBase64,
      scenePhotosBase64: scenePhotosBase64 ?? this.scenePhotosBase64,
      reporterName: reporterName ?? this.reporterName,
      reporterEmail: reporterEmail ?? this.reporterEmail,
      reporterPhone: reporterPhone ?? this.reporterPhone,
      status: status ?? this.status,
      statusStep: statusStep ?? this.statusStep,
      isErPrepared: isErPrepared ?? this.isErPrepared,
      eta: eta ?? this.eta,
      assignedAmbulanceId: assignedAmbulanceId ?? this.assignedAmbulanceId,
      assignedAmbulancePlate:
          assignedAmbulancePlate ?? this.assignedAmbulancePlate,
      assignedAmbulanceCallSign:
          assignedAmbulanceCallSign ?? this.assignedAmbulanceCallSign,
      assignedUnits: assignedUnits ?? this.assignedUnits,
      targetHospitalId: targetHospitalId ?? this.targetHospitalId,
      hospitalName: hospitalName ?? this.hospitalName,
      hospitalLatitude: hospitalLatitude ?? this.hospitalLatitude,
      hospitalLongitude: hospitalLongitude ?? this.hospitalLongitude,
      hospitalDistanceKm: hospitalDistanceKm ?? this.hospitalDistanceKm,
      assignedBy: assignedBy ?? this.assignedBy,
      ambulanceNearSceneAt: ambulanceNearSceneAt ?? this.ambulanceNearSceneAt,
      ambulanceNearEtaMinutes:
          ambulanceNearEtaMinutes ?? this.ambulanceNearEtaMinutes,
      ambulanceNearCallSign: ambulanceNearCallSign ?? this.ambulanceNearCallSign,
      ambulanceEtaMinutes: ambulanceEtaMinutes ?? this.ambulanceEtaMinutes,
      ambulanceDistanceMeters:
          ambulanceDistanceMeters ?? this.ambulanceDistanceMeters,
      ambulanceEtaTarget: ambulanceEtaTarget ?? this.ambulanceEtaTarget,
      ambulanceEtaUpdatedAt:
          ambulanceEtaUpdatedAt ?? this.ambulanceEtaUpdatedAt,
      ambulanceEtaUnitId: ambulanceEtaUnitId ?? this.ambulanceEtaUnitId,
      ambulanceEtaCallSign: ambulanceEtaCallSign ?? this.ambulanceEtaCallSign,
      createdAt: createdAt ?? this.createdAt,
      archived: archived ?? this.archived,
    );
  }
}
