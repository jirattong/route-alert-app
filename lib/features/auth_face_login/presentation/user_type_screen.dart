import 'package:flutter/material.dart';
import '../../driver_radar/presentation/driver_main_screen.dart';
import '../../ambulance/presentation/ambulance_main_screen.dart';
import '../../agency/presentation/agency_main_screen.dart';
import '../data/models/user_face_profile.dart';
import '../data/services/face_auth_repository.dart';
import 'face_login_screen.dart';

class UserTypeScreen extends StatefulWidget {
  const UserTypeScreen({super.key});

  @override
  State<UserTypeScreen> createState() => _UserTypeScreenState();
}

class _UserTypeScreenState extends State<UserTypeScreen> {
  UserFaceProfile? _currentUser;
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final user = await FaceAuthRepository.getCurrentUser();
    if (mounted) {
      setState(() {
        _currentUser = user;
        _isLoadingUser = false;
      });
    }
  }

  void _onLogout() async {
    await FaceAuthRepository.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const FaceLoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 8),

                    // User Profile Identification Card
                    if (!_isLoadingUser && _currentUser != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00A896), Color(0xFF028090)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF00A896).withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.face_retouching_natural_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'สวัสดีคุณ ${_currentUser!.name}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _currentUser!.email,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'เข้าสู่ระบบแล้ว',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Badge เตือนว่าเป็นการเลือกครั้งแรก
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amber.shade400),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: Colors.amber),
                          SizedBox(width: 6),
                          Text(
                            'ตั้งค่าบทบาทบัญชี (กำหนดได้เพียงครั้งเดียว)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    const Text(
                      'คุณคือใคร ?',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'กรุณาเลือกประเภทผู้ใช้งานเพื่อผูกสิทธิ์กับบัญชีนี้',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // --- ปุ่ม 1: ผู้ใช้ทั่วไป (สีน้ำเงิน) ---
                    _buildRoleCard(
                      title: 'ผู้ใช้ทั่วไป',
                      subtitle: 'สำหรับผู้ขับขี่และประชาชนบนท้องถนน',
                      icon: Icons.directions_car_rounded,
                      color: const Color(0xFF5B9EE1),
                      onTap: () {
                        _showOtpVerificationDialog(
                          context,
                          roleName: 'ผู้ใช้ทั่วไป',
                          roleColor: const Color(0xFF5B9EE1),
                          targetScreen: const DriverMainScreen(),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // --- ปุ่ม 2: รถ Ambulance (สีแดง) ---
                    _buildRoleCard(
                      title: 'รถ Ambulance',
                      subtitle: 'สำหรับเจ้าหน้าที่กู้ภัยและทีมปฏิบัติการฉุกเฉิน',
                      icon: Icons.airport_shuttle_rounded,
                      color: const Color(0xFFEB5757),
                      onTap: () {
                        _showOtpVerificationDialog(
                          context,
                          roleName: 'รถ Ambulance',
                          roleColor: const Color(0xFFEB5757),
                          targetScreen: const AmbulanceMainScreen(),
                        );
                      },
                    ),

                    const SizedBox(height: 20),

                    // --- ปุ่ม 3: หน่วยงาน (สีเขียว) ---
                    _buildRoleCard(
                      title: 'หน่วยงาน',
                      subtitle: 'สำหรับโรงพยาบาลและผู้ประสานงานศูนย์รับแจ้งเหตุ',
                      icon: Icons.local_hospital_rounded,
                      color: const Color(0xFF52E197),
                      onTap: () {
                        _showOtpVerificationDialog(
                          context,
                          roleName: 'หน่วยงาน/โรงพยาบาล',
                          roleColor: const Color(0xFF52E197),
                          targetScreen: const AgencyMainScreen(),
                        );
                      },
                    ),

                    const SizedBox(height: 30),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
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
              const SizedBox(width: 10),
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
          TextButton.icon(
            onPressed: _onLogout,
            icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.redAccent),
            label: const Text(
              'ออกจากระบบ',
              style: TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white70, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showOtpVerificationDialog(
    BuildContext context, {
    required String roleName,
    required Color roleColor,
    required Widget targetScreen,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.lock_person_rounded, color: roleColor, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'ยืนยันสิทธิ์ $roleName',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'คุณกำลังเลือกผูกบัญชีเป็น "$roleName"\nเมื่อกดยืนยันแล้ว คุณจะสามารถเข้าถึงระบบงานสำหรับบทบาทนี้ได้ทันที',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => targetScreen),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: roleColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('เข้าใช้งาน', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}