import 'package:shared_preferences/shared_preferences.dart';

/// เช็ค/บันทึกว่าเคยดูหน้าแนะนำการใช้งาน (Onboarding) ของแต่ละ role ไปแล้วหรือยัง
/// — แยกเก็บเป็นรายบทบาท (เดิมเก็บรวมเป็นค่าเดียวตอนอยู่ก่อนหน้าล็อกอิน แต่ย้ายมา
/// โชว์หลังล็อกอินแล้วแยกตาม role เพราะเนื้อหาที่จะอธิบายเจาะจงลงไปถึงระดับปุ่มของ
/// แต่ละ role มีเยอะ ควรรู้ก่อนว่าผู้ใช้เข้า role ไหนถึงจะโชว์เนื้อหาที่ตรงจุด)
/// โชว์แค่ครั้งแรกที่เข้าหน้าหลักของ role นั้นๆ เท่านั้น แต่เปิดดูซ้ำได้เองจากเมนู
/// "ดูคำแนะนำการใช้งานอีกครั้ง" ในหน้าตั้งค่า
class OnboardingService {
  static const String _keyPrefix = 'has_seen_onboarding_v2_';

  static Future<bool> hasSeenOnboarding(String roleKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_keyPrefix$roleKey') ?? false;
  }

  static Future<void> markOnboardingSeen(String roleKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_keyPrefix$roleKey', true);
  }

  /// ล้างสถานะ "เคยดูแล้ว" ของ role นี้ — เรียกตอน logout เท่านั้น (ดู
  /// [FaceAuthRepository.logout]) ให้ตรงกับพฤติกรรมที่ตั้งใจไว้: logout แล้ว
  /// login ใหม่ (ไม่ว่าจะบัญชีเดิมหรือบัญชีอื่นใน role เดียวกัน) จะเห็น Onboarding
  /// อีกครั้งเสมอ ต่างจากแค่ปิดแอปเฉยๆ (ไม่ logout) ที่ session ยังอยู่ ไม่ควรโชว์ซ้ำ
  static Future<void> clearOnboardingSeen(String roleKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$roleKey');
  }
}
