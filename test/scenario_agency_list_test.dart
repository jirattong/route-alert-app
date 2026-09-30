// S05: เคสที่ถูกส่งมา รพ. ไกล (ER ของ รพ. ใกล้สุดเต็ม / เกิดเหตุนอกเมือง) ต้องเห็นในรายการของ รพ. ปลายทาง
import 'package:flutter_test/flutter_test.dart';
import 'package:route_alert/core/models/incident_report.dart';
import 'package:route_alert/core/services/agency_case_filter.dart';

import 'support/scenario_result.dart';

IncidentReport _case(String id, {String? target, double? km, String status = 'pending', String severity = 'วิกฤต (Code Red)'}) =>
    IncidentReport(
      id: id,
      type: 'อุบัติเหตุทางรถยนต์',
      severity: severity,
      description: '',
      latitude: 18.8,
      longitude: 98.9,
      province: 'เชียงใหม่',
      address: '',
      reporterName: 'ผู้แจ้ง',
      reporterEmail: 'r@x.com',
      status: status,
      targetHospitalId: target,
      hospitalDistanceKm: km,
      createdAt: DateTime(2026, 9, 30),
    );

void main() {
  test('[S05] เคสที่ส่งมาที่ รพ. นี้เห็นเสมอแม้ไกลเกินระยะที่ตั้งไว้ ส่วนบัญชีเก่ายังกรองระยะตามเดิม', () {
    final far = _case('far', target: 'H1', km: 38); // ER ของ รพ. ใกล้สุดเต็ม ระบบส่งมาที่ H1 ซึ่งไกล 38 กม.
    final near = _case('near', target: 'H1', km: 2);
    final other = _case('other', target: 'H2', km: 1);
    final done = _case('done', target: 'H1', km: 1, status: 'resolved');
    final minor = _case('minor', target: 'H1', km: 1, severity: 'เล็กน้อย (Low)');

    bool seen(IncidentReport i, {String? me = 'H1', bool criticalOnly = false}) =>
        agencyCaseVisible(i, myHospitalId: me, criticalOnly: criticalOnly, alertDistanceKm: 5);

    expect(seen(far), isTrue, reason: 'เดิมถูกซ่อน (38 > 5 กม.) ทั้งที่ไม่มีโรงพยาบาลอื่นเห็นเคสนี้');
    expect(seen(near), isTrue);
    expect(seen(other), isFalse, reason: 'เคสของโรงพยาบาลอื่น');
    expect(seen(done), isFalse);
    expect(seen(minor, criticalOnly: true), isFalse, reason: 'ตัวกรองวิกฤตที่ผู้ใช้เลือกเองยังทำงาน');
    // บัญชีเก่าที่ไม่ผูกโรงพยาบาล เห็นทุกเคส จึงยังกรองระยะ
    expect(seen(far, me: null), isFalse);
    expect(seen(other, me: null), isTrue);
    expect(agencyCaseVisible(near, myHospitalId: 'H1', dismissedIds: {'near'}), isFalse);
    String v(bool b) => b ? 'เห็น' : 'ไม่เห็น';
    scenarioResult(condition: 'เคสส่งมา H1 ไกล 38 กม. (ER ใกล้สุดเต็ม), ตัวกรองระยะ 5 กม.', expected: 'H1 เห็น',
        actual: 'H1 ${v(seen(far))} (ตัวกรองก่อนแก้: ไม่เห็น — ไม่มีโรงพยาบาลไหนเห็นเคสนี้)');
    scenarioResult(condition: 'เคสของ H2 ห่าง 1 กม. ดูจากบัญชี H1', expected: 'ไม่เห็น', actual: 'H1 ${v(seen(other))}');
    scenarioResult(condition: 'บัญชีเก่าไม่ผูกโรงพยาบาล ดูเคสไกล 38 กม.', expected: 'ไม่เห็น (กรองระยะตามเดิม)', actual: v(seen(far, me: null)));
  });
}
