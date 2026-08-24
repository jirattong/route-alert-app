import 'package:flutter/material.dart';
import '../../auth_face_login/data/models/user_face_profile.dart';
import '../../auth_face_login/data/services/face_auth_repository.dart';
import '../../auth_face_login/presentation/face_login_screen.dart';
import '../../auth_face_login/presentation/face_scan_screen.dart';

class AmbulanceProfileScreen extends StatefulWidget {
  const AmbulanceProfileScreen({super.key});

  @override
  State<AmbulanceProfileScreen> createState() => _AmbulanceProfileScreenState();
}

class _AmbulanceProfileScreenState extends State<AmbulanceProfileScreen> {
  UserFaceProfile? _currentUser;
  String _userEmail = 'ambulance@routealert.com';
  String _username = 'นายสมชาย กู้ชีพ';
  String _vehiclePlate = 'กขค123 (เชียงใหม่)';
  final String _hospitalUnit = 'รพ.มหาราชนครเชียงใหม่';
  String _phone = '099XXXXXXX';
  final int _completedCases = 128;
  bool _isOnDuty = true;

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
        _username = user.name;
        _userEmail = user.email;
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Column(
                  children: [
                    // --- การ์ดข้อมูลผู้ใช้ + จำนวนเคสปฏิบัติการสำเร็จ ---
                    _buildProfileCard(),

                    const SizedBox(height: 20),

                    // --- การ์ดสลับสถานะพร้อมปฏิบัติงาน (On Duty Status) ---
                    _buildDutyStatusCard(),

                    const SizedBox(height: 20),
                    Divider(color: Colors.grey.shade300, thickness: 1.5),
                    const SizedBox(height: 12),

                    // --- เมนูแก้ไขข้อมูลส่วนตัว ---
                    _buildOptionTile(
                      title: 'แก้ไขข้อมูลส่วนตัว (Edit profile)',
                      onTap: () => _showEditProfileModal(context),
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

                    // --- ปุ่ม ออกจากระบบ (Logout) สไตล์สีแดงตาม Figma ---
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

  // --- Header แถบบนพร้อมโลโก้ RouteAlert ---
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
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
                const Icon(Icons.airport_shuttle_outlined,
                    size: 20, color: Color(0xFF2C3E50)),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Icon(Icons.wifi,
                      size: 9, color: Colors.redAccent.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'RouteAlert',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // --- การ์ดข้อมูลผู้ใช้ + Donut Gauge แสดงเคสสำเร็จขอบสีแดงตาม Figma ---
  Widget _buildProfileCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEB5757), width: 1.8), // ขอบสีแดงตามรูป
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEB5757).withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ข้อมูลผู้ใช้ (Ambulance)',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEB5757).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _vehiclePlate,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFEB5757),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Email : $_userEmail',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            'สังกัด : $_hospitalUnit',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 22),

          // วงกลม Donut Gauge แสดงเคสที่ช่วยเหลือสำเร็จ
          Center(
            child: Column(
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: 0.85,
                          strokeWidth: 12,
                          backgroundColor: Color(0xFFFFEAEA),
                          valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFFEB5757)), // วงกลมสีแดงสด
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$_completedCases',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const Text(
                            'เคส',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'ภารกิจกู้ชีพสำเร็จ (Completed Cases)',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- การ์ดสลับสถานะพร้อมปฏิบัติงาน (Duty Status) ---
  Widget _buildDutyStatusCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _isOnDuty ? const Color(0xFFFFEAEA) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isOnDuty ? const Color(0xFFEB5757) : Colors.grey.shade300,
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                _isOnDuty
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_off_rounded,
                color: _isOnDuty ? const Color(0xFFEB5757) : Colors.grey,
                size: 24,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isOnDuty ? 'พร้อมรับแจ้งเหตุ (On Duty)' : 'พักเวรปฏิบัติงาน (Off Duty)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: _isOnDuty ? const Color(0xFFEB5757) : Colors.grey.shade700,
                    ),
                  ),
                  Text(
                    _isOnDuty ? 'เปิดการรับแจ้งเคสฉุกเฉินจากศูนย์' : 'ปิดการรับแจ้งเคสชั่วคราว',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
          ),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: _isOnDuty,
              activeThumbColor: Colors.white,
              activeTrackColor: const Color(0xFFEB5757),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.grey.shade400,
              onChanged: (val) {
                setState(() => _isOnDuty = val);
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- รายการแถบเมนู ---
  Widget _buildOptionTile({
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  // --- ปุ่ม ออกจากระบบ (Logout) สไตล์สีแดงตาม Figma ---
  Widget _buildLogoutButton(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEB5757).withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: () => _showLogoutConfirmDialog(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEB5757), // สีแดงตามรูป Figma
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          elevation: 0,
        ),
        child: const Text(
          'ออกจากระบบ (Logout)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // --- Modal แก้ไขข้อมูลส่วนตัว (ธีมสีแดงเจ้าหน้าที่) ---
  void _showEditProfileModal(BuildContext context) {
    final nameCtrl = TextEditingController(text: _username);
    final emailCtrl = TextEditingController(text: _userEmail);
    final carCtrl = TextEditingController(text: _vehiclePlate);
    final phoneCtrl = TextEditingController(text: _phone);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
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
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildModalTextField('แก้ไขข้อมูลส่วนตัว (Edit profile)', nameCtrl),
              const SizedBox(height: 14),
              _buildModalTextField('แก้ไขอีเมล (Edit email)', emailCtrl),
              const SizedBox(height: 14),
              _buildModalTextField('แก้ไขข้อมูลรถ (Car detail)', carCtrl),
              const SizedBox(height: 14),
              _buildModalTextField('เบอร์มือถือ (Phone)', phoneCtrl),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _username = nameCtrl.text;
                      _userEmail = emailCtrl.text;
                      _vehiclePlate = carCtrl.text;
                      _phone = phoneCtrl.text;
                    });
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('บันทึกข้อมูลเรียบร้อยแล้ว')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEB5757),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: const Text(
                    'บันทึก (SAVE)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Modal แก้ไขรหัสผ่าน (ธีมสีแดงเจ้าหน้าที่) ---
  void _showEditPasswordModal(BuildContext context) {
    final oldPassCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
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
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildModalTextField('รหัสผ่านเก่า', oldPassCtrl, isPassword: true),
              const SizedBox(height: 14),
              _buildModalTextField('รหัสผ่านใหม่', newPassCtrl, isPassword: true),
              const SizedBox(height: 14),
              _buildModalTextField('ยืนยันรหัสผ่าน', confirmPassCtrl, isPassword: true),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('เปลี่ยนรหัสผ่านเรียบร้อยแล้ว')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEB5757),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: const Text(
                    'บันทึก (SAVE)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Helper สร้าง TextField
  Widget _buildModalTextField(String label, TextEditingController controller,
      {bool isPassword = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: isPassword,
          decoration: InputDecoration(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            suffixIcon: const Icon(Icons.edit_outlined,
                color: Color(0xFFEB5757), size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFEB5757), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFEB5757), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // --- Pop-up ยืนยันการออกจากระบบ ขอบขอบแดงตาม Figma ---
  void _showLogoutConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: Color(0xFFEB5757), width: 2), // ขอบสีแดงตามรูป
        ),
        backgroundColor: Colors.white,
        elevation: 10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.logout_rounded,
                size: 80,
                color: Colors.black87,
              ),
              const SizedBox(height: 16),
              const Text(
                'ออกจากระบบ หรือไม่ ?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'ข้อมูลของคุณจะไม่สูญหายจากการออก\nจากระบบ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 24),

              // ปุ่ม 1: ยืนยัน (Confirm) สีแดงสดตาม Figma
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const FaceLoginScreen()),
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEB5757),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'ยืนยัน (Confirm)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ปุ่ม 2: ยกเลิก (Cancel) สีเทา
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA8A8A8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'ยกเลิก (Cancel)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}