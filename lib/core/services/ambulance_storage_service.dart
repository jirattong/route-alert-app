import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// เก็บข้อมูลประจำหน่วยรถพยาบาลของเครื่องนี้ (รหัสหน่วย/ทะเบียน/ชื่อเรียกขาน)
/// เพื่อไม่ให้ทุกเครื่องที่ติดตั้งแอปรายงานตัวเป็น "AMB-1669-01" ซ้ำกันหมด
class AmbulanceStorageService {
  static const String _keyAmbulanceId = 'ambulance_unit_id';
  static const String _keyPlateNumber = 'ambulance_plate_number';
  static const String _keyCallSign = 'ambulance_call_sign';
  static const String _keyOnDuty = 'ambulance_on_duty';
  static const String _keyKeepScreenAwake = 'ambulance_keep_screen_awake';
  static const String _keyHighwayMode = 'ambulance_highway_mode';
  static const String _keyHighPrecisionGps = 'ambulance_high_precision_gps';
  static const String _keyAutoErNotify = 'ambulance_auto_er_notify';
  static const String _keyBroadcastRadius = 'ambulance_broadcast_radius';

  // เดิมหน้าตั้งค่าฝั่งรถพยาบาล (ambulance_settings_screen.dart) เก็บค่าพวกนี้
  // เป็นแค่ local State ล้วนๆ ปิดแอพ/ออกจากหน้าแล้วรีเซ็ตกลับเป็นค่าเริ่มต้นทุกครั้ง
  // ต่างจาก Driver/Agency ที่มี Storage service ของตัวเองบันทึกค่าจริงอยู่แล้ว
  static final ValueNotifier<Map<String, dynamic>> settingsNotifier =
      ValueNotifier<Map<String, dynamic>>({
    'keepScreenAwake': true,
    'isHighwayMode': false,
    'isHighPrecisionGps': true,
    'isAutoErNotify': true,
    'broadcastRadius': 2.0,
  });

  static Future<void> saveSettings({
    required bool keepScreenAwake,
    required bool isHighwayMode,
    required bool isHighPrecisionGps,
    required bool isAutoErNotify,
    required double broadcastRadius,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyKeepScreenAwake, keepScreenAwake);
    await prefs.setBool(_keyHighwayMode, isHighwayMode);
    await prefs.setBool(_keyHighPrecisionGps, isHighPrecisionGps);
    await prefs.setBool(_keyAutoErNotify, isAutoErNotify);
    await prefs.setDouble(_keyBroadcastRadius, broadcastRadius);

    settingsNotifier.value = {
      'keepScreenAwake': keepScreenAwake,
      'isHighwayMode': isHighwayMode,
      'isHighPrecisionGps': isHighPrecisionGps,
      'isAutoErNotify': isAutoErNotify,
      'broadcastRadius': broadcastRadius,
    };
  }

  static Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = {
      'keepScreenAwake': prefs.getBool(_keyKeepScreenAwake) ?? true,
      'isHighwayMode': prefs.getBool(_keyHighwayMode) ?? false,
      'isHighPrecisionGps': prefs.getBool(_keyHighPrecisionGps) ?? true,
      'isAutoErNotify': prefs.getBool(_keyAutoErNotify) ?? true,
      'broadcastRadius': prefs.getDouble(_keyBroadcastRadius) ?? 2.0,
    };
    settingsNotifier.value = settings;
    return settings;
  }

  static final ValueNotifier<Map<String, String>> profileNotifier =
      ValueNotifier<Map<String, String>>({
    'ambulanceId': '',
    'plateNumber': '',
    'callSign': '',
  });

  static final ValueNotifier<bool> onDutyNotifier = ValueNotifier<bool>(true);

  /// บันทึกสถานะพร้อมปฏิบัติงาน (persist จริง) — ถ้าปิด (Off Duty) ฝั่ง
  /// ambulance_home_screen จะหยุด broadcast พิกัดผ่าน MQTT ทำให้ไม่ถูกเลือก
  /// เป็น "รถพยาบาลที่ใกล้ที่สุด" จากฝั่ง Agency ระหว่างพักเวร
  static Future<void> setOnDuty(bool onDuty) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOnDuty, onDuty);
    onDutyNotifier.value = onDuty;
  }

  static Future<bool> loadOnDuty() async {
    final prefs = await SharedPreferences.getInstance();
    final onDuty = prefs.getBool(_keyOnDuty) ?? true;
    onDutyNotifier.value = onDuty;
    return onDuty;
  }

  static Future<void> saveProfile({
    required String ambulanceId,
    required String plateNumber,
    required String callSign,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAmbulanceId, ambulanceId);
    await prefs.setString(_keyPlateNumber, plateNumber);
    await prefs.setString(_keyCallSign, callSign);

    profileNotifier.value = {
      'ambulanceId': ambulanceId,
      'plateNumber': plateNumber,
      'callSign': callSign,
    };
  }

  /// โหลดข้อมูลหน่วย ถ้ายังไม่เคยตั้งค่ามาก่อนจะสุ่มสร้างรหัสหน่วยที่ไม่ซ้ำให้อัตโนมัติ
  static Future<Map<String, String>> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    String? ambulanceId = prefs.getString(_keyAmbulanceId);

    if (ambulanceId == null || ambulanceId.isEmpty) {
      final suffix = (1000 + math.Random().nextInt(9000)).toString();
      ambulanceId = 'AMB-$suffix';
      await prefs.setString(_keyAmbulanceId, ambulanceId);
    }

    final plateNumber = prefs.getString(_keyPlateNumber) ?? 'ยังไม่ระบุทะเบียน';
    final callSign = prefs.getString(_keyCallSign) ?? 'หน่วยกู้ชีพ $ambulanceId';

    final profile = {
      'ambulanceId': ambulanceId,
      'plateNumber': plateNumber,
      'callSign': callSign,
    };
    profileNotifier.value = profile;
    return profile;
  }
}
