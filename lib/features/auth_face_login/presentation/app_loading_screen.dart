import 'package:flutter/material.dart';
import '../../../core/utils/role_screen_resolver.dart';
import '../../../core/utils/slide_from_right_route.dart';
import '../data/models/user_face_profile.dart';
import '../data/services/face_auth_repository.dart';
import 'face_login_screen.dart';

/// หน้าโหลดตอนเปิดแอป — เช็คว่ามี session ที่ยังไม่ได้ logout ค้างอยู่หรือไม่ (ดู
/// CHANGES_SUMMARY.md หัวข้อ 17) แล้วพาไปหน้าที่ถูกต้องด้วยทรานสิชันลากเข้าจากขวา
/// ระหว่างเช็ค (เร็วมาก แค่ไม่กี่ ms) โชว์มือการ์ตูนที่วาดเองด้วย CustomPainter
/// (ไม่ใช้ emoji) นิ้วทั้ง 4 กางออกเป็นพัดแล้วงอเข้าซ้อนกันต่อเนื่องเหมือนในคลิป
/// ตัวอย่างที่ผู้ใช้ส่งมา (นิ้วขยับ ไม่ใช่กำมือเป็นก้อนตันแบบ emoji ✊) — บังคับโชว์
/// อย่างน้อย ~1.1 วินาที กันอนิเมชันกะพริบผ่านตาเร็วเกินจนไม่ทันได้เห็น
class AppLoadingScreen extends StatefulWidget {
  const AppLoadingScreen({super.key});

  @override
  State<AppLoadingScreen> createState() => _AppLoadingScreenState();
}

class _AppLoadingScreenState extends State<AppLoadingScreen>
    with SingleTickerProviderStateMixin {
  static const _minDisplayDuration = Duration(milliseconds: 1100);

  late final AnimationController _handController;

  @override
  void initState() {
    super.initState();
    _handController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )
      ..addStatusListener((status) {
        if (!mounted) return;
        if (status == AnimationStatus.completed) {
          _handController.reverse();
        } else if (status == AnimationStatus.dismissed) {
          _handController.forward();
        }
      })
      ..forward();
    _checkSessionAndNavigate();
  }

  @override
  void dispose() {
    _handController.dispose();
    super.dispose();
  }

  Future<void> _checkSessionAndNavigate() async {
    final results = await Future.wait([
      FaceAuthRepository.getCurrentUser(),
      Future.delayed(_minDisplayDuration),
    ]);
    if (!mounted) return;

    final existingUser = results[0] as UserFaceProfile?;
    final destination = existingUser != null
        ? roleHomeScreenFor(existingUser.role)
        : const FaceLoginScreen();

    Navigator.pushReplacement(context, slideFromRightRoute(destination));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _handController,
              builder: (context, _) {
                return CustomPaint(
                  size: const Size(150, 120),
                  painter: _HandPainter(_handController.value),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'LOADING',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
                color: Color(0xFF3B5BFB),
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// วาดมือการ์ตูนเอง (ไม่ใช้ emoji/ไอคอนสำเร็จรูป) ตามคลิปตัวอย่าง — นิ้วทั้ง 4
/// เป็นแท่งแคปซูลแยกชิ้นที่มองเห็นตลอดทุกเฟรม กางออกเป็นพัด (t=0) แล้วงอเข้า
/// ซ้อนทับกันแน่น (t=1) พร้อมกัน (มีหน่วงจังหวะเล็กน้อยต่อนิ้วให้ดูเป็นคลื่น)
/// ไม่ยุบรวมเป็นก้อนกำมือตันแบบ emoji ✊ — นิ้วโป้งอยู่นิ่งเกือบตลอด ขยับเบาๆ
/// ตามจังหวะเดียวกัน
class _HandPainter extends CustomPainter {
  _HandPainter(this.t);

  final double t;

  static const _fill = Color(0xFF3B5BFB);
  static const _outline = Color(0xFF1B2560);

  double _fingerT(int index) {
    final shifted = (t + index * 0.07).clamp(0.0, 1.0);
    return Curves.easeInOut.transform(shifted);
  }

  void _drawCapsule(
    Canvas canvas,
    Paint fill,
    Paint stroke,
    Offset base,
    double length,
    double width,
    double angle,
  ) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angle);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(-width / 2, -length, width, length),
      Radius.circular(width / 2),
    );
    canvas.drawRRect(rrect, fill);
    canvas.drawRRect(rrect, stroke);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = _fill;
    final stroke = Paint()
      ..color = _outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeJoin = StrokeJoin.round;

    // ฝ่ามือ (นิ่ง อยู่มุมล่างขวา)
    final palm = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.42,
        size.height * 0.46,
        size.width * 0.5,
        size.height * 0.46,
      ),
      Radius.circular(size.height * 0.22),
    );
    canvas.drawRRect(palm, fill);
    canvas.drawRRect(palm, stroke);

    // นิ้วโป้ง — เกือบนิ่ง ขยับเอียงเบาๆ ตามจังหวะเดียวกับนิ้วอื่น
    final thumbWiggle = _fingerT(0) * 0.15;
    canvas.save();
    canvas.translate(size.width * 0.86, size.height * 0.78);
    canvas.rotate(0.95 + thumbWiggle);
    final thumb = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        -size.width * 0.09,
        -size.height * 0.42,
        size.width * 0.18,
        size.height * 0.42,
      ),
      Radius.circular(size.width * 0.09),
    );
    canvas.drawRRect(thumb, fill);
    canvas.drawRRect(thumb, stroke);
    canvas.restore();

    // นิ้วทั้ง 4 — เหยียดกางเป็นพัด (t=0) <-> งอซ้อนกันแน่น (t=1)
    // วาดจากนิ้วขวา(ในสุด)ไปซ้าย(นอกสุด) ให้นิ้วนอกสุดทับอยู่บนสุดตอนซ้อนกัน
    const spreadAngles = [-0.62, -0.32, -0.02, 0.24];
    const curledAngles = [-0.20, -0.09, 0.02, 0.14];
    const spreadDxFrac = [0.30, 0.44, 0.58, 0.70];
    const curledDxFrac = [0.42, 0.50, 0.58, 0.64];

    for (var i = 3; i >= 0; i--) {
      final ft = _fingerT(i);
      final angle = _lerp(spreadAngles[i], curledAngles[i], ft);
      final dxFrac = _lerp(spreadDxFrac[i], curledDxFrac[i], ft);
      final length = _lerp(size.height * 0.62, size.height * 0.34, ft);
      final base = Offset(size.width * dxFrac, size.height * 0.5);
      _drawCapsule(canvas, fill, stroke, base, length, size.width * 0.15, angle);
    }
  }

  @override
  bool shouldRepaint(covariant _HandPainter oldDelegate) => oldDelegate.t != t;
}
