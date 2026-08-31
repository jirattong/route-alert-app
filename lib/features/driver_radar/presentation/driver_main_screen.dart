import 'package:flutter/material.dart';
import '../../auth_face_login/data/services/face_auth_repository.dart';
import '../../auth_face_login/presentation/face_login_screen.dart';
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

  void _onSelectTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _openSosScreen() async {
    final currentUser = await FaceAuthRepository.getCurrentUser();
    final bool isGuest = currentUser == null || currentUser.id == 'guest';

    if (isGuest) {
      if (!mounted) return;
      _showSosLoginRequiredDialog();
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => SosReportScreen(
          onClose: () => Navigator.pop(ctx),
        ),
      ),
    );
  }

  void _showSosLoginRequiredDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.security_rounded,
                color: Color(0xFFDC2626),
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'ต้องเข้าสู่ระบบก่อนแจ้งเหตุฉุกเฉิน (SOS)',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18.5,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'เพื่อความปลอดภัยและป้องกันการแจ้งเหตุเท็จ/สแปม (Anti-Spam)\nระบบจำเป็นต้องยืนยันตัวตนผู้แจ้งเหตุกับศูนย์รับแจ้งเหตุ 1669',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.grey.shade600,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FaceLoginScreen(),
                    ),
                  ).then((_) async {
                    // If user logged in successfully, open SOS directly
                    final user = await FaceAuthRepository.getCurrentUser();
                    if (user != null && user.id != 'guest' && mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (modalCtx) => SosReportScreen(
                            onClose: () => Navigator.pop(modalCtx),
                          ),
                        ),
                      );
                    }
                  });
                },
                icon: const Icon(Icons.login_rounded,
                    color: Colors.white, size: 20),
                label: const Text(
                  'เข้าสู่ระบบ / สแกนใบหน้า (Face ID)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'ยกเลิก',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
      body: IndexedStack(
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