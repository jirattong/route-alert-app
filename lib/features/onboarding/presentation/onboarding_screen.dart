import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final LiquidController _liquidController = LiquidController();
  int _currentPage = 0;

  // ความใกล้ "อยู่ที่หน้าสุดท้าย" แบบต่อเนื่อง (0..1) ขับเคลื่อนปุ่ม "เริ่มต้นใช้งาน"
  // ให้ fade เข้า/ออกตามจังหวะการลากนิ้วจริง ไม่ใช่โผล่/หายตัดทันทีตอนเปลี่ยนหน้า
  // เสร็จแบบเดิม (ดูไม่ต่อเนื่องกับคลื่นที่เพิ่งปรับให้ลื่นขึ้น) — คำนวณจาก
  // slidePercentCallback ของ liquid_swipe ซึ่งรายงานความคืบหน้าการลากสดๆ
  double _lastPageProximity = 0.0;

  // ระลอกคลื่นน้ำจางๆ ที่ตามตำแหน่งนิ้วจริง (ไม่ใช่ตำแหน่งที่ liquid_swipe คำนวณ
  // ภายในซึ่งดึงมาใช้ตรงๆ ไม่ได้) — ใช้ Listener แยกดักจับตำแหน่งนิ้วดิบเอง แล้ว
  // วนแอนิเมชันต่อเนื่องตราบใดที่นิ้วยังแตะจอค้างอยู่ (ไม่ใช่แค่ตอนขยับเท่านั้น) ให้
  // ความรู้สึกเหมือนน้ำมีชีวิต ไม่ใช่ภาพนิ่งที่ขยับตาม 1:1 กับนิ้วอย่างเดียว — คลื่นหลัก
  // (wave ของ liquid_swipe เอง ที่ยึดตำแหน่งนิ้วปัจจุบันอยู่แล้ว) ไม่ถูกแตะต้องเลย
  // ระลอกนี้เป็นแค่ชั้นตกแต่งซ้อนทับด้านบนเท่านั้น ไม่กันการลากใดๆ ทั้งสิ้น
  late final AnimationController _rippleController;
  final ValueNotifier<Offset?> _touchPosition = ValueNotifier(null);
  final ValueNotifier<bool> _isTouching = ValueNotifier(false);

  // แต่ละหน้าต้องมีสีต่างกันจริง (ไม่ใช่สีเดียวกันทั้ง 3 หน้าแบบเดิม) — ไม่งั้นคลื่น
  // liquid swipe จะไม่มีสีให้ morph ให้เห็นตอนลากนิ้วเปลี่ยนหน้า (สีเดิมทำให้หน้าก่อน/
  // หลังกลมกลืนกันจนดูเหมือนไม่มีคลื่นเลย) แต่ละ role ไล่โทนสีในกลุ่มเดียวกันไว้ให้ยัง
  // รู้สึกเป็นชุดเดียวกัน
  static const Map<String, _RoleOnboardingData> _roleData = {
    'driver': _RoleOnboardingData(
      illustrationAsset: 'assets/illustrations/onboarding_driver.svg',
      pages: [
        _PageData(
          color: Color(0xFF3B82F6),
          badgeIcon: Icons.radar_rounded,
          title: 'ผู้ใช้ทั่วไป (Driver)',
          description:
              'แอปจะแจ้งเตือนทันทีเมื่อมีรถพยาบาลเปิดสัญญาณไซเรนกำลังเข้าใกล้ '
              'พร้อมบอกระยะห่างและทิศทางแบบเรียลไทม์ ให้คุณชะลอ/เบี่ยงทางได้ทันเวลา',
        ),
        _PageData(
          color: Color(0xFF8B5CF6),
          badgeIcon: Icons.emergency_share_rounded,
          title: 'ปุ่ม SOS',
          description:
              'มุมขวาล่างของแผนที่ กดเมื่อพบเหตุฉุกเฉิน แอปจะพาไปหน้าแจ้งเหตุ '
              'ให้ถ่ายรูปสถานที่เกิดเหตุและกรอกรายละเอียดส่งตรงถึงศูนย์สั่งการทันที',
        ),
        _PageData(
          color: Color(0xFF06B6D4),
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
      illustrationAsset: 'assets/illustrations/onboarding_ambulance.svg',
      pages: [
        _PageData(
          color: Color(0xFFEB5757),
          badgeIcon: Icons.wifi_tethering_rounded,
          title: 'รถพยาบาล (Ambulance)',
          description:
              'เปิดสัญญาณเตือนแล้วแอปจะกระจายตำแหน่ง/ทิศทาง/ความเร็วของคุณแบบเรียลไทม์ '
              'ให้ผู้ใช้ถนนที่อยู่ใกล้เคียงเห็นและเปิดทางให้ล่วงหน้า',
        ),
        _PageData(
          color: Color(0xFFF2994A),
          badgeIcon: Icons.campaign_rounded,
          title: 'สวิตช์ "ส่งสัญญาณเตือน"',
          description:
              'อยู่ในการ์ดสถานะที่ลากขึ้น-ลงได้ด้านล่างแผนที่ เปิดสวิตช์นี้เพื่อกระจาย'
              'ตำแหน่งของคุณให้ผู้ใช้ถนนใกล้เคียงเห็นและเปิดทางให้ทันเวลา '
              '(ระบบจะเปิดให้อัตโนมัติทันทีที่มีเคสมอบหมายมาจริง)',
        ),
        _PageData(
          color: Color(0xFFEC4899),
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
      illustrationAsset: 'assets/illustrations/onboarding_agency.svg',
      pages: [
        _PageData(
          color: Color(0xFF00A896),
          badgeIcon: Icons.dashboard_customize_rounded,
          title: 'หน่วยงาน/โรงพยาบาล (Agency)',
          description:
              'ศูนย์สั่งการเห็นรถพยาบาลทุกคันบนแผนที่แบบสด มอบหมายเคสให้คันที่ใกล้ที่สุด '
              'และเตรียมทีม ER ล่วงหน้าก่อนรถพยาบาลถึงโรงพยาบาลจริง',
        ),
        _PageData(
          color: Color(0xFF0EA5E9),
          badgeIcon: Icons.local_fire_department_rounded,
          title: 'จุดเสี่ยงอุบัติเหตุ (Hotspot)',
          description:
              'ปุ่มรูปไฟที่แถบด้านบนแผนที่ เปิด/ปิดแผนที่ความหนาแน่นจุดเกิดเหตุสะสม '
              'ช่วยให้เห็นภาพรวมพื้นที่เสี่ยงในเขตรับผิดชอบของคุณ',
        ),
        _PageData(
          color: Color(0xFF10B981),
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

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void dispose() {
    _rippleController.dispose();
    _touchPosition.dispose();
    _isTouching.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _touchPosition.value = event.localPosition;
    _isTouching.value = true;
    _rippleController.repeat();
  }

  void _onPointerMove(PointerMoveEvent event) {
    _touchPosition.value = event.localPosition;
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    _isTouching.value = false;
    _rippleController.stop();
  }

  // liquid_swipe เรียก onPageChangeCallback/slidePercentCallback จากข้างใน build
  // cycle ของ Consumer<LiquidProvider> ของมันเองได้ ถ้า setState() ตรงๆ ทันที
  // อาจชนกฎ "ไม่เรียก setState ระหว่าง build อยู่" ของ Flutter (เจอจริงตอนทดสอบ
  // ด้วย widget test จำลองลาก ไม่ใช่แค่ทฤษฎี) เลื่อนไปอัปเดตหลังเฟรมปัจจุบันจบแทน
  // เพื่อความปลอดภัย ดีเลย์แค่ ~1 เฟรมมองไม่ทันสายตา
  void _scheduleSetState(VoidCallback update) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(update);
    });
  }

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
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUpOrCancel,
        onPointerCancel: _onPointerUpOrCancel,
        child: Stack(
        children: [
          LiquidSwipe(
            liquidController: _liquidController,
            enableLoop: false,
            // เดิมเปลี่ยนมาใช้ circularReveal เพราะคิดว่า liquidReveal คือตัวที่
            // ดูแข็ง/เป็นวงรีเบี้ยว — ที่จริงแล้ว "แข็ง" ตอนนั้นมาจากสีพื้นหลังซ้ำกัน
            // ทุกหน้า (แก้ไปแล้วในหัวข้อ 20) ไม่ใช่จาก wave type เอง เทียบเฟรมจาก
            // วิดีโออ้างอิงที่ผู้ใช้แท็กแล้วชัดเจนว่ารูปทรงคลื่นจริงเป็นเส้นโค้งแบบ S
            // เข้าจากขอบที่กำลังลาก ไม่ใช่วงกลมล้วนแบบ circularReveal เลย —
            // liquidReveal คือของที่ตรงกับวิดีโอจริง กลับมาใช้ตัวนี้แทน
            waveType: WaveType.liquidReveal,
            // เดิม 400px ต้องลากไกลกว่าจะเปลี่ยนหน้าสำเร็จ รู้สึกหนัก/ช้า ลดลงให้
            // ลากสั้นลงแล้วเปลี่ยนหน้าไว ให้ความรู้สึกเฟี๊ยว/ตอบสนองไวขึ้น
            fullTransitionValue: 280,
            // ค่าดีฟอลต์ของ package เอง (0.8) — สูตรเส้นโค้งของ liquidReveal (จุด
            // ควบคุม cubic bezier หลายจุด) ถูกออกแบบ/ปรับแต่งมาคู่กับค่านี้ ตอนลอง
            // ลดเหลือ 0.5 (กึ่งกลางจอ) พร้อมกับสลับไปใช้ circularReveal ไปด้วยก่อน
            // หน้านี้ ทำให้เทียบผลยาก กลับมาใช้ค่าดีฟอลต์เพื่อให้เข้ากับสูตรเดิม
            positionSlideIcon: 0.8,
            // ผู้ใช้ขอเอาไอคอนลูกศรในวงกลมออก เปลี่ยนเป็นสัญลักษณ์ ">>>" จางๆ
            // แค่บอกใบ้ทิศทางที่ควรลาก ไม่ใช่ปุ่มกดที่ดูเด่นเหมือนเดิม
            slideIconWidget: Opacity(
              opacity: 0.55,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  return Transform.translate(
                    offset: Offset(-i * 9.0, 0),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white,
                      size: 30,
                      shadows: [
                        Shadow(color: Colors.black26, blurRadius: 4),
                      ],
                    ),
                  );
                }),
              ),
            ),
            onPageChangeCallback: (page) {
              HapticFeedback.lightImpact();
              _scheduleSetState(() {
                _currentPage = page;
                _lastPageProximity = page == pages.length - 1 ? 1.0 : 0.0;
              });
            },
            // รายงานความคืบหน้าการลากสดๆ (0..1 ต่อการลาก 1 ครั้ง) ใช้ขับเคลื่อน
            // ปุ่ม "เริ่มต้นใช้งาน" ให้ fade ตามจังหวะนิ้วจริงแทนโผล่ตัดทันที —
            // ความหมายจะชัดเจนเฉพาะตอนอยู่หน้าสุดท้าย (ลากออก) หรือหน้าก่อนสุดท้าย
            // (ลากเข้า) เท่านั้น หน้าอื่นๆ ไม่เกี่ยวกับปุ่มนี้เลยคงค่าไว้ที่ 0
            slidePercentCallback: (double h, double v) {
              double proximity;
              if (_currentPage == pages.length - 1) {
                proximity = 1.0 - h;
              } else if (_currentPage == pages.length - 2) {
                proximity = h;
              } else {
                proximity = 0.0;
              }
              final clamped = proximity.clamp(0.0, 1.0);
              _scheduleSetState(() => _lastPageProximity = clamped);
            },
            pages: pages.map((p) => _buildPage(p)).toList(growable: false),
          ),

          // ระลอกคลื่นน้ำจางๆ วาดทับด้านบนสุด ตามตำแหน่งนิ้วจริงที่แตะอยู่ —
          // IgnorePointer กันไม่ให้ชั้นนี้ไปขวางการลากของ LiquidSwipe ข้างล่างเด็ดขาด
          IgnorePointer(
            child: AnimatedBuilder(
              animation:
                  Listenable.merge([_rippleController, _touchPosition, _isTouching]),
              builder: (context, _) {
                if (!_isTouching.value || _touchPosition.value == null) {
                  return const SizedBox.shrink();
                }
                return CustomPaint(
                  size: Size.infinite,
                  painter: _RippleWavePainter(
                    t: _rippleController.value,
                    center: _touchPosition.value!,
                  ),
                );
              },
            ),
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
            // ขยับขึ้นเลี่ยงปุ่ม "เริ่มต้นใช้งาน" ตามจังหวะเดียวกับที่ปุ่ม fade เข้า
            // (แทนกระโดดตัดทันทีแบบเดิม) ให้ทั้งสองอย่างขยับพร้อมกันลื่นๆ
            bottom: 40 + (70 * _lastPageProximity),
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
            // เดิมใช้ AnimatedOpacity/AnimatedScale ผูกกับ isLastPage (bool) ทำให้
            // ปุ่มโผล่/หายตัดทันทีตอนเปลี่ยนหน้าเสร็จเท่านั้น ไม่ต่อเนื่องกับจังหวะ
            // ลากนิ้วจริงเลย — เปลี่ยนมาใช้ _lastPageProximity ที่อัปเดตสดๆ ตาม
            // slidePercentCallback แทน ให้ปุ่ม fade เข้า/ออกและขยายตามนิ้วลากจริง
            child: Opacity(
              opacity: _lastPageProximity,
              child: Transform.scale(
                scale: 0.85 + (0.15 * _lastPageProximity),
                child: IgnorePointer(
                  ignoring: _lastPageProximity < 0.5,
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _finishOnboarding,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: pages.last.color,
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
      ),
    );
  }

  Widget _buildPage(_PageData page) {
    return Container(
      color: page.color,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              // ห่อด้วย RepaintBoundary — เนื้อหาในนี้มี BoxShadow 2 จุด (เบลอ ซึ่ง
              // เป็นการวาดที่กินแรงเครื่องกว่าปกติ) แต่ไม่เคยเปลี่ยนรูปเองเลย ตอน
              // ลากคลื่น liquid swipe ทั้งหน้าโดนหมุน/บีบ/clip ทุกเฟรม ถ้าไม่กันไว้
              // Flutter จะ rasterize เงาใหม่ทุกเฟรมที่ลาก ทำให้คลื่นดูกระตุก/ไม่ลื่น
              // — RepaintBoundary ให้ cache เป็นภาพนิ่งแล้วแค่ขยับ/clip ภาพนั้นแทน
              RepaintBoundary(
                child: SizedBox(
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
                            color: page.color,
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
  final String illustrationAsset;
  final List<_PageData> pages;

  const _RoleOnboardingData({
    required this.illustrationAsset,
    required this.pages,
  });
}

class _PageData {
  final Color color;
  final IconData badgeIcon;
  final String title;
  final String description;

  const _PageData({
    required this.color,
    required this.badgeIcon,
    required this.title,
    required this.description,
  });
}

/// วาดระลอกคลื่นน้ำ 3 วง ขยาย+จางหายออกจากจุดสัมผัส วนซ้ำต่อเนื่องตราบใดที่
/// [_rippleController] ยังหมุนอยู่ (คือตราบใดที่นิ้วยังแตะจอค้างอยู่) — แต่ละวงมี
/// เฟสต่างกัน (i/3 ของรอบ) ให้ดูเหมือนมีคลื่นทยอยแผ่ออกมาต่อเนื่องไม่ขาดตอน ไม่ใช่
/// แค่วงเดียวขยายแล้วหาย ขอบวงใส่ noise แบบ sine เล็กน้อยแทนวงกลมเรียบเป๊ะ ให้ความ
/// รู้สึกเป็นผิวน้ำมากกว่ารูปทรงเรขาคณิต
class _RippleWavePainter extends CustomPainter {
  final double t;
  final Offset center;

  _RippleWavePainter({required this.t, required this.center});

  static const _ringCount = 3;
  static const _maxRadius = 100.0;
  static const _minRadius = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < _ringCount; i++) {
      final phase = (t + i / _ringCount) % 1.0;
      final radius = _minRadius + phase * (_maxRadius - _minRadius);
      final opacity = (1.0 - phase) * 0.4;
      if (opacity <= 0.01) continue;

      final paint = Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + (1.0 - phase) * 3.0;

      final path = Path();
      const segments = 48;
      for (int s = 0; s <= segments; s++) {
        final angle = (s / segments) * 2 * math.pi;
        final wobble = math.sin(angle * 5 + t * 2 * math.pi) * 3.0;
        final point = center +
            Offset(math.cos(angle), math.sin(angle)) * (radius + wobble);
        if (s == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RippleWavePainter oldDelegate) {
    return oldDelegate.t != t || oldDelegate.center != center;
  }
}
