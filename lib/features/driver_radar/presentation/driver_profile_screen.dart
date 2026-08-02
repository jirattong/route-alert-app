import 'package:flutter/material.dart';
import '../../auth_face_login/presentation/face_login_screen.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  // ข้อมูลผู้ใช้งานจำลอง
  String _userEmail = 'username@gmail.com';
  String _username = 'Jirattong User';
  String _birthDate = '01/01/2000';
  String _phone = '099XXXXXXX';
  int _yieldCount = 67; // จำนวนการหลบสำเร็จ

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
                    // --- การ์ดข้อมูลผู้ใช้ + จำนวนการหลบสำเร็จ ---
                    _buildProfileCard(),

                    const SizedBox(height: 24),
                    Divider(color: Colors.grey.shade300, thickness: 1.5),
                    const SizedBox(height: 12),

                    // --- เมนูแก้ไขข้อมูลส่วนตัว ---
                    _buildOptionTile(
                      title: 'แก้ไขข้อมูลส่วนตัว (Edit profile)',
                      onTap: () => _showEditProfileModal(context),
                    ),

                    // --- เมนูแก้ไขรหัสผ่าน ---
                    _buildOptionTile(
                      title: 'แก้ไขรหัสผ่าน (Password)',
                      onTap: () => _showEditPasswordModal(context),
                    ),

                    const SizedBox(height: 28),

                    // --- ปุ่ม ลบบัญชี (Delete Account) ---
                    _buildActionButton(
                      text: 'ลบบัญชี (Delete Account)',
                      color: const Color(0xFFEB5757),
                      onPressed: () => _showDeleteConfirmDialog(context),
                    ),

                    const SizedBox(height: 14),

                    // --- ปุ่ม ออกจากระบบ (Logout) ---
                    _buildActionButton(
                      text: 'ออกจากระบบ (Logout)',
                      color: const Color(0xFF5B9EE1),
                      onPressed: () => _showLogoutConfirmDialog(context),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // ❌ ถอด bottomNavigationBar ออกเพื่อใช้ Shell ร่วมกันใน DriverMainScreen
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
            color: Colors.black.withOpacity(0.06),
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

  // --- การ์ดข้อมูลผู้ใช้ + Donut Gauge แสดงจำนวนการหลบสำเร็จ ---
  Widget _buildProfileCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B9EE1).withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ข้อมูลผู้ใช้',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
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
          const SizedBox(height: 20),

          // วงกลม Gauge แสดงจำนวนการหลบสำเร็จ
          Center(
            child: Column(
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 120,
                        height: 120,
                        child: CircularProgressIndicator(
                          value: 0.67,
                          strokeWidth: 12,
                          backgroundColor: const Color(0xFFE2F0FE),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF5B9EE1)),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '$_yieldCount',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const Text(
                            'ครั้ง',
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
                const SizedBox(height: 14),
                Text(
                  'จำนวนการหลบสำเร็จ (Total Yields)',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper: รายการแถบเลือกเมนู ---
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

  // --- Helper: ปุ่มแอ็กชันใหญ่ ---
  Widget _buildActionButton({
    required String text,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          elevation: 0,
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // --- Modal แก้ไขข้อมูลส่วนตัว ---
  void _showEditProfileModal(BuildContext context) {
    final nameCtrl = TextEditingController(text: _username);
    final emailCtrl = TextEditingController(text: _userEmail);
    final dobCtrl = TextEditingController(text: _birthDate);
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
              _buildModalTextField('แก้ไขวันเกิด (DD/MM/YYYY)', dobCtrl),
              const SizedBox(height: 14),
              _buildModalTextField('เบอร์มือถือ (Phone)', phoneCtrl),
              const SizedBox(height: 24),
              _buildActionButton(
                text: 'บันทึก (SAVE)',
                color: const Color(0xFF5B9EE1),
                onPressed: () {
                  setState(() {
                    _username = nameCtrl.text;
                    _userEmail = emailCtrl.text;
                    _birthDate = dobCtrl.text;
                    _phone = phoneCtrl.text;
                  });
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('บันทึกข้อมูลส่วนตัวเรียบร้อยแล้ว')),
                  );
                },
              ),
            ],
          ),
        );
      },
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
              _buildActionButton(
                text: 'บันทึก (SAVE)',
                color: const Color(0xFF5B9EE1),
                onPressed: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('เปลี่ยนรหัสผ่านเรียบร้อยแล้ว')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

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
                color: Color(0xFF5B9EE1), size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF5B9EE1), width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF5B9EE1), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  // --- Pop-up ยืนยันการลบบัญชี ---
  void _showDeleteConfirmDialog(BuildContext context) {
    _showCustomConfirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      title: 'คุณจะทำการลบบัญชี หรือไม่?',
      subtitle: 'ข้อมูลของคุณจะถูกลบอย่างถาวรไม่\nสามารถกู้คืนได้',
      onConfirm: () {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const FaceLoginScreen()),
          (route) => false,
        );
      },
    );
  }

  // --- Pop-up ยืนยันการออกจากระบบ ---
  void _showLogoutConfirmDialog(BuildContext context) {
    _showCustomConfirmDialog(
      context,
      icon: Icons.logout_rounded,
      title: 'ออกจากระบบ หรือไม่ ?',
      subtitle: 'ข้อมูลของคุณจะไม่สูญหายจากการออก\nจากระบบ',
      onConfirm: () {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const FaceLoginScreen()),
          (route) => false,
        );
      },
    );
  }

  // --- Custom Dialog ---
  void _showCustomConfirmDialog(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: Color(0xFF5B9EE1), width: 2),
        ),
        backgroundColor: Colors.white,
        elevation: 10,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 80, color: Colors.black87),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onConfirm();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0080FF),
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