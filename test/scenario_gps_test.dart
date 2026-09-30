// สถานการณ์ GPS และตำแหน่ง (G01–G15) — เรียกโค้ดจริงของแอป: LocationService, กติกาหมุดของหน้าแจ้งเหตุ,
// HospitalLocationService, EmergencyProximityTier และ AiTrajectoryService (เรดาร์ผู้ขับขี่)
// G16–G20 อยู่ในตัวจำลองหลายเครื่องและเทสต์อื่นที่ติดรหัสเดียวกัน (ดู docs/TEST_SCENARIOS.md)
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_alert/core/models/emergency_proximity_tier.dart';
import 'package:route_alert/core/services/ai_trajectory_service.dart';
import 'package:route_alert/core/services/hospital_location_service.dart';
import 'package:route_alert/core/services/location_service.dart';
import 'package:route_alert/core/services/sos_location_policy.dart';

import 'support/scenario_result.dart';

const _geo = Distance();
LatLng _move(LatLng p, double meters, double bearing) => _geo.offset(p, meters, bearing);
double _meters(LatLng a, LatLng b) => _geo.as(LengthUnit.Meter, a, b);

final _now = DateTime(2026, 9, 30, 10);
GpsSample _sample(LatLng p, {Duration ago = Duration.zero}) => (point: p, at: _now.subtract(ago));

Position _pos(LatLng p, {double accuracy = 8}) => Position(
      latitude: p.latitude,
      longitude: p.longitude,
      timestamp: _now,
      accuracy: accuracy,
      altitude: 300,
      altitudeAccuracy: 5,
      heading: 0,
      headingAccuracy: 5,
      speed: 10,
      speedAccuracy: 1,
    );

Future<LocationFix> _resolve({
  bool permission = true,
  FutureOr<GpsSample?> Function()? current,
  FutureOr<GpsSample?> Function()? lastKnown,
}) =>
    LocationService.resolveFixWith(
      permission: () async => permission,
      current: () async => current == null ? throw TimeoutException('gps') : await current(),
      lastKnown: () async => lastKnown == null ? null : await lastKnown(),
      clock: () => _now,
    );

/// ป้อนพิกัดดิบตามเวลาจำลอง แล้วเก็บพิกัดที่แอปนำไปใช้จริง
Future<List<LatLng>> _feed(List<(Duration at, Object event)> script) async {
  var clock = _now;
  final raw = StreamController<Position>();
  final out = <LatLng>[];
  final sub = LocationService.positionsToLocations(raw.stream, clock: () => clock).listen(out.add);
  for (final (at, event) in script) {
    clock = _now.add(at);
    if (event is Position) {
      raw.add(event);
    } else {
      raw.addError(event);
    }
    await Future<void>.delayed(Duration.zero);
  }
  await raw.close();
  await sub.cancel();
  return out;
}

String _fix(LocationFix f) => f.point == null
    ? 'ไม่มีตำแหน่ง (${f.source.name})'
    : '${f.source.name} (${f.point!.latitude.toStringAsFixed(4)}, ${f.point!.longitude.toStringAsFixed(4)})${f.age != null ? ' อายุ ${f.age!.inMinutes} นาที' : ''}';
String _ll(LatLng p) => '(${p.latitude.toStringAsFixed(4)}, ${p.longitude.toStringAsFixed(4)})';

void main() {
  const scene = LatLng(18.7960, 98.9600);
  final hospitals = HospitalLocationService();

  group('ตำแหน่งของผู้แจ้งเหตุ', () {
    test('[G01] GPS ปกติ: จุดแจ้งเหตุคือตำแหน่งจริง และส่งไปโรงพยาบาลที่ใกล้ที่สุดจากจุดนั้น', () async {
      final fix = await _resolve(current: () => _sample(scene));
      expect(fix.source, LocationSource.gps);
      expect(fix.point, scene);
      final point = sosReportPoint(pinned: fix.point, gps: fix.point)!;
      expect(sosLocationProblem(source: fix.source, pinned: point, pinnedByUser: false), isNull);
      expect(sosLocationBanner(fix.source, pinnedByUser: false), isNull);
      final nearest = hospitals.findNearestHospital(point);
      for (final h in hospitals.allHospitals) {
        expect(nearest.distanceKm <= HospitalLocationService.calculateDistanceKm(point, h.location) + 0.01, isTrue);
      }
      scenarioResult(
        condition: 'อนุญาต GPS, เครื่องได้พิกัด ${_ll(scene)}',
        expected: 'ใช้พิกัดจริง ไม่มีคำเตือน ส่งไป รพ. ใกล้สุด',
        actual: 'ได้ ${_fix(fix)}, คำเตือน: ไม่มี, ส่งได้: ใช่, รพ. ${nearest.profile.hospitalName} ${nearest.distanceKm} กม. '
            '(ใกล้สุดจาก ${hospitals.allHospitals.length} แห่ง)',
      );
    });

    test('[G02] ไม่ได้อนุญาต/ปิด GPS: ไม่ใช้พิกัดเดา ต้องปักหมุดเองก่อนส่ง', () async {
      // มีตำแหน่งเก่าใน cache ก็ห้ามใช้ เพราะผู้ใช้ไม่ได้อนุญาต
      final denied = await _resolve(permission: false, current: () => _sample(scene), lastKnown: () => _sample(scene));
      expect(denied.source, LocationSource.unavailable);
      expect(denied.point, isNull, reason: 'เดิมคืนพิกัดประตูท่าแพ แล้วเคสถูกปักไว้ที่นั่นโดยไม่เตือน');
      final off = await _resolve(current: null, lastKnown: null); // เปิดสิทธิ์แต่ปิด GPS/หาไม่ได้
      expect(off.point, isNull);

      expect(sosLocationBanner(off.source, pinnedByUser: false), contains('หาตำแหน่ง GPS ไม่ได้'));
      expect(sosLocationProblem(source: off.source, pinned: null, pinnedByUser: false), isNotNull,
          reason: 'ส่งไม่ได้ถ้ายังไม่มีหมุด');
      // แผนที่เปิดไว้ที่ตัวเมือง แต่ยังไม่ถือเป็นหมุดจนกว่าผู้แจ้งจะเลื่อน/ยืนยันเอง
      expect(sosLocationProblem(source: off.source, pinned: LocationService.defaultLocation, pinnedByUser: false), isNotNull);
      expect(sosLocationProblem(source: off.source, pinned: scene, pinnedByUser: true), isNull);
      expect(sosLocationBanner(off.source, pinnedByUser: true), isNull);
      scenarioResult(
        condition: 'ผู้ใช้ไม่อนุญาต GPS (มีตำแหน่งเก่าในเครื่อง)',
        expected: 'ไม่ใช้พิกัดใดๆ',
        actual: 'ได้ ${_fix(denied)} (โค้ดเดิม: ประตูท่าแพ ${_ll(LocationService.defaultLocation)})',
      );
      scenarioResult(
        condition: 'อนุญาตแต่ปิด GPS / หาตำแหน่งไม่ได้ → กดส่งโดยยังไม่ปักหมุด',
        expected: 'ขึ้นคำเตือน และส่งไม่ได้',
        actual: 'ได้ ${_fix(off)}, คำเตือน: "${sosLocationBanner(off.source, pinnedByUser: false)}", '
            'ส่งได้: ${sosLocationProblem(source: off.source, pinned: null, pinnedByUser: false) == null ? 'ใช่' : 'ไม่ได้'}',
      );
      scenarioResult(
        condition: 'หาตำแหน่งไม่ได้ → ผู้แจ้งเลื่อนแผนที่ปักหมุดเองแล้วกดส่ง',
        expected: 'ส่งได้ด้วยพิกัดที่ปักหมุด',
        actual: 'ส่งได้: ${sosLocationProblem(source: off.source, pinned: scene, pinnedByUser: true) == null ? 'ใช่' : 'ไม่ได้'} ที่ ${_ll(scene)}',
      );
    });

    test('[G03] GPS ช้า (ในตึก/เพิ่งเปิดเครื่อง): ใช้ตำแหน่งล่าสุดที่ยังใหม่พร้อมเตือน ตำแหน่งเก่าเกินไม่ใช้', () async {
      final recent = await _resolve(current: null, lastKnown: () => _sample(scene, ago: const Duration(minutes: 2)));
      expect(recent.source, LocationSource.lastKnown);
      expect(recent.point, scene);
      expect(recent.age, const Duration(minutes: 2));
      expect(sosLocationBanner(recent.source, age: recent.age, pinnedByUser: false), contains('2 นาที'));
      expect(sosLocationProblem(source: recent.source, pinned: recent.point, pinnedByUser: false), isNull);

      final stale = await _resolve(current: null, lastKnown: () => _sample(scene, ago: const Duration(minutes: 30)));
      expect(stale.source, LocationSource.unavailable, reason: 'ตำแหน่งเมื่อ 30 นาทีก่อน คนอาจอยู่ไกลแล้ว');

      // GPS บางเครื่องรายงาน (0,0) ตอนยังจับดาวเทียมไม่ได้ — ถือว่ายังไม่มีตำแหน่ง
      final nullIsland = await _resolve(current: () => _sample(const LatLng(0, 0)), lastKnown: () => _sample(scene, ago: const Duration(minutes: 1)));
      expect(nullIsland.source, LocationSource.lastKnown);
      expect(nullIsland.point, scene);
      scenarioResult(condition: 'GPS จับไม่ทันใน 8 วิ, ตำแหน่งล่าสุดเมื่อ 2 นาทีก่อน',
          expected: 'ใช้ตำแหน่งล่าสุดพร้อมเตือนให้ตรวจหมุด',
          actual: 'ได้ ${_fix(recent)}, คำเตือน: "${sosLocationBanner(recent.source, age: recent.age, pinnedByUser: false)}"');
      scenarioResult(condition: 'GPS จับไม่ทัน, ตำแหน่งล่าสุดเมื่อ 30 นาทีก่อน',
          expected: 'ไม่ใช้ (เก่าเกิน 5 นาที) ต้องปักหมุดเอง', actual: 'ได้ ${_fix(stale)}');
      scenarioResult(condition: 'GPS รายงาน (0, 0) ตอนยังจับดาวเทียมไม่ได้',
          expected: 'ไม่ใช้ (0,0) ใช้ตำแหน่งล่าสุดแทน', actual: 'ได้ ${_fix(nullIsland)}');
    });

    test('[G04] ผู้แจ้งเลื่อนหมุดเอง (แจ้งแทนคนอื่น/GPS คลาด): ใช้หมุด และคำนวณโรงพยาบาลจากหมุด', () {
      final list = hospitals.allHospitals;
      expect(list.length, greaterThanOrEqualTo(2));
      final gps = _move(list[0].location, 200, 45); // ผู้แจ้งยืนอยู่ใกล้ รพ. แรก
      final pinned = _move(list[1].location, 200, 45); // แต่เหตุเกิดใกล้ รพ. ที่สอง
      final point = sosReportPoint(pinned: pinned, gps: gps)!;
      expect(point, pinned);
      expect(hospitals.findNearestHospital(point).profile.hospitalId, list[1].hospitalId);
      expect(sosReportPoint(pinned: null, gps: gps), gps);
      final fromGps = hospitals.findNearestHospital(gps);
      final fromPin = hospitals.findNearestHospital(point);
      scenarioResult(
        condition: 'เครื่องอยู่ ${_ll(gps)} (ใกล้ ${list[0].hospitalName}) แต่ปักหมุดที่ ${_ll(pinned)}',
        expected: 'เคสใช้หมุด และไป รพ. ใกล้หมุด',
        actual: 'จุดแจ้งเหตุ ${_ll(point)} → ${fromPin.profile.hospitalName} ${fromPin.distanceKm} กม. '
            '(ถ้าใช้ GPS จะไป ${fromGps.profile.hospitalName})',
      );
    });
  });

  group('คุณภาพสัญญาณ GPS', () {
    test('[G05] ในอาคาร ความแม่นยำต่ำ (> 50 ม.): พิกัดถูกกรองทิ้ง แต่ไม่ค้างถาวร', () async {
      const a = scene;
      final b = _move(scene, 30, 90);
      final out = await _feed([
        (Duration.zero, _pos(a, accuracy: 12)),
        (const Duration(seconds: 3), _pos(b, accuracy: 80)), // ในตึก
        (const Duration(seconds: 8), _pos(b, accuracy: 95)),
        (const Duration(seconds: 17), _pos(b, accuracy: 90)), // ไม่มีค่าที่ดีกว่านี้เกิน 15 วิ
      ]);
      expect(out, [a, b], reason: 'ทิ้งค่าที่ไม่แม่นในช่วงแรก แต่เกิน 15 วิแล้วต้องรับค่าล่าสุด (หมุดไม่ค้าง)');
      scenarioResult(
        condition: 'ป้อน 4 ค่า: วินาทีที่ 0 (±12 ม.), 3 (±80 ม.), 8 (±95 ม.), 17 (±90 ม.)',
        expected: 'รับค่าที่ 0, ทิ้งค่าที่ 3 และ 8, รับค่าที่ 17 (ไม่มีค่าดีกว่าเกิน 15 วิ)',
        actual: 'แอปใช้ ${out.length} ค่า: ${out.map(_ll).join(', ')}',
      );
    });

    test('[G06] GPS กระโดดชั่วขณะ (สัญญาณสะท้อนตึก): จุดกระโดดไม่ถูกใช้ ไม่ทำให้ "รถใกล้ถึง" ผิด', () async {
      final road = _move(scene, 900, 180); // รถยังอยู่ห่างจุดเกิดเหตุ 900 ม.
      final spike = _move(scene, 80, 180); // จุดกระโดดไปใกล้จุดเกิดเหตุ
      final out = await _feed([
        (Duration.zero, _pos(road, accuracy: 10)),
        (const Duration(seconds: 2), _pos(spike, accuracy: 150)),
        (const Duration(seconds: 4), _pos(_move(road, 20, 0), accuracy: 9)),
      ]);
      expect(out.length, 2);
      expect(out.every((p) => _meters(p, scene) > 500), isTrue,
          reason: 'ถ้าใช้จุดกระโดด แอปรถจะบันทึก "ใกล้ถึง (< 500 ม.)" ให้ผู้แจ้งทั้งที่ยังไม่ถึง');
      scenarioResult(
        condition: 'รถห่างจุดเกิดเหตุ 900 ม. แล้ว GPS กระโดดไปห่าง 80 ม. (±150 ม.) 1 ครั้ง',
        expected: 'ไม่ใช้จุดกระโดด ไม่เกิด "รถใกล้ถึง"',
        actual: 'แอปใช้ ${out.length} ค่า ระยะถึงจุดเกิดเหตุ ${out.map((p) => '${_meters(p, scene).round()} ม.').join(', ')} → ใกล้สุด '
            '${out.map((p) => _meters(p, scene)).reduce((x, y) => x < y ? x : y).round()} ม. (> 500 ม. ไม่ประกาศใกล้ถึง)',
      );
    });

    test('[G07] GPS ขัดข้องกลางทาง: ไม่ส่งพิกัดปลอม ตำแหน่งค้างที่จุดจริงล่าสุดจนสัญญาณกลับมา', () async {
      const a = scene;
      final b = _move(scene, 150, 0);
      final out = await _feed([
        (Duration.zero, _pos(a)),
        (const Duration(seconds: 2), const LocationServiceDisabledException()),
        (const Duration(seconds: 4), 'GPS timeout'),
        (const Duration(seconds: 5), _pos(const LatLng(0, 0))), // ค่าขยะตอนเริ่มจับสัญญาณใหม่
        (const Duration(seconds: 7), _pos(b)),
      ]);
      expect(out, [a, b]);
      expect(out.contains(LocationService.defaultLocation), isFalse,
          reason: 'เดิม error → ส่งพิกัดประตูท่าแพ รถพยาบาลกระโดดไปท่าแพแล้วประกาศให้ทุกเครื่อง');
      scenarioResult(
        condition: 'จุด A → GPS ถูกปิด → timeout → ค่าขยะ (0,0) → จุด B ห่าง 150 ม.',
        expected: 'ใช้แค่ A และ B ไม่มีพิกัดปลอม',
        actual: 'แอปใช้ ${out.length} ค่า: ${out.map(_ll).join(' → ')} · มีพิกัดท่าแพ: ${out.contains(LocationService.defaultLocation) ? 'มี' : 'ไม่มี'} '
            '(โค้ดเดิมจะได้ A → ท่าแพ → ท่าแพ → (0,0) → B)',
      );
    });
  });

  group('เรดาร์ผู้ขับขี่ (ระยะและเส้นทางรถพยาบาล)', () {
    final ai = AiTrajectoryService();
    const ambulance = LatLng(18.7900, 98.9800);
    final straight = [ambulance, _move(ambulance, 1500, 0), _move(ambulance, 3000, 0)];
    final turnPoint = _move(ambulance, 300, 0);
    final turnAway = [ambulance, turnPoint, _move(turnPoint, 1500, 90)];

    TrajectoryPredictionResult eval(LatLng driver,
        {double driverHeading = 0, double ambHeading = 0, LatLng amb = ambulance, List<LatLng>? route,
        String? label, bool? expectAlert}) {
      final r = ai.evaluateTrajectoryConflict(
        driverPos: driver,
        driverSpeedKmh: 40,
        driverHeadingDeg: driverHeading,
        ambulancePos: amb,
        ambulanceSpeedKmh: 70,
        ambulanceHeadingDeg: ambHeading,
        maxWarningDistanceMeters: 3000,
        routePoints: route,
      );
      if (label != null) {
        scenarioResult(
          condition: '$label (ห่าง ${_meters(driver, amb).round()} ม.${route == null ? ', ไม่มีเส้นทาง' : ''})',
          expected: expectAlert == true ? 'เตือน' : 'ไม่เตือน',
          actual: '${r.shouldAlert ? 'เตือน' : 'ไม่เตือน'} — ${r.category.name} (${r.statusTitleTH}), โอกาสต้องหลบ ${(r.yieldProbability * 100).round()}%',
        );
      }
      return r;
    }

    test('[G08] ระดับเตือนตามระยะ พ.ร.บ.จราจร ม.76 ตรงทุกค่าขอบ', () {
      final cases = <double, EmergencyProximityTier>{
        0.0: EmergencyProximityTier.illegalHazard,
        49.9: EmergencyProximityTier.illegalHazard,
        50.0: EmergencyProximityTier.criticalYield,
        150.0: EmergencyProximityTier.criticalYield,
        150.1: EmergencyProximityTier.approaching,
        500.0: EmergencyProximityTier.approaching,
        500.1: EmergencyProximityTier.radarAwareness,
        3000.0: EmergencyProximityTier.radarAwareness,
        3000.1: EmergencyProximityTier.safeZone,
      };
      cases.forEach((m, tier) {
        final got = EmergencyProximityTier.fromDistance(m);
        scenarioResult(condition: 'ระยะ $m ม.', expected: tier.distanceRangeTH, actual: '${got.distanceRangeTH} — ${got.titleTH}');
        expect(got, tier, reason: '$m ม.');
      });
      expect(EmergencyProximityTier.fromDistance(20, hasAmbulance: false), EmergencyProximityTier.safeZone);
    });

    test('[G09] รถพยาบาลตามหลังในเส้นทางเดียวกัน ≤ 500 ม.: เตือนให้หลบทางทันที', () {
      for (final m in [80.0, 200.0, 350.0, 480.0]) {
        final r = eval(_move(ambulance, m, 0), route: straight, label: 'ผู้ขับขี่ข้างหน้าในเส้นทาง', expectAlert: true);
        expect(r.shouldAlert, isTrue, reason: '$m ม.');
        expect(r.category, TrajectoryConflictCategory.criticalInPath, reason: '$m ม.');
      }
    });

    test('[G10] รถพยาบาลอยู่ในเส้นทาง 0.5–2.5 กม.: เตือนล่วงหน้า', () {
      for (final m in [700.0, 1200.0, 1800.0, 2500.0]) {
        final r = eval(_move(ambulance, m, 0), route: straight, label: 'ผู้ขับขี่ข้างหน้าในเส้นทาง', expectAlert: true);
        expect(r.shouldAlert, isTrue, reason: '$m ม.');
        expect(r.category, TrajectoryConflictCategory.approachingCorridor, reason: '$m ม.');
      }
    });

    test('[G11] อยู่ถนนขนาน/ถนนอื่นใกล้ๆ: ไม่เตือน', () {
      for (final m in [300.0, 900.0, 1600.0]) {
        final r = eval(_move(_move(ambulance, m, 0), 300, 90), route: straight,
            label: 'ถนนขนานห่างเส้นทาง 300 ม. (ระยะตามแนวถนน $m ม.)', expectAlert: false);
        expect(r.shouldAlert, isFalse, reason: '$m ม. (${r.category.name})');
      }
    });

    test('[G12] รถพยาบาลผ่านไปแล้ว: ไม่เตือน', () {
      for (final m in [60.0, 150.0, 250.0]) {
        final r = eval(_move(ambulance, m, 180), route: straight, label: 'อยู่ด้านหลังรถพยาบาล (ผ่านไปแล้ว)', expectAlert: false);
        expect(r.shouldAlert, isFalse, reason: '$m ม.');
        expect(r.category, TrajectoryConflictCategory.movingAway);
      }
    });

    test('[G13] รถพยาบาลจะเลี้ยวออกก่อนถึงเรา = ไม่เตือน / กำลังเลี้ยวเข้าถนนของเรา = เตือนล่วงหน้า', () {
      for (final m in [600.0, 900.0, 1200.0]) {
        final r = eval(_move(ambulance, m, 0), route: turnAway, label: 'รถพยาบาลจะเลี้ยวขวาที่ 300 ม. ก่อนถึงผู้ขับขี่', expectAlert: false);
        expect(r.shouldAlert, isFalse, reason: '$m ม.');
        expect(r.category, TrajectoryConflictCategory.turnBypass);
      }
      const driver = LatLng(19.0284, 99.8962);
      const side = LatLng(19.0260, 99.8850);
      final turnIn = [side, const LatLng(19.0260, 99.8962), driver, const LatLng(19.0350, 99.8962)];
      final r = eval(driver, amb: side, ambHeading: 90, route: turnIn, label: 'รถพยาบาลกำลังเลี้ยวเข้าถนนของผู้ขับขี่', expectAlert: true);
      expect(r.shouldAlert, isTrue);
      expect(r.category, TrajectoryConflictCategory.turnInApproaching);
    });

    test('[G14] ไม่มีข้อมูลเส้นทาง (ระบบนำทางล่ม): ใช้ทิศทาง+ระยะแทน เตือนคันข้างหน้า ไม่เตือนรถสวนเลน', () {
      final ahead = eval(_move(ambulance, 300, 0), label: 'ผู้ขับขี่ข้างหน้า ทิศเดียวกัน', expectAlert: true);
      expect(ahead.shouldAlert, isTrue, reason: ahead.category.name);
      expect(ahead.isRouteAwareActive, isFalse);
      final oncoming = eval(_move(ambulance, 300, 0), driverHeading: 180, label: 'รถสวนเลน (วิ่งสวนทาง)', expectAlert: false);
      expect(oncoming.shouldAlert, isFalse);
      expect(oncoming.category, TrajectoryConflictCategory.opposingLane);
    });

    test('[G15] ไกลเกินรัศมีเตือน 3 กม.: ไม่เตือน ทั้งแบบมีและไม่มีเส้นทาง', () {
      for (final m in [3300.0, 4000.0, 6000.0]) {
        for (final route in [straight, null]) {
          final r = eval(_move(ambulance, m, 0), route: route, label: 'ผู้ขับขี่ข้างหน้า ไกลเกินรัศมี', expectAlert: false);
          expect(r.shouldAlert, isFalse, reason: '$m ม. route=${route != null}');
          expect(r.category, TrajectoryConflictCategory.safeDistance);
        }
      }
    });
  });
}
