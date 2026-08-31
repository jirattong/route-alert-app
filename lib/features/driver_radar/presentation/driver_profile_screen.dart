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
  int _yieldsCount = 14;
  UserFaceProfile? _currentUser;
  String _phone = '081-234-5678';
  String _carPlate = 'กข-9999 เชียงใหม่';

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
    if (_currentUser == null || _currentUser?.id == 'guest') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orangeAccent,
          content: Text('⚠️ กรุณาเข้าสู่ระบบหรือลงทะเบียนก่อนบันทึก Face ID'),
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const FaceLoginScreen()),
      ).then((_) => _loadData());
      return;
    }

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
            content: Text('✅ อัปเดตข้อมูลใบหน้า Face ID สำเร็จเรียบร้อย'),
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

  void _showEditProfileDialog() {
    final nameCtrl = TextEditingController(text: _currentUser?.name ?? '');
    final phoneCtrl = TextEditingController(text: _phone);
    final plateCtrl = TextEditingController(text: _carPlate);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'แก้ไขข้อมูลส่วนตัว (Edit Profile)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'ชื่อ - นามสกุล',
                prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF5B9EE1)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'เบอร์โทรศัพท์ติดต่อ',
                prefixIcon: const Icon(Icons.phone_outlined, color: Color(0xFF5B9EE1)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: plateCtrl,
              decoration: InputDecoration(
                labelText: 'ทะเบียนรถส่วนตัว',
                prefixIcon: const Icon(Icons.directions_car_outlined, color: Color(0xFF5B9EE1)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    if (nameCtrl.text.isNotEmpty && _currentUser != null) {
                      _currentUser = _currentUser!.copyWith(name: nameCtrl.text.trim());
                    }
                    _phone = phoneCtrl.text.trim();
                    _carPlate = plateCtrl.text.trim();
                  });
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ อัปเดตข้อมูลส่วนตัวสำเร็จ'),
                      backgroundColor: Color(0xFF10B981),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B9EE1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('บันทึกข้อมูล', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog() {
    final oldPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'เปลี่ยนรหัสผ่าน (Change Password)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: oldPassCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'รหัสผ่านเดิม',
                prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF5B9EE1)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPassCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'รหัสผ่านใหม่ (อย่างน้อย 6 ตัวอักษร)',
                prefixIcon: const Icon(Icons.lock_reset_rounded, color: Color(0xFF5B9EE1)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPassCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'ยืนยันรหัสผ่านใหม่',
                prefixIcon: const Icon(Icons.check_circle_outline, color: Color(0xFF5B9EE1)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  if (newPassCtrl.text.length < 6) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('รหัสผ่านใหม่ต้องมีความยาวอย่างน้อย 6 ตัวอักษร')),
                    );
                    return;
                  }
                  if (newPassCtrl.text != confirmPassCtrl.text) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('รหัสผ่านใหม่ไม่ตรงกัน กรุณาตรวจสอบอีกครั้ง')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ เปลี่ยนรหัสผ่านสำเร็จเรียบร้อย'),
                      backgroundColor: Color(0xFF10B981),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5B9EE1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('ยืนยันเปลี่ยนรหัสผ่าน', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showYieldHistoryDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.history_rounded, color: Color(0xFF10B981), size: 24),
                  SizedBox(width: 8),
                  Text('ประวัติการเปิดทางช่วยเหลือ (Yield History)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: Color(0xFFFEE2E2), shape: BoxShape.circle),
                  child: const Text('🚑', style: TextStyle(fontSize: 20)),
                ),
                title: const Text('เปิดทางให้รถกู้ชีพ 1669 (ถ.สุเทพ)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('ช่วยประหยัดเวลาส่งผู้ป่วยฉุกเฉิน ~2.5 นาที'),
                trailing: const Text('+1 แต้ม', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
              ),
              Divider(color: Colors.grey.shade200),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: Color(0xFFE0F2FE), shape: BoxShape.circle),
                  child: const Text('🚑', style: TextStyle(fontSize: 20)),
                ),
                title: const Text('เปิดทางให้รถฉุกเฉิน รพ.มหาราชนคร', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('ช่วยประหยัดเวลาส่งผู้ป่วยฉุกเฉิน ~3.0 นาที'),
                trailing: const Text('+1 แต้ม', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text('รวมทั้งหมด $_yieldsCount ครั้ง • ประหยัดเวลารวม ${(_yieldsCount * 2.5).toStringAsFixed(1)} นาที',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
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

                    // Stats & Gamification Card
                    _buildStatsCard(),
                    const SizedBox(height: 20),

                    // Face Biometrics Management Card
                    _buildFaceManagementCard(),
                    const SizedBox(height: 20),

                    // Menu List Tiles
                    _buildMenuTile('แก้ไขข้อมูลส่วนตัว (Edit info)', Icons.person_outline, _showEditProfileDialog),
                    _buildMenuTile('แก้ไขรหัสผ่าน (Password)', Icons.lock_outline, _showChangePasswordDialog),
                    _buildMenuTile('ประวัติการช่วยเหลือ (History)', Icons.history_rounded, _showYieldHistoryDialog),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      child: (_currentUser == null || _currentUser?.id == 'guest')
                          ? ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const FaceLoginScreen(),
                                  ),
                                ).then((_) => _loadData());
                              },
                              icon: const Icon(Icons.login_rounded, color: Colors.white, size: 20),
                              label: const Text(
                                'เข้าสู่ระบบ / ลงทะเบียน (Sign in / Register)',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00A896),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            )
                          : ElevatedButton.icon(
                              onPressed: () async {
                                await FaceAuthRepository.logout();
                                await _loadData();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Color(0xFF00A896),
                                    content: Text('ออกจากระบบแล้ว (สลับเป็นโหมดผู้ใช้ทั่วไป)'),
                                  ),
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
                    const SizedBox(height: 20),
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
    final bool isGuest = _currentUser == null || _currentUser?.id == 'guest';
    final name = isGuest ? 'ผู้ใช้ทั่วไป (Guest Mode)' : (_currentUser?.name ?? 'ผู้ขับขี่ทั่วไป');
    final email = isGuest ? 'โหมดใช้งานด่วน • ยังไม่ได้ลงทะเบียน' : (_currentUser?.email ?? 'driver@routealert.com');

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
                    'บทบาท: ผู้ใช้ทั่วไป (Driver / Citizen)',
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
    final double minutesSaved = _yieldsCount * 2.5;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.workspace_premium_rounded, color: Color(0xFFF59E0B), size: 22),
                  SizedBox(width: 6),
                  Text(
                    'สถิติพลเมืองดี (Good Citizen)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ],
              ),
              Text(
                '🥇 Gold Hero',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$_yieldsCount',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF047857),
                        ),
                      ),
                      const Text(
                        'ครั้งที่เปิดทาง',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${minutesSaved.toStringAsFixed(1)}m',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1D4ED8),
                        ),
                      ),
                      const Text(
                        'ช่วยลดเวลารถกู้ชีพ',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E40AF)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFaceManagementCard() {
    final bool isGuest = _currentUser == null || _currentUser?.id == 'guest';
    final hasFace = !isGuest && (_currentUser?.hasFaceEnrolled ?? false);

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasFace
                    ? Icons.face_retouching_natural_rounded
                    : Icons.face_unlock_rounded,
                color: hasFace
                    ? const Color(0xFF00A896)
                    : const Color(0xFF5B9EE1),
                size: 24,
              ),
              const SizedBox(width: 10),
              const Text(
                'ระบบความปลอดภัย Face ID Login',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isGuest
                ? '⚪ โหมดผู้ใช้ทั่วไป (เข้าสู่ระบบเพื่อเปิดใช้งาน Face ID)'
                : (hasFace
                    ? '✅ ลงทะเบียนใบหน้าแล้ว (สามารถสแกนเข้าสู่ระบบได้ทันที)'
                    : '⚪ ยังไม่ได้ลงทะเบียนใบหน้า'),
            style: TextStyle(
              fontSize: 12.5,
              color: hasFace
                  ? const Color(0xFF00A896)
                  : Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isGuest
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const FaceLoginScreen(),
                            ),
                          ).then((_) => _loadData());
                        }
                      : _onReEnrollFace,
                  icon: const Icon(Icons.camera_front_rounded, size: 16),
                  label: Text(
                    isGuest
                        ? 'เข้าสู่ระบบ / สมัครสมาชิก'
                        : (hasFace ? 'สแกนใบหน้าใหม่' : 'ลงทะเบียน Face ID'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF5B9EE1),
                    side: const BorderSide(color: Color(0xFF5B9EE1)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              if (hasFace) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _onRemoveFace,
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent),
                  tooltip: 'ลบข้อมูลใบหน้า',
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
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: const Color(0xFF5B9EE1)),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
      ),
    );
  }
}