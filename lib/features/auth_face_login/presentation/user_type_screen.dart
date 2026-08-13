import 'package:flutter/material.dart';
import '../../driver_radar/presentation/driver_main_screen.dart';
import '../../ambulance/presentation/ambulance_main_screen.dart';
import '../../agency/presentation/agency_main_screen.dart'; // 👈 นำเข้าไฟล์ AgencyMainScreen ที่พึ่งสร้าง

class UserTypeScreen extends StatelessWidget {
  const UserTypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Column(
          children: [
            // --- Header Bar ด้านบน ---
            _buildHeader(),

            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 10),

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
                          targetScreen: const AgencyMainScreen(), // 👈 เปลี่ยนปลายทางเป็น AgencyMainScreen อย่างถูกต้อง
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

  // --- Header แถบบนพร้อมโลโก้และชื่อ RouteAlert ---
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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

  // --- Helper: การ์ดปุ่มกดเลือกประเภทผู้ใช้ ---
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
            color: color.withOpacity(0.35),
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
                    color: Colors.white.withOpacity(0.2),
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
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Modal หน้าต่างกรอกเบอร์โทรศัพท์และรับ OTP ---
  void _showOtpVerificationDialog(
    BuildContext context, {
    required String roleName,
    required Color roleColor,
    required Widget targetScreen,
  }) {
    final TextEditingController phoneController = TextEditingController();
    final TextEditingController otpController = TextEditingController();
    bool isOtpSent = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                top: 24,
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
                  Text(
                    'ยืนยันตัวตนสำหรับสิทธิ์ "$roleName"',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: roleColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'กรุณากรอกเบอร์โทรศัพท์เพื่อรับรหัส OTP ยืนยันการลงทะเบียน',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // ช่องกรอกเบอร์โทรศัพท์
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'เบอร์โทรศัพท์',
                      hintText: '08X-XXX-XXXX',
                      prefixIcon: const Icon(Icons.phone_android_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      suffixIcon: !isOtpSent
                          ? TextButton(
                              onPressed: () {
                                if (phoneController.text.isNotEmpty) {
                                  setModalState(() => isOtpSent = true);
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text('ส่งรหัส OTP 123456 ไปยังเบอร์ของคุณแล้ว'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              child: const Text('รับ OTP'),
                            )
                          : const Icon(Icons.check_circle, color: Colors.green),
                    ),
                  ),

                  if (isOtpSent) ...[
                    const SizedBox(height: 16),
                    // ช่องกรอก OTP (เมื่อกดรับ OTP แล้ว)
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        letterSpacing: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        labelText: 'รหัส OTP (ทดสอบ: 123456)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // ปุ่มยืนยันสิทธิ์
                  ElevatedButton(
                    onPressed: isOtpSent
                        ? () {
                            Navigator.pop(ctx); // ปิด Modal OTP

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('ยืนยันสิทธิ์บัญชีเป็น "$roleName" สำเร็จ!'),
                                backgroundColor: Colors.green,
                              ),
                            );

                            // นำพาไปยังหน้าหลักตามบทบาทผู้ใช้ที่ส่งเข้ามา
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => targetScreen,
                              ),
                            );
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: roleColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    child: const Text(
                      'ยืนยันและเริ่มใช้งาน',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}