// ทดสอบ "หลายผู้ใช้พร้อมกัน" กับโค้ดจริงของ IncidentService (เทสต์ไม่ได้เขียนตรรกะแอปใหม่)
//
// ข้อจำกัดของการจำลองที่ต้องรู้ก่อนอ่านผล:
// - Firestore = fake_cloud_firestore ในหน่วยความจำ ซึ่ง runTransaction ของมันไม่มี isolation
//   (อ่าน/เขียนตรง ไม่ตรวจชน ไม่ retry) จึงครอบด้วย OptimisticFakeFirestore ที่เลียนแบบ
//   optimistic concurrency ของ Firestore จริง ผล "ผู้ชนะคนเดียว" จึงพิสูจน์ว่าโค้ดแอปถูกต้อง
//   ภายใต้ semantics ของ Firestore ไม่ได้พิสูจน์ตัวเซิร์ฟเวอร์ (ส่วนนั้นใช้ simulator กับ emulator)
// - ทั้งไฟล์รันใน isolate เดียว IncidentService เป็น singleton = "เครื่องเดียว" ผู้ใช้หลายคนใน
//   เทสต์จึงแชร์ cache (SharedPreferences) และ cooldown กัน เทสต์จึงตรวจผลที่ Firestore เป็นหลัก
// - ลำดับเทสต์มีผล: เทสต์ createIncident ต้องรันก่อนเทสต์อื่นที่แตะ cooldown (ดูในเทสต์นั้น)

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_alert/core/models/incident_report.dart';
import 'package:route_alert/core/services/hospital_location_service.dart';
import 'package:route_alert/core/services/incident_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/scenario_result.dart';

/// Firestore จำลองที่ transaction เป็นแบบ optimistic เหมือนของจริง: จำเอกสารที่อ่าน เก็บการเขียน
/// ไว้ก่อน ตอน commit (ทีละรายการ) ถ้าเอกสารที่อ่านไปถูกเปลี่ยนแล้วจะทิ้งผลแล้วรัน handler ใหม่
/// สูงสุด maxAttempts ครั้ง ถ้า handler throw เองจะส่งต่อทันทีไม่ retry ตรงกับ SDK มือถือ
/// (เทียบ "เปลี่ยนแล้ว" ด้วยเนื้อหาเอกสาร ส่วนเซิร์ฟเวอร์จริงเทียบ update time)
class OptimisticFakeFirestore extends FakeFirebaseFirestore {
  Future<void> _commitQueue = Future<void>.value();

  int handlerRuns = 0;
  int conflicts = 0;
  int exhausted = 0;
  int committedWrites = 0;

  /// เรียกหลัง handler อ่านเสร็จแต่ก่อน commit ใช้จำลอง client อื่นเขียนแทรกเข้ามา
  Future<void> Function()? beforeCommit;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    return _runOptimistic(transactionHandler, maxAttempts).timeout(timeout);
  }

  Future<T> _runOptimistic<T>(TransactionHandler<T> handler, int maxAttempts) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      handlerRuns++;
      final tx = _OptimisticTransaction();
      final result = await handler(tx);
      if (beforeCommit != null) await beforeCommit!();
      if (await _serialized(() => _tryCommit(tx))) return result;
      conflicts++;
    }
    exhausted++;
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'aborted',
      message: 'Transaction failed all retries.',
    );
  }

  Future<bool> _tryCommit(_OptimisticTransaction tx) async {
    for (final read in tx.reads.values) {
      if (_fingerprint(await read.ref.get()) != read.fingerprint) return false;
    }
    for (final write in tx.writes) {
      await write();
      committedWrites++;
    }
    return true;
  }

  Future<R> _serialized<R>(Future<R> Function() body) {
    final result = _commitQueue.then((_) => body());
    _commitQueue = result.then((_) {}, onError: (_) {});
    return result;
  }
}

class _TxRead {
  _TxRead(this.ref, this.fingerprint);
  final DocumentReference<Object?> ref;
  final String? fingerprint;
}

class _OptimisticTransaction implements Transaction {
  final reads = <String, _TxRead>{};
  final writes = <Future<void> Function()>[];

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
      DocumentReference<T> documentReference) async {
    if (writes.isNotEmpty) {
      throw StateError(
          'Firestore transactions require all reads to be executed before all writes');
    }
    final snap = await documentReference.get();
    reads.putIfAbsent(
        documentReference.path, () => _TxRead(documentReference, _fingerprint(snap)));
    return snap;
  }

  @override
  Transaction update(DocumentReference documentReference, Map<String, dynamic> data) {
    final copy = Map<String, dynamic>.of(data);
    writes.add(() => documentReference.update(copy));
    return this;
  }

  @override
  Transaction set<T>(DocumentReference<T> documentReference, T data, [SetOptions? options]) {
    writes.add(() => documentReference.set(data, options));
    return this;
  }

  @override
  Transaction delete(DocumentReference documentReference) {
    writes.add(() => documentReference.delete());
    return this;
  }
}

String? _fingerprint(DocumentSnapshot<Object?> snap) => snap.exists
    ? jsonEncode(_canonical(snap.data()), toEncodable: (o) => o.toString())
    : null;

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) k: _canonical(value[k])};
  }
  if (value is List) return [for (final v in value) _canonical(v)];
  return value;
}

class _ResultRow {
  _ResultRow(this.scenario, this.load, this.expected, this.observed, this.verdict);
  final String scenario;
  final String load;
  final String expected;
  final String observed;
  final String verdict;
}

const _validStatuses = {
  'pending',
  'assigned',
  'at_scene',
  'transporting',
  'approaching_er',
  'resolved',
  'cancelled',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final svc = IncidentService();
  final hospitals = HospitalLocationService();
  final logs = <String>[];
  final rows = <_ResultRow>[];
  late OptimisticFakeFirestore db;
  late DebugPrintCallback originalDebugPrint;

  CollectionReference<Map<String, dynamic>> incidents() => db.collection('incident_reports');

  Future<Map<String, dynamic>> docData(String id) async =>
      (await incidents().doc(id).get()).data()!;

  Set<String> unitIdsOf(Map<String, dynamic> data) =>
      ((data['assignedUnitIds'] as List?) ?? const []).map((e) => '$e').toSet();

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> waitUntil(FutureOr<bool> Function() condition, String what) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!await condition()) {
      if (DateTime.now().isAfter(deadline)) fail('รอไม่ถึงเงื่อนไข: $what');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<void> waitForCache(Iterable<String> ids) => waitUntil(() async {
        final cached = (await svc.getLocalIncidents()).map((i) => i.id).toSet();
        return cached.containsAll(ids);
      }, 'cache ในเครื่องได้รับเคสจาก listener');

  LatLng spot(int n) {
    final r = Random(n);
    return LatLng(18.75 + r.nextDouble() * 1.2, 98.9 + r.nextDouble() * 1.0);
  }

  // สร้างรายงานแบบเดียวกับ _submitReport ใน sos_report_screen.dart (ใช้ findNearestHospital จริง)
  IncidentReport sosReport(int n, {required String id}) {
    final at = spot(n);
    final nearest = hospitals.findNearestHospital(at);
    return IncidentReport(
      id: id,
      type: 'อุบัติเหตุทางรถยนต์',
      severity: 'วิกฤต (Code Red - หมดสติ / บาดเจ็บสาหัส)',
      description: 'ผู้ใช้จำลอง #$n',
      latitude: at.latitude,
      longitude: at.longitude,
      province: 'เชียงใหม่',
      address:
          'บริเวณพิกัด ${at.latitude.toStringAsFixed(4)}, ${at.longitude.toStringAsFixed(4)} (เชียงใหม่)',
      reporterName: 'ผู้แจ้งจำลอง $n',
      reporterEmail: 'reporter$n@sim.routealert.test',
      reporterPhone: '081-234-5678',
      status: 'pending',
      targetHospitalId: nearest.profile.hospitalId,
      hospitalName: nearest.profile.hospitalName,
      hospitalLatitude: nearest.profile.latitude,
      hospitalLongitude: nearest.profile.longitude,
      hospitalDistanceKm: nearest.distanceKm,
      eta: '${nearest.etaMinutes} นาที',
      createdAt: DateTime.now(),
    );
  }

  // เคสที่ผู้แจ้ง "เครื่องอื่น" ส่งเข้ามาแล้ว เขียนด้วย toMap() รูปแบบเดียวกับ createIncident
  // (createIncident ทดสอบแยกในกลุ่มแรก และติด cooldown ต่อเครื่องหลังจากนั้น)
  Future<List<IncidentReport>> seedCases(int count, {int from = 0}) async {
    final base = DateTime.now().millisecondsSinceEpoch;
    final seeded = [
      for (var n = from; n < from + count; n++) sosReport(n, id: 'Case #AVCB$base${1000 + n}'),
    ];
    for (final r in seeded) {
      await incidents().doc(r.id).set(r.toMap());
    }
    await waitForCache(seeded.map((r) => r.id));
    return seeded;
  }

  void expectTargetUnchanged(Map<String, dynamic> data, IncidentReport seeded) {
    expect(data['targetHospitalId'], seeded.targetHospitalId);
    expect(data['hospitalName'], seeded.hospitalName);
    expect(data['hospitalLatitude'], seeded.hospitalLatitude);
    expect(data['hospitalLongitude'], seeded.hospitalLongitude);
    expect(data['hospitalDistanceKm'], seeded.hospitalDistanceKm);
    expect(data['eta'], seeded.eta);
  }

  int logCount(String needle) => logs.where((l) => l.contains(needle)).length;

  void record(String scenario, String load, String expected, String observed,
      {String verdict = 'ผ่าน'}) {
    rows.add(_ResultRow(scenario, load, expected, observed, verdict));
    scenarioResult(condition: '$scenario · $load', expected: expected, actual: observed);
  }

  setUpAll(() {
    originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });

  tearDownAll(() {
    debugPrint = originalDebugPrint;
    IncidentService.firestoreOverride = null;
    final out = StringBuffer()
      ..writeln()
      ..writeln('ผลทดสอบหลายผู้ใช้พร้อมกัน: IncidentService จริง + Firestore จำลอง (optimistic transaction)')
      ..writeln('| # | สถานการณ์ | ภาระพร้อมกัน | ผลที่ต้องได้ | ผลที่วัดได้ | สรุป |')
      ..writeln('|---|---|---|---|---|---|');
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      out.writeln(
          '| ${i + 1} | ${r.scenario} | ${r.load} | ${r.expected} | ${r.observed} | ${r.verdict} |');
    }
    // ignore: avoid_print
    print(out.toString());
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    logs.clear();
    db = OptimisticFakeFirestore();
    IncidentService.firestoreOverride = db;
    // เหมือนแอปจริง: ทุกเครื่องฟัง incident_reports ทั้ง collection แล้วเก็บลง cache
    await svc.initialize();
    await settle();
  });

  tearDown(settle);

  group('ผู้แจ้งเหตุหลายคนส่ง SOS พร้อมกัน', () {
    test('[S01][S02] 20 คนส่งพร้อมกัน: บันทึกครบ id ไม่ซ้ำ ส่งถึง รพ. ใกล้สุด และ cooldown ยังกันต่อเครื่อง',
        () async {
      // IncidentService เป็น singleton (1 เครื่องต่อโปรเซส) และไม่มี hook รีเซ็ต cooldown
      // ด่าน cooldown ถูกเช็คก่อน await แรกของ createIncident คำขอ 20 รายการที่ยิงในรอบ
      // event loop เดียวจึงผ่านด่านทั้งหมด ได้ผลเท่ากับผู้แจ้ง 20 คนบน 20 เครื่องที่ยังไม่เคยแจ้ง
      expect(svc.remainingCooldownSeconds, 0,
          reason: 'เทสต์นี้ต้องรันก่อนเทสต์อื่นที่แตะ cooldown (รันไฟล์นี้ตามลำดับปกติ)');

      const reporters = 20;
      // ms เดียวกันทุกคน = กรณีเลวร้ายที่สุดของรูปแบบ id ในแอป ส่วนเลขท้ายไม่ซ้ำกัน
      final ms = DateTime.now().millisecondsSinceEpoch;
      final reports = [
        for (var n = 0; n < reporters; n++) sosReport(n, id: 'Case #AVCB$ms${1000 + n}'),
      ];

      final results = await Future.wait(reports.map(svc.createIncident));
      expect(results.map((r) => r['success']), everyElement(isTrue), reason: '$results');
      expect(results.map((r) => r['message']),
          everyElement('ส่งรายงานเหตุฉุกเฉินเรียบร้อยแล้ว'));

      final snap = await incidents().get();
      expect(snap.docs.length, reporters);
      expect(snap.docs.map((d) => d.id).toSet(), reports.map((r) => r.id).toSet());

      final perHospital = <String, int>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        expect(data['id'], doc.id, reason: 'listener ของแอปอ่านฟิลด์ id ไม่ใช่ doc.id');
        final stored = IncidentReport.fromMap(data);
        final sent = reports.singleWhere((r) => r.id == doc.id);
        expect(stored.reporterEmail, sent.reporterEmail);
        expect(stored.status, 'pending');
        expect(stored.statusStep, 0);
        expect(stored.assignedAmbulanceId, isNull);
        expect(DateTime.tryParse(data['createdAt'] as String), isNotNull);
        expect(stored.targetHospitalId, sent.targetHospitalId);
        expect(stored.hospitalName, sent.hospitalName);
        expect(stored.eta, sent.eta);
        // ตรวจกฎเลือก รพ. แยกอีกชั้น: ระยะเป็นกิโลเมตรเต็ม และไม่มี รพ. ไหนใกล้กว่า
        final km = stored.hospitalDistanceKm!;
        expect(km, km.roundToDouble());
        final at = LatLng(stored.latitude, stored.longitude);
        for (final h in hospitals.allHospitals) {
          expect(km <= HospitalLocationService.calculateDistanceKm(at, h.location), isTrue,
              reason: '${doc.id} ถูกส่งไป ${stored.targetHospitalId} แต่ ${h.hospitalId} ใกล้กว่า');
        }
        perHospital.update(stored.targetHospitalId!, (v) => v + 1, ifAbsent: () => 1);
      }
      record(
        'ผู้แจ้ง 20 คนส่ง SOS พร้อมกัน (createIncident)',
        '20 คำขอ',
        'บันทึกครบ 20 เอกสาร, id ไม่ซ้ำ, ฟิลด์ รพ. ตรงกับที่คำนวณตอนแจ้ง',
        'บันทึก ${snap.docs.length}/$reporters, แยกตาม รพ. '
            '${(perHospital.keys.toList()..sort()).map((k) => '$k=${perHospital[k]}').join(' ')}',
      );

      // เครื่องเดิมกดแจ้งซ้ำทันที ต้องติด cooldown และไม่เขียนอะไรเลย
      final remaining = svc.remainingCooldownSeconds;
      expect(remaining, inInclusiveRange(110, 120));
      final again =
          await svc.createIncident(sosReport(reporters, id: 'Case #AVCB$ms${1000 + reporters}'));
      expect(again['success'], isFalse);
      expect(again['message'], contains('ป้องกันสแปม'));
      expect((await incidents().get()).docs.length, reporters);

      // ผู้แจ้งยกเลิกเคสตัวเองที่ยังรออยู่ แล้ว cooldown ต้องลดเหลือไม่เกิน 8 วินาที
      expect(await svc.cancelIncident(reports.first.id, reason: 'แจ้งผิด'), isTrue);
      final cancelled = await docData(reports.first.id);
      expect(cancelled['status'], 'cancelled');
      expect(cancelled['cancelReason'], 'แจ้งผิด');
      expect(cancelled['cancelledBy'], 'reporter');
      expect(DateTime.tryParse(cancelled['cancelledAt'] as String), isNotNull);
      final afterCancel = svc.remainingCooldownSeconds;
      expect(afterCancel, inInclusiveRange(1, 8));
      record(
        'Cooldown กันสแปมต่อเครื่อง',
        'เครื่องเดิมส่งซ้ำทันที แล้วยกเลิกเคสตัวเอง',
        'ส่งซ้ำถูกปฏิเสธและไม่เขียน, หลังยกเลิก cooldown ลดเหลือ ≤ 8 วิ',
        'ถูกปฏิเสธ (เหลือ $remaining วิ), เอกสารยังเป็น $reporters, หลังยกเลิกเหลือ $afterCancel วิ',
      );
    });
  });

  group('แจ้งเหตุตอนเชื่อมต่อไม่ได้', () {
    test('[S04] เซิร์ฟเวอร์ไม่รับตอนแจ้งเหตุ: แอปบอกว่าไม่สำเร็จ ไม่ติด cooldown และส่งใหม่ได้ทันที', () async {
      svc.debugResetCooldown();
      // Firestore ที่ปฏิเสธทุกการเขียน = เน็ตหลุด/เซิร์ฟเวอร์ไม่รับ ในมุมของแอป
      final offline = FakeFirebaseFirestore(securityRules: '''
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} { allow read, write: if false; }
  }
}''');
      final ms = DateTime.now().millisecondsSinceEpoch;
      IncidentService.firestoreOverride = offline;
      final Map<String, dynamic> failed;
      try {
        failed = await svc.createIncident(sosReport(701, id: 'Case #AVCB${ms}7010'));
      } finally {
        IncidentService.firestoreOverride = db;
      }
      expect(failed['success'], isFalse, reason: 'ต้องไม่บอกผู้แจ้งว่าส่งแล้วทั้งที่ศูนย์ไม่ได้รับ');
      expect(failed['message'], contains('ส่งไปยังศูนย์ไม่สำเร็จ'));
      expect(svc.remainingCooldownSeconds, 0, reason: 'ส่งไม่ถึงศูนย์ = ยังไม่นับเป็นการแจ้ง');

      final retry = await svc.createIncident(sosReport(701, id: 'Case #AVCB${ms}7011'));
      expect(retry['success'], isTrue);
      expect((await incidents().doc('Case #AVCB${ms}7011').get()).exists, isTrue);
      expect(svc.remainingCooldownSeconds, greaterThan(100), reason: 'ส่งสำเร็จแล้วค่อยเริ่ม cooldown');
      svc.debugResetCooldown();

      record(
        'S04 แจ้งเหตุตอนเซิร์ฟเวอร์ไม่รับ',
        'Firestore ปฏิเสธการเขียน แล้วกดส่งใหม่',
        'แอปบอกว่าไม่สำเร็จ, ไม่ติด cooldown, ส่งใหม่ได้ทันที',
        'ครั้งแรก success=false, cooldown 0 วิ, ส่งใหม่สำเร็จและบันทึกจริง (เดิมติด cooldown 2 นาที)',
      );
    });
  });

  group('รถพยาบาลและโรงพยาบาลแย่งรับเคสเดียวกัน', () {
    // เคสเดียวรับได้หลายคัน: สิ่งที่ต้องพิสูจน์ไม่ใช่ "ผู้ชนะคนเดียว" แล้ว แต่คือ ไม่มีการเขียนทับกัน
    // (ทุกคันที่แอปบอกว่าสำเร็จต้องอยู่ในเอกสารจริง และคันที่บอกว่าไม่สำเร็จต้องไม่อยู่) และนับจำนวนคันถูก
    test('[S09] รถ 10 คันกดรับเคสเดียวกันพร้อมกัน × 8 เคส: ทุกคันที่สำเร็จอยู่ในเคสจริง ไม่มีใครถูกเขียนทับ',
        () async {
      const cases = 8;
      const perCase = 10;
      final seeded = await seedCases(cases);
      String unitFor(int c, int a) => 'AMB-${1000 + c * perCase + a}';
      String plateOf(String unit) => 'กข ${unit.substring(4)}';

      final calls = <(int, String)>[];
      final futures = <Future<bool>>[];
      for (var a = 0; a < perCase; a++) {
        for (var c = 0; c < cases; c++) {
          final unit = unitFor(c, a);
          calls.add((c, unit));
          futures.add(svc.acceptIncidentByAmbulance(
              id: seeded[c].id, ambulancePlate: plateOf(unit), ambulanceId: unit));
        }
      }
      final outcomes = await Future.wait(futures);

      final joined = <int, Set<String>>{};
      final failed = <int, List<String>>{};
      for (var c = 0; c < cases; c++) {
        joined[c] = {
          for (var i = 0; i < calls.length; i++)
            if (calls[i].$1 == c && outcomes[i]) calls[i].$2,
        };
        failed[c] = [
          for (var i = 0; i < calls.length; i++)
            if (calls[i].$1 == c && !outcomes[i]) calls[i].$2,
        ];
        final data = await docData(seeded[c].id);
        expect(joined[c], isNotEmpty);
        expect(unitIdsOf(data), joined[c], reason: 'เคส ${seeded[c].id}: สำเร็จ = อยู่ในเอกสาร');
        expect(data['assignedVehicleCount'], joined[c]!.length);
        final first = (data['assignedUnits'] as List).first as Map;
        expect(data['assignedAmbulanceId'], first['unitId'], reason: 'คันหลัก = คันแรกที่เข้าเคส');
        expect(data['status'], 'assigned');
        expect(data['statusStep'], 1);
        expect(data['assignedBy'], 'ambulance');
        expect(data['assignedAmbulanceCallSign'], 'กู้ชีพ ${plateOf('${first['unitId']}')}');
        expectTargetUnchanged(data, seeded[c]);
      }
      final totalJoined = joined.values.fold<int>(0, (n, s) => n + s.length);
      final totalFailed = cases * perCase - totalJoined;
      // คันที่ไม่สำเร็จ = transaction ชนจนครบ 5 รอบ แอปตอบ false (ไม่อ้างว่าสำเร็จ) กดใหม่ได้
      expect(db.exhausted, totalFailed);

      // กดซ้ำ = สำเร็จโดยไม่เขียน, คันที่พลาดกดใหม่ = เข้าเคสได้
      final writesBefore = db.committedWrites;
      for (var c = 0; c < cases; c++) {
        final w = joined[c]!.first;
        expect(await svc.acceptIncidentByAmbulance(
            id: seeded[c].id, ambulancePlate: plateOf(w), ambulanceId: w), isTrue);
      }
      expect(db.committedWrites, writesBefore);
      var retried = 0;
      for (var c = 0; c < cases; c++) {
        for (final u in failed[c]!) {
          expect(await svc.acceptIncidentByAmbulance(
              id: seeded[c].id, ambulancePlate: plateOf(u), ambulanceId: u), isTrue);
          retried++;
        }
        expect((await docData(seeded[c].id))['assignedVehicleCount'], perCase);
      }

      record(
        'รถหลายคันกด "รับเคส" เคสเดียวกันพร้อมกัน (เคสเดียวรับได้หลายคัน)',
        '$cases เคส × $perCase คัน = ${cases * perCase} transaction พร้อมกัน',
        'ทุกคันที่สำเร็จอยู่ในเคสจริง, นับจำนวนคันถูก, กดซ้ำไม่เขียน, คันที่พลาดกดใหม่ได้',
        'สำเร็จรอบแรก $totalJoined คัน (อยู่ในเอกสารครบ เขียนทับ 0), ชนจน retry ครบ $totalFailed คัน '
            '→ แอปตอบ false, กดใหม่สำเร็จ $retried/$retried, สุดท้ายเคสละ $perCase คัน',
      );
    });

    test('[S09][S08] รพ. สั่งจ่ายคันแรกแข่งกับรถกดรับเอง: รพ. ไม่ส่งซ้อนถ้ามีรถแล้ว, ไม่มีการเขียนทับ, ข้าม รพ. แค่ log',
        () async {
      const cases = 6;
      const hospitalCalls = 3;
      const selfCalls = 5;
      final seeded = await seedCases(cases, from: 100);

      final kinds = <(int, String, bool, String)>[]; // (case, unit, isHospital, callingHospital)
      final futures = <Future<bool>>[];
      var crossHospitalCalls = 0;
      for (var c = 0; c < cases; c++) {
        final rng = Random(c);
        final order = [
          for (var h = 0; h < hospitalCalls; h++) (true, h),
          for (var a = 0; a < selfCalls; a++) (false, a),
        ]..shuffle(rng);
        for (final (isHospital, k) in order) {
          final unit = isHospital ? 'AMB-2$c$k' : 'AMB-3$c$k';
          final calling = 'HOSP-0${k + 1}';
          if (isHospital && calling != seeded[c].targetHospitalId) crossHospitalCalls++;
          kinds.add((c, unit, isHospital, calling));
          final delay = Duration(milliseconds: rng.nextInt(3));
          futures.add(Future<void>.delayed(delay).then((_) => isHospital
              // ปุ่ม "ส่งรถพยาบาล" ของ รพ. = คันแรกเท่านั้น (ส่งเพิ่มเป็นอีกปุ่ม)
              ? svc.dispatchIncidentByHospital(
                  id: seeded[c].id,
                  ambulanceId: unit,
                  ambulancePlate: 'กข ${unit.substring(4)}',
                  ambulanceCallSign: 'หน่วยกู้ชีพ $unit',
                  callingHospitalId: calling,
                  onlyIfUnassigned: true,
                )
              : svc.acceptIncidentByAmbulance(
                  id: seeded[c].id,
                  ambulancePlate: 'กข ${unit.substring(4)}',
                  ambulanceId: unit,
                )));
        }
      }
      final outcomes = await Future.wait(futures);

      var hospitalFirst = 0;
      for (var c = 0; c < cases; c++) {
        final won = [
          for (var i = 0; i < kinds.length; i++)
            if (kinds[i].$1 == c && outcomes[i]) kinds[i],
        ];
        final data = await docData(seeded[c].id);
        expect(unitIdsOf(data), won.map((w) => w.$2).toSet());
        final hospitalWins = won.where((w) => w.$3).toList();
        expect(hospitalWins.length, lessThanOrEqualTo(1), reason: 'รพ. ส่งคันแรกได้ครั้งเดียว');
        final primary = data['assignedAmbulanceId'];
        if (hospitalWins.isNotEmpty) {
          expect(primary, hospitalWins.single.$2, reason: 'รพ. สำเร็จได้เฉพาะตอนเคสยังว่าง');
          expect(data['assignedBy'], 'hospital');
          expect(data['assignedAmbulanceCallSign'], 'หน่วยกู้ชีพ $primary');
          hospitalFirst++;
        } else {
          expect(data['assignedBy'], 'ambulance');
        }
        expectTargetUnchanged(data, seeded[c]);

        // มาช้ากว่า: รพ. (คันแรก) ได้ "มีรถแล้ว" ไม่เขียน, รถกดรับเอง = ร่วมเคสเพิ่ม 1 คัน
        final before = await docData(seeded[c].id);
        final late = await svc.assignAmbulance(
          id: seeded[c].id,
          ambulanceId: 'AMB-4${c}00',
          ambulancePlate: 'กข 4${c}00',
          callingHospitalId: seeded[c].targetHospitalId,
          onlyIfUnassigned: true,
        );
        expect(late.outcome, DispatchOutcome.alreadyHasVehicles);
        expect(await docData(seeded[c].id), before);
        final join = await svc.assignAmbulance(
            id: seeded[c].id, ambulanceId: 'AMB-4${c}01', ambulancePlate: 'กข 4${c}01',
            selfAccepted: true);
        expect(join.outcome, DispatchOutcome.joined);
        final after = await docData(seeded[c].id);
        expect(after['assignedVehicleCount'], (before['assignedVehicleCount'] as int) + 1);
        expect(after['assignedAmbulanceId'], before['assignedAmbulanceId'], reason: 'คันหลักไม่เปลี่ยน');
      }
      // สั่งจ่ายข้าม รพ. ไม่ถูกบล็อก แค่ log เตือน (ตามที่ออกแบบไว้)
      expect(logCount('ไม่บล็อก แค่แจ้งเตือน'), crossHospitalCalls);

      record(
        'รพ. สั่งจ่ายคันแรก แข่งกับรถกดรับเอง',
        '$cases เคส × ${hospitalCalls + selfCalls} ผู้แข่ง (รพ. $hospitalCalls + รถ $selfCalls)',
        'รพ. สำเร็จได้เฉพาะตอนเคสยังไม่มีรถ, ทุกคันที่สำเร็จอยู่ในเอกสาร, คันหลักไม่เปลี่ยน',
        'รพ. ได้คันแรก $hospitalFirst เคส รถได้คันแรก ${cases - hospitalFirst} เคส, เขียนทับ 0, '
            'รพ. มาช้าได้ "มีรถแล้ว", รถมาช้าร่วมเคสได้, สั่งข้าม รพ. $crossHospitalCalls ครั้ง = log เตือน',
      );
    });

    test('[S09] สเกล 50 เคส ผู้แข่ง 2-12 รายต่อเคส (ผสม รพ./รถ) พร้อมกัน: ไม่มีการเขียนทับ นับคันถูกทุกเคส',
        () async {
      const cases = 50;
      final seeded = await seedCases(cases, from: 200);
      final rng = Random(2026);
      final kinds = <(int, String, bool)>[];
      final futures = <Future<bool>>[];
      for (var c = 0; c < cases; c++) {
        final contenders = 2 + rng.nextInt(11);
        for (var k = 0; k < contenders; k++) {
          final isHospital = rng.nextDouble() < 0.4;
          final unit = 'AMB-${5000 + c * 20 + k}';
          kinds.add((c, unit, isHospital));
          final delay = Duration(milliseconds: rng.nextInt(4));
          futures.add(Future<void>.delayed(delay).then((_) => isHospital
              ? svc.dispatchIncidentByHospital(
                  id: seeded[c].id,
                  ambulanceId: unit,
                  ambulancePlate: 'กข ${unit.substring(4)}',
                  ambulanceCallSign: 'หน่วยกู้ชีพ $unit',
                  callingHospitalId: seeded[c].targetHospitalId,
                  onlyIfUnassigned: true,
                )
              : svc.acceptIncidentByAmbulance(
                  id: seeded[c].id,
                  ambulancePlate: 'กข ${unit.substring(4)}',
                  ambulanceId: unit,
                )));
        }
      }
      final outcomes = await Future.wait(futures);

      var vehicles = 0;
      for (var c = 0; c < cases; c++) {
        final won = [
          for (var i = 0; i < kinds.length; i++)
            if (kinds[i].$1 == c && outcomes[i]) kinds[i],
        ];
        final data = await docData(seeded[c].id);
        expect(won, isNotEmpty, reason: 'เคส ${seeded[c].id}');
        expect(unitIdsOf(data), won.map((w) => w.$2).toSet(), reason: 'เคส ${seeded[c].id}');
        expect(data['assignedVehicleCount'], won.length);
        expect(won.where((w) => w.$3).length, lessThanOrEqualTo(1));
        expect(data['status'], 'assigned');
        expectTargetUnchanged(data, seeded[c]);
        vehicles += won.length;
      }

      record(
        'สเกล: หลายเคสพร้อมกัน ผู้แข่งสุ่ม 2-12 รายต่อเคส',
        '${kinds.length} transaction พร้อมกันบน $cases เคส',
        'ทุกเคสมีรถ, สำเร็จ = อยู่ในเอกสาร, นับคันถูก, รพ. ไม่ส่งซ้อนคันแรก',
        'รถเข้าเคสรวม $vehicles คันใน $cases เคส, handler รันรวม ${db.handlerRuns} ครั้ง '
            '(retry จากการชน ${db.conflicts}), เขียนทับ 0',
      );
    });

    test('[S09] แย่งกันหนักจน retry ครบ 5 ครั้ง: แอปตอบ false ไม่อ้างว่าสำเร็จ และเคสยังรับต่อได้',
        () async {
      final seeded = (await seedCases(1, from: 300)).single;
      var erReady = false;
      // agency กด "เตรียม ER" แทรกระหว่างอ่านกับ commit ทุกรอบ (เมธอดจริงของแอป)
      db.beforeCommit = () async {
        erReady = !erReady;
        await svc.setErPrepared(seeded.id, erReady);
      };
      Future<bool> dispatch() => svc.dispatchIncidentByHospital(
            id: seeded.id,
            ambulanceId: 'AMB-3001',
            ambulancePlate: 'กข 3001',
            ambulanceCallSign: 'หน่วยกู้ชีพ AMB-3001',
            callingHospitalId: seeded.targetHospitalId,
          );

      expect(await dispatch(), isFalse);
      final runsWhenExhausted = db.handlerRuns;
      expect(runsWhenExhausted, 5, reason: 'แอปใช้ maxAttempts ค่าเริ่มต้น 5');
      expect(db.exhausted, 1);
      final data = await docData(seeded.id);
      expect(data['status'], 'pending');
      expect(data['assignedAmbulanceId'], isNull);

      db.beforeCommit = null;
      expect(await dispatch(), isTrue);
      expect((await docData(seeded.id))['assignedAmbulanceId'], 'AMB-3001');

      record(
        'Transaction ชนจนครบ 5 รอบ (จำลอง agency เขียนแทรกทุกรอบ)',
        '1 dispatch + การเขียนแทรก 5 ครั้ง',
        'แอปตอบ false, ไม่มีการมอบหมายครึ่งๆ กลางๆ, ลองใหม่ได้',
        'handler รัน $runsWhenExhausted รอบแล้วตอบ false, เคสยัง pending, ลองใหม่สำเร็จ',
      );
    });
  });

  group('สถานะรถว่าง/ไม่ว่าง', () {
    test('[S10] getBusyAmbulanceIds / unitHasOpenCase สะท้อนเคสค้าง และคืนรถเมื่อจบหรือถูกปิดเคส',
        () async {
      final seeded = await seedCases(3, from: 400);
      final (a, b, c) = (seeded[0], seeded[1], seeded[2]);

      final assigned = await Future.wait([
        svc.acceptIncidentByAmbulance(id: a.id, ambulancePlate: 'กข 0001', ambulanceId: 'AMB-0001'),
        svc.dispatchIncidentByHospital(
          id: b.id,
          ambulanceId: 'AMB-0002',
          ambulancePlate: 'กข 0002',
          ambulanceCallSign: 'หน่วยกู้ชีพ AMB-0002',
          callingHospitalId: b.targetHospitalId,
        ),
      ]);
      expect(assigned, [true, true]);
      await waitUntil(() async => setEquals(await svc.getBusyAmbulanceIds(), {'AMB-0001', 'AMB-0002'}),
          'busy = AMB-0001, AMB-0002');
      expect(await svc.unitHasOpenCase('AMB-0001'), isTrue);
      expect(await svc.unitHasOpenCase('AMB-0002'), isTrue);
      expect(await svc.unitHasOpenCase('AMB-0003'), isFalse);
      expect(await svc.unitHasOpenCase(''), isFalse);

      // AMB-0001 จบงาน, รพ. ปิดเคสของ AMB-0002 → ว่างทั้งคู่
      expect(await svc.reportAmbulanceAtScene(a.id), isTrue);
      expect(await svc.reportAmbulanceTransporting(a.id), isTrue);
      expect(await svc.resolveIncident(a.id), isTrue);
      expect(await svc.closeIncidentByHospital(b.id, reason: 'โรงพยาบาลปิดเคส'), isTrue);
      await waitUntil(() async => (await svc.getBusyAmbulanceIds()).isEmpty, 'busy ว่าง');
      expect(await svc.unitHasOpenCase('AMB-0001'), isFalse);
      expect(await svc.unitHasOpenCase('AMB-0002'), isFalse);

      // รถที่ว่างแล้วรับเคสใหม่ได้
      expect(await svc.acceptIncidentByAmbulance(
          id: c.id, ambulancePlate: 'กข 0001', ambulanceId: 'AMB-0001'), isTrue);
      await waitUntil(() async => setEquals(await svc.getBusyAmbulanceIds(), {'AMB-0001'}),
          'busy = AMB-0001');

      record(
        'สถานะรถไม่ว่าง (getBusyAmbulanceIds / unitHasOpenCase)',
        'รถ 2 คันรับ 2 เคสพร้อมกัน แล้วจบ/ปิดเคส',
        'รถที่มีเคสเปิด = ไม่ว่าง, จบหรือปิดเคสแล้ว = ว่างและรับเคสใหม่ได้',
        'ไม่ว่าง {AMB-0001, AMB-0002} → ว่างทั้งหมด → AMB-0001 รับเคสใหม่ได้',
      );
    });
  });

  group('วงจรเคสพร้อมกันหลายคัน', () {
    test('[S15] รถ 20 คันเดินงานพร้อมกัน 20 เคส: ขั้นไม่ถอยหลัง ผู้แจ้งเห็นจนถึง resolved', () async {
      const missions = 20;
      final seeded = await seedCases(missions, from: 500);
      final seen = <String, List<(String, int)>>{};
      final subs = <StreamSubscription>[];
      for (final r in seeded) {
        seen[r.id] = [];
        // ผู้แจ้งแต่ละคนฟังเอกสารของตัวเองแยกกัน
        subs.add(incidents().doc(r.id).snapshots().listen((s) {
          final d = s.data();
          if (d != null) seen[r.id]!.add((d['status'] as String, d['statusStep'] as int));
        }));
      }
      await settle();

      Future<void> runMission(int i) async {
        final r = seeded[i];
        final unit = 'AMB-${6000 + i}';
        final rng = Random(i);
        Future<void> jitter() => Future<void>.delayed(Duration(milliseconds: rng.nextInt(3)));
        expect(await svc.dispatchIncidentByHospital(
          id: r.id,
          ambulanceId: unit,
          ambulancePlate: 'กข ${6000 + i}',
          ambulanceCallSign: 'หน่วยกู้ชีพ $unit',
          callingHospitalId: r.targetHospitalId,
        ), isTrue);
        await jitter();
        await svc.updateAmbulanceEta(r.id, etaMinutes: 7, distanceMeters: 4200, target: 'scene');
        await jitter();
        expect(await svc.markAmbulanceNearScene(r.id, etaMinutes: 1), isTrue);
        await jitter();
        expect(await svc.reportAmbulanceAtScene(r.id), isTrue);
        await jitter();
        expect(await svc.reportAmbulanceTransporting(r.id), isTrue);
        await svc.updateAmbulanceEta(r.id, etaMinutes: 5, distanceMeters: 2500, target: 'hospital');
        await jitter();
        expect(await svc.reportAmbulanceApproachingHospital(r.id), isTrue);
        await jitter();
        expect(await svc.resolveIncident(r.id), isTrue);
      }

      await Future.wait([for (var i = 0; i < missions; i++) runMission(i)]);
      await settle();
      for (final s in subs) {
        await s.cancel();
      }

      var observedUpdates = 0;
      for (var i = 0; i < missions; i++) {
        final r = seeded[i];
        final data = await docData(r.id);
        expect(data['status'], 'resolved');
        expect(data['statusStep'], 5);
        expect(data['assignedAmbulanceId'], 'AMB-${6000 + i}');
        expect(data['ambulanceEtaTarget'], 'hospital');
        expect(data['ambulanceEtaMinutes'], 5);
        final etaAt = data['ambulanceEtaUpdatedAt'] as String;
        expect(etaAt.endsWith('Z'), isTrue, reason: 'ETA ใช้เวลา UTC');
        expect(DateTime.tryParse(etaAt), isNotNull);
        expect(DateTime.tryParse(data['ambulanceNearSceneAt'] as String), isNotNull);
        expect(data['ambulanceNearEtaMinutes'], 1);
        expectTargetUnchanged(data, r);

        final steps = seen[r.id]!;
        observedUpdates += steps.length;
        expect(steps.last, ('resolved', 5));
        for (var k = 1; k < steps.length; k++) {
          expect(steps[k].$2 >= steps[k - 1].$2, isTrue,
              reason: '${r.id}: statusStep ถอยหลัง ${steps[k - 1]} → ${steps[k]}');
        }
        expect(steps.every((s) => _validStatuses.contains(s.$1)), isTrue);
      }
      await waitUntil(() async => (await svc.getBusyAmbulanceIds()).isEmpty, 'รถว่างทั้งหมด');

      record(
        'วงจรเคสครบทุกขั้นพร้อมกัน (dispatch → ETA → ใกล้ถึง → ถึงที่เกิดเหตุ → นำส่ง → ใกล้ รพ. → จบ)',
        '$missions คัน × 8 การเขียน = ${missions * 8} การเขียนสลับกัน',
        'ทุกเคสจบที่ (resolved, 5), ขั้นไม่ถอยหลัง, หน่วยรถไม่เปลี่ยน, ฟิลด์ รพ. ไม่เปลี่ยน',
        '$missions/$missions เคส resolved, ผู้แจ้งเห็นอัปเดต $observedUpdates ครั้ง ถอยหลัง 0, '
            'รถว่างครบหลังจบงาน',
      );
    });

    test('[G16][S15] markAmbulanceNearScene เรียกซ้ำไม่เขียนทับ (กันด้วย cache ในเครื่อง)', () async {
      final r = (await seedCases(1, from: 600)).single;
      expect(await svc.dispatchIncidentByHospital(
        id: r.id,
        ambulanceId: 'AMB-6601',
        ambulancePlate: 'กข 6601',
        callingHospitalId: r.targetHospitalId,
      ), isTrue);
      await waitUntil(() async => (await svc.getIncidentById(r.id))?.assignedAmbulanceId == 'AMB-6601',
          'cache เห็นการมอบหมาย');

      expect(await svc.markAmbulanceNearScene(r.id, etaMinutes: 0), isTrue);
      final first = await docData(r.id);
      expect(first['ambulanceNearEtaMinutes'], 1, reason: 'ETA ต่ำสุดถูกปัดเป็น 1 นาที');
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(await svc.markAmbulanceNearScene(r.id, etaMinutes: 9), isTrue);
      final second = await docData(r.id);
      expect(second['ambulanceNearSceneAt'], first['ambulanceNearSceneAt']);
      expect(second['ambulanceNearEtaMinutes'], 1);

      record(
        'แจ้ง "รถใกล้ถึง" ซ้ำ (markAmbulanceNearScene)',
        'เรียก 2 ครั้งจากเครื่องเดียวกัน',
        'บันทึกครั้งเดียว ครั้งที่ 2 ไม่เขียนทับ',
        'เวลา/ETA ยังเป็นค่าครั้งแรก',
      );
    });

    test('[S17] รพ. ปิดเคสได้ทุกสถานะ: cancelled + cancelledBy hospital, รถว่าง, สั่งจ่ายซ้ำไม่ได้', () async {
      final seeded = await seedCases(4, from: 700);
      final (p, a, s, done) = (seeded[0], seeded[1], seeded[2], seeded[3]);
      Future<bool> dispatch(IncidentReport r, String unit) => svc.dispatchIncidentByHospital(
            id: r.id,
            ambulanceId: unit,
            ambulancePlate: 'กข ${unit.substring(4)}',
            ambulanceCallSign: 'หน่วยกู้ชีพ $unit',
            callingHospitalId: r.targetHospitalId,
          );
      expect(await dispatch(a, 'AMB-7001'), isTrue);
      expect(await dispatch(s, 'AMB-7002'), isTrue);
      expect(await svc.reportAmbulanceAtScene(s.id), isTrue);
      expect(await dispatch(done, 'AMB-7003'), isTrue);
      expect(await svc.resolveIncident(done.id), isTrue);

      final closed = await Future.wait([
        for (final r in [p, a, s]) svc.closeIncidentByHospital(r.id, reason: 'โรงพยาบาลปิดเคส'),
      ]);
      expect(closed, [true, true, true]);

      final expectations = {p.id: (0, null), a.id: (1, 'AMB-7001'), s.id: (2, 'AMB-7002')};
      for (final MapEntry(key: id, value: (step, unit)) in expectations.entries) {
        final data = await docData(id);
        expect(data['status'], 'cancelled');
        expect(data['cancelledBy'], 'hospital');
        expect(data['cancelReason'], 'โรงพยาบาลปิดเคส');
        final at = data['cancelledAt'] as String;
        expect(DateTime.tryParse(at), isNotNull);
        expect(at.endsWith('Z'), isFalse, reason: 'แอปเก็บเวลาท้องถิ่นไม่มี offset');
        expect(data['statusStep'], step, reason: 'ปิดเคสไม่แตะ statusStep');
        expect(data['assignedAmbulanceId'], unit, reason: 'ปิดเคสไม่แตะการมอบหมาย');
      }
      await waitUntil(() async => (await svc.getBusyAmbulanceIds()).isEmpty, 'รถว่างหลังปิดเคส');
      expect(await svc.unitHasOpenCase('AMB-7001'), isFalse);
      expect(await svc.unitHasOpenCase('AMB-7002'), isFalse);

      // เคสที่ปิดหรือจบแล้วต้องมอบหมายใหม่ไม่ได้ ทั้งจาก รพ. และจากรถ
      for (final r in [p, a, s, done]) {
        final before = await docData(r.id);
        expect(await dispatch(r, 'AMB-7999'), isFalse, reason: r.id);
        expect(await svc.acceptIncidentByAmbulance(
            id: r.id, ambulancePlate: 'กข 7998', ambulanceId: 'AMB-7998'), isFalse);
        expect(await docData(r.id), before);
      }

      // ผู้แจ้งยกเลิกเองได้เฉพาะ (pending, 0) ตาม cache ในเครื่อง — เคสนี้มีรถรับแล้ว
      final other = (await seedCases(1, from: 750)).single;
      expect(await dispatch(other, 'AMB-7501'), isTrue);
      await waitUntil(() async => (await svc.getIncidentById(other.id))?.status == 'assigned',
          'cache เห็นว่ามีรถรับแล้ว');
      final beforeCancel = await docData(other.id);
      expect(await svc.cancelIncident(other.id, reason: 'ไม่รอแล้ว'), isFalse);
      expect(await docData(other.id), beforeCancel);

      record(
        'โรงพยาบาลปิดเคส (closeIncidentByHospital) + สั่งจ่ายหลังปิด',
        'ปิด 3 เคสพร้อมกัน (pending/assigned/at_scene) แล้วลองสั่งจ่ายซ้ำ',
        'cancelled + cancelledBy=hospital, รถว่าง, เคสที่จบ/ปิดแล้วสั่งจ่ายไม่ได้',
        'ปิดครบ 3/3 statusStep เดิม, รถว่าง, สั่งจ่ายซ้ำ 8/8 ครั้งได้ false, '
            'ผู้แจ้งยกเลิกเคสที่มีรถรับแล้วถูกปฏิเสธ',
      );
    });
  });

  group('จุดเสี่ยงที่แก้แล้ว (เดิมเกิดจริง — ดูผลการทดสอบหลายผู้ใช้)', () {
    test('[S10] รพ. 2 แห่งส่งรถคันเดียวกันไปคนละเคสพร้อมกัน: ได้เคสเดียว (ล็อกรถใน transaction)', () async {
      final seeded = await seedCases(2, from: 800);
      // ทั้งสองฝั่งเห็นรถคันนี้ว่างจาก cache ในเครื่อง ณ ตอนที่กด
      expect(await svc.getBusyAmbulanceIds(), isNot(contains('AMB-8001')));
      final results = await Future.wait([
        for (final r in seeded)
          svc.assignAmbulance(
            id: r.id,
            ambulanceId: 'AMB-8001',
            ambulancePlate: 'กข 8001',
            ambulanceCallSign: 'หน่วยกู้ชีพ AMB-8001',
            callingHospitalId: r.targetHospitalId,
            onlyIfUnassigned: true,
          ),
      ]);
      final outcomes = results.map((r) => r.outcome).toList();
      expect(outcomes.where((o) => o == DispatchOutcome.assigned).length, 1);
      expect(outcomes.where((o) => o == DispatchOutcome.vehicleBusy).length, 1);
      final loser = seeded[outcomes.indexOf(DispatchOutcome.vehicleBusy)];
      final winner = seeded[outcomes.indexOf(DispatchOutcome.assigned)];
      expect(results[outcomes.indexOf(DispatchOutcome.vehicleBusy)].busyCaseId, winner.id);
      final lost = await docData(loser.id);
      expect(lost['status'], 'pending');
      expect(lost['assignedAmbulanceId'], isNull);
      // เคสที่ไม่ได้รถยังส่งคันอื่นได้ตามปกติ
      expect(await svc.dispatchIncidentByHospital(
          id: loser.id, ambulanceId: 'AMB-8002', ambulancePlate: 'กข 8002', onlyIfUnassigned: true), isTrue);

      record(
        'แก้แล้ว: รถคันเดียวถูกส่งไป 2 เคสพร้อมกัน',
        '2 รพ. เลือกรถว่างคันเดียวกันพร้อมกัน',
        'รถ 1 คันมีเคสเปิดได้ 1 เคส',
        'สำเร็จ 1 เคส อีกเคสได้ "รถไม่ว่าง" และยังเป็น pending ส่งคันอื่นได้ '
            '(เดิมสำเร็จทั้งสอง — transaction ล็อกแค่เอกสารเคส)',
      );
    });

    test('[S17] รพ. ปิดเคสแล้ว การเลื่อนสถานะของรถที่ค้างอยู่ลงมาทีหลังไม่ทำให้เคสกลับมาเปิด', () async {
      final r = (await seedCases(1, from: 850)).single;
      expect(await svc.dispatchIncidentByHospital(
        id: r.id,
        ambulanceId: 'AMB-8501',
        ambulancePlate: 'กข 8501',
        callingHospitalId: r.targetHospitalId,
      ), isTrue);
      expect(await svc.reportAmbulanceAtScene(r.id), isTrue);
      expect(await svc.reportAmbulanceTransporting(r.id), isTrue);
      expect(await svc.closeIncidentByHospital(r.id, reason: 'โรงพยาบาลปิดเคส'), isTrue);
      // การเขียน approaching_er อัตโนมัติ (≤ 1.5 กม.) ที่รถคำนวณก่อนเห็น snapshot ใหม่
      expect(await svc.advanceIncidentStatus(id: r.id, status: 'approaching_er'),
          ProgressOutcome.caseClosed);
      expect(await svc.reportAmbulanceApproachingHospital(r.id), isFalse);

      final data = await docData(r.id);
      expect(data['status'], 'cancelled');
      expect(data['cancelledBy'], 'hospital');
      await waitUntil(() async => !(await svc.getBusyAmbulanceIds()).contains('AMB-8501'),
          'รถว่าง');

      record(
        'แก้แล้ว: เคสที่ปิดแล้วถูกเขียนสถานะทับ',
        'รพ. ปิดเคส แล้วการเขียน approaching_er ของรถลงมาทีหลัง',
        'เคสที่ปิดแล้วไม่เปลี่ยนสถานะอีก',
        'การเลื่อนสถานะได้ "เคสปิดแล้ว" สถานะยังเป็น cancelled และรถว่าง '
            '(เดิมกลายเป็น approaching_er)',
      );
    });
  });

  group('หลายคันต่อเคส (นับตามทะเบียน)', () {
    test('[S11] 2 บัญชีบนรถคันเดียวกัน (ทะเบียนเดียวกัน) นับเป็น 1 คัน และรับเคสอื่นไม่ได้', () async {
      final seeded = await seedCases(2, from: 950);
      final (a, b) = (seeded[0], seeded[1]);
      expect((await svc.assignAmbulance(id: a.id, ambulanceId: 'AMB-9501', ambulancePlate: 'กข 9501',
              selfAccepted: true)).outcome,
          DispatchOutcome.assigned);
      // เจ้าหน้าที่อีกคนบนรถคันเดียวกัน ล็อกอินอีกบัญชี (unitId อื่น) พิมพ์ทะเบียนเว้นวรรคต่างกัน
      final crew = await svc.assignAmbulance(
          id: a.id, ambulanceId: 'AMB-9599', ambulancePlate: 'กข-9501', selfAccepted: true);
      expect(crew.outcome, DispatchOutcome.joined);
      final data = await docData(a.id);
      expect(data['assignedVehicleCount'], 1);
      expect(unitIdsOf(data), {'AMB-9501', 'AMB-9599'});
      expect(crew.incident!.vehicleCount, 1);
      expect(crew.incident!.hasUnit('AMB-9599'), isTrue);
      // บัญชีที่สองพยายามรับอีกเคส = รถคันเดิม ยังไม่ว่าง
      final other = await svc.assignAmbulance(
          id: b.id, ambulanceId: 'AMB-9599', ambulancePlate: 'กข 9501', selfAccepted: true);
      expect(other.outcome, DispatchOutcome.vehicleBusy);
      expect(other.busyCaseId, a.id);
      // รถคันที่สอง (คนละทะเบียน) = 2 คัน
      expect((await svc.assignAmbulance(id: a.id, ambulanceId: 'AMB-9502', ambulancePlate: 'ขค 9502'))
          .outcome, DispatchOutcome.joined);
      expect((await docData(a.id))['assignedVehicleCount'], 2);
      expect(IncidentReport.fromMap(await docData(a.id)).vehiclesLabel, 'กข 9501, ขค 9502');

      record(
        'หลายบัญชีบนรถคันเดียวกัน',
        '2 บัญชีทะเบียนเดียวกัน + รถอีกทะเบียน เข้าเคสเดียว',
        'นับตามทะเบียน, รถคันเดิมรับเคสอื่นไม่ได้',
        '3 บัญชี = 2 คัน (กข 9501, ขค 9502), บัญชีที่สองรับอีกเคสได้ "รถไม่ว่าง"',
      );
    });

    test('[S10][S11] ล็อกของเคสที่จบ/ปิดแล้วถือว่าว่าง และรถที่ยังไม่ตั้งทะเบียนไม่ถูกนับรวมกัน', () async {
      final seeded = await seedCases(3, from: 970);
      expect(await svc.dispatchIncidentByHospital(
          id: seeded[0].id, ambulanceId: 'AMB-9701', ambulancePlate: 'กข 9701'), isTrue);
      expect(await svc.closeIncidentByHospital(seeded[0].id), isTrue);
      // ไม่มีใครปลดล็อก แต่เคสที่ล็อกชี้อยู่ปิดแล้ว → รับเคสใหม่ได้
      expect(await svc.dispatchIncidentByHospital(
          id: seeded[1].id, ambulanceId: 'AMB-9701', ambulancePlate: 'กข 9701'), isTrue);
      final lock = (await db.collection('ambulance_locks').doc('plate_กข9701').get()).data()!;
      expect(lock['openCaseId'], seeded[1].id);

      // สองคันที่ยังไม่ตั้งทะเบียน = คนละคัน (ใช้รหัสหน่วยแทน)
      for (final u in ['AMB-9711', 'AMB-9712']) {
        expect(await svc.acceptIncidentByAmbulance(
            id: seeded[2].id, ambulancePlate: AssignedUnit.unsetPlate, ambulanceId: u), isTrue);
      }
      expect((await docData(seeded[2].id))['assignedVehicleCount'], 2);
    });

    test('[S08] เจ้าหน้าที่ 2 คนของ รพ. เดียวกันกด "ส่งรถพยาบาล" พร้อมกัน: ได้รถคันเดียว', () async {
      final seeded = await seedCases(6, from: 960);
      var single = 0;
      for (final (i, r) in seeded.indexed) {
        // สองเครื่องเลือก "คันใกล้สุด" ต่างกันได้ (เห็นตำแหน่งรถคนละจังหวะ)
        final results = await Future.wait([
          for (final k in [1, 2])
            svc.assignAmbulance(
              id: r.id,
              ambulanceId: 'AMB-96$i$k',
              ambulancePlate: 'ชซ 96$i$k',
              callingHospitalId: r.targetHospitalId,
              onlyIfUnassigned: true,
            ),
        ]);
        final outcomes = results.map((x) => x.outcome).toSet();
        expect(outcomes, {DispatchOutcome.assigned, DispatchOutcome.alreadyHasVehicles});
        final data = await docData(r.id);
        expect(data['assignedVehicleCount'], 1);
        single++;
      }
      record(
        'S08 เจ้าหน้าที่ รพ. เดียวกัน 2 เครื่องกดส่งรถพร้อมกัน',
        '6 เคส × 2 เครื่อง',
        'ได้รถ 1 คันต่อเคส อีกเครื่องได้ "มีรถรับแล้ว"',
        'ได้คันเดียว $single/6 เคส',
      );
    });

    test('[S14][S16] รถหลายคันในเคสเดียว: สถานะเดินหน้าอย่างเดียว, เริ่มนำส่งแล้วไม่รับรถเพิ่ม, จบเป็นขั้น 5 เสมอ',
        () async {
      final r = (await seedCases(1, from: 990)).single;
      for (final (u, p) in [('AMB-9901', 'กข 9901'), ('AMB-9902', 'กข 9902')]) {
        expect(await svc.acceptIncidentByAmbulance(id: r.id, ambulancePlate: p, ambulanceId: u), isTrue);
      }
      // คันแรกถึงและเริ่มนำส่ง คันที่สองกด "ถึงจุดเกิดเหตุ" ทีหลัง → ไม่ถอยสถานะ
      expect(await svc.advanceIncidentStatus(id: r.id, status: 'at_scene'), ProgressOutcome.updated);
      expect(await svc.advanceIncidentStatus(id: r.id, status: 'transporting'), ProgressOutcome.updated);
      expect(await svc.advanceIncidentStatus(id: r.id, status: 'at_scene'), ProgressOutcome.alreadyPast);
      expect((await docData(r.id))['status'], 'transporting');
      expect((await svc.assignAmbulance(id: r.id, ambulanceId: 'AMB-9903', ambulancePlate: 'กข 9903'))
          .outcome, DispatchOutcome.notJoinable);
      // หน้ารายละเอียดเคยส่ง resolved เป็นขั้น 4 — ตอนนี้คำนวณจากสถานะเสมอ
      expect(await svc.updateIncidentProgressStep(id: r.id, step: 4, status: 'resolved'), isTrue);
      final data = await docData(r.id);
      expect(data['status'], 'resolved');
      expect(data['statusStep'], 5);
      expect((await svc.assignAmbulance(id: r.id, ambulanceId: 'AMB-9903', ambulancePlate: 'กข 9903'))
          .outcome, DispatchOutcome.caseClosed);
      await waitUntil(() async => (await svc.getBusyAmbulanceIds()).isEmpty, 'ทุกคันว่าง');
    });

    test('[G18][S16] ETA หลายคัน: ผู้แจ้งเห็นคันที่ถึงเร็วที่สุด ไม่สลับไปมา', () {
      final now = DateTime.now();
      final inc = IncidentReport.fromMap({
        'id': 'X',
        'createdAt': now.toIso8601String(),
        'status': 'assigned',
        'ambulanceEtaUnitId': 'A',
        'ambulanceEtaMinutes': 5,
        'ambulanceEtaTarget': 'scene',
        'ambulanceEtaUpdatedAt': now.subtract(const Duration(seconds: 20)).toIso8601String(),
      });
      bool send(String unit, int eta, {String target = 'scene', DateTime? at}) =>
          inc.shouldPublishEta(unitId: unit, etaMinutes: eta, target: target, now: at ?? now);
      expect(send('A', 9), isTrue, reason: 'คันเดิมอัปเดตของตัวเองได้เสมอ');
      expect(send('B', 7), isFalse, reason: 'คันที่ช้ากว่าไม่ทับ');
      expect(send('B', 3), isTrue, reason: 'คันที่เร็วกว่าแทนได้');
      expect(send('B', 7, target: 'hospital'), isTrue, reason: 'เปลี่ยนช่วงทาง');
      expect(send('B', 7, at: now.add(const Duration(seconds: 80))), isTrue,
          reason: 'คันเดิมหยุดส่งเกิน 90 วิ');
    });
  });

  group('ผู้แจ้งยกเลิกพร้อมกับที่รถรับเคส', () {
    test('[S18] ผู้แจ้งกดยกเลิกขณะเครื่องตัวเองยังเห็น pending แต่รถรับเคสไปแล้ว: ยกเลิกไม่ได้ เคสยังเดินต่อ',
        () async {
      final r = (await seedCases(1, from: 900)).single;
      await settle();
      final prefs = await SharedPreferences.getInstance();
      final staleCache = prefs.getString('local_incident_reports_v2')!;
      expect(await svc.acceptIncidentByAmbulance(
          id: r.id, ambulancePlate: 'กข 9001', ambulanceId: 'AMB-9001'), isTrue);
      await settle();
      // cache ของเครื่องผู้แจ้งยังไม่ได้ snapshot ใหม่ (ยังเห็น pending, 0)
      SharedPreferences.setMockInitialValues({'local_incident_reports_v2': staleCache});
      expect(await svc.cancelIncident(r.id, reason: 'รอนานเกินไป'), isFalse);

      final data = await docData(r.id);
      expect(data['status'], 'assigned');
      expect(data['assignedAmbulanceId'], 'AMB-9001');

      // เคสที่ยังไม่มีรถจริงๆ ยกเลิกได้ตามปกติ
      final free = (await seedCases(1, from: 910)).single;
      expect(await svc.cancelIncident(free.id, reason: 'แจ้งผิด'), isTrue);
      expect((await docData(free.id))['status'], 'cancelled');
      svc.debugResetCooldown();

      record(
        'S18 ผู้แจ้งยกเลิกทับการรับเคส',
        'รถกดรับ ขณะที่ cache เครื่องผู้แจ้งยังเห็น pending',
        'ยกเลิกได้เฉพาะเคสที่เซิร์ฟเวอร์ยังไม่มีรถรับ',
        'ยกเลิกถูกปฏิเสธ เคสยังเป็น assigned (เดิมถูกยกเลิกทั้งที่มีรถ), เคสที่ยังไม่มีรถยกเลิกได้',
      );
    });
  });
}
