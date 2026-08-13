import 'package:flutter/material.dart';
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

  final List<Widget> _pages = const [
    AgencyHomeScreen(),         // Index 0: แผนที่เฝ้าระวัง
    AgencyIncidentListScreen(), // Index 1: รายการเคส ER
    AgencySettingsScreen(),     // Index 2: ตั้งค่า (เสียง, Background)
    AgencyProfileScreen(),      // Index 3: ข้อมูลสถิติ (Dashboard)
  ];

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