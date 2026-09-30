import '../models/incident_report.dart';

/// เคสไหนแสดงในหน้ารายการเคสของโรงพยาบาล (แยกออกมาให้ทดสอบได้)
///
/// เคสที่ระบบส่งมาที่โรงพยาบาลนี้ (targetHospitalId ตรง) ต้องเห็นเสมอไม่ว่าไกลแค่ไหน —
/// เดิมตัวกรองระยะ (ค่าเริ่มต้น 5 กม.) ซ่อนเคสที่ไกลจาก รพ. ทั้งที่ไม่มีโรงพยาบาลอื่นเห็นเคสนั้นเลย
/// เช่น เกิดเหตุนอกเมือง หรือ ER ของ รพ. ที่ใกล้สุดเต็มจึงถูกส่งมาที่นี่ (เจอจากสถานการณ์ทดสอบ S05)
/// ตัวกรองระยะจึงใช้กับบัญชีเก่าที่ยังไม่ผูกโรงพยาบาล (เห็นทุกเคสในระบบ) เท่านั้น
bool agencyCaseVisible(
  IncidentReport incident, {
  String? myHospitalId,
  bool criticalOnly = false,
  double alertDistanceKm = 5.0,
  Set<String> dismissedIds = const {},
}) {
  if (incident.isClosed || dismissedIds.contains(incident.id)) return false;
  if (myHospitalId != null && incident.targetHospitalId != myHospitalId) return false;
  if (criticalOnly &&
      !(incident.severity.contains('Code Red') || incident.severity.contains('วิกฤต'))) {
    return false;
  }
  final routedHere = myHospitalId != null && incident.targetHospitalId == myHospitalId;
  final dist = incident.hospitalDistanceKm;
  if (!routedHere && dist != null && dist > alertDistanceKm) return false;
  return true;
}
