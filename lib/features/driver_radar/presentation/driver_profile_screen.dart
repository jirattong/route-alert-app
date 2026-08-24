import 'package:flutter/material.dart';
import '../../../core/services/driver_storage_service.dart';
import '../../auth_face_login/data/models/user_face_profile.dart';
import '../../auth_face_login/data/services/face_auth_repository.dart';
import '../../auth_face_login/presentation/face_login_screen.dart';
import '../../auth_face_login/presentation/face_scan_screen.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  int _yieldsCount = 67;
  UserFaceProfile? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final count = await DriverStorageService.getYieldCount();
    final user = await FaceAuthRepository.getCurrentUser();
    if (mounted) {
      setState(() {
        _yieldsCount = count;
        _currentUser = user;
      });
    }
  }

  void _onReEnrollFace() async {
    final newEmbedding = await Navigator.push<List<double>>(
      context,
      MaterialPageRoute(
        builder: (_) => FaceScanScreen(
          mode: FaceScanMode.register,
          registrationEmail: _currentUser?.email,
          registrationName: _currentUser?.name,
        ),
      ),
    );

    if (newEmbedding != null && newEmbedding.isNotEmpty && _currentUser != null) {
      await FaceAuthRepository.updateUserFaceEmbedding(_currentUser!.email, newEmbedding);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF00A896),
            content: Text('อัปเดตข้อมูลใบหน้า Face ID สำเร็จเรียบร้อย'),
          ),
        );
      }
    }
  }

  void _onRemoveFace() async {
    if (_currentUser == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('ยืนยันลบข้อมูลใบหน้า?'),
        content: const Text('เมื่อลบแล้ว คุณจะไม่สามารถเข้าสู่ระบบด้วย Face Login ได้จนกว่าจะลงทะเบียนใหม่'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('ยืนยันลบ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FaceAuthRepository.removeUserFaceEmbedding(_currentUser!.email);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบข้อมูลใบหน้าเรียบร้อยแล้ว')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  children: [
                    // Profile Header Card
                    _buildUserProfileCard(),
                    const SizedBox(height: 18),

                    // Stats Card
                    _buildStatsCard(),
                    const SizedBox(height: 20),

                    // Face Biometrics Management Card
                    _buildFaceManagementCard(),
                    const SizedBox(height: 24),

                    _buildMenuTile('แก้ไขข้อมูลส่วนตัว (Edit info)', Icons.person_outline, () {}),
                    _buildMenuTile('แก้ไขรหัสผ่าน (Password)', Icons.lock_outline, () {}),
                    _buildMenuTile('ประวัติการช่วยเหลือ (History)', Icons.history_rounded, () {}),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await FaceAuthRepository.logout();
                          if (!context.mounted) return;
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const FaceLoginScreen(),
                            ),
                            (route) => false,
                          );
                        },
                        icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                        label: const Text(
                          'ออกจากระบบ (Logout)',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.shade400,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: Text(
          'RouteAlert Driver Profile',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildUserProfileCard() {
    final name = _currentUser?.name ?? 'ผู้ขับขี่ทั่วไป';
    final email = _currentUser?.email ?? 'driver@routealert.com';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF5B9EE1).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person, color: Color(0xFF5B9EE1), size: 36),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B9EE1).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'บทบาท: ผู้ใช้ทั่วไป (Driver)',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF5B9EE1),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B9EE1).withValues(alpha: 0.1),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'สถิติการเปิดทางช่วยเหลือ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 110,
            height: 110,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 110,
                  height: 110,
                  child: CircularProgressIndicator(
                    value: (_yieldsCount % 100) / 100,
                    strokeWidth: 10,
                    backgroundColor: Colors.grey.shade200,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFF5B9EE1)),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Text(
                  '$_yieldsCount',
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'ครั้งที่เปิดทางให้รถฉุกเฉินสำเร็จ (Yields)',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildFaceManagementCard() {
    final hasFace = _currentUser?.faceEmbedding.isNotEmpty ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasFace ? const Color(0xFF00A896) : Colors.orangeAccent,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasFace ? Icons.verified_user_rounded : Icons.gpp_maybe_rounded,
                color: hasFace ? const Color(0xFF00A896) : Colors.orangeAccent,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text(
                'ความปลอดภัยชีวมิติ (Face ID AI)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasFace
                ? 'ผูกใบหน้า 3 มุมมองเรียบร้อย (เปิดใช้งาน MobileFaceNet Auto Login)'
                : 'ยังไม่ได้ผูกข้อมูลใบหน้า สามารถสแกนเพื่อเข้าสู่ระบบแบบไร้รหัสผ่านได้',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _onReEnrollFace,
                  icon: const Icon(Icons.face_retouching_natural_rounded, size: 16, color: Colors.white),
                  label: Text(
                    hasFace ? 'สแกนใบหน้าใหม่' : 'ลงทะเบียนใบหน้า',
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A896),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              if (hasFace) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _onRemoveFace,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  ),
                  child: const Text('ลบ', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile(String title, IconData icon, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF5B9EE1), size: 22),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}