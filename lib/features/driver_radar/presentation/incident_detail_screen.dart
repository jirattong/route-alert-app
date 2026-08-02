import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'driver_home_screen.dart';
import 'incident_list_screen.dart';
import 'driver_settings_screen.dart';
import 'driver_profile_screen.dart';

class IncidentDetailScreen extends StatelessWidget {
  final Map<String, dynamic> incidentData;

  const IncidentDetailScreen({
    super.key,
    required this.incidentData,
  });

  @override
  Widget build(BuildContext context) {
    // พิกัดจำลองจุดเกิดเหตุ และ ตำแหน่งรถพยาบาล
    final LatLng incidentLocation = const LatLng(19.0284, 99.8962);
    final LatLng ambulanceLocation = const LatLng(19.0350, 99.8962);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // --- 1. Header Bar ด้านบนตาม Figma ---
            _buildHeader(),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // --- 2. ส่วนแผนที่ครึ่งบนพร้อมปุ่มย้อนกลับ < ---
                    SizedBox(
                      height: 240,
                      child: Stack(
                        children: [
                          FlutterMap(
                            options: MapOptions(
                              initialCenter: ambulanceLocation,
                              initialZoom: 15.0,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.routealert.app',
                              ),
                              // เส้นทางเดินรถ (Polyline)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: [ambulanceLocation, incidentLocation],
                                    strokeWidth: 4.0,
                                    color: const Color(0xFFEB5757),
                                  ),
                                ],
                              ),
                              // หมุดแสดงตำแหน่ง
                              MarkerLayer(
                                markers: [
                                  // หมุดรถพยาบาล
                                  Marker(
                                    point: ambulanceLocation,
                                    width: 44,
                                    height: 44,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 6)
                                        ],
                                      ),
                                      child: const Center(
                                          child: Text('🚑',
                                              style: TextStyle(fontSize: 22))),
                                    ),
                                  ),
                                  // หมุดจุดเกิดเหตุ
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

                          // ปุ่มย้อนกลับ < ย้อนไปหน้าก่อนหน้า
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

                    const SizedBox(height: 20),

                    // --- 3. ป้าย Case ID สีฟ้าทรงแคปซูลตาม Figma ---
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8BB7F0),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8BB7F0).withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        incidentData['id'] ?? 'Case #AVCB00021',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Divider(color: Colors.grey.shade400, thickness: 1.5),
                    ),
                    const SizedBox(height: 12),

                    // --- 4. ตารางแสดงรายละเอียดเคสตาม Figma ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            labelTH: 'สถานะ',
                            labelEN: '(Status)',
                            value: incidentData['status'] ?? 'กำลังเดินทางรับเคส',
                            valueColor: incidentData['statusColor'] ??
                                const Color(0xFF5B9EE1),
                          ),
                          _buildDetailRow(
                            labelTH: 'ประเภทอุบัติเหตุ',
                            labelEN: '(Type of incident)',
                            value: incidentData['type'] ?? 'อุบัติเหตุทางรถยนต์',
                          ),
                          _buildDetailRow(
                            labelTH: 'ระดับความรุนแรง',
                            labelEN: '(Severity)',
                            value: 'ปานกลาง (Medium)',
                          ),
                          // ระบุเป้าหมายเวลาคาดการณ์ชัดเจน
                          _buildDetailRow(
                            labelTH: 'คาดว่าจะถึงจุดเกิดเหตุ',
                            labelEN: '(Estimated Time of Arrival)',
                            value: '4 นาที',
                            valueColor: const Color(0xFFEB5757),
                            isBold: true,
                          ),
                        ],
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

      // --- 5. Bottom Navigation Bar ---
      bottomNavigationBar: _buildBottomNavigationBar(context),
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

  // --- Helper: แถวข้อมูลหัวข้อและรายละเอียดตาม Figma ---
  Widget _buildDetailRow({
    required String labelTH,
    required String labelEN,
    required String value,
    Color valueColor = Colors.black87,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
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
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      labelEN,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5B9EE1),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                ':',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                    color: valueColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: Colors.grey.shade300, thickness: 1),
        ],
      ),
    );
  }

  // --- Bottom Navigation Bar ---
  Widget _buildBottomNavigationBar(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: BottomNavigationBar(
        currentIndex: 1,
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const DriverHomeScreen()));
          } else if (index == 1) {
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const IncidentListScreen()));
          } else if (index == 2) {
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const DriverSettingsScreen()));
          } else if (index == 3) {
            Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const DriverProfileScreen()));
          }
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF2C3E50),
        unselectedItemColor: Colors.grey.shade400,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined, size: 28), label: 'Map'),
          BottomNavigationBarItem(
              icon: Icon(Icons.airport_shuttle_rounded, size: 28),
              label: 'Ambulance'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined, size: 28), label: 'Settings'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded, size: 28),
              label: 'Profile'),
        ],
      ),
    );
  }
}