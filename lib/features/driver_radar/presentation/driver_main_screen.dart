import 'package:flutter/material.dart';
import 'driver_home_screen.dart';
import 'incident_list_screen.dart';
import 'driver_settings_screen.dart';
import 'driver_profile_screen.dart';

class DriverMainScreen extends StatefulWidget {
  const DriverMainScreen({super.key});

  @override
  State<DriverMainScreen> createState() => _DriverMainScreenState();
}

class _DriverMainScreenState extends State<DriverMainScreen> {
  int _currentIndex = 0;

  // รวมหน้าทั้ง 4 หน้าไว้ใน IndexedStack เพื่อสลับหน้าได้ลื่นไหล ไร้การกระตุก
  final List<Widget> _pages = const [
    DriverHomeScreen(),       // Index 0: หน้า Map
    IncidentListScreen(),     // Index 1: หน้า Incident
    DriverSettingsScreen(),   // Index 2: หน้า Settings
    DriverProfileScreen(),    // Index 3: หน้า Profile
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 🚀 ใช้ IndexedStack เพื่อโหลดทุกหน้าไว้ใน Memory สลับได้ทันที 60-120 FPS
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),

      // แถบเมนูน้านล่างรวมไว้ที่นี่ที่เดียว
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
          selectedItemColor: const Color(0xFF2C3E50),
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
              icon: Icon(Icons.airport_shuttle_outlined, size: 28),
              activeIcon: Icon(Icons.airport_shuttle_rounded, size: 28),
              label: 'Ambulance',
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