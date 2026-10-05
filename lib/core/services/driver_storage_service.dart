import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'driver_presence.dart';

class DriverStorageService {
  static const String _keyBackground = 'driver_bg_mode';
  static const String _keyVolume = 'driver_volume';
  static const String _keyOuterDistanceMeters = 'driver_outer_meters';
  static const String _keyInnerDistanceMeters = 'driver_inner_meters';
  static const String _keyYieldCount = 'driver_yield_count';
  static const String _keyYieldHistory = 'driver_yield_history';
  static const String _keySirenDetectionEnabled = 'driver_siren_detection_enabled';
  static const String _keyBackgroundAlertEnabled = 'driver_background_alert_enabled';

  static final ValueNotifier<Map<String, dynamic>> settingsNotifier =
      ValueNotifier<Map<String, dynamic>>({
    'background': true,
    'volume': 80.0,
    'outerMeters': 1500.0, // ค่าเริ่มต้น 1500 เมตร (1.5 กม.)
    'innerMeters': 400.0,  // ค่าเริ่มต้น 400 เมตร
  });

  static Future<void> saveSettings({
    required bool background,
    required double volume,
    required double outerMeters,
    required double innerMeters,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBackground, background);
    await prefs.setDouble(_keyVolume, volume);
    await prefs.setDouble(_keyOuterDistanceMeters, outerMeters);
    await prefs.setDouble(_keyInnerDistanceMeters, innerMeters);

    settingsNotifier.value = {
      'background': background,
      'volume': volume,
      'outerMeters': outerMeters,
      'innerMeters': innerMeters,
    };
  }

  static Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final loaded = {
      'background': prefs.getBool(_keyBackground) ?? true,
      'volume': prefs.getDouble(_keyVolume) ?? 80.0,
      'outerMeters': prefs.getDouble(_keyOuterDistanceMeters) ?? 1500.0,
      'innerMeters': prefs.getDouble(_keyInnerDistanceMeters) ?? 400.0,
    };
    // เดิม loadSettings() คืนค่าที่บันทึกไว้จริงให้ผู้เรียกเท่านั้น แต่ไม่เคยอัปเดต
    // settingsNotifier ที่หน้าจอหลัก (driver_home_screen) ใช้อ่านค่ารัศมีจริง ทำให้
    // ทุกครั้งที่เปิดแอปใหม่ ค่ารัศมีจะย้อนกลับไปเป็นค่าเริ่มต้น hardcode แทนที่จะ
    // เป็นค่าที่ผู้ใช้ตั้งไว้ล่าสุด จึงต้อง sync ค่าที่โหลดได้กลับเข้า notifier ด้วย
    settingsNotifier.value = loaded;
    return loaded;
  }

  // เดิม default เป็น 67 ทำให้เครื่องที่เพิ่งลงแอพใหม่ (ยังไม่เคยเปิดทางให้ใครเลย)
  // โชว์สถิติปลอมว่าเปิดทางไปแล้ว 67 ครั้ง จึงแก้ default ให้ตรงความจริงเป็น 0
  static Future<int> getYieldCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyYieldCount) ?? 0;
  }

  static Future<int> incrementYieldCount() async {
    final prefs = await SharedPreferences.getInstance();
    int current = prefs.getInt(_keyYieldCount) ?? 0;
    current += 1;
    await prefs.setInt(_keyYieldCount, current);
    return current;
  }

  /// บันทึกประวัติการเปิดทางแต่ละครั้งจริง (เดิมหน้าประวัติโชว์ 2 แถวตัวอย่าง
  /// hardcode ตายตัวเสมอ ไม่ว่าผู้ใช้จะเปิดทางไปแล้วกี่ครั้งจริงก็ตาม)
  static Future<void> addYieldHistoryEntry(String label) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getYieldHistory();
    history.insert(0, {
      'label': label,
      'time': DateTime.now().toIso8601String(),
    });
    // เก็บย้อนหลังไม่เกิน 50 รายการล่าสุดพอ ป้องกันข้อมูลบวมไม่จำกัด
    final trimmed = history.take(50).toList();
    await prefs.setString(_keyYieldHistory, jsonEncode(trimmed));
  }

  static Future<List<Map<String, dynamic>>> getYieldHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyYieldHistory);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // ตรวจจับเสียงไซเรนผ่านไมโครโฟน — ฟีเจอร์ที่ต้องใช้ไมโครโฟนตลอดเวลาที่เปิดหน้าแผนที่
  // จึงต้องเป็น opt-in และ default ปิดไว้ก่อนเสมอ (คำนึงถึงแบตเตอรี่/ความเป็นส่วนตัว)
  // จนกว่าผู้ใช้จะเปิดเองจากหน้าตั้งค่า
  static final ValueNotifier<bool> sirenDetectionEnabledNotifier =
      ValueNotifier<bool>(false);

  static Future<bool> getSirenDetectionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_keySirenDetectionEnabled) ?? false;
    sirenDetectionEnabledNotifier.value = enabled;
    return enabled;
  }

  static Future<void> setSirenDetectionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySirenDetectionEnabled, enabled);
    sirenDetectionEnabledNotifier.value = enabled;
  }

  // แจ้งเตือนพื้นหลัง (แจ้งเตือนแม้ล็อกหน้าจอ/สลับแอป) — ต้องใช้สิทธิ์ตำแหน่งแบบ
  // "ตลอดเวลา" (locationAlways) และบน Android จะรันเป็น foreground service ค้าง
  // notification ไว้ตลอด ซึ่งกินแบตเตอรี่เพิ่มขึ้น จึง default ปิดไว้เสมอ
  // (opt-in เท่านั้น) จนกว่าผู้ใช้จะเปิดเองจากหน้าตั้งค่าและอนุญาตสิทธิ์จริง
  static final ValueNotifier<bool> backgroundAlertEnabledNotifier =
      ValueNotifier<bool>(false);

  static Future<bool> getBackgroundAlertEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_keyBackgroundAlertEnabled) ?? false;
    backgroundAlertEnabledNotifier.value = enabled;
    return enabled;
  }

  static Future<void> setBackgroundAlertEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBackgroundAlertEnabled, enabled);
    backgroundAlertEnabledNotifier.value = enabled;
  }

  // แชร์ตำแหน่ง (ไม่ระบุตัวตน) ให้ผู้ขับขี่คนอื่นเห็นบนแผนที่ — เปิดไว้เป็นค่าเริ่มต้น ปิดได้ที่หน้าตั้งค่า
  // ส่งเฉพาะตอนเปิดหน้าแผนที่อยู่ ไม่มีชื่อ/อีเมล/เบอร์ ใช้รหัสสุ่มประจำเครื่อง
  static const String _keySharePresence = 'driver_share_presence';
  static const String _keyPresenceId = 'driver_presence_id';
  static final ValueNotifier<bool> sharePresenceNotifier = ValueNotifier<bool>(true);

  static Future<bool> getSharePresence() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_keySharePresence) ?? true;
    sharePresenceNotifier.value = enabled;
    return enabled;
  }

  static Future<void> setSharePresence(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySharePresence, enabled);
    sharePresenceNotifier.value = enabled;
  }

  static Future<String> getPresenceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_keyPresenceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = DriverPresence.newAnonymousId();
    await prefs.setString(_keyPresenceId, id);
    return id;
  }
}
