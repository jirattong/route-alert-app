import 'package:flutter/material.dart';
import 'driver_home_screen.dart';
import 'incident_list_screen.dart';
import 'sos_report_screen.dart';
import 'driver_settings_screen.dart';
import 'driver_profile_screen.dart';

class DriverMainScreen extends StatefulWidget {
  const DriverMainScreen({super.key});

  @override
  State<DriverMainScreen> createState() => _DriverMainScreenState();
}

class _DriverMainScreenState extends State<DriverMainScreen> {
  int _currentIndex = 0;
  bool _isShowingSosScreen = false;

  void _onSelectTab(int index) {
    setState(() {
      _currentIndex = index;
      _isShowingSosScreen = false; // ปิดหน้า SOS เมื่อสลับแท็บ
    });
  }

  void _openSosScreen() {
    setState(() {
      _isShowingSosScreen = true;
    });
  }

  void _closeSosScreen() {
    setState(() {
      _isShowingSosScreen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> basePages = [
      DriverHomeScreen(
        onOpenSos: _openSosScreen,
      ),
      IncidentListScreen(
        onOpenSos: _openSosScreen,
      ),
      const DriverSettingsScreen(),
      const DriverProfileScreen(),
    ];

    return Scaffold(
      body: _isShowingSosScreen
          ? SosReportScreen(onClose: _closeSosScreen)
          : IndexedStack(
              index: _currentIndex,
              children: basePages,
            ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onSelectTab,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF5B9EE1),
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