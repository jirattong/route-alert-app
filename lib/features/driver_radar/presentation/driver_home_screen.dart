import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_settings.dart';
import 'sos_report_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  int _currentSpeed = 67;

  // พิกัดผู้ใช้ (หน้า ม.พะเยา)
  final LatLng _userLocation = const LatLng(19.0284, 99.8962);

  // พิกัดรถพยาบาลจำลอง
  LatLng _ambulanceLocation = const LatLng(19.0400, 99.8962);
  int _simStep = 0;

  // คำนวณระยะห่างระหว่างผู้ใช้กับรถพยาบาล (กิโลเมตร)
  double _calculateDistance() {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Kilometer, _userLocation, _ambulanceLocation);
  }

  // ฟังก์ชันจำลองรถพยาบาลวิ่งเข้าหาผู้ใช้
  void _simulateAmbulanceApproach() {
    setState(() {
      _simStep = (_simStep + 1) % 4;
      if (_simStep == 0) {
        // อยู่นอกวง (1.5 KM)
        _ambulanceLocation = const LatLng(19.0420, 99.8962);
      } else if (_simStep == 1) {
        // เข้าสู่วงนอก - สีฟ้า (1.0 KM)
        _ambulanceLocation = const LatLng(19.0370, 99.8962);
      } else if (_simStep == 2) {
        // เข้าสู่วงใน - สีแดง (0.4 KM / 400 M)
        _ambulanceLocation = const LatLng(19.0320, 99.8962);
      } else if (_simStep == 3) {
        // แซงผ่านไปแล้ว
        _ambulanceLocation = const LatLng(19.0230, 99.8962);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    double distanceKm = _calculateDistance();
    bool isInBlueZone = distanceKm <= AppSettings.detectionZone;
    bool isInRedZone = distanceKm <= AppSettings.alertDistance;

    return Scaffold(
      // เมื่ออยู่ในวงเตือนสีแดง สีพื้นหลังจะติดโทนแดงอ่อนๆ
      backgroundColor: isInRedZone ? const Color(0xFFFFC1C1) : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isInRedZone),

            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // --- 1. แผนที่ + วงกลม 2 ระยะ ---
                  _buildMapView(isInBlueZone, isInRedZone),

                  // --- 2. ฟิลเตอร์สีแดงทับแผนที่เมื่อเกิดเหตุฉุกเฉิน ---
                  if (isInRedZone)
                    IgnorePointer(
                      child: Container(
                        color: Colors.red.withOpacity(0.15),
                      ),
                    ),

                  // --- 3. ปุ่ม SOS ---
                  Positioned(
                    right: 20,
                    bottom: 110,
                    child: _buildSosButton(),
                  ),

                  // --- 4. แผง Speedometer & สวิตช์ Background ---
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildSpeedGauge(),
                        const SizedBox(width: 12),
                        Expanded(child: _buildBackgroundToggleCard()),
                      ],
                    ),
                  ),

                  // --- 5. ปุ่มจำลองรถพยาบาล (มุมขวาบน) ---
                  Positioned(
                    top: 16,
                    right: 16,
                    child: _buildSimulationButton(),
                  ),

                  // 🚨 --- 6. หน้าต่างแจ้งเตือนฉุกเฉินกลางจอ --- 🚨
                  if (isInRedZone)
                    _buildCenterEmergencyAlert(distanceKm),
                ],
              ),
            ),
          ],
        ),
      ),
      // ❌ ถอด bottomNavigationBar ออกเพื่อใช้ Shell ร่วมกันใน DriverMainScreen
    );
  }

  // --- Header Bar (ปรับสีพื้นตามสถานะฉุกเฉิน) ---
  Widget _buildHeader(bool isRed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isRed ? const Color(0xFFFFB3B3) : Colors.white,
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
                const Icon(Icons.airport_shuttle_outlined, size: 20, color: Color(0xFF2C3E50)),
                Positioned(top: 4, right: 4, child: Icon(Icons.wifi, size: 9, color: Colors.redAccent.shade700)),
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

  // --- แผนที่ + วงกลมเรดาร์ 2 สี ---
  Widget _buildMapView(bool showAmbulanceMarker, bool isRedZone) {
    return FlutterMap(
      options: MapOptions(
        initialCenter: _userLocation,
        initialZoom: 14.8,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.routealert.app',
        ),
        CircleLayer(
          circles: [
            // วงนอกสีฟ้า
            CircleMarker(
              point: _userLocation,
              radius: AppSettings.detectionZone * 1000,
              useRadiusInMeter: true,
              color: const Color(0xFF5B9EE1).withOpacity(0.12),
              borderColor: const Color(0xFF5B9EE1),
              borderStrokeWidth: 2.0,
            ),
            // วงในสีแดง
            CircleMarker(
              point: _userLocation,
              radius: AppSettings.alertDistance * 1000,
              useRadiusInMeter: true,
              color: const Color(0xFFEB5757).withOpacity(0.22),
              borderColor: const Color(0xFFEB5757),
              borderStrokeWidth: 2.5,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: _userLocation,
              width: 42,
              height: 42,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                ),
                child: const Icon(Icons.navigation_rounded, color: Color(0xFF5B9EE1), size: 28),
              ),
            ),
            if (showAmbulanceMarker)
              Marker(
                point: _ambulanceLocation,
                width: 48,
                height: 48,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red, width: 2),
                    boxShadow: const [BoxShadow(color: Colors.redAccent, blurRadius: 8)],
                  ),
                  child: const Center(
                    child: Text('🚑', style: TextStyle(fontSize: 24)),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // 🚨 --- การ์ดเตือนภัยกลางจอ --- 🚨
  Widget _buildCenterEmergencyAlert(double distanceKm) {
    int distanceMeter = (distanceKm * 1000).round();

    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.82,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0xFFEB5757), width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.redAccent.withOpacity(0.35),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_rounded,
              size: 88,
              color: Color(0xFFFFB800),
            ),
            const SizedBox(height: 12),
            const Text(
              'แจ้งเตือน',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'มีรถพยาบาล',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'ระยะ $distanceMeter M',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- ปุ่มทดสอบการจำลอง ---
  Widget _buildSimulationButton() {
    return FloatingActionButton.extended(
      heroTag: 'simBtnHome',
      onPressed: _simulateAmbulanceApproach,
      backgroundColor: Colors.white,
      elevation: 4,
      icon: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF5B9EE1)),
      label: Text(
        _simStep == 0
            ? 'ทดสอบ: รถเข้าวงฟ้า'
            : _simStep == 1
                ? 'ทดสอบ: รถเข้าวงแดง (เตือน!)'
                : _simStep == 2
                    ? 'ทดสอบ: รถแซงผ่าน'
                    : 'รีเซ็ต',
        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildSpeedGauge() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF5B9EE1), width: 3),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$_currentSpeed', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF5B9EE1), height: 1.0)),
          const SizedBox(height: 2),
          const Text('KM/H', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF5B9EE1))),
        ],
      ),
    );
  }

  Widget _buildBackgroundToggleCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ทำงานเบื้องหลัง', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
              Text('(Background)', style: TextStyle(fontSize: 12, color: Color(0xFF5B9EE1), fontWeight: FontWeight.w600)),
            ],
          ),
          Transform.scale(
            scale: 0.9,
            child: Switch(
              value: AppSettings.isBackgroundMode,
              activeColor: Colors.white,
              activeTrackColor: const Color(0xFF5B9EE1),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: Colors.grey.shade300,
              onChanged: (value) {
                setState(() => AppSettings.isBackgroundMode = value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSosButton() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: const Color(0xFFEB5757).withOpacity(0.45), blurRadius: 12, spreadRadius: 2, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const SosReportScreen()));
          },
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFEB5757), width: 3),
            ),
            child: const Center(
              child: Text('SOS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFEB5757))),
            ),
          ),
        ),
      ),
    );
  }
}