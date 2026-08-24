import 'package:flutter/material.dart';
import 'ambulance_home_screen.dart';
import 'ambulance_settings_screen.dart';
import 'ambulance_incident_list_screen.dart';
import 'ambulance_profile_screen.dart';

class AmbulanceMainScreen extends StatefulWidget {
  const AmbulanceMainScreen({super.key});

  @override
  State<AmbulanceMainScreen> createState() => _AmbulanceMainScreenState();
}

class _AmbulanceMainScreenState extends State<AmbulanceMainScreen> {
  int _currentIndex = 0;

  // รวมหน้าทั้ง 4 หน้าของฝั่งรถพยาบาลไว้ใน IndexedStack เพื่อสลับหน้าลื่นไหลไม่กระตุก
  final List<Widget> _pages = const [
    AmbulanceHomeScreen(),          // Index 0: หน้า Map / Home ฝั่งรถพยาบาล
    AmbulanceIncidentListScreen(),  // Index 1: หน้า Incident เคสฝั่งรถพยาบาล
    AmbulanceSettingsScreen(),        // Index 2: หน้า Settings
    AmbulanceProfileScreen(),          // Index 3: หน้า Profile
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 🚀 ใช้ IndexedStack ให้สลับหน้าได้เนียนๆ 60-120 FPS
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),

      // แถบนำทางด้านล่างสไตล์ธีมสีแดงเจ้าหน้าที่กู้ภัย
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index; // เปลี่ยนเฉพาะ Index เพื่อสลับหน้าทันที
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFFEB5757), // สีแดงสำหรับฝั่งรถพยาบาล
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