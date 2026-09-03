import 'package:flutter/material.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/theme_settings_service.dart';
import '../../auth_face_login/data/services/face_auth_repository.dart';
import '../../auth_face_login/presentation/face_login_screen.dart';
import 'driver_home_screen.dart';
import 'incident_detail_screen.dart';
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
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    ThemeSettingsService.loadSettings();
    _pages = [
      DriverHomeScreen(onOpenSos: _openSosScreen),
      IncidentListScreen(onOpenSos: _openSosScreen),
      const DriverSettingsScreen(),
      const DriverProfileScreen(),
    ];
  }

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

    final currentPos = await LocationService.getCurrentLocation();

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => SosReportScreen(
          initialLocation: currentPos,
          onClose: () => Navigator.pop(ctx),
          onSubmitted: (incident) {
            Navigator.pop(ctx);
            setState(() => _currentIndex = 1); // Switch to Incident tab!
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => IncidentDetailScreen(incident: incident),
              ),
            );
          },
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
              'เพื่อความปลอดภัย ป้องกันการแจ้งเหตุเท็จ และเพื่อดึงเบอร์โทรศัพท์ติดต่อกลับส่งตรงให้ศูนย์สั่งการ 1669 ทันทีโดยไม่ต้องเสียเวลากรอกในยามเร่งด่วน\nกรุณายืนยันตัวตนก่อนเข้าหน้าแจ้งเหตุฉุกเฉิน (SOS)',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
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
                      final currentPos = await LocationService.getCurrentLocation();
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (modalCtx) => SosReportScreen(
                            initialLocation: currentPos,
                            onClose: () => Navigator.pop(modalCtx),
                            onSubmitted: (incident) {
                              Navigator.pop(modalCtx);
                              setState(() => _currentIndex = 1);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => IncidentDetailScreen(incident: incident),
                                ),
                              );
                            },
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
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeSettingsService.isNightMode,
      builder: (context, isDark, _) {
        return Scaffold(
          backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          body: IndexedStack(
            index: _currentIndex,
            children: _pages,
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                ),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: _onSelectTab,
              type: BottomNavigationBarType.fixed,
              backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              selectedItemColor: isDark ? const Color(0xFF60A5FA) : const Color(0xFF5B9EE1),
              unselectedItemColor: isDark ? const Color(0xFF64748B) : Colors.grey.shade400,
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
      },
    );
  }
}