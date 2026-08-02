import 'package:flutter/material.dart';
import 'user_type_screen.dart'; // 👈 นำเข้าหน้าเลือกประเภทผู้ใช้

class FaceLoginScreen extends StatefulWidget {
  const FaceLoginScreen({super.key});

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

class _FaceLoginScreenState extends State<FaceLoginScreen> {
  // สลับสถานะระหว่าง Login (true) และ Register (false)
  bool isLogin = true;

  // ควบคุมการ ซ่อน/แสดง รหัสผ่าน
  bool obscurePassword = true;
  bool obscureRePassword = true;

  // Controllers สำหรับดึงข้อมูลจากช่องกรอก
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _rePasswordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _rePasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ปรับสีพื้นหลังตาม Figma (ฟ้าอ่อนเมื่อ Login / เขียวอ่อนเมื่อ Register)
    final Color backgroundColor =
        isLogin ? const Color(0xFFE2F0FE) : const Color(0xFFE3F8EB);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // --- โลโก้แอป RouteAlert ---
                _buildAppLogo(),
                const SizedBox(height: 12),
                const Text(
                  'RouteAlert',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 24),

                // --- ปุ่มสลับ Tab (Login | Register) ---
                _buildTabToggle(),
                const SizedBox(height: 28),

                // --- ฟอร์มแสดงผลตาม Tab ที่เลือก ---
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: isLogin ? _buildLoginForm() : _buildRegisterForm(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- ส่วนสร้างโลโก้แอปพลิเคชัน ---
  Widget _buildAppLogo() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF2C3E50), width: 3),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.airport_shuttle_outlined,
            size: 52,
            color: Color(0xFF2C3E50),
          ),
          Positioned(
            top: 18,
            right: 18,
            child: Icon(Icons.wifi, size: 22, color: Colors.redAccent.shade700),
          ),
          Positioned(
            bottom: 38,
            left: 42,
            child: Icon(Icons.add, size: 16, color: Colors.redAccent.shade700),
          ),
        ],
      ),
    );
  }

  // --- ปุ่ม Toggle สลับ Login / Register แบบ Capsule ---
  Widget _buildTabToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => isLogin = true),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
              decoration: BoxDecoration(
                color: isLogin ? const Color(0xFF5B9EE1) : Colors.transparent,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Text(
                'Login',
                style: TextStyle(
                  color: isLogin ? Colors.white : const Color(0xFF5B9EE1),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          Container(
            height: 14,
            width: 1,
            color: Colors.grey.shade300,
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          GestureDetector(
            onTap: () => setState(() => isLogin = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 8),
              decoration: BoxDecoration(
                color: !isLogin ? const Color(0xFF52E197) : Colors.transparent,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Text(
                'Register',
                style: TextStyle(
                  color: !isLogin ? Colors.white : const Color(0xFF52E197),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- ฟอร์ม LOGIN ---
  Widget _buildLoginForm() {
    return Column(
      key: const ValueKey('login_form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInputLabel('Email'),
        _buildTextField(
          controller: _emailController,
          hintText: 'Email@gmail.com',
        ),
        const SizedBox(height: 16),
        _buildInputLabel('Password'),
        _buildTextField(
          controller: _passwordController,
          hintText: 'Password',
          isPassword: true,
          obscureText: obscurePassword,
          onToggleVisibility: () {
            setState(() => obscurePassword = !obscurePassword);
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              // TODO: ลิงก์ไปหน้าลืมรหัสผ่าน
            },
            child: const Text(
              'forgot password?',
              style: TextStyle(
                color: Color(0xFF4A90E2),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _buildActionButton(
          text: 'LOGIN',
          color: const Color(0xFF5B9EE1),
          onPressed: () {
            // ล็อกอินผ่าน Email/Password -> นำพาไปหน้าเลือกประเภทผู้ใช้
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const UserTypeScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Divider(color: Colors.grey.shade400, thickness: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(child: Divider(color: Colors.grey.shade400, thickness: 1)),
          ],
        ),
        const SizedBox(height: 16),
        // Social Logins
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSocialButton(Icons.g_mobiledata, Colors.redAccent, () {}),
            const SizedBox(width: 16),
            _buildSocialButton(Icons.apple, Colors.black, () {}),
            const SizedBox(width: 16),
            _buildSocialButton(Icons.facebook, const Color(0xFF1877F2), () {}),
          ],
        ),
        const SizedBox(height: 20),
        // --- ปุ่ม FACE LOGIN ---
        _buildFaceLoginButton(),
      ],
    );
  }

  // --- ฟอร์ม REGISTER ---
  Widget _buildRegisterForm() {
    return Column(
      key: const ValueKey('register_form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInputLabel('Email'),
        _buildTextField(
          controller: _emailController,
          hintText: 'Email@gmail.com',
        ),
        const SizedBox(height: 16),
        _buildInputLabel('Password'),
        _buildTextField(
          controller: _passwordController,
          hintText: 'Password',
          isPassword: true,
          obscureText: obscurePassword,
          onToggleVisibility: () {
            setState(() => obscurePassword = !obscurePassword);
          },
        ),
        const SizedBox(height: 16),
        _buildInputLabel('Re-Password'),
        _buildTextField(
          controller: _rePasswordController,
          hintText: 'Re-Password',
          isPassword: true,
          obscureText: obscureRePassword,
          onToggleVisibility: () {
            setState(() => obscureRePassword = !obscureRePassword);
          },
        ),
        const SizedBox(height: 28),
        _buildActionButton(
          text: 'REGISTER',
          color: const Color(0xFF52E197),
          onPressed: () {
            // 🔗 เชื่อมต่อหน้าเลือกประเภทผู้ใช้ (UserTypeScreen) หลังจากกด REGISTER
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const UserTypeScreen(),
              ),
            );
          },
        ),
      ],
    );
  }

  // --- Helper: ป้ายชื่อหัวข้อช่องกรอก ---
  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, left: 4.0),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  // --- Helper: ช่องกรอกข้อความ (TextField) ---
  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? obscureText : false,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF5B9EE1), width: 1.5),
          ),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    obscureText
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
                  onPressed: onToggleVisibility,
                )
              : null,
        ),
      ),
    );
  }

  // --- Helper: ปุ่มกดหลัก (LOGIN / REGISTER) ---
  Widget _buildActionButton({
    required String text,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 10,
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
            borderRadius: BorderRadius.circular(28),
          ),
          elevation: 0,
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  // --- Helper: ปุ่ม FACE LOGIN สแกนใบหน้าด้วย Deep Learning ---
  Widget _buildFaceLoginButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: () {
          // กด Face Login ก็สามารเปิดไปยังหน้าเลือกประเภทผู้ใช้ได้ชั่วคราวในการ Demo
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const UserTypeScreen(),
            ),
          );
        },
        icon: const Icon(Icons.face_retouching_natural_rounded,
            color: Colors.white, size: 22),
        label: const Text(
          'FACE LOGIN',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 0.8,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF8E9AAF),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  // --- Helper: ปุ่ม Social Login ---
  Widget _buildSocialButton(
      IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 26, color: color),
      ),
    );
  }
}