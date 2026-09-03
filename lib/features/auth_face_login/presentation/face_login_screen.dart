import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/email_otp_service.dart';
import '../../../core/services/google_auth_service.dart';
import '../../../core/widgets/google_logo.dart';
import '../data/models/user_face_profile.dart';
import '../data/services/face_auth_repository.dart';
import '../../../core/ml/anti_spoofing_service.dart';
import '../../../core/ml/face_recognition_service.dart';
import 'face_scan_screen.dart';
import '../../driver_radar/presentation/driver_main_screen.dart';
import '../../ambulance/presentation/ambulance_main_screen.dart';
import '../../agency/presentation/agency_main_screen.dart';

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

  // Selected Role for Registration ('driver', 'ambulance', 'agency')
  String _selectedRole = 'driver';

  // Email OTP Verification State
  bool _isEmailVerified = false;
  String? _verifiedEmail;

  // Real-time Email Check State
  bool _isCheckingEmail = false;
  bool _isEmailAlreadyRegistered = false;
  Timer? _emailDebounceTimer;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _rePasswordController = TextEditingController();

  List<double>? _registeredFaceEmbedding;

  @override
  void initState() {
    super.initState();
    // Ensure no pre-existing session is logged in by default on startup
    FaceAuthRepository.logout();
    // Pre-warm AI biometric models asynchronously so Face Scan launches with 0ms delay
    unawaited(AntiSpoofingService().initialize());
    unawaited(FaceRecognitionService().initialize());
    _passwordController.addListener(_onPasswordInputChanged);
    _emailController.addListener(_onEmailInputChanged);
  }

  void _onPasswordInputChanged() {
    if (!isLogin && mounted) {
      setState(() {});
    }
  }

  void _onEmailInputChanged() {
    final rawEmail = _emailController.text.trim();
    final lowerEmail = rawEmail.toLowerCase();

    // If user changes email text after verifying, reset verified state
    if (_isEmailVerified && lowerEmail != _verifiedEmail) {
      setState(() {
        _isEmailVerified = false;
        _verifiedEmail = null;
      });
    }

    _emailDebounceTimer?.cancel();

    if (isLogin) {
      if (_isEmailAlreadyRegistered || _isCheckingEmail) {
        setState(() {
          _isEmailAlreadyRegistered = false;
          _isCheckingEmail = false;
        });
      }
      return;
    }

    if (rawEmail.isEmpty) {
      if (_isEmailAlreadyRegistered || _isCheckingEmail) {
        setState(() {
          _isEmailAlreadyRegistered = false;
          _isCheckingEmail = false;
        });
      }
      return;
    }

    final bool isValidEmail =
        RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(rawEmail);

    if (!isValidEmail) {
      if (_isEmailAlreadyRegistered || _isCheckingEmail) {
        setState(() {
          _isEmailAlreadyRegistered = false;
          _isCheckingEmail = false;
        });
      }
      return;
    }

    // Debounce duplicate email check
    _emailDebounceTimer = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      setState(() => _isCheckingEmail = true);

      final isRegistered =
          await FaceAuthRepository.isEmailRegistered(lowerEmail);

      if (!mounted) return;
      if (_emailController.text.trim().toLowerCase() == lowerEmail) {
        setState(() {
          _isCheckingEmail = false;
          _isEmailAlreadyRegistered = isRegistered;
        });
      }
    });
  }

  @override
  void dispose() {
    _emailController.removeListener(_onEmailInputChanged);
    _passwordController.removeListener(_onPasswordInputChanged);
    _emailDebounceTimer?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _rePasswordController.dispose();
    super.dispose();
  }

  void _onBackPressed() {
    FocusScope.of(context).unfocus();
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DriverMainScreen()),
        (route) => false,
      );
    }
  }

  void _navigateToRoleScreen(UserFaceProfile user) {
    if (!mounted) return;
    Widget targetScreen;
    if (user.role == 'ambulance') {
      targetScreen = const AmbulanceMainScreen();
    } else if (user.role == 'agency') {
      targetScreen = const AgencyMainScreen();
    } else {
      targetScreen = const DriverMainScreen();
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => targetScreen),
      (route) => false,
    );
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
        const SnackBar(
          backgroundColor: Colors.orangeAccent,
          content: Text('⚠️ กรุณากรอกอีเมลและรหัสผ่านให้ครบถ้วน'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await FaceAuthRepository.authenticateWithPassword(
        email: email,
        password: password,
      );

      if (!mounted) return;

      if (result.isSuccess && result.matchedUser != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF00A896),
            content: Text('🎉 ${result.message}'),
          ),
        );

        _navigateToRoleScreen(result.matchedUser!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('⚠️ ${result.message}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('เกิดข้อผิดพลาดในการเข้าสู่ระบบ: $e'),
          ),
        );
      }
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

  void _onEnterAsGuest() async {
    final guestUser = UserFaceProfile(
      id: 'guest',
      email: 'guest@routealert.app',
      name: 'ผู้ใช้ทั่วไป (Guest)',
      role: 'driver',
      faceEmbedding: [],
      registeredAt: DateTime.now(),
    );
    await FaceAuthRepository.setCurrentUser(guestUser);
    if (!mounted) return;
    _onBackPressed();
  }

  void _onGoogleLogin() async {
    setState(() => _isLoading = true);
    final result = await GoogleAuthService.signInWithGoogle();
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result.requiresManualInput) {
      _showGoogleInputModal();
      return;
    }

    if (!result.isSuccess) {
      if (result.message != 'ยกเลิกการเข้าสู่ระบบด้วย Google') {
        _showGoogleInputModal();
      }
      return;
    }

    _handleGoogleUser(result);
  }

  void _handleGoogleUser(GoogleAuthResult result) async {
    // Case 1: Existing Google user with registered Face ID
    if (!result.isNewUser && result.existingUser != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF00A896),
          content: Text('🎉 เข้าสู่ระบบสำเร็จ ยินดีต้อนรับคุณ ${result.googleName}'),
        ),
      );
      _navigateToRoleScreen(result.existingUser!);
      return;
    }

    // Case 2: New Google user without Face ID -> Prompt & Navigate to 3D Face ID Enrollment
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F8F5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.face_retouching_natural_rounded,
                  color: Color(0xFF00A896), size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              'ยินดีต้อนรับคุณ ${result.googleName}!',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'บัญชี Google (${result.googleEmail}) ยืนยันตัวตนสำเร็จแล้ว\nเพื่อความปลอดภัยสูงสุด กรุณาสแกนใบหน้า Face ID 3 มิติเพื่อผูกบัญชี',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
                label: const Text(
                  'เริ่มสแกนใบหน้า (Face ID)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A896),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final embeddingResult = await Navigator.push<List<double>>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FaceScanScreen(
                        mode: FaceScanMode.register,
                        registrationName: result.googleName,
                        registrationEmail: result.googleEmail,
                        registrationRole: 'driver',
                      ),
                    ),
                  );

                  if (embeddingResult != null && embeddingResult.isNotEmpty) {
                    final profile = UserFaceProfile(
                      id: result.googleEmail!,
                      email: result.googleEmail!,
                      name: result.googleName!,
                      role: 'driver',
                      faceEmbedding: embeddingResult,
                      avatarPath: result.googlePhotoUrl,
                      registeredAt: DateTime.now(),
                    );
                    await FaceAuthRepository.registerUser(profile);
                    if (mounted) {
                      _navigateToRoleScreen(profile);
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGoogleInputModal() {
    final googleEmailCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 58,
              height: 58,
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const GoogleLogo(size: 34),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sign in with Google',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'กรุณาระบุบัญชี Google ของคุณเพื่อดำเนินการต่อ',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white24),
              ),
              child: TextField(
                controller: googleEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.email_outlined, color: Colors.white60),
                  hintText: 'yourname@gmail.com',
                  hintStyle: TextStyle(color: Colors.white38),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () async {
                  final email = googleEmailCtrl.text.trim();
                  if (email.isEmpty || !email.contains('@')) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: Colors.redAccent,
                        content: Text('⚠️ กรุณากรอกอีเมล Google ให้ถูกต้อง'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  setState(() => _isLoading = true);
                  final processed = await GoogleAuthService.processGoogleUser(
                    email: email,
                    name: email.split('@').first,
                  );
                  setState(() => _isLoading = false);
                  if (mounted) _handleGoogleUser(processed);
                },
                child: const Text(
                  'เข้าสู่ระบบด้วย Google',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Request Email OTP ---
  void _onRequestEmailOtp() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orangeAccent,
          content: Text('⚠️ กรุณากรอกอีเมลก่อนขอรับรหัส OTP'),
        ),
      );
      return;
    }

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

    // Check duplicate email
    setState(() => _isLoading = true);
    final isDuplicate = await FaceAuthRepository.isEmailRegistered(email);
    setState(() {
      _isLoading = false;
      _isEmailAlreadyRegistered = isDuplicate;
    });

    if (!mounted) return;

    if (isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('⚠️ อีเมลนี้มีอยู่ในระบบแล้ว (ไม่ต้องขอ OTP) กรุณาใช้อีเมลอื่น หรือกดเข้าสู่ระบบ'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // Send OTP
    setState(() => _isLoading = true);
    final result = await EmailOtpService.sendOtp(email: email);
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result.isSuccess) {
      _showOtpModal(email, result.debugOtpCode);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(result.message),
        ),
      );
    }
  }

  // --- Show 6-Digit OTP Modal Sheet ---
  void _showOtpModal(String email, String? debugOtp) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OtpVerificationSheet(
        email: email,
        debugOtp: debugOtp,
        onVerified: () {
          Navigator.pop(ctx);
          setState(() {
            _isEmailVerified = true;
            _verifiedEmail = email.toLowerCase();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF00A896),
              content: Text('🛡️ ยืนยันอีเมลสำเร็จเรียบร้อย!'),
            ),
          );
        },
      ),
    );
  }

  // --- Show Forgot & Reset Password Modal Sheet ---
  void _showForgotPasswordModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ForgotPasswordSheet(
        initialEmail: _emailController.text.trim(),
        onPasswordResetSuccess: (email, newPassword) {
          Navigator.pop(ctx);
          setState(() {
            _emailController.text = email;
            _passwordController.text = newPassword;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF00A896),
              content: Text('🎉 รีเซ็ตรหัสผ่านใหม่สำเร็จ! กรุณากดเข้าสู่ระบบ'),
              duration: Duration(seconds: 4),
            ),
          );
        },
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

    if (!_isEmailVerified || _verifiedEmail != email.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orangeAccent,
          content: Text('⚠️ กรุณากดปุ่ม "ขอ OTP" เพื่อยืนยันอีเมลก่อนทำการสแกนหน้า'),
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
          registrationRole: _selectedRole,
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

    // 1. Email OTP verification check
    if (!_isEmailVerified || _verifiedEmail != email.toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orangeAccent,
          content: Text('⚠️ กรุณากดปุ่ม "ขอ OTP" เพื่อยืนยันอีเมลของคุณก่อนลงทะเบียน'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // 2. Duplicate email check (Usernames can be duplicated)
    setState(() => _isLoading = true);
    final isDuplicateEmail = await FaceAuthRepository.isEmailRegistered(email);
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (isDuplicateEmail) {
      setState(() => _isEmailAlreadyRegistered = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('⚠️ อีเมลนี้ถูกใช้งานแล้ว กรุณาใช้อีเมลอื่น หรือเข้าสู่ระบบ'),
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
      role: _selectedRole,
      faceEmbedding: _registeredFaceEmbedding!,
      registeredAt: DateTime.now(),
    );

    await FaceAuthRepository.registerUser(newProfile);
    await FaceAuthRepository.updateUserPassword(email, password);

    _navigateToRoleScreen(newProfile);
  }

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor =
        isLogin ? const Color(0xFFE2F0FE) : const Color(0xFFE3F8EB);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87),
          onPressed: _onBackPressed,
        ),
        title: Text(
          isLogin ? 'เข้าสู่ระบบ (Sign In)' : 'ลงทะเบียน (Register)',
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
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
                if (!isLogin) {
                  setState(() {
                    isLogin = true;
                    _isCheckingEmail = false;
                    _isEmailAlreadyRegistered = false;
                  });
                }
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
                if (isLogin) {
                  setState(() {
                    isLogin = false;
                  });
                  _onEmailInputChanged();
                }
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
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _showForgotPasswordModal,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'ลืมรหัสผ่าน?',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        _buildGoogleSignInButton(),
        const SizedBox(height: 16),
        _buildGuestModeButton(),
      ],
    );
  }

  Widget _buildGuestModeButton() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: Colors.grey.shade400, thickness: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'หรือเข้าใช้งานด่วน',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(child: Divider(color: Colors.grey.shade400, thickness: 1)),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _onEnterAsGuest,
            icon: const Icon(Icons.explore_rounded, color: Color(0xFF00A896), size: 20),
            label: const Text(
              'เข้าใช้งานแบบผู้ใช้ทั่วไป (Guest Mode)',
              style: TextStyle(
                color: Color(0xFF00A896),
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF00A896), width: 1.5),
              backgroundColor: Colors.white.withValues(alpha: 0.8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
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
        _buildInputLabel('Gmail / Email (อีเมลยืนยันตัวตน)'),
        // Email Field with Integrated OTP Request & Verified Badge
        _buildEmailWithOtpField(),
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
        const SizedBox(height: 14),
        _buildInputLabel('เลือกบทบาทการใช้งาน (Role)'),
        _buildRoleSelector(),
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
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: Divider(color: Colors.grey.shade400, thickness: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'หรือลงทะเบียนด้วย Google',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(child: Divider(color: Colors.grey.shade400, thickness: 1)),
          ],
        ),
        const SizedBox(height: 14),
        _buildGoogleSignInButton(),
      ],
    );
  }

  Widget _buildRoleSelector() {
    return Row(
      children: [
        _buildRoleChip(
            'driver', 'ผู้ใช้ทั่วไป', Icons.directions_car_rounded, const Color(0xFF5B9EE1)),
        const SizedBox(width: 8),
        _buildRoleChip(
            'ambulance', 'Ambulance', Icons.airport_shuttle_rounded, const Color(0xFFEB5757)),
        const SizedBox(width: 8),
        _buildRoleChip(
            'agency', 'หน่วยงาน', Icons.local_hospital_rounded, const Color(0xFF00A896)),
      ],
    );
  }

  Widget _buildRoleChip(
      String roleKey, String label, IconData icon, Color color) {
    final isSelected = _selectedRole == roleKey;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedRole = roleKey);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? color : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: isSelected ? Colors.white : color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailWithOtpField() {
    final bool isValidFormat =
        RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
            .hasMatch(_emailController.text.trim());

    Color borderColor = Colors.transparent;
    if (_isEmailAlreadyRegistered) {
      borderColor = Colors.redAccent;
    } else if (_isEmailVerified) {
      borderColor = const Color(0xFF00A896);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: _isEmailAlreadyRegistered
                ? const Color(0xFFFFF5F5)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: borderColor == Colors.transparent ? 0 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _isEmailAlreadyRegistered
                    ? Colors.red.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      Icons.email_outlined,
                      color: _isEmailAlreadyRegistered
                          ? Colors.redAccent
                          : Colors.grey,
                      size: 20,
                    ),
                    hintText: 'name@gmail.com',
                    hintStyle:
                        TextStyle(color: Colors.grey.shade400, fontSize: 13.5),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: _isCheckingEmail
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF00A896),
                          ),
                        ),
                      )
                    : _isEmailAlreadyRegistered
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.redAccent),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    size: 14, color: Colors.redAccent),
                                SizedBox(width: 4),
                                Text(
                                  'มีในระบบแล้ว',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _isEmailVerified
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F8F5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFF00A896)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified_user_rounded,
                                        size: 14, color: Color(0xFF00A896)),
                                    SizedBox(width: 4),
                                    Text(
                                      'ยืนยันแล้ว',
                                      style: TextStyle(
                                        color: Color(0xFF00A896),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ElevatedButton(
                                onPressed: (_isLoading ||
                                        _isEmailAlreadyRegistered ||
                                        !isValidFormat)
                                    ? null
                                    : _onRequestEmailOtp,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00A896),
                                  disabledBackgroundColor:
                                      Colors.grey.shade300,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  minimumSize: Size.zero,
                                ),
                                child: Text(
                                  'ขอ OTP',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: (_isEmailAlreadyRegistered ||
                                            !isValidFormat)
                                        ? Colors.grey.shade600
                                        : Colors.white,
                                  ),
                                ),
                              ),
              ),
            ],
          ),
        ),
        if (_isEmailAlreadyRegistered) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 16, color: Colors.redAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '⚠️ อีเมลนี้มีอยู่ในระบบแล้ว (ไม่ต้องขอ OTP) กรุณาใช้อีเมลอื่น หรือกดปุ่ม "Sign in"',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.red.shade800,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (!_isEmailVerified &&
            isValidFormat &&
            !_isCheckingEmail) ...[
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(Icons.check_circle_outline_rounded,
                  size: 14, color: Colors.teal.shade600),
              const SizedBox(width: 4),
              Text(
                '✓ อีเมลนี้สามารถใช้ลงทะเบียนได้ (กด "ขอ OTP" เพื่อยืนยัน)',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.teal.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
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

  Widget _buildGoogleSignInButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _onGoogleLogin,
          borderRadius: BorderRadius.circular(20),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 13, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GoogleLogo(size: 20),
                SizedBox(width: 10),
                Text(
                  'เข้าสู่ระบบด้วย Google',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
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

/// 6-Digit Email OTP Verification Bottom Sheet with 60s Countdown
class _OtpVerificationSheet extends StatefulWidget {
  final String email;
  final String? debugOtp;
  final VoidCallback onVerified;

  const _OtpVerificationSheet({
    required this.email,
    this.debugOtp,
    required this.onVerified,
  });

  @override
  State<_OtpVerificationSheet> createState() => _OtpVerificationSheetState();
}

class _OtpVerificationSheetState extends State<_OtpVerificationSheet> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  int _countdown = 60;
  Timer? _timer;
  String? _errorMessage;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    // Auto focus first pin box
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  void _startCountdown() {
    _countdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() => _countdown--);
      } else {
        _timer?.cancel();
      }
    });
  }

  void _onResendOtp() async {
    if (_countdown > 0) return;
    final result = await EmailOtpService.sendOtp(email: widget.email);
    if (result.isSuccess) {
      _startCountdown();
      setState(() {
        _errorMessage = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF00A896),
            content: Text(result.message),
          ),
        );
      }
    }
  }

  void _submitOtp() {
    final code = _controllers.map((c) => c.text.trim()).join();
    if (code.length < 6) {
      setState(() => _errorMessage = 'กรุณากรอกรหัส OTP ให้ครบทั้ง 6 หลัก');
      return;
    }

    setState(() => _isVerifying = true);
    final result = EmailOtpService.verifyOtp(email: widget.email, inputOtp: code);
    setState(() => _isVerifying = false);

    if (result.isSuccess) {
      HapticFeedback.heavyImpact();
      widget.onVerified();
    } else {
      HapticFeedback.vibrate();
      setState(() {
        _errorMessage = result.message;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 28,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFF00A896).withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mark_email_read_rounded,
                color: Color(0xFF00A896), size: 32),
          ),
          const SizedBox(height: 14),
          const Text(
            'ยืนยันรหัส OTP 6 หลัก',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'ระบบได้ส่งรหัสยืนยันไปยัง\n${widget.email}\n(กรุณาตรวจสอบในกล่องจดหมาย Inbox หรือ Junk Mail)',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 24),

          // 6 PIN Input Boxes
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              return SizedBox(
                width: 44,
                height: 52,
                child: TextField(
                  controller: _controllers[index],
                  focusNode: _focusNodes[index],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(1),
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.zero,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFF00A896), width: 2),
                    ),
                  ),
                  onChanged: (val) {
                    if (val.isNotEmpty && index < 5) {
                      _focusNodes[index + 1].requestFocus();
                    } else if (val.isEmpty && index > 0) {
                      _focusNodes[index - 1].requestFocus();
                    }
                    if (index == 5 && val.isNotEmpty) {
                      _submitOtp();
                    }
                  },
                ),
              );
            }),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
            ),
          ],

          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _countdown > 0
                    ? 'ขอรหัสใหม่ได้ใน ($_countdown วินาที)'
                    : 'ไม่ได้รับรหัส OTP?',
                style: const TextStyle(color: Colors.white60, fontSize: 13),
              ),
              if (_countdown == 0)
                TextButton(
                  onPressed: _onResendOtp,
                  child: const Text(
                    'ส่งรหัสใหม่อีกครั้ง',
                    style: TextStyle(
                      color: Color(0xFF00A896),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isVerifying ? null : _submitOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A896),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 0,
              ),
              child: Text(
                _isVerifying ? 'กำลังตรวจสอบ...' : 'ยืนยันรหัส OTP',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 3-Step Apple-Style Forgot & Reset Password Sheet
class _ForgotPasswordSheet extends StatefulWidget {
  final String initialEmail;
  final Function(String email, String newPassword) onPasswordResetSuccess;

  const _ForgotPasswordSheet({
    required this.initialEmail,
    required this.onPasswordResetSuccess,
  });

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  int _step = 1; // 1: Email, 2: OTP, 3: New Password
  bool _isLoading = false;
  String? _errorMessage;

  // Step 1: Email
  late final TextEditingController _emailController;

  // Step 2: OTP
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  int _countdown = 60;
  Timer? _timer;

  // Step 3: New Password
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
    _newPasswordController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // --- Password Strength Rules ---
  bool get _hasMinLength => _newPasswordController.text.length >= 8;
  bool get _hasUpperLower =>
      _newPasswordController.text.contains(RegExp(r'[A-Z]')) &&
      _newPasswordController.text.contains(RegExp(r'[a-z]'));
  bool get _hasNumber => _newPasswordController.text.contains(RegExp(r'[0-9]'));
  bool get _hasSpecialChar => _newPasswordController.text
      .contains(RegExp(r'[!@#$%^&*(),.?":{}|<>\-_=+]'));

  int get _passwordStrengthScore {
    int score = 0;
    if (_hasMinLength) score++;
    if (_newPasswordController.text.contains(RegExp(r'[A-Z]'))) score++;
    if (_newPasswordController.text.contains(RegExp(r'[a-z]'))) score++;
    if (_hasNumber) score++;
    if (_hasSpecialChar) score++;
    return score;
  }

  bool get _isPasswordSecure =>
      _hasMinLength && _hasUpperLower && _hasNumber && _hasSpecialChar;

  // --- Step 1: Send OTP ---
  void _sendResetOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'กรุณากรอกอีเมลของคุณ');
      return;
    }

    final bool isValidEmail =
        RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
    if (!isValidEmail) {
      setState(() => _errorMessage = 'รูปแบบอีเมลไม่ถูกต้อง');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final isRegistered = await FaceAuthRepository.isEmailRegistered(email);
    if (!isRegistered) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'ไม่พบอีเมลนี้ในระบบ กรุณาตรวจสอบอีเมลหรือสมัครสมาชิกใหม่';
      });
      return;
    }

    final result = await EmailOtpService.sendOtp(email: email);
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      setState(() {
        _step = 2;
      });
      _startCountdown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _otpFocusNodes[0].requestFocus();
      });
    } else {
      setState(() => _errorMessage = result.message);
    }
  }

  void _startCountdown() {
    _countdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 0) {
        setState(() => _countdown--);
      } else {
        _timer?.cancel();
      }
    });
  }

  // --- Step 2: Verify OTP ---
  void _verifyResetOtp() {
    final code = _otpControllers.map((c) => c.text.trim()).join();
    if (code.length < 6) {
      setState(() => _errorMessage = 'กรุณากรอกรหัส OTP ให้ครบทั้ง 6 หลัก');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = EmailOtpService.verifyOtp(
        email: _emailController.text.trim(), inputOtp: code);
    setState(() => _isLoading = false);

    if (result.isSuccess) {
      HapticFeedback.heavyImpact();
      setState(() {
        _step = 3;
        _errorMessage = null;
      });
    } else {
      HapticFeedback.vibrate();
      setState(() => _errorMessage = result.message);
    }
  }

  // --- Step 3: Save New Password ---
  void _saveNewPassword() async {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      setState(() => _errorMessage = 'กรุณากรอกรหัสผ่านให้ครบถ้วน');
      return;
    }

    if (!_isPasswordSecure) {
      setState(() => _errorMessage =
          'รหัสผ่านต้องมีความยาวอย่างน้อย 8 ตัวอักษร และมีตัวพิมพ์ใหญ่ พิมพ์เล็ก ตัวเลข และอักขระพิเศษ');
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() => _errorMessage = 'รหัสผ่านและการยืนยันรหัสผ่านไม่ตรงกัน');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    await FaceAuthRepository.updateUserPassword(email, newPassword);

    setState(() => _isLoading = false);
    HapticFeedback.heavyImpact();
    widget.onPasswordResetSuccess(email, newPassword);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 28,
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _buildCurrentStep(),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 1:
        return _buildStep1Email();
      case 2:
        return _buildStep2Otp();
      case 3:
        return _buildStep3NewPassword();
      default:
        return const SizedBox.shrink();
    }
  }

  // --- Step 1: Input Email Layout ---
  Widget _buildStep1Email() {
    return Column(
      key: const ValueKey('step_1_email'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHandleBar(),
        const SizedBox(height: 18),
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: const Color(0xFF5B9EE1).withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.lock_reset_rounded,
              color: Color(0xFF5B9EE1), size: 32),
        ),
        const SizedBox(height: 14),
        const Text(
          'ลืมรหัสผ่าน / รีเซ็ตรหัสผ่าน',
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 6),
        const Text(
          'กรุณากรอกอีเมลของคุณ เราจะส่งรหัส OTP 6 หลัก\nเพื่อใช้ยืนยันตัวตนในการตั้งรหัสผ่านใหม่',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.email_outlined, color: Colors.white60),
              hintText: 'name@gmail.com',
              hintStyle: TextStyle(color: Colors.white38),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: InputBorder.none,
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _sendResetOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5B9EE1),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              elevation: 0,
            ),
            child: Text(
              _isLoading ? 'กำลังส่งรหัส OTP...' : 'ขอรหัส OTP เพื่อรีเซ็ต',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Step 2: Input OTP Layout ---
  Widget _buildStep2Otp() {
    return Column(
      key: const ValueKey('step_2_otp'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHandleBar(),
        const SizedBox(height: 18),
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: const Color(0xFF00A896).withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.mark_email_read_rounded,
              color: Color(0xFF00A896), size: 32),
        ),
        const SizedBox(height: 14),
        const Text(
          'กรอกรหัส OTP 6 หลัก',
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 6),
        Text(
          'รหัสถูกส่งไปยังอีเมล\n${_emailController.text.trim()}\n(กรุณาตรวจสอบในกล่องจดหมาย Inbox หรือ Junk Mail)',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 22),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 44,
              height: 52,
              child: TextField(
                controller: _otpControllers[index],
                focusNode: _otpFocusNodes[index],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(1),
                  FilteringTextInputFormatter.digitsOnly,
                ],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFF00A896), width: 2),
                  ),
                ),
                onChanged: (val) {
                  if (val.isNotEmpty && index < 5) {
                    _otpFocusNodes[index + 1].requestFocus();
                  } else if (val.isEmpty && index > 0) {
                    _otpFocusNodes[index - 1].requestFocus();
                  }
                  if (index == 5 && val.isNotEmpty) {
                    _verifyResetOtp();
                  }
                },
              ),
            );
          }),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _countdown > 0
                  ? 'ขอรหัสใหม่ได้ใน ($_countdown วินาที)'
                  : 'ไม่ได้รับรหัส OTP?',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
            if (_countdown == 0)
              TextButton(
                onPressed: _sendResetOtp,
                child: const Text(
                  'ส่งรหัสใหม่อีกครั้ง',
                  style: TextStyle(
                    color: Color(0xFF00A896),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyResetOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A896),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              elevation: 0,
            ),
            child: Text(
              _isLoading ? 'กำลังตรวจสอบ...' : 'ยืนยันรหัส OTP',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Step 3: Input New Password Layout ---
  Widget _buildStep3NewPassword() {
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
      key: const ValueKey('step_3_new_password'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHandleBar(),
        const SizedBox(height: 18),
        const Text(
          'ตั้งรหัสผ่านใหม่ (Reset Password)',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 6),
        Text(
          'สำหรับบัญชี: ${_emailController.text.trim()}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF34D399), fontSize: 13),
        ),
        const SizedBox(height: 16),
        // New Password
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: TextField(
            controller: _newPasswordController,
            obscureText: _obscureNewPassword,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              prefixIcon:
                  const Icon(Icons.lock_outline_rounded, color: Colors.white60),
              hintText: 'รหัสผ่านใหม่ (อย่างน้อย 8 ตัวอักษร)',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: InputBorder.none,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNewPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white60,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscureNewPassword = !_obscureNewPassword),
              ),
            ),
          ),
        ),

        // Live Strength Meter
        if (_newPasswordController.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ระดับความปลอดภัย:',
                  style: TextStyle(fontSize: 11, color: Colors.white70)),
              Text(strengthText,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: barColor)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: List.generate(5, (index) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: index < 4 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: index < score ? barColor : Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ],

        const SizedBox(height: 12),
        // Confirm Password
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: TextField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              prefixIcon:
                  const Icon(Icons.lock_reset_rounded, color: Colors.white60),
              hintText: 'ยืนยันรหัสผ่านใหม่อีกครั้ง',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: InputBorder.none,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white60,
                  size: 20,
                ),
                onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
          ),
        ),

        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
            textAlign: TextAlign.center,
          ),
        ],

        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveNewPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A896),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              elevation: 0,
            ),
            child: Text(
              _isLoading ? 'กำลังบันทึกรหัสผ่านใหม่...' : 'บันทึกรหัสผ่านใหม่',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHandleBar() {
    return Container(
      width: 44,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}