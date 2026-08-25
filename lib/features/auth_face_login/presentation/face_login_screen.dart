import 'package:flutter/material.dart';
import '../../agency/presentation/agency_main_screen.dart';
import '../../ambulance/presentation/ambulance_main_screen.dart';
import '../../driver_radar/presentation/driver_main_screen.dart';
import '../data/models/user_face_profile.dart';
import '../data/services/face_auth_repository.dart';
import 'face_scan_screen.dart';

class FaceLoginScreen extends StatefulWidget {
  const FaceLoginScreen({super.key});

  @override
  State<FaceLoginScreen> createState() => _FaceLoginScreenState();
}

class _FaceLoginScreenState extends State<FaceLoginScreen> {
  bool isLogin = true;
  bool obscurePassword = true;
  bool obscureRePassword = true;
  bool _isLoading = false;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _rePasswordController = TextEditingController();

  List<double>? _registeredFaceEmbedding;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() {
      if (!isLogin && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _rePasswordController.dispose();
    super.dispose();
  }

  // --- Password Strength Rules (NIST / Enterprise Standard) ---
  bool get _hasMinLength => _passwordController.text.length >= 8;
  bool get _hasUpperLower =>
      _passwordController.text.contains(RegExp(r'[A-Z]')) &&
      _passwordController.text.contains(RegExp(r'[a-z]'));
  bool get _hasNumber => _passwordController.text.contains(RegExp(r'[0-9]'));
  bool get _hasSpecialChar =>
      _passwordController.text.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>\-_=+]'));

  int get _passwordStrengthScore {
    int score = 0;
    if (_hasMinLength) score++;
    if (_passwordController.text.contains(RegExp(r'[A-Z]'))) score++;
    if (_passwordController.text.contains(RegExp(r'[a-z]'))) score++;
    if (_hasNumber) score++;
    if (_hasSpecialChar) score++;
    return score;
  }

  bool get _isPasswordSecure =>
      _hasMinLength && _hasUpperLower && _hasNumber && _hasSpecialChar;

  void _onNormalLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกอีเมลและรหัสผ่านให้ครบถ้วน')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final users = await FaceAuthRepository.getAllUsers();
      final user = users.firstWhere(
        (u) => u.email.trim().toLowerCase() == email.toLowerCase(),
        orElse: () => UserFaceProfile(
          id: email,
          email: email,
          name: email.split('@').first,
          role: 'driver',
          faceEmbedding: [],
          registeredAt: DateTime.now(),
        ),
      );

      await FaceAuthRepository.setCurrentUser(user);

      if (!mounted) return;
      Widget targetScreen = const DriverMainScreen();
      if (user.role == 'ambulance') targetScreen = const AmbulanceMainScreen();
      if (user.role == 'agency') targetScreen = const AgencyMainScreen();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => targetScreen),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

    // Check email format
    final bool isValidEmail =
        RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
    if (!isValidEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('⚠️ รูปแบบอีเมลไม่ถูกต้อง กรุณาตรวจสอบอีเมลอีกครั้ง'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final isDuplicateEmail = await FaceAuthRepository.isEmailRegistered(email);
    final isDuplicateUser = await FaceAuthRepository.isUsernameRegistered(name);
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (isDuplicateEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('⚠️ อีเมลนี้มีอยู่ในระบบแล้ว กรุณาใช้อีเมลอื่น หรือสลับไปเข้าสู่ระบบ'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    if (isDuplicateUser) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('⚠️ ชื่อผู้ใช้นี้ถูกใช้งานแล้ว กรุณาเปลี่ยนชื่อผู้ใช้'),
          duration: Duration(seconds: 4),
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
            content: Text('🎉 บันทึกข้อมูลใบหน้า 3 มิติ (12 เฟรม) เรียบร้อย'),
          ),
        );
      }
    }
  }

  void _onRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final rePassword = _rePasswordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty || rePassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบถ้วนทุกช่อง')),
      );
      return;
    }

    // 1. Email format check
    final bool isValidEmail =
        RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
    if (!isValidEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('⚠️ รูปแบบอีเมลไม่ถูกต้อง (ตัวอย่าง: name@example.com)'),
        ),
      );
      return;
    }

    // 2. Duplicate checks
    setState(() => _isLoading = true);
    final isDuplicateEmail = await FaceAuthRepository.isEmailRegistered(email);
    final isDuplicateUser = await FaceAuthRepository.isUsernameRegistered(name);
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (isDuplicateEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('⚠️ อีเมลนี้ถูกใช้งานแล้ว กรุณาใช้อีเมลอื่น หรือเข้าสู่ระบบ'),
        ),
      );
      return;
    }

    if (isDuplicateUser) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('⚠️ ชื่อผู้ใช้นี้ถูกใช้งานแล้ว กรุณาระบุชื่ออื่น'),
        ),
      );
      return;
    }

    // 3. Password Security Requirements check
    if (!_isPasswordSecure) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orangeAccent,
          content: Text(
              '⚠️ รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร, ตัวพิมพ์ใหญ่, ตัวพิมพ์เล็ก, ตัวเลข และอักขระพิเศษ (@#\$%!)'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // 4. Password match check
    if (password != rePassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('⚠️ รหัสผ่านและการยืนยันรหัสผ่านไม่ตรงกัน'),
        ),
      );
      return;
    }

    // 5. Face ID Enrollment check
    if (_registeredFaceEmbedding == null || _registeredFaceEmbedding!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('⚠️ กรุณากดปุ่ม "สแกนใบหน้า (Face ID)" เพื่อบันทึกใบหน้า 3 มิติก่อนลงทะเบียน'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

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
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF00A896),
        content: Text('🎉 ลงทะเบียนสำเร็จ ยินดีต้อนรับสู่ RouteAlert'),
      ),
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DriverMainScreen()),
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
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20.0),
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
                const SizedBox(height: 24),
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
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: const Color(0xFF00A896),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00A896).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Center(
        child: Icon(
          Icons.alt_route_rounded,
          color: Colors.white,
          size: 44,
        ),
      ),
    );
  }

  Widget _buildTabToggle() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!isLogin) setState(() => isLogin = true);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isLogin ? const Color(0xFF5B9EE1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: isLogin
                      ? [
                          BoxShadow(
                            color: const Color(0xFF5B9EE1).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : [],
                ),
                alignment: Alignment.center,
                child: Text(
                  'Sign in',
                  style: TextStyle(
                    color: isLogin ? Colors.white : Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (isLogin) setState(() => isLogin = false);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: !isLogin ? const Color(0xFF00A896) : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: !isLogin
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00A896).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : [],
                ),
                alignment: Alignment.center,
                child: Text(
                  'Register',
                  style: TextStyle(
                    color: !isLogin ? Colors.white : Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
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
        const SizedBox(height: 18),
        _buildActionButton(
          text: _isLoading ? 'กำลังเข้าสู่ระบบ...' : 'LOGIN',
          color: const Color(0xFF5B9EE1),
          onPressed: _isLoading ? () {} : _onNormalLogin,
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
        _buildInputLabel('Full Name (ชื่อ-นามสกุล)'),
        _buildTextField(
          controller: _nameController,
          hintText: 'ชื่อและนามสกุลจริง',
          icon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: 14),
        _buildInputLabel('Email (อีเมลใช้งาน)'),
        _buildTextField(
          controller: _emailController,
          hintText: 'name@domain.com',
          icon: Icons.email_outlined,
        ),
        const SizedBox(height: 14),
        _buildInputLabel('Password (รหัสผ่านความปลอดภัยสูง)'),
        _buildTextField(
          controller: _passwordController,
          hintText: 'รหัสผ่านอย่างน้อย 8 ตัวอักษร',
          isPassword: true,
          obscureText: obscurePassword,
          icon: Icons.lock_outline_rounded,
          onToggleVisibility: () {
            setState(() => obscurePassword = !obscurePassword);
          },
        ),

        // Live Password Strength Bar & Security Checklist
        if (_passwordController.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildPasswordStrengthBar(),
          const SizedBox(height: 10),
          _buildPasswordSecurityChecklist(),
        ],

        const SizedBox(height: 14),
        _buildInputLabel('Confirm Password (ยืนยันรหัสผ่าน)'),
        _buildTextField(
          controller: _rePasswordController,
          hintText: 'กรอกรหัสผ่านอีกครั้งให้ตรงกัน',
          isPassword: true,
          obscureText: obscureRePassword,
          icon: Icons.lock_reset_rounded,
          onToggleVisibility: () {
            setState(() => obscureRePassword = !obscureRePassword);
          },
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _onScanFaceForRegistration,
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
                ? 'ผูกใบหน้า 3 มิติเรียบร้อย (กดเพื่อสแกนใหม่)'
                : 'สแกนใบหน้าเพื่อผูกบัญชี (Face ID 3D)',
            style: TextStyle(
              color: _registeredFaceEmbedding != null
                  ? const Color(0xFF00A896)
                  : const Color(0xFF2C3E50),
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 13),
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
          text: _isLoading ? 'กำลังบันทึกข้อมูล...' : 'REGISTER',
          color: const Color(0xFF00A896),
          onPressed: _isLoading ? () {} : _onRegister,
        ),
      ],
    );
  }

  Widget _buildPasswordStrengthBar() {
    final score = _passwordStrengthScore;
    Color barColor;
    String strengthText;

    if (score <= 2) {
      barColor = Colors.redAccent;
      strengthText = 'ความปลอดภัยต่ำ (Weak)';
    } else if (score == 3 || score == 4) {
      barColor = Colors.orangeAccent;
      strengthText = 'ความปลอดภัยปานกลาง (Medium)';
    } else {
      barColor = const Color(0xFF00A896);
      strengthText = 'ความปลอดภัยสูงมาก (Strong)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ระดับความปลอดภัยรหัสผ่าน:',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
            Text(
              strengthText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: List.generate(5, (index) {
            final isFilled = index < score;
            return Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: index < 4 ? 4 : 0),
                decoration: BoxDecoration(
                  color: isFilled ? barColor : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildPasswordSecurityChecklist() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'เงื่อนไขรหัสผ่านที่ปลอดภัย (Enterprise Standard):',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          _buildCheckItem('ความยาวอย่างน้อย 8 ตัวอักษร', _hasMinLength),
          _buildCheckItem(
              'มีตัวพิมพ์ใหญ่ (A-Z) และตัวพิมพ์เล็ก (a-z)', _hasUpperLower),
          _buildCheckItem('มีตัวเลขอย่างน้อย 1 ตัว (0-9)', _hasNumber),
          _buildCheckItem(
              'มีอักขระพิเศษอย่างน้อย 1 ตัว (@\$!%*?&#)', _hasSpecialChar),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String text, bool isPassed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isPassed ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 14,
            color: isPassed ? const Color(0xFF00A896) : Colors.grey.shade500,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              color: isPassed ? Colors.black87 : Colors.grey.shade600,
              fontWeight: isPassed ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, left: 4.0),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13.5,
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
          prefixIcon: icon != null
              ? Icon(icon, color: Colors.grey.shade500, size: 20)
              : null,
          hintText: hintText,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13.5),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Color(0xFF00A896), width: 1.5),
          ),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    obscureText
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: Colors.grey.shade500,
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
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          elevation: 2,
          shadowColor: color.withValues(alpha: 0.4),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildFaceLoginButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF00A896).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00A896).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _onFaceLogin,
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.face_unlock_rounded,
                  color: Color(0xFF00A896),
                  size: 26,
                ),
                SizedBox(width: 10),
                Text(
                  'เข้าสู่ระบบด้วย Face ID Biometrics',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00A896),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}