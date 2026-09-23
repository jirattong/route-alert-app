import 'package:flutter/material.dart';
import '../../../core/services/ambulance_storage_service.dart';
import '../../../core/services/theme_settings_service.dart';
import '../../onboarding/presentation/onboarding_screen.dart';

class AmbulanceSettingsScreen extends StatefulWidget {
  /// เรียกเมื่อกด "สอนการใช้งานปุ่มต่างๆ" — ให้ AmbulanceMainScreen สลับไปแท็บแผนที่
  /// แล้วเปิด Coach Mark ชี้ปุ่มจริงให้ (Coach Mark ผูกอยู่กับ AmbulanceHomeScreen
  /// คนละหน้ากับหน้านี้ เลยต้องส่งผ่าน callback ขึ้นไปให้ตัว MainScreen จัดการ)
  final VoidCallback? onShowCoachMark;

  const AmbulanceSettingsScreen({super.key, this.onShowCoachMark});

  @override
  State<AmbulanceSettingsScreen> createState() =>
      _AmbulanceSettingsScreenState();
}

class _AmbulanceSettingsScreenState extends State<AmbulanceSettingsScreen> {
  // สถานะการตั้งค่าฝั่งรถพยาบาล — เดิมเป็นแค่ local State ปิดแอพ/ออกจากหน้าแล้ว
  // รีเซ็ตทุกครั้ง ตอนนี้บันทึกจริงผ่าน AmbulanceStorageService (เหมือน Driver/
  // Agency ที่มี Storage service ของตัวเองอยู่แล้ว)
  bool _keepScreenAwake = true; // หน้าจอเปิดตลอด
  bool _isHighwayMode = false; // โหมดทางหลวง
  bool _isHighPrecisionGps = true; // GPS ความละเอียดสูง
  bool _isAutoErNotify = true; // แจ้งเตือนห้อง ER อัตโนมัติ
  double _broadcastRadius = 2.0; // ระยะยิงสัญญาณเตือน (KM)

  // Dark mode — เดิมมีแค่ฝั่ง Driver ทั้งที่ ThemeSettingsService เป็น service
  // กลางใช้ร่วมกันได้ทุก role อยู่แล้ว
  bool _isNightMode = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _isNightMode = ThemeSettingsService.isNightMode.value;
    ThemeSettingsService.isNightMode.addListener(_onNightModeChanged);
  }

  @override
  void dispose() {
    ThemeSettingsService.isNightMode.removeListener(_onNightModeChanged);
    super.dispose();
  }

  void _onNightModeChanged() {
    if (mounted) {
      setState(() => _isNightMode = ThemeSettingsService.isNightMode.value);
    }
  }

  Future<void> _loadSettings() async {
    final settings = await AmbulanceStorageService.loadSettings();
    if (!mounted) return;
    setState(() {
      _keepScreenAwake = settings['keepScreenAwake'] as bool;
      _isHighwayMode = settings['isHighwayMode'] as bool;
      _isHighPrecisionGps = settings['isHighPrecisionGps'] as bool;
      _isAutoErNotify = settings['isAutoErNotify'] as bool;
      _broadcastRadius = settings['broadcastRadius'] as double;
    });
  }

  Future<void> _persistSettings() async {
    await AmbulanceStorageService.saveSettings(
      keepScreenAwake: _keepScreenAwake,
      isHighwayMode: _isHighwayMode,
      isHighPrecisionGps: _isHighPrecisionGps,
      isAutoErNotify: _isAutoErNotify,
      broadcastRadius: _broadcastRadius,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _isNightMode ? const Color(0xFF121212) : Colors.white;
    return Scaffold(
      backgroundColor: bgColor,
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
                    // การ์ด 0: โหมดกลางคืน (Dark Mode) — เดิมมีแค่ฝั่ง Driver
                    _buildRedSwitchCard(
                      title: 'โหมดกลางคืน',
                      subtitle: 'Dark Mode',
                      value: _isNightMode,
                      onChanged: (val) => ThemeSettingsService.setNightMode(val),
                    ),
                    const SizedBox(height: 16),

                    // การ์ด 1: หน้าจอเปิดตลอด (Keep Screen Awake)
                    _buildRedSwitchCard(
                      title: 'หน้าจอเปิดตลอด',
                      subtitle: 'Keep Screen Awake',
                      value: _keepScreenAwake,
                      onChanged: (val) {
                        setState(() => _keepScreenAwake = val);
                        _persistSettings();
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
                        _persistSettings();
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
                        // บันทึกตอนปล่อยนิ้วเท่านั้น (ไม่ใช่ทุกครั้งที่ onChanged
                        // ยิงระหว่างลาก ซึ่งถี่เกินไปไม่จำเป็นต้องเขียนดิสก์ทุกเฟรม)
                        onChangeEnd: (_) => _persistSettings(),
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
                        _persistSettings();
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
                    _buildCoachMarkTourCard(),
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

  // --- เมนู ดูคำแนะนำการใช้งานอีกครั้ง ---
  Widget _buildOnboardingReplayCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00A896), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00A896).withValues(alpha: 0.12),
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
                  const OnboardingScreen(role: 'ambulance', isReplay: true),
            ),
          );
        },
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF00A896)),
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
  Widget _buildCoachMarkTourCard() {
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
        onTap: () => widget.onShowCoachMark?.call(),
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

  // --- Header Bar พร้อมโลโก้ RouteAlert ---
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: _isNightMode ? const Color(0xFF1E1E1E) : Colors.white,
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
          Text(
            'RouteAlert',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _isNightMode ? Colors.white : Colors.black87,
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
        color: _isNightMode ? const Color(0xFF1E1E1E) : Colors.white,
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _isNightMode ? Colors.white : Colors.black87,
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
        color: _isNightMode ? const Color(0xFF1E1E1E) : Colors.white,
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
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _isNightMode ? Colors.white : Colors.black87,
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