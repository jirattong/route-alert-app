// S20: ผู้ใช้เห็นกันบนแผนที่ตามบทบาท — ผู้ขับขี่เห็นผู้ขับขี่คนอื่นและรถพยาบาลทุกคัน,
// รถพยาบาลเห็นรถพยาบาลคันอื่น (ไม่รับตำแหน่งผู้ขับขี่) — เรียกโค้ดจริง driver_presence.dart / EmergencyMqttService
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_alert/core/services/driver_presence.dart';
import 'package:route_alert/core/services/emergency_mqtt_service.dart';

import 'support/scenario_result.dart';

EmergencyVehicleData _amb(String id, String plate, {double lat = 18.79}) => EmergencyVehicleData(
      id: id,
      callSign: 'กู้ชีพ $id',
      latitude: lat,
      longitude: 98.98,
      speed: 40,
      heading: 0,
      plateNumber: plate,
      emergencyType: 'x',
      sirenActive: true,
      timestamp: DateTime(2026, 10, 1),
    );

void main() {
  test('[S20] ผู้ขับขี่ 10 คนเห็นกันเอง: ไม่เห็นตัวเองซ้ำ, ข้อมูลไม่ระบุตัวตน, ออกจากแผนที่/เงียบเกิน 30 วิแล้วหายไป', () {
    var now = DateTime(2026, 10, 1, 9);
    final registry = DriverPresenceRegistry(clock: () => now);
    final ids = List.generate(10, (i) => DriverPresence.newAnonymousId(math.Random(i)));
    expect(ids.toSet().length, 10);
    for (final (i, id) in ids.indexed) {
      final payload = DriverPresence(id: id, latitude: 18.79 + i * 0.001, longitude: 98.98, heading: 90, speedKmh: 35).toJson();
      // ข้อมูลที่ส่งออกไปมีแค่รหัสสุ่ม พิกัด ทิศ ความเร็ว — ไม่มีชื่อ/อีเมล/เบอร์
      expect((jsonDecode(payload) as Map).keys.toSet(), {'id', 'lat', 'lng', 'hd', 'kmh', 'on'});
      registry.update(DriverPresence.tryParse(payload)!);
    }
    final me = ids.first;
    final seenByMe = registry.others(me);
    expect(seenByMe.length, 9, reason: 'เห็นคนอื่น 9 คน ไม่รวมตัวเอง');
    expect(seenByMe.any((d) => d.id == me), isFalse);

    // คนที่ 2 ปิดสวิตช์แชร์/ออกจากแอป → ส่ง on:false หายทันที
    registry.update(DriverPresence(id: ids[1], latitude: 0, longitude: 0, online: false));
    final afterOff = registry.others(me).length;
    expect(afterOff, 8);

    // ผ่านไป 31 วิ มีแค่ 3 คนที่ส่ง heartbeat → ที่เหลือหายจากแผนที่
    now = now.add(const Duration(seconds: 20));
    for (final id in ids.sublist(2, 5)) {
      registry.update(DriverPresence(id: id, latitude: 18.8, longitude: 98.98));
    }
    now = now.add(const Duration(seconds: 11));
    expect(registry.purge(), isTrue);
    final afterStale = registry.others(me).map((d) => d.id).toSet();
    expect(afterStale, ids.sublist(2, 5).toSet());

    // ข้อมูลเสีย/พิกัดเป็นไปไม่ได้ ไม่ถูกนำมาแสดง
    expect(DriverPresence.tryParse('{"id":"D-1","lat":95,"lng":98}'), isNull);
    expect(DriverPresence.tryParse('not json'), isNull);

    scenarioResult(condition: 'ผู้ขับขี่ 10 คนส่งตำแหน่ง ดูจากเครื่องคนที่ 1', expected: 'เห็นคนอื่น 9 คน ไม่เห็นตัวเอง',
        actual: 'เห็น ${seenByMe.length} คน · มีตัวเองในรายการ: ${seenByMe.any((d) => d.id == me) ? 'มี' : 'ไม่มี'}');
    scenarioResult(condition: 'ข้อมูลที่ส่งออกไปต่อ 1 คน', expected: 'ไม่มีชื่อ/อีเมล/เบอร์',
        actual: 'ฟิลด์: ${(jsonDecode(DriverPresence(id: me, latitude: 18.79, longitude: 98.98).toJson()) as Map).keys.join(', ')} (รหัสสุ่ม เช่น $me)');
    scenarioResult(condition: 'คนที่ 2 ปิดสวิตช์แชร์ตำแหน่ง', expected: 'หายจากแผนที่ทันที', actual: 'เหลือ $afterOff คน');
    scenarioResult(condition: 'ผ่านไป 31 วิ มีแค่ 3 คนที่ยังส่ง heartbeat', expected: 'เหลือ 3 คน (คนที่เงียบเกิน 30 วิหาย)',
        actual: 'เหลือ ${afterStale.length} คน');
  });

  test('[S20] ส่งตำแหน่งเมื่อขยับ ≥ 15 ม. (ไม่ถี่กว่า 5 วิ) หรือทุก 15 วิตอนจอดนิ่ง', () {
    final t0 = DateTime(2026, 10, 1, 9);
    const p0 = LatLng(18.79, 98.98);
    final moved = const Distance().offset(p0, 40, 0);
    final cases = <(String, Duration, LatLng, bool)>[
      ('ขยับ 40 ม. หลังส่งไป 2 วิ', const Duration(seconds: 2), moved, false),
      ('ขยับ 40 ม. หลังส่งไป 6 วิ', const Duration(seconds: 6), moved, true),
      ('จอดนิ่ง 10 วิ', const Duration(seconds: 10), p0, false),
      ('จอดนิ่ง 16 วิ (heartbeat)', const Duration(seconds: 16), p0, true),
    ];
    for (final (label, after, pos, expected) in cases) {
      final got = shouldPublishPresence(now: t0.add(after), position: pos, lastSentAt: t0, lastSentPosition: p0);
      scenarioResult(condition: label, expected: expected ? 'ส่ง' : 'ยังไม่ส่ง', actual: got ? 'ส่ง' : 'ยังไม่ส่ง');
      expect(got, expected, reason: label);
    }
    expect(shouldPublishPresence(now: t0, position: p0), isTrue, reason: 'ครั้งแรกส่งทันที');
  });

  test('[S20] รถพยาบาลเห็นรถพยาบาลคันอื่น ไม่เห็นคันตัวเอง/บัญชีอื่นบนรถคันเดียวกัน และไม่รับตำแหน่งผู้ขับขี่', () {
    final fleet = [
      _amb('AMB-1', 'กข 1111'), // คันนี้
      _amb('AMB-9', 'กข-1111'), // อีกบัญชีบนรถคันเดียวกัน
      _amb('AMB-2', 'ขค 2222'),
      _amb('AMB-3', 'คง 3333'),
    ];
    final seen = otherAmbulances(fleet, ownUnitId: 'AMB-1', ownPlate: 'กข 1111').map((v) => v.id).toList();
    expect(seen, ['AMB-2', 'AMB-3']);
    // รถยังไม่ตั้งทะเบียน: ตัดเฉพาะคันตัวเอง (ไม่เหมารวมทุกคันที่ไม่มีทะเบียน)
    final unset = otherAmbulances([_amb('AMB-1', 'ยังไม่ระบุทะเบียน'), _amb('AMB-5', 'ยังไม่ระบุทะเบียน')],
        ownUnitId: 'AMB-1', ownPlate: 'ยังไม่ระบุทะเบียน');
    expect(unset.map((v) => v.id), ['AMB-5']);
    // ตำแหน่งผู้ขับขี่ใช้ topic แยก ที่แอปรถพยาบาลไม่ subscribe
    expect(EmergencyMqttService.topicDriverPresence, isNot(EmergencyMqttService.topicAmbulanceBroadcast));
    expect(EmergencyMqttService().activeDrivers, isEmpty, reason: 'ยังไม่ subscribe = ไม่มีข้อมูลผู้ขับขี่');

    scenarioResult(condition: 'รถ AMB-1 (กข 1111) ดูแผนที่ — ออนไลน์ 4 บัญชี (AMB-9 อยู่รถคันเดียวกัน)',
        expected: 'เห็น AMB-2, AMB-3', actual: 'เห็น ${seen.join(', ')}');
    scenarioResult(condition: 'แอปรถพยาบาลกับตำแหน่งผู้ขับขี่', expected: 'ไม่รับ (topic แยก ไม่ subscribe)',
        actual: 'topic ผู้ขับขี่ ${EmergencyMqttService.topicDriverPresence} · ข้อมูลผู้ขับขี่ในแอปรถ ${EmergencyMqttService().activeDrivers.length} คน');
  });
}
