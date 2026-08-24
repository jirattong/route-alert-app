import 'package:flutter/material.dart';
import 'agency_incident_detail_screen.dart';

class AgencyIncidentListScreen extends StatefulWidget {
  const AgencyIncidentListScreen({super.key});

  @override
  State<AgencyIncidentListScreen> createState() =>
      _AgencyIncidentListScreenState();
}

class _AgencyIncidentListScreenState extends State<AgencyIncidentListScreen> {
  // รายการเคสที่กำลังมุ่งหน้ามาที่โรงพยาบาล
  final List<Map<String, dynamic>> _incomingIncidents = [
    {
      'id': 'Case #SIXSEVEN67',
      'location': 'อ.ฝาง จ.เชียงใหม่',
      'type': 'อุบัติเหตุทางรถยนต์',
      'severity': 'วิกฤต (Critical)',
      'status': 'กำลังรอยืนยัน (ER)',
      'isErPrepared': false, // ยังไม่ได้เตรียมเตียง
      'eta': '8 นาที',
      'hasPolice': true,
      'hasAmbulance': true,
    },
    {
      'id': 'Case #AVCB00021',
      'location': 'อ.ฝาง จ.เชียงใหม่',
      'type': 'อุบัติเหตุทางรถยนต์',
      'severity': 'ปานกลาง (Medium)',
      'vehiclePlate': 'กขค123',
      'status': 'กำลังเดินทางส่งเคส',
      'isErPrepared': true, // เตรียมเตียงเรียบร้อย
      'eta': '4 นาที',
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
            _buildHeader(),
            const SizedBox(height: 16),
            
            Text(
              'เคสที่กำลังมุ่งหน้ามา (Incoming ER)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),

            // ลิสต์รายการการ์ด
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                itemCount: _incomingIncidents.length,
                itemBuilder: (context, index) {
                  return _buildAgencyIncidentCard(_incomingIncidents[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- การ์ดขอบสีเขียวแบบ Figma ---
  Widget _buildAgencyIncidentCard(Map<String, dynamic> item) {
    bool isPrepared = item['isErPrepared'] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF69F0AE), width: 2), // ขอบสีเขียวสว่าง
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF69F0AE).withValues(alpha: 0.15),
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
              Text(
                item['location'],
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 2),
              Text(
                item['id'],
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 4),
              Text(
                item['type'],
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87),
              ),
              const SizedBox(height: 4),
              if (item['vehiclePlate'] != null)
                Text(
                  'เลขรถรับเคส : ${item['vehiclePlate']}',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Text(
                    item['status'],
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32), // ตัวหนังสือเขียวเข้ม
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (item['hasAmbulance'] == true) const Text('🚑', style: TextStyle(fontSize: 18)),
                  if (item['hasPolice'] == true) const Text('🚓', style: TextStyle(fontSize: 18)),
                ],
              ),
              const SizedBox(height: 16),

              // ปุ่มยืนยันเตรียมเตียง ER
              Center(
                child: SizedBox(
                  width: 170,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: isPrepared
                        ? null
                        : () {
                            setState(() {
                              item['isErPrepared'] = true;
                              item['status'] = 'เตรียม ER เรียบร้อย';
                            });
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF69F0AE), // สีเขียวสว่างตาม Figma
                      disabledBackgroundColor: Colors.grey.shade400, // สีเทาเมื่อกดแล้ว
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      elevation: isPrepared ? 0 : 3,
                    ),
                    child: Text(
                      isPrepared ? 'ยืนยันเรียบร้อย' : 'ยืนยันเตียง ER',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isPrepared ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ปุ่มลูกศรเข้าดูรายละเอียดเคส (พร้อมรูปถ่าย)
          Positioned(
            right: 0,
            top: 20,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AgencyIncidentDetailScreen(incidentData: item),
                  ),
                );
              },
              child: const Icon(Icons.chevron_right_rounded, color: Colors.black54, size: 36),
            ),
          ),
        ],
      ),
    );
  }

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
}