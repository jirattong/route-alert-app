import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class AmbulanceIncidentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> incidentData;

  const AmbulanceIncidentDetailScreen({
    super.key,
    required this.incidentData,
  });

  @override
  State<AmbulanceIncidentDetailScreen> createState() =>
      _AmbulanceIncidentDetailScreenState();
}

class _AmbulanceIncidentDetailScreenState
    extends State<AmbulanceIncidentDetailScreen> {
  late int _currentStep;
  final List<String> _photoList = [];

  // ลำดับขั้นตอนการปฏิบัติงาน (Forward-Only State)
  final List<Map<String, String>> _statusSteps = [
    {'title': 'กำลังรอยืนยัน', 'desc': 'รอรถพยาบาลกดรับเคส'},
    {'title': 'กำลังเดินทางไปรับเคส', 'desc': 'ยิงสัญญาณเตือนผู้ใช้บนถนนเปิดทาง'},
    {'title': 'ถึงจุดเกิดเหตุแล้ว', 'desc': 'กำลังปฐมพยาบาลและประเมินผู้ป่วย'},
    {'title': 'รับผู้ป่วยแล้ว - กำลังส่ง รพ.', 'desc': 'นำทางและแจ้งห้อง ER เตรียมรับสาย'},
    {'title': 'ถึงโรงพยาบาล (เสร็จสิ้น)', 'desc': 'ส่งมอบผู้ป่วยและปิดภารกิจ'},
  ];

  @override
  void initState() {
    super.initState();
    _currentStep = widget.incidentData['statusStep'] ?? 1;
  }

  void _takePhoto() {
    setState(() {
      _photoList.add('https://picsum.photos/300/200?random=${_photoList.length + 1}');
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📸 บันทึกรูปภาพหน้างานส่งไปยังห้อง ER เรียบร้อยแล้ว')),
    );
  }

  // ⏳ ⏳ หน้าต่างยืนยันเปลี่ยนสถานะ พร้อมคูลดาวน์นับถอยหลัง 3 วินาที
  void _showNextStatusConfirmDialog() {
    if (_currentStep >= _statusSteps.length - 1) return;

    final nextStepInfo = _statusSteps[_currentStep + 1];
    int cooldownSec = 3; // ⏳ ตัวแปรนับถอยหลัง 3 วินาที

    showDialog(
      context: context,
      barrierDismissible: false, // ป้องกันการกดปิดนอกจอด้านนอกขณะนับเวลา
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // เริ่มนับถอยหลัง Timer 3 วินาที
            Timer? timer;
            if (cooldownSec > 0 && !(timer?.isActive ?? false)) {
              timer = Timer.periodic(const Duration(seconds: 1), (t) {
                if (cooldownSec > 0) {
                  setModalState(() {
                    cooldownSec--;
                  });
                } else {
                  t.cancel();
                }
              });
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
                side: const BorderSide(color: Color(0xFFEB5757), width: 2),
              ),
              backgroundColor: Colors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFEAEA),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.published_with_changes_rounded,
                        size: 44,
                        color: Color(0xFFEB5757),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ยืนยันเปลี่ยนสถานะ ?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'เปลี่ยนเป็น: "${nextStepInfo['title']}"',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFEB5757),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '(${nextStepInfo['desc']})',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ปุ่มยกเลิก และ ปุ่มยืนยัน (ติดคูลดาวน์ 3 วินาที)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              timer?.cancel();
                              Navigator.pop(ctx);
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(color: Colors.grey.shade400),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: Text(
                              'ยกเลิก',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            // 🔒 ปิดปุ่มไว้จนกว่าคูลดาวน์ 3 วินาทีจะครบ
                            onPressed: cooldownSec == 0
                                ? () {
                                    timer?.cancel();
                                    Navigator.pop(ctx);
                                    setState(() {
                                      _currentStep++;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'อัปเดตสถานะเป็น "${_statusSteps[_currentStep]['title']}" เรียบร้อยแล้ว'),
                                        backgroundColor: const Color(0xFFEB5757),
                                      ),
                                    );
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEB5757),
                              disabledBackgroundColor: Colors.grey.shade300,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: Text(
                              cooldownSec > 0
                                  ? 'รอ ($cooldownSec วิ)'
                                  : 'ยืนยันอัปเดต',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: cooldownSec > 0
                                    ? Colors.grey.shade600
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final LatLng incidentLocation = const LatLng(19.0284, 99.8962);
    final LatLng ambulanceLocation = const LatLng(19.0350, 99.8962);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // --- แผนที่ครึ่งบน ---
                    SizedBox(
                      height: 210,
                      child: Stack(
                        children: [
                          FlutterMap(
                            options: MapOptions(
                              initialCenter: ambulanceLocation,
                              initialZoom: 15.0,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.routealert.app',
                              ),
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: [ambulanceLocation, incidentLocation],
                                    strokeWidth: 4.5,
                                    color: const Color(0xFFEB5757),
                                  ),
                                ],
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: ambulanceLocation,
                                    width: 44,
                                    height: 44,
                                    child: const Center(
                                        child: Text('🚑', style: TextStyle(fontSize: 26))),
                                  ),
                                  Marker(
                                    point: incidentLocation,
                                    width: 36,
                                    height: 36,
                                    child: const Icon(
                                      Icons.location_on_rounded,
                                      color: Color(0xFFEB5757),
                                      size: 38,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Positioned(
                            top: 16,
                            left: 16,
                            child: CircleAvatar(
                              backgroundColor: Colors.white,
                              radius: 20,
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                    color: Colors.black87, size: 20),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // --- ป้าย Case ID ---
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEB5757),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEB5757).withOpacity(0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        widget.incidentData['id'] ?? 'Case #AVCB00021',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 📊 --- แถบ Visual Stepper แสดงความคืบหน้า 5 ขั้นตอน --- 📊
                    _buildStatusStepper(),

                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Divider(color: Colors.grey.shade300, thickness: 1.5),
                    ),

                    // --- รายละเอียดเคส ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            labelTH: 'สถานะปัจจุบัน',
                            labelEN: '(Current Status)',
                            value: _statusSteps[_currentStep]['title']!,
                            valueColor: const Color(0xFFEB5757),
                            isBold: true,
                          ),
                          _buildDetailRow(
                            labelTH: 'ประเภทอุบัติเหตุ',
                            labelEN: '(Type of incident)',
                            value: widget.incidentData['type'] ?? 'อุบัติเหตุทางรถยนต์',
                          ),
                          _buildDetailRow(
                            labelTH: 'ระดับความรุนแรง',
                            labelEN: '(Severity)',
                            value: widget.incidentData['severity'] ?? 'ปานกลาง (Medium)',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // --- ส่วนถ่ายรูปภาพหน้างาน ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'รูปภาพหน้างาน',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    '(Image - For ER Staff)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFEB5757),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              ElevatedButton.icon(
                                onPressed: _takePhoto,
                                icon: const Icon(Icons.camera_alt_rounded,
                                    size: 16, color: Colors.white),
                                label: const Text('ถ่ายรูป',
                                    style: TextStyle(color: Colors.white, fontSize: 13)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFEB5757),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _photoList.isEmpty
                              ? Container(
                                  height: 80,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'ยังไม่มีรูปภาพหน้างาน',
                                      style: TextStyle(
                                          color: Colors.grey.shade500, fontSize: 12),
                                    ),
                                  ),
                                )
                              : SizedBox(
                                  height: 80,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: _photoList.length,
                                    itemBuilder: (ctx, index) {
                                      return Container(
                                        margin: const EdgeInsets.only(right: 10),
                                        width: 110,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          image: DecorationImage(
                                            image: NetworkImage(_photoList[index]),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 🔘 --- ปุ่มเปลี่ยนสถานะขั้นตอนถัดไป --- 🔘
                    if (_currentStep < _statusSteps.length - 1)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _showNextStatusConfirmDialog,
                            icon: const Icon(Icons.arrow_forward_rounded,
                                color: Colors.white),
                            label: Text(
                              'ถัดไป: ${_statusSteps[_currentStep + 1]['title']}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEB5757),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                          ),
                        ),
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

  // --- แถบ Visual Stepper แสดงความคืบหน้า ---
  Widget _buildStatusStepper() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_statusSteps.length, (index) {
          bool isPassed = index <= _currentStep;
          bool isCurrent = index == _currentStep;

          return Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isPassed ? const Color(0xFFEB5757) : Colors.grey.shade200,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isCurrent ? Colors.redAccent.shade700 : Colors.transparent,
                    width: isCurrent ? 2.5 : 0,
                  ),
                ),
                child: Center(
                  child: isPassed
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                ),
              ),
              if (index < _statusSteps.length - 1)
                Container(
                  width: 35,
                  height: 3,
                  color: index < _currentStep
                      ? const Color(0xFFEB5757)
                      : Colors.grey.shade300,
                ),
            ],
          );
        }),
      ),
    );
  }

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

  Widget _buildDetailRow({
    required String labelTH,
    required String labelEN,
    required String value,
    Color valueColor = Colors.black87,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      labelTH,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      labelEN,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFEB5757),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Text(':', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                    color: valueColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Divider(color: Colors.grey.shade200, thickness: 1),
        ],
      ),
    );
  }
}