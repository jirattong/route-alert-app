import 'package:flutter/material.dart';
import '../../auth_face_login/data/models/user_face_profile.dart';
import '../../auth_face_login/data/services/face_auth_repository.dart';
import '../../auth_face_login/presentation/face_login_screen.dart';
import '../../auth_face_login/presentation/face_scan_screen.dart';

class AgencyProfileScreen extends StatefulWidget {
  const AgencyProfileScreen({super.key});

  @override
  State<AgencyProfileScreen> createState() => _AgencyProfileScreenState();
}

class _AgencyProfileScreenState extends State<AgencyProfileScreen> {
  UserFaceProfile? _currentUser;
  String _hospitalName = 'โรงพยาบาลมหาราชนครเชียงใหม่';
  String _contactNumber = '053-999-999 (เบอร์สายตรง ER)';
  bool _isErAvailable = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = await FaceAuthRepository.getCurrentUser();
    if (mounted && user != null) {
      setState(() {
        _currentUser = user;
        _hospitalName = user.name;
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
      await _loadUserData();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // --- 1. Header Bar ด้านบน ---
            _buildHeader(),

            // --- 2. เนื้อหาหลัก ---
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  children: [
                    // --- การ์ด Dashboard สถิติ (ขอบเรืองแสงสีเขียวตาม Figma) ---
                    _buildDashboardCard(),

                    const SizedBox(height: 24),

                    // --- ฟังก์ชันสำคัญ EMS: สวิตช์สถานะห้องฉุกเฉิน (ER Status) ---
                    _buildErStatusCard(),

                    const SizedBox(height: 24),
                    Divider(color: Colors.grey.shade300, thickness: 1.5),
                    const SizedBox(height: 12),

                    // --- เมนูแก้ไขข้อมูลหน่วยงาน ---
                    _buildOptionTile(
                      title: 'แก้ไขข้อมูลหน่วยงาน (Edit info)',
                      onTap: () => _showEditInfoModal(context),
                    ),

                    // --- เมนูจัดการ Face ID ---
                    _buildOptionTile(
                      title: 'จัดการระบบจดจำใบหน้า (Face ID Security)',
                      onTap: _onReEnrollFace,
                    ),

                    // --- เมนูแก้ไขรหัสผ่าน ---
                    _buildOptionTile(
                      title: 'แก้ไขรหัสผ่าน (Password)',
                      onTap: () => _showEditPasswordModal(context),
                    ),

                    const SizedBox(height: 32),

                    // --- ปุ่ม ออกจากระบบ (Logout) สีเขียวเข้มตาม Figma ---
                    _buildLogoutButton(context),

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

  // --- Header แถบบน ---
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF2C3E50), width: 2),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.airport_shuttle_outlined, size: 20, color: Color(0xFF2C3E50)),
                Positioned(top: 4, right: 4, child: Icon(Icons.wifi, size: 9, color: Colors.redAccent.shade700)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Text('RouteAlert', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  // --- การ์ด Dashboard สถิติ (เรืองแสงสีเขียวตาม Figma) ---
  Widget _buildDashboardCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFF69F0AE), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF69F0AE).withValues(alpha: 0.3), // แสงเรืองรองสีเขียว
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'ข้อมูลหน่วยงาน',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _hospitalName,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 24),

          // วงกลมใหญ่ (จำนวนเคสรับเข้าต่อเดือน)
          _buildGauge(
            valueText: '154',
            labelText: 'จำนวนเคสรับเข้าต่อเดือน',
            size: 130,
            strokeWidth: 14,
            progress: 0.75,
          ),

          const SizedBox(height: 28),

          // วงกลมเล็ก 2 วงคู่กัน (ประสิทธิภาพ ER และ เคสวิกฤต)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildGauge(
                valueText: '92%',
                labelText: 'เตรียม ER ทันเวลา',
                size: 90,
                strokeWidth: 10,
                progress: 0.92,
              ),
              _buildGauge(
                valueText: '34',
                labelText: 'เคสวิกฤต (Code Red)',
                size: 90,
                strokeWidth: 10,
                progress: 0.35,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Helper: วงกลม Gauge UI ---
  Widget _buildGauge({
    required String valueText,
    required String labelText,
    required double size,
    required double strokeWidth,
    required double progress,
  }) {
    return Column(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: strokeWidth,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF69F0AE)), // สีเขียวสว่าง
                  strokeCap: StrokeCap.round,
                ),
              ),
              Text(
                valueText,
                style: TextStyle(
                  fontSize: size * 0.3,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          labelText,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // --- การ์ดสลับสถานะความพร้อมห้องฉุกเฉิน (EMS Real-World Protocol) ---
  Widget _buildErStatusCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: _isErAvailable ? const Color(0xFFE8F5E9) : const Color(0xFFFFEAEA), // เขียวอ่อน / แดงอ่อน
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isErAvailable ? const Color(0xFF2E7D32) : const Color(0xFFEB5757),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                _isErAvailable ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: _isErAvailable ? const Color(0xFF2E7D32) : const Color(0xFFEB5757),
                size: 28,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isErAvailable ? 'ER พร้อมรับเคส (Available)' : 'เตียงเต็ม (ER Divert/Bypass)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _isErAvailable ? const Color(0xFF2E7D32) : const Color(0xFFEB5757),
                    ),
                  ),
                  Text(
                    _isErAvailable ? 'รับรถพยาบาลได้ตามปกติ' : 'แจ้งรถพยาบาลให้เปลี่ยนเส้นทาง',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ],
          ),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: _isErAvailable,
              activeThumbColor: Colors.white,
              activeTrackColor: const Color(0xFF2E7D32),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFFEB5757),
              onChanged: (val) {
                setState(() => _isErAvailable = val);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      val ? '✅ อัปเดตสถานะ: ห้องฉุกเฉินพร้อมรับผู้ป่วย' : '🚨 อัปเดตสถานะ: ประกาศเตียงเต็ม (Divert)',
                    ),
                    backgroundColor: val ? const Color(0xFF2E7D32) : const Color(0xFFEB5757),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- รายการแถบเมนู ---
  Widget _buildOptionTile({required String title, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 22),
          ],
        ),
      ),
    );
  }

  // --- ปุ่ม ออกจากระบบ (Logout) สไตล์สีเขียวเข้มตาม Figma ---
  Widget _buildLogoutButton(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(color: const Color(0xFF1B5E20).withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: ElevatedButton(
        onPressed: () {
          // ออกจากระบบกลับไปหน้าล็อกอิน
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const FaceLoginScreen()),
            (route) => false,
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1B5E20), // สีเขียวเข้มตามรูป Figma
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          elevation: 0,
        ),
        child: const Text(
          'ออกจากระบบ (Logout)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
    );
  }

  // --- Modal แก้ไขข้อมูลหน่วยงาน ---
  void _showEditInfoModal(BuildContext context) {
    final nameCtrl = TextEditingController(text: _hospitalName);
    final phoneCtrl = TextEditingController(text: _contactNumber);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            top: 20,
            left: 24,
            right: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),
              _buildModalTextField('ชื่อหน่วยงาน / โรงพยาบาล', nameCtrl),
              const SizedBox(height: 14),
              _buildModalTextField('เบอร์โทรศัพท์ฉุกเฉิน (ER Hotline)', phoneCtrl),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _hospitalName = nameCtrl.text;
                      _contactNumber = phoneCtrl.text;
                    });
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  child: const Text('บันทึก (SAVE)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalTextField(String label, TextEditingController controller, {bool isPassword = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: isPassword,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // --- Modal แก้ไขรหัสผ่าน ---
  void _showEditPasswordModal(BuildContext context) {
    final oldPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            top: 20,
            left: 24,
            right: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),
              _buildModalTextField('รหัสผ่านเดิม', oldPassCtrl, isPassword: true),
              const SizedBox(height: 14),
              _buildModalTextField('รหัสผ่านใหม่ (อย่างน้อย 6 ตัวอักษร)', newPassCtrl, isPassword: true),
              const SizedBox(height: 14),
              _buildModalTextField('ยืนยันรหัสผ่านใหม่', confirmPassCtrl, isPassword: true),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
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
                        backgroundColor: Color(0xFF2E7D32),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  child: const Text('บันทึก (SAVE)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}