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
