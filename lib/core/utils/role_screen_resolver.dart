import 'package:flutter/material.dart';
import '../../features/agency/presentation/agency_main_screen.dart';
import '../../features/ambulance/presentation/ambulance_main_screen.dart';
import '../../features/driver_radar/presentation/driver_main_screen.dart';

/// คืนหน้าหลักที่ถูกต้องตาม role ของผู้ใช้ — ดึงออกมาเป็นฟังก์ชันกลางเพราะต้องใช้
/// ทั้งใน AppLoadingScreen (ตอนเจอ session เก่าค้างอยู่) และ FaceLoginScreen (ตอน
/// ล็อกอิน/สมัครสำเร็จ) กันโค้ดตรรกะนี้ซ้ำกันคนละที่แล้ววันหนึ่งแก้ไม่ครบ
Widget roleHomeScreenFor(String role) {
  switch (role) {
    case 'ambulance':
      return const AmbulanceMainScreen();
    case 'agency':
      return const AgencyMainScreen();
    default:
      return const DriverMainScreen();
  }
}
