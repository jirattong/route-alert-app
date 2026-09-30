import 'package:flutter/material.dart';
import '../../../core/services/notification_router.dart';
import '../../../core/services/onboarding_service.dart';
import '../../onboarding/presentation/onboarding_screen.dart';
import 'agency_home_screen.dart';
import 'agency_incident_list_screen.dart';
import 'agency_settings_screen.dart';
import 'agency_profile_screen.dart';

class AgencyMainScreen extends StatefulWidget {
  const AgencyMainScreen({super.key});

  @override
  State<AgencyMainScreen> createState() => _AgencyMainScreenState();
}

class _AgencyMainScreenState extends State<AgencyMainScreen> {
  int _currentIndex = 0;
  late final List<Widget> _pages;

  // ฟังก์ชันเปิด Coach Mark ที่ AgencyHomeScreen ส่งขึ้นมาให้ตอน initState ของมัน
  // เก็บไว้เรียกตอนผู้ใช้กด "สอนการใช้งานปุ่มต่างๆ" จากหน้าตั้งค่า (คนละหน้ากัน
  // แต่ยังอยู่ใน IndexedStack เดียวกัน เลยเรียกใช้ผ่าน callback แทนได้)
  VoidCallback? _showAgencyCoachMark;

  @override
  void initState() {
    super.initState();
    _pages = [
      AgencyHomeScreen(
        onCoachMarkReady: (fn) => _showAgencyCoachMark = fn,
      ), // Index 0: แผนที่เฝ้าระวัง
      const AgencyIncidentListScreen(), // Index 1: รายการเคส ER
      AgencySettingsScreen(onShowCoachMark: _showCoachMarkTour), // Index 2: ตั้งค่า (เสียง, Background)
      const AgencyProfileScreen(), // Index 3: ข้อมูลสถิติ (Dashboard)
    ];
    _maybeShowOnboarding();
    // กดแจ้งเตือนตอนแอปปิดอยู่ → ค่อยเปิดหน้าเคสหลังหน้าหลักแสดงแล้ว
    WidgetsBinding.instance
        .addPostFrameCallback((_) => NotificationRouter.instance.onHomeShown());
  }

  @override
  void dispose() {
    NotificationRouter.instance.onHomeHidden();
    super.dispose();
  }

  // โชว์หน้าแนะนำการใช้งานแบบละเอียด (Onboarding) เฉพาะครั้งแรกที่เข้าหน้าหลักของ
  // Agency หลังล็อกอินเท่านั้น — เดิมเคยโชว์ก่อนล็อกอินรวมทั้ง 3 role ในหน้าเดียว
  // ย้ายมาตรงนี้เพราะรู้ role แน่ชัดแล้ว อธิบายเจาะจงเรื่องปุ่ม/ฟีเจอร์ได้ตรงจุดกว่า
  void _maybeShowOnboarding() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final seen = await OnboardingService.hasSeenOnboarding('agency');
      if (seen || !mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const OnboardingScreen(role: 'agency'),
        ),
      );
    });
  }

  // สลับไปแท็บแผนที่ (หน้าหลัก) แล้วเปิด Coach Mark ให้ทันที — เรียกจากปุ่ม
  // "สอนการใช้งานปุ่มต่างๆ" ในหน้าตั้งค่า ต้องรอเฟรมถัดไปก่อนเพราะปุ่ม/แถบต้อง
  // แสดงผลจริงบนจอถึงจะชี้ตำแหน่งได้ถูกต้อง (สลับแท็บอย่างเดียวยังไม่พอ)
  void _showCoachMarkTour() {
    setState(() => _currentIndex = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showAgencyCoachMark?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF2E7D32), // สีเขียวเข้มสำหรับหน่วยงาน
          unselectedItemColor: Colors.grey.shade400,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined, size: 28),
              activeIcon: Icon(Icons.map_rounded, size: 28),
              label: 'Map',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.local_hospital_outlined, size: 28),
              activeIcon: Icon(Icons.local_hospital_rounded, size: 28),
              label: 'Incident',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined, size: 28),
              activeIcon: Icon(Icons.settings_rounded, size: 28),
              label: 'Settings',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded, size: 28),
              activeIcon: Icon(Icons.person_rounded, size: 28),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}