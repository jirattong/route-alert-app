import 'package:flutter/material.dart';

/// Emergency Proximity Distance Tiers based on Thai Traffic Law (พ.ร.บ. จราจรทางบก พ.ศ. 2522 มาตรา 76)
/// Categorizes proximity between private drivers and approaching emergency ambulances.
enum EmergencyProximityTier {
  /// 🔴 วิกฤต / ผิดกฎหมาย (< 50 เมตร)
  /// พ.ร.บ. จราจรทางบก พ.ศ. 2522 ม.76 ห้ามขับตามหลังรถฉุกเฉินในระยะต่ำกว่า 50 เมตร
  illegalHazard,

  /// 🟠 ระยะประชิด / ต้องเปิดทางทันที (50 - 150 เมตร)
  /// รถพยาบาลประชิดตัว ผู้ขับขี่ต้องชิดขอบทางด้านซ้ายเพื่อเปิดทาง
  criticalYield,

  /// 🟡 ระยะเข้าใกล้ / เตรียมตัว (150 - 500 เมตร)
  /// รถพยาบาลกำลังตามหลังมา เตรียมชะลอความเร็วและเบี่ยงซ้าย
  approaching,

  /// 🔵 ระยะตรวจจับเรดาร์ (500 - 3,000 เมตร)
  /// ตรวจพบรถฉุกเฉินเปิดไซเรนในรัศมีเส้นทาง
  radarAwareness,

  /// 🟢 ระยะปลอดภัย (> 3,000 เมตร หรือไม่มีรถฉุกเฉิน)
  safeZone;

  static EmergencyProximityTier fromDistance(double meters, {bool hasAmbulance = true}) {
    if (!hasAmbulance || meters > 3000.0) {
      return EmergencyProximityTier.safeZone;
    }
    if (meters < 50.0) {
      return EmergencyProximityTier.illegalHazard;
    }
    if (meters <= 150.0) {
      return EmergencyProximityTier.criticalYield;
    }
    if (meters <= 500.0) {
      return EmergencyProximityTier.approaching;
    }
    return EmergencyProximityTier.radarAwareness;
  }

  /// Title for Alert Banners
  String get titleTH {
    switch (this) {
      case EmergencyProximityTier.illegalHazard:
        return '🚨 ผิดกฎหมาย! ห้ามตามหลังฉุกเฉิน < 50 ม.';
      case EmergencyProximityTier.criticalYield:
        return '⚠️ รถพยาบาลประชิดตัว! ให้ชิดซ้ายเปิดทางทันที';
      case EmergencyProximityTier.approaching:
        return '⚡ รถพยาบาลตามหลังมา เตรียมชะลอและเบี่ยงซ้าย';
      case EmergencyProximityTier.radarAwareness:
        return '📡 พบรถฉุกเฉินเปิดไซเรนในรัศมีเส้นทาง';
      case EmergencyProximityTier.safeZone:
        return '🛡️ เส้นทางปกติ ปลอดภัย ไร้รถฉุกเฉินกีดขวาง';
    }
  }

  /// Short Distance Tag
  String get distanceRangeTH {
    switch (this) {
      case EmergencyProximityTier.illegalHazard:
        return '< 50 ม.';
      case EmergencyProximityTier.criticalYield:
        return '50 - 150 ม.';
      case EmergencyProximityTier.approaching:
        return '150 - 500 ม.';
      case EmergencyProximityTier.radarAwareness:
        return '500 ม. - 3 กม.';
      case EmergencyProximityTier.safeZone:
        return '> 3 กม.';
    }
  }

  /// Actionable instruction for the driver
  String get instructionTH {
    switch (this) {
      case EmergencyProximityTier.illegalHazard:
        return 'ห้ามขับตามหลังในระยะนี้โดยเด็ดขาด! ชะลอรถและเว้นระยะห่างทันที (พ.ร.บ. จราจรทางบก ม.76)';
      case EmergencyProximityTier.criticalYield:
        return 'รถพยาบาลกำลังประชิด ให้สัญญาณไฟเลี้ยวซ้ายและหลบเข้าขอบทางเพื่อเปิดทาง';
      case EmergencyProximityTier.approaching:
        return 'ตรวจพบสัญญาณไซเรนตามหลัง เตรียมพร้อมชะลอและเบี่ยงซ้ายอย่างปลอดภัย';
      case EmergencyProximityTier.radarAwareness:
        return 'มีรถฉุกเฉินปฏิบัติการอยู่ในเส้นทาง ขับขี่ด้วยความระมัดระวัง';
      case EmergencyProximityTier.safeZone:
        return 'ไม่มีรถฉุกเฉินในระยะประชิด ขับขี่ปลอดภัยตามกฎจราจร';
    }
  }

  /// Legal citation reference
  String get legalReferenceTH {
    switch (this) {
      case EmergencyProximityTier.illegalHazard:
        return 'พ.ร.บ. จราจรทางบก พ.ศ. 2522 มาตรา 76 (ม.76): ห้ามมิให้ผู้ขับขี่ขับรถตามหลังรถฉุกเฉินซึ่งกำลังปฏิบัติหน้าที่ในระยะต่ำกว่า 50 เมตร (ฝ่าฝืนปรับสูงสุด 1,000 บาท)';
      case EmergencyProximityTier.criticalYield:
        return 'พ.ร.บ. จราจรทางบก พ.ศ. 2522 มาตรา 76 (2): ผู้ขับขี่ต้องหยุดรถหรือจอดชิดขอบทางด้านซ้ายเพื่อเปิดทางแก่รถฉุกเฉินทันที';
      default:
        return '';
    }
  }

  /// Primary color theme
  Color get primaryColor {
    switch (this) {
      case EmergencyProximityTier.illegalHazard:
        return const Color(0xFFDC2626); // Crimson Red
      case EmergencyProximityTier.criticalYield:
        return const Color(0xFFEA580C); // Emergency Orange
      case EmergencyProximityTier.approaching:
        return const Color(0xFFF59E0B); // Amber / Yellow
      case EmergencyProximityTier.radarAwareness:
        return const Color(0xFF2563EB); // Radar Blue
      case EmergencyProximityTier.safeZone:
        return const Color(0xFF10B981); // Emerald Green
    }
  }

  /// Soft background color
  Color get lightBgColor {
    switch (this) {
      case EmergencyProximityTier.illegalHazard:
        return const Color(0xFFFEF2F2);
      case EmergencyProximityTier.criticalYield:
        return const Color(0xFFFFF7ED);
      case EmergencyProximityTier.approaching:
        return const Color(0xFFFFFBEB);
      case EmergencyProximityTier.radarAwareness:
        return const Color(0xFFEFF6FF);
      case EmergencyProximityTier.safeZone:
        return const Color(0xFFECFDF5);
    }
  }

  /// Border color
  Color get borderColor {
    switch (this) {
      case EmergencyProximityTier.illegalHazard:
        return const Color(0xFFEF4444);
      case EmergencyProximityTier.criticalYield:
        return const Color(0xFFF97316);
      case EmergencyProximityTier.approaching:
        return const Color(0xFFFBBF24);
      case EmergencyProximityTier.radarAwareness:
        return const Color(0xFF60A5FA);
      case EmergencyProximityTier.safeZone:
        return const Color(0xFF34D399);
    }
  }
}
