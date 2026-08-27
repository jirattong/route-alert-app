import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/services/emergency_mqtt_service.dart';
import '../../../core/services/location_service.dart';

class AmbulanceHomeScreen extends StatefulWidget {
  const AmbulanceHomeScreen({super.key});

  @override
  State<AmbulanceHomeScreen> createState() => _AmbulanceHomeScreenState();
}

class _AmbulanceHomeScreenState extends State<AmbulanceHomeScreen> {
  // สถานะเปิด/ปิดส่งสัญญาณเตือนฉุกเฉิน
  bool _isNotificationAlert = false;

  // ข้อมูลพิกัดรถพยาบาล และจุดเกิดเหตุ
  LatLng _ambulanceLocation = const LatLng(19.0350, 99.8962);
  final LatLng _incidentLocation = const LatLng(19.0284, 99.8962);

  StreamSubscription<LatLng>? _locationSub;
  Timer? _broadcastTimer;

  @override
  void initState() {
    super.initState();
    _initAmbulanceTracking();
  }

  void _initAmbulanceTracking() async {
    await EmergencyMqttService().initialize();
    final pos = await LocationService.getCurrentLocation();
    if (pos != null && mounted) {
      setState(() => _ambulanceLocation = pos);
    }

    _locationSub = LocationService.getLiveLocationStream().listen((newPos) {
      if (!mounted) return;
      setState(() => _ambulanceLocation = newPos);
      if (_isNotificationAlert) {
        _broadcastCurrentLocation();
      }
    });

    // Heartbeat broadcast every 3s when alert is active
    _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_isNotificationAlert && mounted) {
        _broadcastCurrentLocation();
      }
    });
  }

  void _broadcastCurrentLocation() {
    EmergencyMqttService().broadcastAmbulanceLocation(
      EmergencyVehicleData(
        id: 'AMB-1669-01',
        callSign: 'กู้ชีพนครพิงค์ 01',
        latitude: _ambulanceLocation.latitude,
        longitude: _ambulanceLocation.longitude,
        speed: 65.0,
        emergencyType: 'ผู้ป่วยวิกฤตฉุกเฉิน (Red Code)',
        sirenActive: _isNotificationAlert,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _broadcastTimer?.cancel();
    super.dispose();
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

            // --- 2. พื้นที่แผนที่ interactive และแผงควบคุมด้านล่าง ---
            Expanded(
              child: Stack(
                children: [
                  _buildMapView(),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: _buildAmbulanceStatusCard(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      // ❌ ถอด bottomNavigationBar ออกเพื่อใช้ Shell ร่วมกันใน AmbulanceMainScreen
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

  // --- แผนที่แสดงพิกัดรถพยาบาลและเส้นทาง ---
  Widget _buildMapView() {
    return FlutterMap(
      options: MapOptions(
        initialCenter: _ambulanceLocation,
        initialZoom: 15.2,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.routealert.app',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: [_ambulanceLocation, _incidentLocation],
              strokeWidth: 4.5,
              color: const Color(0xFFEB5757),
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: _ambulanceLocation,
              width: 48,
              height: 48,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFEB5757), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEB5757).withValues(alpha: 0.4),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('🚑', style: TextStyle(fontSize: 24)),
                ),
              ),
            ),
            Marker(
              point: _incidentLocation,
              width: 38,
              height: 38,
              child: const Icon(
                Icons.location_on_rounded,
                color: Color(0xFFEB5757),
                size: 40,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- การ์ดแสดงสถานะของรถ Ambulance ---
  Widget _buildAmbulanceStatusCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEB5757), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEB5757).withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusRow('สถานะ', '(Status)', 'กำลังรับเคส'),
          const SizedBox(height: 8),
          _buildStatusRow('ระยะห่าง', '(Distance)', '1.67 KM'),
          const SizedBox(height: 8),
          _buildStatusRow('เวลาที่คาดว่าจะมาถึง', '(ETA)', '2 นาที'),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ส่งสัญญาณเตือน',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    '(Notification alert)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFEB5757),
                    ),
                  ),
                ],
              ),
              Transform.scale(
                scale: 1.0,
                child: Switch(
                  value: _isNotificationAlert,
                  activeThumbColor: Colors.white,
                  activeTrackColor: const Color(0xFFEB5757),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: Colors.grey.shade400,
                  onChanged: (value) {
                    setState(() => _isNotificationAlert = value);
                    if (value) {
                      _broadcastCurrentLocation();
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          value
                              ? '🔴 เริ่มบรอดแคสต์สัญญาณเตือนไปยังผู้ใช้รอบข้างแล้ว'
                              : '⚪ ปิดการส่งสัญญาณเตือน',
                        ),
                        backgroundColor:
                            value ? const Color(0xFFEB5757) : Colors.black87,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ),
            ],
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
                  color: Color(0xFFEB5757),
                ),
              ),
            ],
          ),
        ),
        const Text(
          ':',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
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