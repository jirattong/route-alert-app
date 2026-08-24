import 'package:flutter/material.dart';

class AmbulanceSettingsScreen extends StatefulWidget {
  const AmbulanceSettingsScreen({super.key});

  @override
  State<AmbulanceSettingsScreen> createState() =>
      _AmbulanceSettingsScreenState();
}

class _AmbulanceSettingsScreenState extends State<AmbulanceSettingsScreen> {
  // สถานะการตั้งค่าฝั่งรถพยาบาล
  bool _keepScreenAwake = true; // หน้าจอเปิดตลอด
  bool _isHighwayMode = false; // โหมดทางหลวง
  bool _isHighPrecisionGps = true; // GPS ความละเอียดสูง
  bool _isAutoErNotify = true; // แจ้งเตือนห้อง ER อัตโนมัติ
  double _broadcastRadius = 2.0; // ระยะยิงสัญญาณเตือน (KM)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // --- 1. Header Bar ด้านบน ---
            _buildHeader(),

            // --- 2. รายการการ์ดตั้งค่าขอบสีแดงตาม Figma ---
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  children: [
                    // การ์ด 1: หน้าจอเปิดตลอด (Keep Screen Awake)
                    _buildRedSwitchCard(
                      title: 'หน้าจอเปิดตลอด',
                      subtitle: 'Keep Screen Awake',
                      value: _keepScreenAwake,
                      onChanged: (val) {
                        setState(() => _keepScreenAwake = val);
                      },
                    ),
                    const SizedBox(height: 16),

                    // การ์ด 2: โหมดทางหลวง (HighWay / Expressway Mode)
                    _buildRedSwitchCard(
                      title: 'โหมดทางหลวง',
                      subtitle: 'HighWay / Expressway Mode (ขยายรัศมี 3 KM)',
                      value: _isHighwayMode,
                      onChanged: (val) {
                        setState(() {
                          _isHighwayMode = val;
                          if (val) {
                            _broadcastRadius = 3.0; // ขยายรัศมีอัตโนมัติ
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // การ์ด 3: ปรับระยะส่งสัญญาณเตือน (Broadcast Radius)
                    _buildRedSliderCard(
                      title: 'ระยะส่งสัญญาณเตือน',
                      subtitle: 'Broadcast Alert Distance',
                      valueText: '${_broadcastRadius.toStringAsFixed(1)} KM',
                      icon: Icons.radar_rounded,
                      child: Slider(
                        value: _broadcastRadius,
                        min: 1.0,
                        max: 3.0,
                        divisions: 20,
                        activeColor: const Color(0xFFEB5757),
                        inactiveColor: const Color(0xFFFFEAEA),
                        onChanged: (val) {
                          setState(() {
                            _broadcastRadius = (val * 10).round() / 10.0;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // การ์ด 4: ติดตามพิกัดแบบความละเอียดสูง (High-Precision GPS)
                    _buildRedSwitchCard(
                      title: 'พิกัด Real-time ความละเอียดสูง',
                      subtitle: 'High-Precision GPS (ส่งพิกัดทุก 1 วินาที)',
                      value: _isHighPrecisionGps,
                      onChanged: (val) {
                        setState(() => _isHighPrecisionGps = val);
                      },
                    ),
                    const SizedBox(height: 16),

                    // การ์ด 5: แจ้งเตือนห้อง ER อัตโนมัติเมื่อใกล้ถึง รพ.
                    _buildRedSwitchCard(
                      title: 'แจ้งเตือนห้อง ER อัตโนมัติ',
                      subtitle: 'Auto Notify ER (เมื่อเข้าใกล้ รพ. 2 KM)',
                      value: _isAutoErNotify,
                      onChanged: (val) {
                        setState(() => _isAutoErNotify = val);
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // ❌ ไม่ใส่ bottomNavigationBar เพราะควบคุมผ่าน AmbulanceMainScreen
    );
  }

  // --- Header Bar พร้อมโลโก้ RouteAlert ---
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
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

  // --- Helper: การ์ดเปิด/ปิดสวิตช์ ขอบสีแดงตาม Figma ---
  Widget _buildRedSwitchCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEB5757), width: 1.8), // ขอบแดงตามรูป
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEB5757).withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
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
                    color: Color(0xFFEB5757),
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.95,
            child: Switch(
              value: value,
              activeThumbColor: Colors.white,
              activeTrackColor: const Color(0xFFEB5757), // สวิตช์สีแดง
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.grey.shade300,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper: การ์ด Slider สไตล์ฝั่งรถพยาบาล ---
  Widget _buildRedSliderCard({
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
        border: Border.all(color: const Color(0xFFEB5757), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEB5757).withValues(alpha: 0.12),
            blurRadius: 10,
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
                  Icon(icon, color: const Color(0xFFEB5757), size: 20),
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
                  color: Color(0xFFEB5757),
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