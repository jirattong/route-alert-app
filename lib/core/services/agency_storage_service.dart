import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// เก็บค่าตั้งค่าฝั่ง Agency/Dispatcher ลง SharedPreferences จริง
/// (ก่อนหน้านี้หน้า Settings ของ Agency เป็นแค่ local state ปิดแอพแล้วรีเซ็ตทุกครั้ง)
class AgencyStorageService {
  static const String _keyBackground = 'agency_bg_mode';
  static const String _keyVolume = 'agency_volume';
  static const String _keyAlertDistanceKm = 'agency_alert_distance_km';
  static const String _keyCriticalOnly = 'agency_critical_only';
  static const String _keyVoiceAnnouncement = 'agency_voice_announcement';
  static const String _keyScreenFlashAlert = 'agency_screen_flash_alert';
  static const String _keyDismissedIncidentIds = 'agency_dismissed_incident_ids';

  static final ValueNotifier<Map<String, dynamic>> settingsNotifier =
      ValueNotifier<Map<String, dynamic>>({
    'background': true,
    'volume': 80.0,
    'alertDistanceKm': 5.0,
    'criticalOnly': false,
    'voiceAnnouncement': true,
    'screenFlashAlert': true,
  });

  static Future<void> saveSettings({
    required bool background,
    required double volume,
    required double alertDistanceKm,
    required bool criticalOnly,
    required bool voiceAnnouncement,
    required bool screenFlashAlert,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBackground, background);
    await prefs.setDouble(_keyVolume, volume);
    await prefs.setDouble(_keyAlertDistanceKm, alertDistanceKm);
    await prefs.setBool(_keyCriticalOnly, criticalOnly);
    await prefs.setBool(_keyVoiceAnnouncement, voiceAnnouncement);
    await prefs.setBool(_keyScreenFlashAlert, screenFlashAlert);

    settingsNotifier.value = {
      'background': background,
      'volume': volume,
      'alertDistanceKm': alertDistanceKm,
      'criticalOnly': criticalOnly,
      'voiceAnnouncement': voiceAnnouncement,
      'screenFlashAlert': screenFlashAlert,
    };
  }

  static Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = {
      'background': prefs.getBool(_keyBackground) ?? true,
      'volume': prefs.getDouble(_keyVolume) ?? 80.0,
      'alertDistanceKm': prefs.getDouble(_keyAlertDistanceKm) ?? 5.0,
      'criticalOnly': prefs.getBool(_keyCriticalOnly) ?? false,
      'voiceAnnouncement': prefs.getBool(_keyVoiceAnnouncement) ?? true,
      'screenFlashAlert': prefs.getBool(_keyScreenFlashAlert) ?? true,
    };
    settingsNotifier.value = settings;
    return settings;
  }

  /// เคสที่ Agency กด "ลบออกจากหน้าจอ" ด้วยตัวเอง (เก็บแค่ id ไว้ในเครื่อง ไม่แตะ
  /// ข้อมูลใน Firestore เลย) — สำหรับซ่อนเคสที่ยังไม่ resolved ออกจากรายการเมื่อ
  /// agency ไม่ต้องการเห็นแล้ว ข้อมูลจริงยังอยู่ครบใน database เผื่อใช้กับ heatmap/
  /// เว็บดูข้อมูลย้อนหลังในอนาคต
  static Future<Set<String>> loadDismissedIncidentIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_keyDismissedIncidentIds) ?? const []).toSet();
  }

  static Future<void> setDismissedIncidentIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyDismissedIncidentIds, ids.toList());
  }
}
