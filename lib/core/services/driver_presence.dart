import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'emergency_mqtt_service.dart' show EmergencyVehicleData;

/// ตำแหน่งของผู้ขับขี่ที่แชร์ให้ผู้ขับขี่คนอื่นเห็นบนแผนที่ (ผ่าน MQTT topic แยกจากรถพยาบาล)
/// ไม่มีชื่อ/อีเมล/เบอร์ — ใช้รหัสสุ่มประจำเครื่องเท่านั้น (ความเป็นส่วนตัว)
class DriverPresence {
  const DriverPresence({
    required this.id,
    required this.latitude,
    required this.longitude,
    this.heading = 0,
    this.speedKmh = 0,
    this.online = true,
  });

  final String id;
  final double latitude;
  final double longitude;
  final double heading;
  final double speedKmh;
  final bool online; // false = ออกจากแผนที่/ปิดการแชร์ — ลบทันทีไม่ต้องรอหมดเวลา

  LatLng get point => LatLng(latitude, longitude);

  String toJson() => jsonEncode({
        'id': id,
        'lat': double.parse(latitude.toStringAsFixed(5)), // ~1 ม. พอสำหรับแผนที่
        'lng': double.parse(longitude.toStringAsFixed(5)),
        'hd': heading.round(),
        'kmh': speedKmh.round(),
        'on': online,
      });

  static DriverPresence? tryParse(String payload) {
    try {
      final m = jsonDecode(payload) as Map<String, dynamic>;
      final id = m['id'];
      final lat = (m['lat'] as num?)?.toDouble();
      final lng = (m['lng'] as num?)?.toDouble();
      if (id is! String || id.isEmpty || lat == null || lng == null) return null;
      if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) return null;
      return DriverPresence(
        id: id,
        latitude: lat,
        longitude: lng,
        heading: (m['hd'] as num?)?.toDouble() ?? 0,
        speedKmh: (m['kmh'] as num?)?.toDouble() ?? 0,
        online: m['on'] != false,
      );
    } catch (_) {
      return null;
    }
  }

  /// รหัสสุ่มประจำเครื่อง เช่น D-3f9a01c2 (บันทึกไว้ใน DriverStorageService)
  static String newAnonymousId([math.Random? random]) {
    final r = random ?? math.Random.secure();
    return 'D-${List.generate(4, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }
}

/// รายชื่อผู้ขับขี่ที่ออนไลน์ (ฝั่งรับ) — หมดเวลาตามนาฬิกาเครื่องนี้ ไม่พึ่งนาฬิกาเครื่องผู้ส่ง
class DriverPresenceRegistry {
  DriverPresenceRegistry({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// เงียบเกินนี้ = ออฟไลน์ (ผู้ขับขี่ส่ง heartbeat ทุก 15 วิ แม้จอดนิ่ง)
  static const Duration staleAfter = Duration(seconds: 30);

  final DateTime Function() _clock;
  final Map<String, DriverPresence> _drivers = {};
  final Map<String, DateTime> _lastSeen = {};

  /// คืน true ถ้ารายชื่อเปลี่ยน
  bool update(DriverPresence p) {
    if (!p.online) {
      _lastSeen.remove(p.id);
      return _drivers.remove(p.id) != null;
    }
    _drivers[p.id] = p;
    _lastSeen[p.id] = _clock();
    return true;
  }

  /// ลบคนที่เงียบเกิน [staleAfter] — คืน true ถ้ามีคนถูกลบ
  bool purge() {
    final now = _clock();
    final stale = _lastSeen.entries.where((e) => now.difference(e.value) > staleAfter).map((e) => e.key).toList();
    for (final id in stale) {
      _drivers.remove(id);
      _lastSeen.remove(id);
    }
    return stale.isNotEmpty;
  }

  /// ผู้ขับขี่คนอื่น (ไม่รวมตัวเอง)
  List<DriverPresence> others(String? selfId) => _drivers.values.where((d) => d.id != selfId).toList();

  void clear() {
    _drivers.clear();
    _lastSeen.clear();
  }
}

/// ควรส่งตำแหน่งตัวเองรอบนี้ไหม — ขยับเกิน 15 ม. (ไม่ถี่กว่า 5 วิ) หรือครบ 15 วิ (heartbeat ตอนจอดนิ่ง)
bool shouldPublishPresence({
  required DateTime now,
  required LatLng position,
  DateTime? lastSentAt,
  LatLng? lastSentPosition,
}) {
  if (lastSentAt == null || lastSentPosition == null) return true;
  final since = now.difference(lastSentAt);
  if (since >= const Duration(seconds: 15)) return true;
  if (since < const Duration(seconds: 5)) return false;
  return const Distance().as(LengthUnit.Meter, lastSentPosition, position) >= 15;
}

/// รถพยาบาลคันอื่นบนแผนที่ของรถพยาบาล (ไม่รวมคันตัวเอง และบัญชีอื่นบนรถคันเดียวกัน = ทะเบียนเดียวกัน)
List<EmergencyVehicleData> otherAmbulances(List<EmergencyVehicleData> fleet, {required String ownUnitId, String? ownPlate}) {
  String norm(String? p) => (p ?? '').toLowerCase().replaceAll(RegExp(r'[\s\-./_#]'), '');
  final mine = norm(ownPlate);
  return fleet.where((v) {
    if (v.id == ownUnitId) return false;
    if (mine.isNotEmpty && mine != norm('ยังไม่ระบุทะเบียน') && norm(v.plateNumber) == mine) return false;
    return true;
  }).toList();
}
