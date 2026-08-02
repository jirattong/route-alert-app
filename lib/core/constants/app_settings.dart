class AppSettings {
  // ค่ารัศมีวงนอกตรวจจับสัญญาณบนแมพ (กิโลเมตร)
  static double detectionZone = 1.5;

  // ค่ารัศมีวงในแจ้งเตือนด้วยเสียง (กิโลเมตร)
  static double alertDistance = 0.5;

  // สถานะเปิด/ปิดเสียง และ ทำงานเบื้องหลัง
  static bool isVoiceAlert = true;
  static bool isBackgroundMode = false;
  static double volume = 80.0;
}