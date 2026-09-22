import 'package:flutter/material.dart';
import '../../../core/services/agency_storage_service.dart';
import '../../onboarding/presentation/onboarding_screen.dart';

class AgencySettingsScreen extends StatefulWidget {
  /// เรียกเมื่อกด "สอนการใช้งานปุ่มต่างๆ" — ให้ AgencyMainScreen สลับไปแท็บแผนที่
  /// แล้วเปิด Coach Mark ชี้ปุ่มจริงให้ (Coach Mark ผูกอยู่กับ AgencyHomeScreen
  /// คนละหน้ากับหน้านี้ เลยต้องส่งผ่าน callback ขึ้นไปให้ตัว MainScreen จัดการ)
  final VoidCallback? onShowCoachMark;

  const AgencySettingsScreen({super.key, this.onShowCoachMark});

  @override
  State<AgencySettingsScreen> createState() => _AgencySettingsScreenState();
}

class _AgencySettingsScreenState extends State<AgencySettingsScreen> {
  // สถานะการตั้งค่า (ค่าเริ่มต้นจำลอง)
  bool _isBackgroundMode = true;
  double _volume = 80.0;
  double _alertDistance = 5.0; // หน่วยงานมักจะแจ้งเตือนระยะไกลกว่ารถทั่วไป (เช่น 5 KM)
  
  // ฟังก์ชันใหม่ที่เพิ่มเข้ามาสำหรับหน่วยงาน (ER / ศูนย์สั่งการ)
  bool _criticalOnly = false; // เตือนเฉพาะเคสวิกฤต
  bool _voiceAnnouncement = true; // เตือนด้วยเสียงพูด (TTS)
  bool _screenFlashAlert = true; // กะพริบหน้าจอ

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await AgencyStorageService.loadSettings();
    if (mounted) {
      setState(() {
        _isBackgroundMode = settings['background'];
        _volume = settings['volume'];
        _alertDistance = settings['alertDistanceKm'];
        _criticalOnly = settings['criticalOnly'];
        _voiceAnnouncement = settings['voiceAnnouncement'];
        _screenFlashAlert = settings['screenFlashAlert'];
      });
    }
  }

  void _persistSettings() {
    AgencyStorageService.saveSettings(
      background: _isBackgroundMode,
      volume: _volume,
      alertDistanceKm: _alertDistance,
      criticalOnly: _criticalOnly,
      voiceAnnouncement: _voiceAnnouncement,
      screenFlashAlert: _screenFlashAlert,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // --- 1. Header Bar ด้านบน ---
            _buildHeader(),

            // --- 2. รายการการ์ดตั้งค่าขอบสีเขียวสว่างตาม Figma ---
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: Column(
                  children: [
                    // การ์ด 1: ทำงานเบื้องหลัง (Background)
                    _buildGreenSwitchCard(
                      title: 'ทำงานเบื้องหลัง',
                      subtitle: '(Background)',
                      value: _isBackgroundMode,
                      onChanged: (val) {
                        setState(() => _isBackgroundMode = val);
                        _persistSettings();
                      },
                    ),
                    const SizedBox(height: 16),

                    // การ์ด 2: ระดับเสียง (Volume)
                    _buildGreenSliderCard(
                      title: 'ระดับเสียง',
                      subtitle: 'Volume',
                      valueText: '${_volume.round()}',
                      icon: Icons.volume_up_rounded,
                      child: Slider(
                        value: _volume,
                        min: 0,
                        max: 100,
                        activeColor: const Color(0xFF1B5E20), // เขียวเข้มตรงตัวเลื่อน
                        inactiveColor: const Color(0xFF69F0AE), // เขียวสว่างตรงแถบ
                        onChanged: (val) {
                          setState(() => _volume = val);
                        },
                        onChangeEnd: (_) => _persistSettings(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // การ์ด 3: ระยะเริ่มต้นแจ้งเตือน (Alert Trigger Distance)
                    _buildGreenSliderCard(
                      title: 'ระยะเริ่มต้นแจ้งเตือน',
                      subtitle: 'Alert Trigger Distance',
                      valueText: '${_alertDistance.toStringAsFixed(1)} KM',
                      icon: Icons.radar_rounded,
                      child: Slider(
                        value: _alertDistance,
                        min: 1.0,
                        max: 15.0, // สำหรับโรงพยาบาล อาจต้องรู้ล่วงหน้าไกลหน่อย (15 KM)
                        divisions: 28,
                        activeColor: const Color(0xFF1B5E20),
                        inactiveColor: const Color(0xFF69F0AE),
                        onChanged: (val) {
                          setState(() => _alertDistance = val);
                        },
                        onChangeEnd: (_) => _persistSettings(),
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    const Divider(thickness: 1.5, color: Color(0xFFEEEEEE)),
                    const SizedBox(height: 20),
                    
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'การตั้งค่าเฉพาะหน่วยงาน (ER / Dispatcher)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // การ์ด 4: แจ้งเตือนเฉพาะเคสวิกฤต (ลดความรำคาญในห้อง ER)
                    _buildGreenSwitchCard(
                      title: 'แจ้งเตือนเฉพาะเคสวิกฤต',
                      subtitle: '(Critical / Code Red Only)',
                      value: _criticalOnly,
                      onChanged: (val) {
                        setState(() => _criticalOnly = val);
                        _persistSettings();
                      },
                    ),
                    const SizedBox(height: 16),

                    // การ์ด 5: การเตือนด้วยเสียงพูด (Voice Announcement)
                    _buildGreenSwitchCard(
                      title: 'อ่านรายละเอียดเคสด้วยเสียงพูด',
                      subtitle: '(Voice Announcement)',
                      value: _voiceAnnouncement,
                      onChanged: (val) {
                        setState(() => _voiceAnnouncement = val);
                        _persistSettings();
                      },
                    ),
                    const SizedBox(height: 16),

                    // การ์ด 6: กะพริบหน้าจอเมื่อมีเคส (ดึงดูดสายตาในห้อง ER ที่เสียงดัง)
                    _buildGreenSwitchCard(
                      title: 'กะพริบหน้าจอเมื่อรถเข้าใกล้',
                      subtitle: '(Screen Flash Alert)',
                      value: _screenFlashAlert,
                      onChanged: (val) {
                        setState(() => _screenFlashAlert = val);
                        _persistSettings();
                      },
                    ),
                    const SizedBox(height: 16),

                    // ดูคำแนะนำการใช้งาน (Onboarding) ซ้ำอีกครั้ง
                    _buildOnboardingReplayCard(context),
                    const SizedBox(height: 16),

                    // สอนการใช้งานปุ่มต่างๆ (Coach Mark) — ชี้ตำแหน่งปุ่มจริงบนแผนที่
                    // พร้อมคำอธิบาย เดิมโชว์อัตโนมัติครั้งแรก เปลี่ยนเป็นกดดูเองได้ตาม
                    // ใจที่นี่แทน (ผู้ใช้ขอให้ย้ายมาไว้ในหน้าตั้งค่าแทนการโชว์อัตโนมัติ)
                    _buildCoachMarkCard(context),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- เมนู ดูคำแนะนำการใช้งานอีกครั้ง ---
  Widget _buildOnboardingReplayCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1B5E20), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E20).withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const OnboardingScreen(role: 'agency', isReplay: true),
            ),
          );
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF1B5E20)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'ดูคำแนะนำการใช้งานอีกครั้ง',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }

  // --- เมนู สอนการใช้งานปุ่มต่างๆ (Coach Mark) ---
  Widget _buildCoachMarkCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2563EB), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: widget.onShowCoachMark,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.touch_app_rounded, color: Color(0xFF2563EB)),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'สอนการใช้งานปุ่มต่างๆ',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }

  // --- Header แถบบน ---
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
                const Icon(Icons.airport_shuttle_outlined, size: 20, color: Color(0xFF2C3E50)),
                Positioned(top: 4, right: 4, child: Icon(Icons.wifi, size: 9, color: Colors.redAccent.shade700)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Text('RouteAlert', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  // --- Helper: การ์ดเปิด/ปิดสวิตช์ (สไตล์ขอบเขียวสว่าง แสงเรืองรองแบบ Figma) ---
  Widget _buildGreenSwitchCard({
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
        border: Border.all(color: const Color(0xFF69F0AE), width: 2), // ขอบสีเขียวสว่าง
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF69F0AE).withValues(alpha: 0.2), // แสงเรืองรองสีเขียว
            blurRadius: 12,
            spreadRadius: 2,
            offset: const Offset(0, 0),
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
                    color: Color(0xFF2E7D32), // สีเขียวเข้มให้อ่านง่าย
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
              activeTrackColor: Colors.grey.shade400, // ใน Figma สวิตช์ปิด-เปิดใช้สีเทาเหมือนกัน
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.grey.shade400,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper: การ์ด Slider (สไตล์ขอบเขียวสว่าง) ---
  Widget _buildGreenSliderCard({
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
        border: Border.all(color: const Color(0xFF69F0AE), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF69F0AE).withValues(alpha: 0.2),
            blurRadius: 12,
            spreadRadius: 2,
            offset: const Offset(0, 0),
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
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2E7D32),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(icon, color: Colors.black87, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 12, // แถบเลื่อนหนาขึ้นตามรูป
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                    activeTickMarkColor: Colors.transparent,
                    inactiveTickMarkColor: Colors.transparent,
                  ),
                  child: child,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                valueText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B5E20), // สีตัวเลขสีเขียวเข้ม
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}