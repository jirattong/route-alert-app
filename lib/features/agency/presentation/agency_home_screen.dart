import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/services/emergency_mqtt_service.dart';

class AgencyHomeScreen extends StatefulWidget {
  const AgencyHomeScreen({super.key});

  @override
  State<AgencyHomeScreen> createState() => _AgencyHomeScreenState();
}

class _AgencyHomeScreenState extends State<AgencyHomeScreen> {
  final MapController _mapController = MapController();
  final LatLng _agencyLocation = const LatLng(19.0284, 99.8962);

  // Active Ambulances List (with live MQTT sync)
  final List<Map<String, dynamic>> _activeAmbulances = [
    {
      'id': 'AMB-1669-01',
      'plate': 'กขค123 (เชียงใหม่)',
      'callSign': 'หน่วยกู้ชีพนครพิงค์ 01',
      'location': const LatLng(19.0400, 99.8962),
      'status': 'กำลังนำส่งผู้ป่วย (In Transit)',
      'distance': '1.67 KM',
      'eta': '2 นาที',
      'speed': '65 km/h',
      'emergencyType': 'ผู้ป่วยวิกฤตฉุกเฉิน (Red Code)',
      'isPrepared': false,
    },
    {
      'id': 'AMB-1669-02',
      'plate': 'ผก9988 (เชียงใหม่)',
      'callSign': 'หน่วยกู้ชีพมหาราช 02',
      'location': const LatLng(19.0320, 99.8850),
      'status': 'กำลังรับเคสที่เกิดเหตุ',
      'distance': '3.20 KM',
      'eta': '5 นาที',
      'speed': '45 km/h',
      'emergencyType': 'อุบัติเหตุจราจร (Yellow Code)',
      'isPrepared': true,
    }
  ];

  Map<String, dynamic>? _selectedAmbulance;
  StreamSubscription<EmergencyVehicleData>? _mqttSubscription;
  bool _isErAvailable = true;

  @override
  void initState() {
    super.initState();
    _initLiveMqttFleet();
  }

  void _initLiveMqttFleet() async {
    await EmergencyMqttService().initialize();
    _mqttSubscription = EmergencyMqttService().emergencyStream.listen((data) {
      if (!mounted) return;

      final distanceMeters = EmergencyMqttService.calculateDistanceInMeters(
        _agencyLocation,
        LatLng(data.latitude, data.longitude),
      );

      final distanceKm = (distanceMeters / 1000).toStringAsFixed(2);
      final estimatedMinutes = (distanceMeters / 600).clamp(1, 60).round();

      setState(() {
        final existingIndex =
            _activeAmbulances.indexWhere((a) => a['id'] == data.id);

        final updatedData = {
          'id': data.id,
          'plate': data.callSign,
          'callSign': data.callSign,
          'location': LatLng(data.latitude, data.longitude),
          'status': data.sirenActive ? 'เปิดสัญญาณไซเรนฉุกเฉิน' : 'ปฏิบัติการปกติ',
          'distance': '$distanceKm KM',
          'eta': '$estimatedMinutes นาที',
          'speed': '${data.speed.toStringAsFixed(0)} km/h',
          'emergencyType': data.emergencyType,
          'isPrepared': existingIndex != -1
              ? (_activeAmbulances[existingIndex]['isPrepared'] ?? false)
              : false,
        };

        if (existingIndex != -1) {
          _activeAmbulances[existingIndex] = updatedData;
        } else {
          _activeAmbulances.add(updatedData);
        }

        if (_selectedAmbulance?['id'] == data.id) {
          _selectedAmbulance = updatedData;
        }
      });
    });
  }

  @override
  void dispose() {
    _mqttSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFleetStatsBar(),
            Expanded(
              child: Stack(
                children: [
                  _buildMapView(),
                  Positioned(
                    top: 14,
                    left: 16,
                    right: 16,
                    child: _buildTopAlertBadge(),
                  ),
                  if (_selectedAmbulance != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF00A896).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_hospital_rounded,
                    size: 20, color: Color(0xFF00A896)),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RouteAlert Agency Dispatch',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                  Text(
                    'ศูนย์สั่งการและเฝ้าระวัง 1669',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ],
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _isErAvailable = !_isErAvailable;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: _isErAvailable
                      ? const Color(0xFF00A896)
                      : Colors.redAccent.shade700,
                  content: Text(_isErAvailable
                      ? 'สถานะ ER: เปิดรับเคสฉุกเฉินปกติ (Available)'
                      : 'สถานะ ER: เตียงเต็ม แจ้งเตือนส่งต่อไป รพ.ใกล้เคียง (Divert)'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _isErAvailable
                    ? const Color(0xFF00A896).withValues(alpha: 0.15)
                    : Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isErAvailable ? Icons.check_circle : Icons.warning_rounded,
                    size: 14,
                    color: _isErAvailable
                        ? const Color(0xFF00A896)
                        : Colors.redAccent,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isErAvailable ? 'ER พร้อมรับ' : 'ER เต็ม (Divert)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _isErAvailable
                          ? const Color(0xFF00A896)
                          : Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFleetStatsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF0F172A),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('รถพยาบาลในระบบ', '${_activeAmbulances.length} คัน',
              Icons.directions_car_rounded, const Color(0xFF5B9EE1)),
          Container(width: 1, height: 26, color: Colors.white12),
          _buildStatItem('เคสวิกฤตสีแดง', '1 เคส',
              Icons.warning_amber_rounded, Colors.redAccent),
          Container(width: 1, height: 26, color: Colors.white12),
          _buildStatItem('เวลาเฉลี่ย ETA', '3.5 นาที', Icons.timer_rounded,
              const Color(0xFF00A896)),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color iconColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 10)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildTopAlertBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00A896), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.radar_rounded, color: Color(0xFF00A896), size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'เรดาร์สด: รพ.มหาราชนครเชียงใหม่ (รับสัญญาณ MQTT)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          Text(
            'Live',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.redAccent.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapView() {
    final ambulanceMarkers = _activeAmbulances.map((ambulance) {
      final isSelected = _selectedAmbulance?['id'] == ambulance['id'];

      return Marker(
        point: ambulance['location'],
        width: isSelected ? 58 : 46,
        height: isSelected ? 58 : 46,
        child: GestureDetector(
          onTap: () {
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
                color: isSelected
                    ? const Color(0xFF00A896)
                    : Colors.redAccent.shade400,
                width: isSelected ? 3 : 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isSelected
                          ? const Color(0xFF00A896)
                          : Colors.redAccent)
                      .withValues(alpha: 0.5),
                  blurRadius: isSelected ? 12 : 6,
                  spreadRadius: isSelected ? 3 : 1,
                ),
              ],
            ),
            child: Center(
              child: Text('🚑',
                  style: TextStyle(fontSize: isSelected ? 22 : 17)),
            ),
          ),
        ),
      );
    }).toList();

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _agencyLocation,
        initialZoom: 14.2,
        onTap: (_, __) => setState(() => _selectedAmbulance = null),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.routealert.app',
        ),
        if (_selectedAmbulance != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [_selectedAmbulance!['location'], _agencyLocation],
                strokeWidth: 4.0,
                color: const Color(0xFF00A896),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: _agencyLocation,
              width: 52,
              height: 52,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: const Color(0xFF00A896), width: 3),
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(0xFF00A896).withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.local_hospital_rounded,
                      color: Color(0xFF00A896), size: 28),
                ),
              ),
            ),
            ...ambulanceMarkers,
          ],
        ),
      ],
    );
  }

  Widget _buildSelectedAmbulanceCard() {
    final amb = _selectedAmbulance!;
    final bool isPrepared = amb['isPrepared'] ?? false;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF00A896), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    amb['callSign'] ?? amb['id'],
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'ทะเบียน: ${amb['plate']}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() => _selectedAmbulance = null),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoCol('ระยะทาง', amb['distance']),
                _buildInfoCol('เวลา ETA', amb['eta']),
                _buildInfoCol('ความเร็ว', amb['speed'] ?? '60 km/h'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      amb['isPrepared'] = !isPrepared;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: isPrepared
                            ? Colors.grey.shade800
                            : const Color(0xFF00A896),
                        content: Text(isPrepared
                            ? 'ยกเลิกการเตรียมเตียงห้องฉุกเฉิน'
                            : 'ยืนยันความพร้อมเตียงและทีมแพทย์ฉุกเฉินเรียบร้อย'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: Icon(
                    isPrepared
                        ? Icons.check_circle_rounded
                        : Icons.hotel_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  label: Text(
                    isPrepared
                        ? 'เตียงพร้อมแล้ว (Ready)'
                        : 'กดเพื่อยืนยันเตรียมเตียง ER',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPrepared
                        ? const Color(0xFF00A896)
                        : const Color(0xFF0F172A),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCol(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87)),
      ],
    );
  }
}