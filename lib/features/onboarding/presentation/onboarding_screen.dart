import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:liquid_swipe/liquid_swipe.dart';
import '../../../core/services/onboarding_service.dart';

/// หน้าแนะนำการใช้งานแบบละเอียด แยกเนื้อหาตาม role — โชว์ **หลังล็อกอินแล้ว**
/// ตอนเข้าหน้าหลักของแต่ละ role เป็นครั้งแรกเท่านั้น (เดิมเคยโชว์ก่อนล็อกอินแบบ
/// รวมทั้ง 3 role ในหน้าเดียว แต่เปลี่ยนมาเป็นแบบนี้เพราะรู้ role แน่ชัดแล้ว
/// อธิบายลงรายละเอียดปุ่ม/ฟีเจอร์ของ role นั้นได้เจาะจงกว่า และมีเนื้อหาเยอะพอที่
/// จะลากเปลี่ยนหน้าได้หลายหน้าต่อ role เดียว) ใช้เอฟเฟกต์ Liquid Swipe เดิม
class OnboardingScreen extends StatefulWidget {
  /// 'driver' | 'ambulance' | 'agency'
  final String role;

  /// true = เปิดจากเมนู "ดูอีกครั้ง" ในหน้าตั้งค่า (ไม่ต้อง mark ว่าเห็นแล้วซ้ำ,
  /// กดปิดแล้วแค่ pop กลับหน้าเดิม)
  final bool isReplay;

  const OnboardingScreen({
    super.key,
    required this.role,
    this.isReplay = false,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final LiquidController _liquidController = LiquidController();
  int _currentPage = 0;

  static const Map<String, _RoleOnboardingData> _roleData = {
    'driver': _RoleOnboardingData(
      color: Color(0xFF3B82F6),
      illustrationAsset: 'assets/illustrations/onboarding_driver.svg',
      pages: [
        _PageData(
          badgeIcon: Icons.radar_rounded,
          title: 'ผู้ใช้ทั่วไป (Driver)',
          description:
              'แอปจะแจ้งเตือนทันทีเมื่อมีรถพยาบาลเปิดสัญญาณไซเรนกำลังเข้าใกล้ '
              'พร้อมบอกระยะห่างและทิศทางแบบเรียลไทม์ ให้คุณชะลอ/เบี่ยงทางได้ทันเวลา',
        ),
        _PageData(
          badgeIcon: Icons.emergency_share_rounded,
          title: 'ปุ่ม SOS',
          description:
              'มุมขวาล่างของแผนที่ กดเมื่อพบเหตุฉุกเฉิน แอปจะพาไปหน้าแจ้งเหตุ '
              'ให้ถ่ายรูปสถานที่เกิดเหตุและกรอกรายละเอียดส่งตรงถึงศูนย์สั่งการทันที',
        ),
        _PageData(
          badgeIcon: Icons.my_location_rounded,
          title: 'วงรัศมีแจ้งเตือน + ปุ่มจัดกึ่งกลาง GPS',
          description:
              'วงสีฟ้าบนแผนที่คือระยะเรดาร์ (เห็นล่วงหน้า) วงสีแดงคือระยะวิกฤต '
              '(ต้องหลบทาง) ปรับระยะทั้งสองได้ในหน้าตั้งค่า ส่วนปุ่มวงกลมข้างแผนที่ '
              'ใช้เลื่อนกลับมาที่ตำแหน่งปัจจุบันของคุณทันที',
        ),
      ],
    ),
    'ambulance': _RoleOnboardingData(
      color: Color(0xFFEB5757),
      illustrationAsset: 'assets/illustrations/onboarding_ambulance.svg',
      pages: [
        _PageData(
          badgeIcon: Icons.wifi_tethering_rounded,
          title: 'รถพยาบาล (Ambulance)',
          description:
              'เปิดสัญญาณเตือนแล้วแอปจะกระจายตำแหน่ง/ทิศทาง/ความเร็วของคุณแบบเรียลไทม์ '
              'ให้ผู้ใช้ถนนที่อยู่ใกล้เคียงเห็นและเปิดทางให้ล่วงหน้า',
        ),
        _PageData(
          badgeIcon: Icons.campaign_rounded,
          title: 'สวิตช์ "ส่งสัญญาณเตือน"',
          description:
              'อยู่ในการ์ดสถานะที่ลากขึ้น-ลงได้ด้านล่างแผนที่ เปิดสวิตช์นี้เพื่อกระจาย'
              'ตำแหน่งของคุณให้ผู้ใช้ถนนใกล้เคียงเห็นและเปิดทางให้ทันเวลา '
              '(ระบบจะเปิดให้อัตโนมัติทันทีที่มีเคสมอบหมายมาจริง)',
        ),
        _PageData(
          badgeIcon: Icons.home_work_rounded,
          title: 'โหมดทดสอบในห้อง + ปุ่มจัดกึ่งกลาง GPS',
          description:
              'เปิด "โหมดทดสอบในห้อง" ตอนสาธิต/ทดสอบในอาคาร เพื่อข้ามการจับคู่'
              'เส้นทางถนนจริงที่ไม่ตรงกับตำแหน่งจำลอง ส่วนปุ่มวงกลมข้างแผนที่ใช้'
              'เลื่อนกลับมาที่ตำแหน่งรถพยาบาลของคุณทันที',
        ),
      ],
    ),
    'agency': _RoleOnboardingData(
      color: Color(0xFF00A896),
      illustrationAsset: 'assets/illustrations/onboarding_agency.svg',
      pages: [
        _PageData(
          badgeIcon: Icons.dashboard_customize_rounded,
          title: 'หน่วยงาน/โรงพยาบาล (Agency)',
          description:
              'ศูนย์สั่งการเห็นรถพยาบาลทุกคันบนแผนที่แบบสด มอบหมายเคสให้คันที่ใกล้ที่สุด '
              'และเตรียมทีม ER ล่วงหน้าก่อนรถพยาบาลถึงโรงพยาบาลจริง',
        ),
        _PageData(
          badgeIcon: Icons.local_fire_department_rounded,
          title: 'จุดเสี่ยงอุบัติเหตุ (Hotspot)',
          description:
              'ปุ่มรูปไฟที่แถบด้านบนแผนที่ เปิด/ปิดแผนที่ความหนาแน่นจุดเกิดเหตุสะสม '
              'ช่วยให้เห็นภาพรวมพื้นที่เสี่ยงในเขตรับผิดชอบของคุณ',
        ),
        _PageData(
          badgeIcon: Icons.local_hospital_rounded,
          title: 'สถานะห้องฉุกเฉิน (ER)',
          description:
              'ปุ่ม "ER ว่าง/ER เต็ม" ที่แถบด้านบน กดเพื่ออัปเดตสถานะจริง '
              'มีผลโดยตรงต่อการเลือกโรงพยาบาลปลายทางของระบบ — รพ. ที่ ER ว่างจะถูก'
              'เลือกก่อนแม้จะไกลกว่าเล็กน้อย',
        ),
      ],
    ),
  };

  _RoleOnboardingData get _data => _roleData[widget.role]!;

  void _finishOnboarding() async {
    if (widget.isReplay) {
      if (mounted) Navigator.pop(context);
      return;
    }
    await OnboardingService.markOnboardingSeen(widget.role);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pages = _data.pages;
    final isLastPage = _currentPage == pages.length - 1;

    return Scaffold(
      body: Stack(
        children: [
          LiquidSwipe(
            liquidController: _liquidController,
            enableLoop: false,
            waveType: WaveType.liquidReveal,
            fullTransitionValue: 400,
            slideIconWidget: const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.black45),
            onPageChangeCallback: (page) {
              setState(() => _currentPage = page);
            },
            pages: pages.map((p) => _buildPage(p)).toList(growable: false),
          ),

          if (!isLastPage)
            Positioned(
              top: 50,
              right: 20,
              child: TextButton(
                onPressed: _finishOnboarding,
                child: const Text(
                  'ข้าม',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                ),
              ),
            ),

          Positioned(
            bottom: isLastPage ? 110 : 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(pages.length, (i) {
                final active = i == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: active ? 1.0 : 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),

          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: isLastPage ? 1.0 : 0.0,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutBack,
                scale: isLastPage ? 1.0 : 0.85,
                child: IgnorePointer(
                  ignoring: !isLastPage,
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _finishOnboarding,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _data.color,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        widget.isReplay ? 'ปิด' : 'เริ่มต้นใช้งาน',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(_PageData page) {
    return Container(
      color: _data.color,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              SizedBox(
                width: 260,
                height: 260,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 260,
                      height: 260,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(28),
                      child: SvgPicture.asset(
                        _data.illustrationAsset,
                        fit: BoxFit.contain,
                      ),
                    ),
                    Positioned(
                      right: 6,
                      bottom: 14,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _data.color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Icon(page.badgeIcon,
                            size: 20, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              Text(
                page.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                page.description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleOnboardingData {
  final Color color;
  final String illustrationAsset;
  final List<_PageData> pages;

  const _RoleOnboardingData({
    required this.color,
    required this.illustrationAsset,
    required this.pages,
  });
}

class _PageData {
  final IconData badgeIcon;
  final String title;
  final String description;

  const _PageData({
    required this.badgeIcon,
    required this.title,
    required this.description,
  });
}
