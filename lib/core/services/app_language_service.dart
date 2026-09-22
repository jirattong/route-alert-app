import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// สลับภาษาไทย/อังกฤษแบบเบา ไม่ใช้ Flutter gen-l10n (เพื่อความเสถียร ไม่ต้องพึ่ง
/// codegen) — persist ผ่าน SharedPreferences เหมือน ThemeSettingsService
///
/// ขอบเขตปัจจุบัน: แปลเฉพาะหน้าจอที่สำคัญที่สุดสำหรับนักท่องเที่ยว/ชาวต่างชาติที่
/// เจออุบัติเหตุ (หน้าแจ้งเหตุ SOS) ก่อน — หน้าจออื่นในแอปยังเป็นภาษาไทยเท่านั้น
/// เพิ่ม key ใหม่ใน AppStrings ได้เรื่อยๆ เพื่อขยายความครอบคลุมทีหลัง
class AppLanguageService {
  static const String _prefKey = 'app_language_is_english';

  static final ValueNotifier<bool> isEnglish = ValueNotifier<bool>(false);

  static Future<bool> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_prefKey) ?? false;
    isEnglish.value = value;
    return value;
  }

  static Future<void> setEnglish(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    isEnglish.value = value;
  }

  static Future<bool> toggle() async {
    final newValue = !isEnglish.value;
    await setEnglish(newValue);
    return newValue;
  }
}
