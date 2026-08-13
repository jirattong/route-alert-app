import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class AgencyHomeScreen extends StatefulWidget {
  const AgencyHomeScreen({super.key});

  @override
  State<AgencyHomeScreen> createState() => _AgencyHomeScreenState();
}

class _AgencyHomeScreenState extends State<AgencyHomeScreen> {
  // พิกัดประจำฐานของหน่วยงาน (โรงพยาบาล)
  final LatLng _agencyLocation = const LatLng(19.0284, 99.8962);

  // จำลองข้อมูลรถพยาบาลที่กำลังมุ่งหน้ามา (อาจมีหลายคัน)
  final List<Map<String, dynamic>> _activeAmbulances = [
    {
      'id': 'Case #ABC2020207',
      'plate': 'กขค123',
      'location': const LatLng(19.0400, 99.8962),
      'status': 'กำลังรับเคส',
      'distance': '1.67 KM',
      'eta': '2 นาที',
      'isPrepared': false, // สถานะว่า รพ. เตรียมเตียงหรือยัง
    },
    {
      'id': 'Case #XYZ998877',
      'plate': 'ผก9988',
      'location': const LatLng(19.0320, 99.8850),
      'status': 'กำลังส่ง รพ.',
      'distance': '3.20 KM',
      'eta': '5 นาที',
      'isPrepared': true,
    }
  ];

  // เก็บข้อมูลรถพยาบาลที่ถูกกดเลือก (ถ้าเป็น null คือไม่ได้กดเลือกคันไหน)
  Map<String, dynamic>? _selectedAmbulance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // --- 1. Header Bar ด้านบน ---
            _buildHeader(),

            // --- 2. พื้นที่แผนที่และแดชบอร์ดเฝ้าระวัง ---
            Expanded(
              child: Stack(
                children: [
                  // แผนที่
                  _buildMapView(),

                  // ป้ายกำกับด้านบนแผนที่
                  Positioned(
                    top: 16,
                    left: 20,
                    right: 20,
                    child: _buildTopAlertBadge(),
                  ),

                  // 🚨 แผงข้อมูลรถพยาบาล (จะแสดงก็ต่อเมื่อมีการกดหมุดรูปรถ)
                  if (_selectedAmbulance != null)
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 20,
                      child: _buildSelectedAmbulanceCard(),
                    ),
                ],
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

  // --- ป้ายกำกับด้านบนแผนที่ (Top Badge) ---
  Widget _buildTopAlertBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2E7D32), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_hospital_rounded, color: Color(0xFF2E7D32), size: 20),
          const SizedBox(width: 8),
          Text(
            'เรดาร์เฝ้าระวัง: รพ.มหาราชนครเชียงใหม่',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  // --- แผนที่ (Interactive Map) ---
  Widget _buildMapView() {
    // สร้าง Marker สำหรับรถพยาบาลทุกคันที่มีในระบบ
    List<Marker> ambulanceMarkers = _activeAmbulances.map((ambulance) {
      bool isSelected = _selectedAmbulance?['id'] == ambulance['id'];
      
      return Marker(
        point: ambulance['location'],
        width: isSelected ? 56 : 44, // ถ้ารถคันไหนถูกกด ให้หมุดใหญ่ขึ้นนิดนึง
        height: isSelected ? 56 : 44,
        child: GestureDetector(
          onTap: () {
            // เมื่อกดที่รูปรถ ให้อัปเดตข้อมูลมาแสดงที่การ์ด
            setState(() {
              _selectedAmbulance = ambulance;
            });
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? const Color(0xFF69F0AE) : const Color(0xFFEB5757), 
                width: isSelected ? 3 : 2,
              ),
              boxShadow: [
                if (isSelected)
                  BoxShadow(
                    color: const Color(0xFF69F0AE).withOpacity(0.6),
                    blurRadius: 12,
                  ),
              ],
            ),
            child: Center(
              child: Text('🚑', style: TextStyle(fontSize: isSelected ? 24 : 18)),
            ),
          ),
        ),
      );
    }).toList();

    return FlutterMap(
      options: MapOptions(
        initialCenter: _agencyLocation,
        initialZoom: 14.5,
        onTap: (tapPosition, point) {
          // ถ้ากดพื้นที่ว่างบนแผนที่ ให้ซ่อนการ์ดข้อมูล
          setState(() {
            _selectedAmbulance = null;
          });
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.routealert.app',
        ),

        // เส้นทางรถ (วาดเฉพาะคันที่กดเลือก)
        if (_selectedAmbulance != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [_selectedAmbulance!['location'], _agencyLocation],
                strokeWidth: 4.5,
                color: const Color(0xFF69F0AE), // เส้นนำทางสีเขียวสว่าง
              ),
            ],
          ),

        MarkerLayer(
          markers: [
            // 🏥 หมุดของโรงพยาบาล (กดไม่ได้ เป็น Base Station)
            Marker(
              point: _agencyLocation,
              width: 56,
              height: 56,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF2E7D32), width: 2.5),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF2E7D32).withOpacity(0.4), blurRadius: 10),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.local_hospital_rounded, color: Color(0xFF2E7D32), size: 30),
                ),
              ),
            ),
            
            // นำ Marker รถพยาบาลทั้งหมดมาใส่
            ...ambulanceMarkers,
          ],
        ),
      ],
    );
  }

  // --- การ์ดข้อมูลเมื่อกดที่หมุดรถ (ดีไซน์ขอบสีเขียวอ่อนตาม Figma) ---
  Widget _buildSelectedAmbulanceCard() {
    bool isPrepared = _selectedAmbulance!['isPrepared'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF69F0AE), width: 2.5), // ขอบสีเขียวสว่างแบบ Figma
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF69F0AE).withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // หัว Case ID พร้อมปุ่มปิด X
          Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.center,
                child: Text(
                  _selectedAmbulance!['id'],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: () => setState(() => _selectedAmbulance = null),
                  child: Icon(Icons.close_rounded, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // ข้อมูลสถานะต่างๆ
          _buildStatusRow('สถานะ', '(Status)', _selectedAmbulance!['status']),
          const SizedBox(height: 8),
          _buildStatusRow('ระยะห่าง', '(Distance)', _selectedAmbulance!['distance']),
          const SizedBox(height: 8),
          _buildStatusRow('เวลาที่คาดว่าจะมาถึง', '(ETA)', _selectedAmbulance!['eta']),
          const SizedBox(height: 16),

          // ปุ่มรับทราบ (ER Prepare)
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              onPressed: isPrepared
                  ? null
                  : () {
                      setState(() {
                        _selectedAmbulance!['isPrepared'] = true;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ แจ้งเตือนไปยังรถพยาบาล: "ห้องฉุกเฉินเตรียมพร้อมแล้ว"'),
                          backgroundColor: Color(0xFF2E7D32),
                        ),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: isPrepared ? 0 : 2,
              ),
              child: Text(
                isPrepared ? 'ER เตรียมพร้อมรับผู้ป่วยแล้ว' : 'กดรับทราบและเตรียมเตียง (ER)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isPrepared ? Colors.grey.shade600 : Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String labelTH, String labelEN, String value) {
    return Row(
      children: [
        SizedBox(
          width: 170,
          child: Row(
            children: [
              Text(
                labelTH,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                labelEN,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2E7D32), 
                ),
              ),
            ],
          ),
        ),
        const Text(':', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}