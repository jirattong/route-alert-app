import 'package:flutter/material.dart';
import 'ambulance_incident_detail_screen.dart';

class AmbulanceIncidentListScreen extends StatefulWidget {
  const AmbulanceIncidentListScreen({super.key});

  @override
  State<AmbulanceIncidentListScreen> createState() =>
      _AmbulanceIncidentListScreenState();
}

class _AmbulanceIncidentListScreenState
    extends State<AmbulanceIncidentListScreen> {
  // เขตปฏิบัติการจำลอง
  String _selectedDistrict = 'อ.เมืองเชียงใหม่';
  final List<String> _districts = [
    'ทั้งหมดในโซน',
    'อ.เมืองเชียงใหม่',
    'อ.ฝาง จ.เชียงใหม่',
    'อ.แม่ริม',
    'อ.หางดง',
  ];

  // รายการเคสเหตุการณ์ฉุกเฉินสำหรับรถพยาบาล
  final List<Map<String, dynamic>> _incidents = [
    {
      'id': 'Case #AVCB00021',
      'location': 'อ.ฝาง จ.เชียงใหม่',
      'district': 'อ.ฝาง จ.เชียงใหม่',
      'type': 'อุบัติเหตุทางรถยนต์',
      'severity': 'ปานกลาง (Medium)',
      'vehiclePlate': 'กขค123',
      'status': 'กำลังเดินทางไปรับเคส',
      'statusStep': 1, // 0: รอยืนยัน, 1: กำลังไปรับเคส, 2: ถึงจุดเกิดเหตุ, 3: กำลังไป รพ., 4: ถึง รพ.
      'isAccepted': true,
      'hasPolice': true,
      'hasAmbulance': true,
    },
    {
      'id': 'Case #SIXSEVEN67',
      'location': 'อ.ฝาง จ.เชียงใหม่',
      'district': 'อ.ฝาง จ.เชียงใหม่',
      'type': 'อุบัติเหตุทางรถยนต์',
      'severity': 'วิกฤต (Critical)',
      'vehiclePlate': 'ยังไม่มีรถรับหมาย',
      'status': 'กำลังรอยืนยัน',
      'statusStep': 0,
      'isAccepted': false,
      'hasPolice': true,
      'hasAmbulance': true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // --- 1. Header Bar ด้านบน ---
            _buildHeader(),

            // --- 2. ตัวเลือกเขตปฏิบัติการ/อำเภอ ---
            const SizedBox(height: 12),
            _buildAreaSelectorBar(),

            // --- 3. หัวข้อ "เหตุในบริเวณพื้นที่" ---
            const SizedBox(height: 16),
            Text(
              'เหตุในบริเวณพื้นที่',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),

            // --- 4. ลิสต์รายการเคสขอบสีแดงตาม Figma ---
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: _incidents.length,
                itemBuilder: (context, index) {
                  return _buildAmbulanceIncidentCard(_incidents[index]);
                },
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

  // --- ตัวเลือกเขตปฏิบัติการ ---
  Widget _buildAreaSelectorBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.my_location_rounded,
                  color: Color(0xFFEB5757), size: 20),
              const SizedBox(width: 6),
              Text(
                'เขตปฏิบัติการ:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFEB5757).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFEB5757), width: 1.2),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedDistrict,
                icon: const Icon(Icons.arrow_drop_down_rounded,
                    color: Color(0xFFEB5757), size: 24),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFEB5757),
                ),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() => _selectedDistrict = newValue);
                  }
                },
                items: _districts.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- การ์ดเคสขอบสีแดง ถอดแบบจาก Figma เป๊ะๆ ---
  Widget _buildAmbulanceIncidentCard(Map<String, dynamic> item) {
    bool isAccepted = item['isAccepted'] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEB5757), width: 1.8), // ขอบสีแดงตามรูป
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEB5757).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. สถานที่
              Text(
                item['location'],
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),

              // 2. เลข Case ID
              Text(
                item['id'],
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),

              // 3. ประเภทอุบัติเหตุ
              Text(
                item['type'],
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),

              // 4. เลขรถที่รับเคส
              Text(
                'เลขรถที่รับเคส : ${item['vehiclePlate']}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 10),

              // 5. สถานะ + ไอคอนรถพยาบาล/ตำรวจ
              Row(
                children: [
                  Text(
                    item['status'],
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isAccepted
                          ? const Color(0xFFEB5757)
                          : Colors.redAccent.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (item['hasAmbulance'] == true)
                    const Text('🚑', style: TextStyle(fontSize: 18)),
                  if (item['hasPolice'] == true)
                    const Text('🚓', style: TextStyle(fontSize: 18)),
                ],
              ),

              const SizedBox(height: 16),

              // 6. ปุ่มกดรับเคส (ยืนยัน / ยืนยันเรียบร้อย)
              Center(
                child: SizedBox(
                  width: 170,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: isAccepted
                        ? null // ถ้ากดรับแล้ว ปุ่มจะกลายเป็นสีเทาจางตาม Figma
                        : () {
                            setState(() {
                              item['isAccepted'] = true;
                              item['status'] = 'กำลังเดินทางไปรับเคส';
                              item['vehiclePlate'] = 'กขค123 (รถของเรา)';
                            });

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('🔴 ยืนยันรับเคสเรียบร้อยแล้ว!'),
                                backgroundColor: Color(0xFFEB5757),
                              ),
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEB5757),
                      disabledBackgroundColor: const Color(0xFFA3A3A3), // สีเทาปุ่มยืนยันเรียบร้อย
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      elevation: isAccepted ? 0 : 3,
                    ),
                    child: Text(
                      isAccepted ? 'ยืนยันเรียบร้อย' : 'ยืนยัน',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ปุ่มลูกศร > มุมขวาบน เพื่อกดเข้าดูหน้ารายละเอียดเคสฉุกเฉิน
          Positioned(
            right: 0,
            top: 20,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AmbulanceIncidentDetailScreen(incidentData: item),
                  ),
                );
              },
              child: const Icon(
                Icons.chevron_right_rounded,
                color: Colors.black54,
                size: 36,
              ),
            ),
          ),
        ],
      ),
    );
  }
}