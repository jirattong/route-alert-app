import 'package:latlong2/latlong.dart';

import 'location_service.dart';

/// กติกาตำแหน่งของหน้าแจ้งเหตุ (แยกออกมาให้ทดสอบได้ — สถานการณ์ G02–G04)

/// จุดที่ใช้แจ้งเหตุ: หมุดที่ผู้แจ้งเลื่อน/ยืนยัน มาก่อน GPS (แจ้งแทนคนอื่น หรือ GPS คลาดเคลื่อน)
LatLng? sosReportPoint({LatLng? pinned, LatLng? gps}) => pinned ?? gps;

/// ส่งเคสได้ไหม — null = ได้, ข้อความ = ยังไม่ได้ (ต้องปักหมุดเองก่อน)
/// หา GPS ไม่ได้ ห้ามใช้พิกัดเดา ต้องให้ผู้แจ้งเลื่อนแผนที่ให้หมุดอยู่ที่จุดเกิดเหตุเอง
String? sosLocationProblem({
  required LocationSource source,
  required LatLng? pinned,
  required bool pinnedByUser,
}) {
  if (pinned == null || (source == LocationSource.unavailable && !pinnedByUser)) {
    return '📍 หาตำแหน่ง GPS ไม่ได้ — เลื่อนแผนที่ให้หมุดอยู่ตรงจุดเกิดเหตุ แล้วกด "ยืนยันพิกัด" ก่อนส่ง';
  }
  return null;
}

/// แถบเตือนเหนือแผนที่ (null = ไม่ต้องเตือน)
String? sosLocationBanner(LocationSource source, {Duration? age, required bool pinnedByUser}) {
  if (pinnedByUser) return null;
  switch (source) {
    case LocationSource.gps:
      return null;
    case LocationSource.lastKnown:
      final min = (age?.inMinutes ?? 0).clamp(1, 60);
      return '⚠️ สัญญาณ GPS อ่อน ใช้ตำแหน่งล่าสุดเมื่อราว $min นาทีก่อน — ตรวจหมุดให้ตรงจุดเกิดเหตุก่อนส่ง';
    case LocationSource.unavailable:
      return '📍 หาตำแหน่ง GPS ไม่ได้ (ไม่ได้อนุญาตหรือปิด GPS) — เลื่อนแผนที่ปักหมุดจุดเกิดเหตุเอง';
  }
}
