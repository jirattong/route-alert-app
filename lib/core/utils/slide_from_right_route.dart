import 'package:flutter/material.dart';

/// ทรานสิชันแบบลากหน้าใหม่เข้ามาจากขวาสุดของจอ พร้อม fade เบาๆ — ใช้แทน
/// MaterialPageRoute เริ่มต้น (ที่แค่ fade+scale จางๆ) ตอนออกจากหน้าโหลด
/// (AppLoadingScreen) ไปหน้าล็อกอิน/หน้าหลักของแต่ละ role ให้ดูมีมิติ/หวือหวาขึ้น
/// ตามที่ผู้ใช้ขอ
PageRouteBuilder<T> slideFromRightRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 550),
    reverseTransitionDuration: const Duration(milliseconds: 400),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}
