import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/models/incident_report.dart';
import '../../../core/services/incident_service.dart';
import '../../../core/services/hospital_location_service.dart';
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

  int _monthlyCaseCount = 0;
  double _erOnTimeRate = 0.0;
  int _criticalCaseCount = 0;
  // จำนวนเคสของ 6 เดือนล่าสุด เรียงเก่า -> ใหม่ (index 5 = เดือนปัจจุบัน)
  List<int> _sixMonthTrend = List.filled(6, 0);
  StreamSubscription<List<IncidentReport>>? _incidentSub;
  StreamSubscription<HospitalProfile>? _hospitalSub;

  // โรงพยาบาลของบัญชี agency ที่ล็อกอินอยู่ (เพิ่มตอนทำ multi-hospital) — null
  // หมายถึงบัญชีเก่าที่ยังไม่มี hospitalId จะไม่กรองสถิติอะไรเลย (เห็นเหมือนเดิม)
  String? _myHospitalId;

  @override
  void initState() {
    super.initState();
    _initProfileScreen();
  }

  // ต้องรู้ hospitalId ของบัญชีที่ล็อกอินอยู่ก่อน ถึงจะโหลดสถิติ/โปรไฟล์
  // โรงพยาบาลได้อย่างถูกต้อง — เดิมสามฟังก์ชันนี้เรียกพร้อมกันหมดตอน initState()
  // แข่งกันเอง (เจอระหว่างแก้ไขรอบ multi-hospital) เรียงลำดับให้ชัดเจนแทน และ
  // reuse _currentUser จาก _loadUserData() แทนที่จะดึงซ้ำ
  Future<void> _initProfileScreen() async {
    await _loadUserData();
    _myHospitalId = _currentUser?.hospitalId;
    _loadIncidentStats();
    _loadHospitalProfile();
  }

  List<IncidentReport> _filterByMyHospital(List<IncidentReport> list) {
    if (_myHospitalId == null) return list;
    return list.where((i) => i.targetHospitalId == _myHospitalId).toList();
  }

  @override
  void dispose() {
    _incidentSub?.cancel();
    _hospitalSub?.cancel();
    super.dispose();
  }

  // โหลดข้อมูลหน่วยงาน/สถานะ ER จริงจาก HospitalLocationService (เดิม _isErAvailable
  // และ _hospitalName เป็นแค่ local state ที่ไม่เชื่อมกับ service จริงเลย)
  Future<void> _loadHospitalProfile() async {
    // เดิมเรียก initialize() ไม่ส่ง hospitalId เลย ได้ HOSP-01 เสมอไม่ว่าบัญชี
    // agency ไหนจะล็อกอินอยู่ (เจอตอนวางแผน multi-hospital)
    await HospitalLocationService().initialize(hospitalId: _myHospitalId);
    final profile = HospitalLocationService().currentProfile;
    if (mounted) {
      setState(() {
        _hospitalName = profile.hospitalName;
        _contactNumber = profile.erPhone;
        _isErAvailable = profile.isErAvailable;
      });
    }

    _hospitalSub = HospitalLocationService().profileStream.listen((profile) {
      if (mounted) {
        setState(() {
          _hospitalName = profile.hospitalName;
          _contactNumber = profile.erPhone;
          _isErAvailable = profile.isErAvailable;
        });
      }
    });
  }

  // คำนวณสถิติจริงจากเคสในระบบ (เดิมเป็นเลข 154/92%/34 hardcode คงที่)
  Future<void> _loadIncidentStats() async {
    await IncidentService().initialize();
    // เดิมคำนวณสถิติจากเคสทุกโรงพยาบาลในระบบรวมกัน ไม่ใช่แค่ของโรงพยาบาลนี้
    // (เจอตอนวางแผน multi-hospital)
    final initial = _filterByMyHospital(await IncidentService().getLocalIncidents());
    if (mounted) _computeStats(initial);

    _incidentSub = IncidentService().incidentsStream.listen((list) {
      if (mounted) _computeStats(_filterByMyHospital(list));
    });
  }

  void _computeStats(List<IncidentReport> incidents) {
    final now = DateTime.now();
    final thisMonth = incidents
        .where((i) =>
            i.status != 'cancelled' &&
            i.createdAt.year == now.year &&
            i.createdAt.month == now.month)
        .toList();

    final total = thisMonth.length;
    final erPreparedCount = thisMonth.where((i) => i.isErPrepared).length;
    final criticalCount = thisMonth
        .where((i) =>
            i.severity.contains('Code Red') || i.severity.contains('วิกฤต'))
        .length;

    // นับจำนวนเคสของ 6 เดือนล่าสุดจริง (ไม่รวมเคสที่ถูกยกเลิก) สำหรับกราฟแนวโน้ม
    final trend = List<int>.filled(6, 0);
    for (int i = 0; i < 6; i++) {
      final target = DateTime(now.year, now.month - (5 - i));
      trend[i] = incidents
          .where((inc) =>
              inc.status != 'cancelled' &&
              inc.createdAt.year == target.year &&
              inc.createdAt.month == target.month)
          .length;
    }

    setState(() {
      _monthlyCaseCount = total;
      _erOnTimeRate = total > 0 ? erPreparedCount / total : 0.0;
      _criticalCaseCount = criticalCount;
      _sixMonthTrend = trend;
    });
  }

  Future<void> _loadUserData() async {
    final user = await FaceAuthRepository.getCurrentUser();
    if (mounted && user != null) {
      setState(() {
        _currentUser = user;
        // หมายเหตุ: user.name คือชื่อบัญชีส่วนตัวของเจ้าหน้าที่ (dispatcher) ไม่ใช่ชื่อ
        // โรงพยาบาล/หน่วยงาน ซึ่งโหลดแยกจาก HospitalLocationService ใน _loadHospitalProfile()
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

                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton(
                        onPressed: () => _showDeleteAccountDialog(context),
                        child: const Text(
                          'ลบบัญชีและข้อมูลของฉันถาวร (Delete Account)',
                          style: TextStyle(color: Colors.redAccent, fontSize: 13),
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

          // วงกลมใหญ่ (จำนวนเคสรับเข้าต่อเดือน) — คำนวณจากเคสจริงในระบบ
          _buildGauge(
            valueText: '$_monthlyCaseCount',
            labelText: 'จำนวนเคสรับเข้าต่อเดือน',
            size: 130,
            strokeWidth: 14,
            progress: (_monthlyCaseCount / 50.0).clamp(0.0, 1.0),
          ),

          const SizedBox(height: 28),

          // วงกลมเล็ก 2 วงคู่กัน (ประสิทธิภาพ ER และ เคสวิกฤต) — คำนวณจากเคสจริง
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildGauge(
                valueText: '${(_erOnTimeRate * 100).round()}%',
                labelText: 'เตรียม ER ทันเวลา',
                size: 90,
                strokeWidth: 10,
                progress: _erOnTimeRate,
              ),
              _buildGauge(
                valueText: '$_criticalCaseCount',
                labelText: 'เคสวิกฤต (Code Red)',
                size: 90,
                strokeWidth: 10,
                progress: (_criticalCaseCount / 30.0).clamp(0.0, 1.0),
              ),
            ],
          ),

          const SizedBox(height: 28),
          _buildMonthlyTrendChart(),
        ],
      ),
    );
  }

  // --- กราฟแนวโน้มจำนวนเคสย้อนหลัง 6 เดือน (คำนวณจากเคสจริงในระบบ) ---
  Widget _buildMonthlyTrendChart() {
    final now = DateTime.now();
    const monthAbbrTH = [
      'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
      'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
    ];
    final maxVal = _sixMonthTrend.reduce((a, b) => a > b ? a : b);
    final chartMax = (maxVal < 5 ? 5 : maxVal).toDouble() * 1.2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'แนวโน้มจำนวนเคสย้อนหลัง 6 เดือน',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: BarChart(
            BarChartData(
              maxY: chartMax,
              alignment: BarChartAlignment.spaceAround,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx > 5) return const SizedBox.shrink();
                      final monthIdx = (now.month - (5 - idx) - 1) % 12;
                      final normalizedIdx = monthIdx < 0 ? monthIdx + 12 : monthIdx;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          monthAbbrTH[normalizedIdx],
                          style: const TextStyle(fontSize: 10, color: Colors.black54),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    return BarTooltipItem(
                      '${rod.toY.round()} เคส',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    );
                  },
                ),
              ),
              barGroups: List.generate(_sixMonthTrend.length, (i) {
                final isCurrentMonth = i == _sixMonthTrend.length - 1;
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: _sixMonthTrend[i].toDouble(),
                      width: 18,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      color: isCurrentMonth
                          ? const Color(0xFF1B5E20)
                          : const Color(0xFF1B5E20).withValues(alpha: 0.35),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
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
              onChanged: (val) async {
                // เขียนสถานะจริงลง HospitalLocationService (sync ข้าม device ผ่าน Firestore)
                // เดิม setState local เฉยๆ ไม่เคยเรียก service เลย
                final success =
                    await HospitalLocationService().updateErAvailability(val);
                if (!mounted) return;
                setState(() {
                  if (success) _isErAvailable = val;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? (val
                              ? '✅ อัปเดตสถานะ: ห้องฉุกเฉินพร้อมรับผู้ป่วย'
                              : '🚨 อัปเดตสถานะ: ประกาศเตียงเต็ม (Divert)')
                          : '❌ อัปเดตสถานะไม่สำเร็จ กรุณาลองใหม่',
                    ),
                    backgroundColor: success
                        ? (val ? const Color(0xFF2E7D32) : const Color(0xFFEB5757))
                        : Colors.grey,
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

  // ลบบัญชี + ข้อมูลใบหน้าถาวร (รองรับสิทธิ "ขอให้ลบข้อมูล" ตาม PDPA)
  void _showDeleteAccountDialog(BuildContext context) {
    if (_currentUser == null) return;
    final passCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบบัญชีและข้อมูลของฉัน'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'การลบบัญชีจะลบข้อมูลใบหน้า รหัสผ่าน และโปรไฟล์ทั้งหมดอย่างถาวร กู้คืนไม่ได้',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'ยืนยันด้วยรหัสผ่านปัจจุบัน'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () async {
              final authResult = await FaceAuthRepository.authenticateWithPassword(
                email: _currentUser!.email,
                password: passCtrl.text,
              );
              if (!authResult.isSuccess) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('รหัสผ่านไม่ถูกต้อง')),
                  );
                }
                return;
              }

              await FaceAuthRepository.deleteAccount(_currentUser!.email);

              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const FaceLoginScreen()),
                (route) => false,
              );
            },
            child: const Text('ลบถาวร',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
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
        onPressed: () async {
          // ออกจากระบบกลับไปหน้าล็อกอิน (เดิมไม่ได้เคลียร์ session จริงเลย)
          await FaceAuthRepository.logout();
          if (!context.mounted) return;
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
                  onPressed: () async {
                    // บันทึกจริงผ่าน HospitalLocationService (sync ข้าม device ผ่าน Firestore)
                    // เดิมแก้แค่ local state หาย ทันทีที่ปิดแอพ/รีสตาร์ท
                    final currentLocation =
                        HospitalLocationService().currentProfile.location;
                    final success =
                        await HospitalLocationService().updatePinnedLocation(
                      newLocation: currentLocation,
                      hospitalName: nameCtrl.text,
                      erPhone: phoneCtrl.text,
                    );
                    if (success && mounted) {
                      setState(() {
                        _hospitalName = nameCtrl.text;
                        _contactNumber = phoneCtrl.text;
                      });
                    }
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success
                            ? '✅ บันทึกข้อมูลหน่วยงานสำเร็จ'
                            : '❌ บันทึกข้อมูลไม่สำเร็จ กรุณาลองใหม่'),
                        backgroundColor:
                            success ? const Color(0xFF2E7D32) : Colors.grey,
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
                  onPressed: () async {
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
                    if (_currentUser == null) return;

                    // ตรวจรหัสผ่านเดิมจริงก่อนอนุญาตให้เปลี่ยน (เดิมไม่เช็คเลย)
                    final authResult = await FaceAuthRepository.authenticateWithPassword(
                      email: _currentUser!.email,
                      password: oldPassCtrl.text,
                    );
                    if (!authResult.isSuccess) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('รหัสผ่านเดิมไม่ถูกต้อง')),
                        );
                      }
                      return;
                    }

                    await FaceAuthRepository.updateUserPassword(
                      _currentUser!.email,
                      newPassCtrl.text,
                    );

                    if (!ctx.mounted) return;
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