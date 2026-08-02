import 'package:flutter/material.dart';
import '../../../core/constants/app_settings.dart';

class DriverSettingsScreen extends StatefulWidget {
  const DriverSettingsScreen({super.key});

  @override
  State<DriverSettingsScreen> createState() => _DriverSettingsScreenState();
}

class _DriverSettingsScreenState extends State<DriverSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    // คำนวณจำนวน Step ของระยะแจ้งเตือนเสียงให้ขยับทีละ 100 เมตร (0.1 KM)
    int alertDivisions = ((AppSettings.detectionZone - 0.1) * 10).round();
    if (alertDivisions < 1) alertDivisions = 1;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // --- 1. Header Bar ด้านบน ---
            _buildHeader(),

            // --- 2. รายการการ์ดตั้งค่าต่างๆ ---
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  children: [
                    // การ์ด 1: การแจ้งเตือนด้วยเสียง
                    _buildSwitchCard(
                      title: 'การแจ้งเตือนด้วยเสียง',
                      subtitle: 'VOICE ALERT',
                      value: AppSettings.isVoiceAlert,
                      onChanged: (val) =>
                          setState(() => AppSettings.isVoiceAlert = val),
                    ),
                    const SizedBox(height: 16),

                    // การ์ด 2: ทำงานเบื้องหลัง
                    _buildSwitchCard(
                      title: 'ทำงานเบื้องหลัง',
                      subtitle: '(Background)',
                      value: AppSettings.isBackgroundMode,
                      onChanged: (val) =>
                          setState(() => AppSettings.isBackgroundMode = val),
                    ),
                    const SizedBox(height: 16),

                    // การ์ด 3: ระดับเสียง
                    _buildSliderCard(
                      title: 'ระดับเสียง',
                      subtitle: 'Volume',
                      valueText: '${AppSettings.volume.round()}%',
                      icon: AppSettings.volume == 0
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      child: Slider(
                        value: AppSettings.volume,
                        min: 0.0,
                        max: 100.0,
                        activeColor: const Color(0xFF5B9EE1),
                        inactiveColor: const Color(0xFFE2F0FE),
                        onChanged: AppSettings.isVoiceAlert
                            ? (val) =>
                                setState(() => AppSettings.volume = val)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // การ์ด 4: ระยะตรวจจับสัญญาณ (วงนอก - สีฟ้า)
                    _buildSliderCard(
                      title: 'ระยะตรวจจับสัญญาณ',
                      subtitle: 'Detection Zone (วงนอก - แสดงบนแผนที่)',
                      valueText:
                          '${AppSettings.detectionZone.toStringAsFixed(1)} KM',
                      icon: Icons.radar_rounded,
                      child: Slider(
                        value: AppSettings.detectionZone,
                        min: 0.5,
                        max: 3.0,
                        divisions: 25,
                        activeColor: const Color(0xFF5B9EE1),
                        inactiveColor: const Color(0xFFE2F0FE),
                        onChanged: (val) {
                          final stepVal = (val * 10).round() / 10.0;
                          setState(() {
                            if (stepVal >= AppSettings.alertDistance) {
                              AppSettings.detectionZone = stepVal;
                            } else {
                              AppSettings.detectionZone =
                                  AppSettings.alertDistance;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // การ์ด 5: ระยะเริ่มต้นแจ้งเตือน (วงใน - สีแดง)
                    _buildSliderCard(
                      title: 'ระยะเริ่มต้นแจ้งเตือน',
                      subtitle: 'Alert Trigger Distance (วงใน - ยิงเสียงเตือน)',
                      valueText: AppSettings.alertDistance < 1.0
                          ? '${(AppSettings.alertDistance * 1000).round()} ม.'
                          : '${AppSettings.alertDistance.toStringAsFixed(1)} KM',
                      icon: Icons.add_alert_rounded,
                      child: Slider(
                        value: AppSettings.alertDistance,
                        min: 0.1,
                        max: AppSettings.detectionZone,
                        divisions: alertDivisions,
                        activeColor: const Color(0xFFEB5757),
                        inactiveColor: const Color(0xFFFFEAEA),
                        onChanged: (val) {
                          final stepVal = (val * 10).round() / 10.0;
                          setState(() {
                            AppSettings.alertDistance = stepVal;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // ❌ ถอด bottomNavigationBar ออกเพื่อใช้ Shell ร่วมกันใน DriverMainScreen
    );
  }

  // --- Header แถบบนพร้อมโลโก้ RouteAlert ---
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF2C3E50), width: 2),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.airport_shuttle_outlined,
                    size: 20, color: Color(0xFF2C3E50)),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(Icons.wifi,
                      size: 9, color: Colors.redAccent.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'RouteAlert',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper: การ์ดเปิด/ปิด สวิตช์ ---
  Widget _buildSwitchCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B9EE1).withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5B9EE1),
                ),
              ),
            ],
          ),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: value,
              activeColor: Colors.white,
              activeTrackColor: const Color(0xFF5B9EE1),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.grey.shade300,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper: การ์ดปรับระดับด้วย Slider (ซ่อนจุดไข่ปลา) ---
  Widget _buildSliderCard({
    required String title,
    required String subtitle,
    required String valueText,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B9EE1).withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: const Color(0xFF5B9EE1), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              Text(
                valueText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5B9EE1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 10,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              activeTickMarkColor: Colors.transparent,
              inactiveTickMarkColor: Colors.transparent,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}