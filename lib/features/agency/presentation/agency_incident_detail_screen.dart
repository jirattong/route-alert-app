import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class AgencyIncidentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> incidentData;

  const AgencyIncidentDetailScreen({
    super.key,
    required this.incidentData,
  });

  @override
  State<AgencyIncidentDetailScreen> createState() =>
      _AgencyIncidentDetailScreenState();
}

class _AgencyIncidentDetailScreenState
    extends State<AgencyIncidentDetailScreen> {
  // ภาพจำลองที่ได้รับมาจากเจ้าหน้าที่รถพยาบาล (ตาม Figma ของคุณ)
  final List<String> _receivedPhotos = [
    'https://i.pravatar.cc/300?img=1', // ใช้ placeholder คนจำลองแทน
    'https://i.pravatar.cc/300?img=5',
  ];

  @override
  Widget build(BuildContext context) {
    const LatLng hospitalLocation = LatLng(19.0284, 99.8962);
    const LatLng ambulanceLocation = LatLng(19.0350, 99.8962);
    bool isPrepared = widget.incidentData['isErPrepared'] ?? false;

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
                    // --- 1. แผนที่ครึ่งบน ---
                    SizedBox(
                      height: 200,
                      child: Stack(
                        children: [
                          FlutterMap(
                            options: const MapOptions(
                              initialCenter: ambulanceLocation,
                              initialZoom: 15.0,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              ),
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: [ambulanceLocation, hospitalLocation],
                                    strokeWidth: 4.5,
                                    color: const Color(0xFF69F0AE), // เส้นทางสีเขียว
                                  ),
                                ],
                              ),
                              const MarkerLayer(
                                markers: [
                                  Marker(
                                    point: ambulanceLocation,
                                    width: 44,
                                    height: 44,
                                    child: Center(child: Text('🚑', style: TextStyle(fontSize: 26))),
                                  ),
                                  Marker(
                                    point: hospitalLocation,
                                    width: 44,
                                    height: 44,
                                    child: Center(
                                      child: Icon(Icons.local_hospital_rounded, color: Color(0xFF2E7D32), size: 38),
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
                                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87, size: 20),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // --- 2. ป้าย Case ID ทรงแคปซูลสีเขียวสว่างตาม Figma ---
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF69F0AE),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF69F0AE).withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        widget.incidentData['id'] ?? 'Case #AVCB00021',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87, // ตัวหนังสือดำบนพื้นเขียวสว่าง
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Divider(color: Colors.grey.shade400, thickness: 1.5),
                    ),
                    const SizedBox(height: 12),

                    // --- 3. รายละเอียดเคส (ข้อความย่อยสีเขียวเข้ม) ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            labelTH: 'สถานะ',
                            labelEN: '(Status)',
                            value: widget.incidentData['status'] ?? 'กำลังเดินทางส่งเคส',
                            valueColor: const Color(0xFF2E7D32),
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
                            value: widget.incidentData['severity'] ?? 'ปานกลาง',
                          ),
                          _buildDetailRow(
                            labelTH: 'ความว่าจะถึงที่หมาย', // ตามคำพิมพ์ในรูป Figma
                            labelEN: '(Estimated Time of Arrival)',
                            value: widget.incidentData['eta'] ?? '4 นาที',
                          ),
                          _buildDetailRow(
                            labelTH: 'หมายเลขที่รับหมาย',
                            labelEN: '(Car Detail)',
                            value: widget.incidentData['vehiclePlate'] ?? 'กขค123',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // --- 4. โซนแสดงรูปภาพ (เฉพาะหน่วยงาน/แพทย์ที่เห็นได้) ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'รูปภาพ (รูปประกอบไม่มีส่วนเกี่ยวข้อง)',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                          const Text(
                            '(Image)',
                            style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          
                          // แสดงรูปภาพ 2 รูปแนวนอนแบบใน Figma
                          Row(
                            children: _receivedPhotos.map((photoUrl) {
                              return Expanded(
                                child: Container(
                                  height: 180,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    image: DecorationImage(
                                      image: NetworkImage(photoUrl),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // --- 5. ปุ่มยืนยัน (สีเขียวสว่างตาม Figma) ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: isPrepared
                              ? null
                              : () {
                                  setState(() {
                                    widget.incidentData['isErPrepared'] = true;
                                    widget.incidentData['status'] = 'เตรียม ER เรียบร้อย';
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('✅ ยืนยันการเตรียมเตียงห้องฉุกเฉินแล้ว'),
                                      backgroundColor: Color(0xFF2E7D32),
                                    ),
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF69F0AE),
                            disabledBackgroundColor: Colors.grey.shade400,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            elevation: isPrepared ? 0 : 2,
                          ),
                          child: Text(
                            isPrepared ? 'ยืนยันรับเคสเรียบร้อย' : 'ยืนยัน',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isPrepared ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
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
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    Text(
                      labelEN,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600),
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
                  style: TextStyle(fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: valueColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Divider(color: Colors.grey.shade300, thickness: 1),
        ],
      ),
    );
  }
}