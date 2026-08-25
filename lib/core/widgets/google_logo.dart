import 'package:flutter/material.dart';

/// Official Google 4-Color 'G' Logo (Custom Painted for 100% authentic crisp rendering)
class GoogleLogo extends StatelessWidget {
  final double size;

  const GoogleLogo({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width;
    final double radius = s / 2;
    final center = Offset(radius, radius);

    // Official Google Brand Colors
    final paintBlue = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;

    // Blue Bar (Horizontal arm)
    final blueBarPath = Path()
      ..moveTo(center.dx, center.dy - s * 0.1)
      ..lineTo(s * 0.96, center.dy - s * 0.1)
      ..lineTo(s * 0.96, center.dy + s * 0.1)
      ..lineTo(center.dx, center.dy + s * 0.1)
      ..close();

    // Outer Circle segments
    final rect = Rect.fromCircle(center: center, radius: radius * 0.92);
    const strokeW = 0.22;
    final strokeWidth = s * strokeW;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Blue Arc (right)
    ringPaint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -0.785, 1.1, false, ringPaint);

    // Green Arc (bottom)
    ringPaint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0.315, 1.57, false, ringPaint);

    // Yellow Arc (left)
    ringPaint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 1.885, 1.4, false, ringPaint);

    // Red Arc (top)
    ringPaint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, 3.285, 1.65, false, ringPaint);

    // Draw blue horizontal tongue
    canvas.drawPath(blueBarPath, paintBlue);

    // Minor touch up for blue bar edge
    final blueEdge = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.5, center.dy - s * 0.1, s * 0.46, s * 0.2),
      Radius.circular(s * 0.02),
    );
    canvas.drawRRect(blueEdge, paintBlue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
