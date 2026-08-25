import 'package:flutter/material.dart';
import '../data/models/user_face_profile.dart';
import '../data/services/face_auth_repository.dart';
import 'face_scan_screen.dart';
import 'user_type_screen.dart';

class FaceLoginScreen extends StatefulWidget {
  const FaceLoginScreen({super.key});

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

class _FaceLoginScreenState extends State<FaceLoginScreen> {
  bool isLogin = true;
  bool obscurePassword = true;
  bool obscureRePassword = true;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _rePasswordController = TextEditingController();

  List<double>? _registeredFaceEmbedding;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _rePasswordController.dispose();
    super.dispose();
  }

  void _onNormalLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกอีเมลและรหัสผ่านให้ครบถ้วน')),
      );
      return;
    }

    final user = UserFaceProfile(
      id: 'USER_${DateTime.now().millisecondsSinceEpoch}',
      email: email,
      name: email.split('@').first,
      role: 'driver',
      faceEmbedding: [],
      registeredAt: DateTime.now(),
    );
    await FaceAuthRepository.setCurrentUser(user);

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UserTypeScreen()),
    );
  }

  void _onFaceLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FaceScanScreen(mode: FaceScanMode.login),
      ),
    );
  }

  void _onScanFaceForRegistration() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orangeAccent,
          content: Text('⚠️ กรุณากรอก "ชื่อ" และ "อีเมล" ก่อนทำการสแกนใบหน้า'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final result = await Navigator.push<List<double>>(
      context,
      MaterialPageRoute(
        builder: (_) => FaceScanScreen(
          mode: FaceScanMode.register,
          registrationEmail: email,
          registrationName: name,
          registrationRole: 'driver',
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _registeredFaceEmbedding = result;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF00A896),
            content: Text('🎉 บันทึกข้อมูลใบหน้า 3D ลงฐานข้อมูลเรียบร้อย'),
          ),
        );
      }
    }
  }

  void _onRegister() async {
    final name = _nameController.text.trim().isEmpty ? 'ผู้ใช้งาน' : _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final rePassword = _rePasswordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกอีเมลและรหัสผ่าน')),
      );
      return;
    }

    if (password != rePassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('รหัสผ่านและการยืนยันรหัสผ่านไม่ตรงกัน')),
      );
      return;
    }

    if (_registeredFaceEmbedding == null || _registeredFaceEmbedding!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('⚠️ กรุณากดปุ่ม "สแกนใบหน้า (Face ID)" เพื่อบันทึกใบหน้าก่อนลงทะเบียน'),
        ),
      );
      return;
    }

    final newProfile = UserFaceProfile(
      id: email,
      email: email,
      name: name,
      role: 'driver',
      faceEmbedding: _registeredFaceEmbedding!,
      registeredAt: DateTime.now(),
    );

    await FaceAuthRepository.registerUser(newProfile);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF00A896),
        content: Text('ลงทะเบียนสำเร็จ ยินดีต้อนรับสู่ RouteAlert'),
      ),
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const UserTypeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                _buildTabToggle(),
                const SizedBox(height: 28),
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

  Widget _buildAppLogo() {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF2C3E50), width: 3),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.airport_shuttle_outlined,
            size: 50,
            color: Color(0xFF2C3E50),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Icon(Icons.wifi, size: 20, color: Colors.redAccent.shade700),
          ),
          Positioned(
            bottom: 34,
            left: 40,
            child: Icon(Icons.add, size: 16, color: Colors.redAccent.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildTabToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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

  Widget _buildLoginForm() {
    return Column(
      key: const ValueKey('login_form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInputLabel('Email'),
        _buildTextField(
          controller: _emailController,
          hintText: 'Email@gmail.com',
          icon: Icons.email_outlined,
        ),
        const SizedBox(height: 16),
        _buildInputLabel('Password'),
        _buildTextField(
          controller: _passwordController,
          hintText: 'Password',
          isPassword: true,
          obscureText: obscurePassword,
          icon: Icons.lock_outline_rounded,
          onToggleVisibility: () {
            setState(() => obscurePassword = !obscurePassword);
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {},
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
          onPressed: _onNormalLogin,
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
        _buildFaceLoginButton(),
      ],
    );
  }

  Widget _buildRegisterForm() {
    return Column(
      key: const ValueKey('register_form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInputLabel('Full Name'),
        _buildTextField(
          controller: _nameController,
          hintText: 'John Doe',
          icon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: 14),
        _buildInputLabel('Email'),
        _buildTextField(
          controller: _emailController,
          hintText: 'Email@gmail.com',
          icon: Icons.email_outlined,
        ),
        const SizedBox(height: 14),
        _buildInputLabel('Password'),
        _buildTextField(
          controller: _passwordController,
          hintText: 'Password',
          isPassword: true,
          obscureText: obscurePassword,
          icon: Icons.lock_outline_rounded,
          onToggleVisibility: () {
            setState(() => obscurePassword = !obscurePassword);
          },
        ),
        const SizedBox(height: 14),
        _buildInputLabel('Re-Password'),
        _buildTextField(
          controller: _rePasswordController,
          hintText: 'Re-Password',
          isPassword: true,
          obscureText: obscureRePassword,
          icon: Icons.lock_reset_rounded,
          onToggleVisibility: () {
            setState(() => obscureRePassword = !obscureRePassword);
          },
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _onScanFaceForRegistration,
          icon: Icon(
            _registeredFaceEmbedding != null
                ? Icons.check_circle_rounded
                : Icons.face_retouching_natural_rounded,
            color: _registeredFaceEmbedding != null
                ? const Color(0xFF00A896)
                : const Color(0xFF2C3E50),
          ),
          label: Text(
            _registeredFaceEmbedding != null
                ? 'ผูกใบหน้าเรียบร้อย (กดเพื่อสแกนใหม่)'
                : 'สแกนใบหน้าเพื่อผูกบัญชี (Face Register)',
            style: TextStyle(
              color: _registeredFaceEmbedding != null
                  ? const Color(0xFF00A896)
                  : const Color(0xFF2C3E50),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: BorderSide(
              color: _registeredFaceEmbedding != null
                  ? const Color(0xFF00A896)
                  : Colors.grey.shade400,
              width: 1.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            backgroundColor: _registeredFaceEmbedding != null
                ? const Color(0xFF00A896).withValues(alpha: 0.08)
                : Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        _buildActionButton(
          text: 'REGISTER',
          color: const Color(0xFF52E197),
          onPressed: _onRegister,
        ),
      ],
    );
  }

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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    IconData? icon,
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
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? obscureText : false,
        decoration: InputDecoration(
          prefixIcon: icon != null ? Icon(icon, color: Colors.grey.shade500, size: 20) : null,
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
            color: color.withValues(alpha: 0.4),
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

  Widget _buildFaceLoginButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _onFaceLogin,
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
          backgroundColor: const Color(0xFF00A896),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          elevation: 0,
        ),
      ),
    );
  }

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
              color: Colors.black.withValues(alpha: 0.04),
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