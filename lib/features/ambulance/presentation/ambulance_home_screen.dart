import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/incident_report.dart';
import '../../../core/services/emergency_mqtt_service.dart';
import '../../../core/services/hospital_location_service.dart';
import '../../../core/services/incident_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/osrm_routing_service.dart';

class AmbulanceHomeScreen extends StatefulWidget {
  const AmbulanceHomeScreen({super.key});

  @override
  State<AmbulanceHomeScreen> createState() => _AmbulanceHomeScreenState();
}

class _AmbulanceHomeScreenState extends State<AmbulanceHomeScreen> {
  // สถานะเปิด/ปิดส่งสัญญาณเตือนฉุกเฉิน
  bool _isNotificationAlert = true;

  // ข้อมูลพิกัดรถพยาบาล
  LatLng _ambulanceLocation = const LatLng(19.0350, 99.8962);
  LatLng _incidentLocation = const LatLng(19.0284, 99.8962);
  late LatLng _hospitalLocation;

  // Active Assigned Incident
  IncidentReport? _activeIncident;

  List<LatLng> _routePoints = [];
  String _turnInstruction = 'มุ่งหน้าไปจุดเกิดเหตุ';
  double _distanceKm = 1.67;
  int _etaMinutes = 2;

  StreamSubscription<LatLng>? _locationSub;
  StreamSubscription<List<IncidentReport>>? _incidentSub;
  StreamSubscription<HospitalProfile>? _hospitalSub;
  Timer? _broadcastTimer;

  @override
  void initState() {
    super.initState();
    _hospitalLocation = HospitalLocationService().hospitalLocation;

    _initAmbulanceTracking();
    _initHospitalListener();
    _initIncidentListener();
  }

  void _initHospitalListener() {
    _hospitalSub = HospitalLocationService().profileStream.listen((profile) {
      if (!mounted) return;
      setState(() {
        _hospitalLocation = profile.location;
      });
      _updateRoute();
    });
  }

  void _initIncidentListener() async {
    await IncidentService().initialize();
    _incidentSub = IncidentService().incidentsStream.listen((list) {
      if (!mounted) return;
      // Find active incident assigned to this ambulance or in progress
      final assigned = list.firstWhere(
        (i) =>
            i.status != 'resolved' &&
            i.status != 'cancelled' &&
            (i.assignedAmbulanceId == 'AMB-1669-01' ||
                i.status == 'assigned' ||
                i.status == 'at_scene' ||
                i.status == 'transporting' ||
                i.status == 'approaching_er'),
        orElse: () => list.isNotEmpty &&
                list.first.status != 'resolved' &&
                list.first.status != 'cancelled'
            ? list.first
            : IncidentReport(
                id: 'Case #1669-LIVE',
                type: 'ผู้ป่วยวิกฤตฉุกเฉิน',
                severity: 'วิกฤต (Code Red)',
                description: 'รอข้อมูลจุดเกิดเหตุ',
                latitude: 19.0284,
                longitude: 99.8962,
                province: 'เชียงใหม่',
                address: 'อ.เมือง จ.เชียงใหม่',
                reporterName: 'ศูนย์สั่งการ 1669',
                reporterEmail: '',
                status: 'assigned',
                statusStep: 1,
                createdAt: DateTime.now(),
              ),
      );

      setState(() {
        _activeIncident = assigned;
        _incidentLocation = LatLng(assigned.latitude, assigned.longitude);
      });
      _updateRoute();
    });
  }

  void _initAmbulanceTracking() async {
    await EmergencyMqttService().initialize();
    final pos = await LocationService.getCurrentLocation();
    if (pos != null && mounted) {
      setState(() => _ambulanceLocation = pos);
    }
    await _updateRoute();

    _locationSub =
        LocationService.getLiveLocationStream().listen((newPos) async {
      if (!mounted) return;
      setState(() => _ambulanceLocation = newPos);
      await _updateRoute();
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

  Future<void> _updateRoute() async {
    // Stage 1: Heading to Incident Scene (step <= 2)
    // Stage 2: Transporting to Hospital (step >= 3)
    final int step = _activeIncident?.statusStep ?? 1;
    final LatLng destination =
        step >= 3 ? _hospitalLocation : _incidentLocation;

    final route = await OsrmRoutingService().getDrivingRoute(
      start: _ambulanceLocation,
      destination: destination,
    );
    if (!mounted) return;
    setState(() {
      _routePoints = route.points;
      _turnInstruction = route.nextTurnInstruction;
      _distanceKm = route.distanceMeters / 1000.0;
      _etaMinutes = (route.durationSeconds / 60.0).ceil();
    });

    // Auto trigger "Approaching Hospital" when step is 3 and distance <= 1.5 km
    if (step == 3 && _distanceKm <= 1.5 && _activeIncident != null) {
      IncidentService().reportAmbulanceApproachingHospital(_activeIncident!.id);
    }
  }

  void _broadcastCurrentLocation() {
    final int step = _activeIncident?.statusStep ?? 1;
    final destName = step >= 3
        ? 'โรงพยาบาลมหาราชนคร (ER)'
        : (_activeIncident?.address ?? 'จุดเกิดเหตุ');

    EmergencyMqttService().broadcastAmbulanceLocation(
      EmergencyVehicleData(
        id: 'AMB-1669-01',
        callSign: 'กู้ชีพนครพิงค์ 01',
        latitude: _ambulanceLocation.latitude,
        longitude: _ambulanceLocation.longitude,
        speed: 65.0,
        emergencyType:
            _activeIncident?.type ?? 'ผู้ป่วยวิกฤตฉุกเฉิน (Red Code)',
        sirenActive: _isNotificationAlert,
        timestamp: DateTime.now(),
        routePoints: _routePoints.isNotEmpty
            ? _routePoints
            : [
                _ambulanceLocation,
                step >= 3 ? _hospitalLocation : _incidentLocation
              ],
        turnIntent: _turnInstruction,
        destinationName: destName,
      ),
    );
  }

  // --- Modal สำหรับโทรรายงานสัญญาณชีพและอาการคนไข้สู่ ER ---
  void _showTeleReportDialog() {
    final bpCtrl = TextEditingController(
        text: _activeIncident?.vitalSigns ?? 'BP: 120/80, HR: 88, SpO2: 98%');
    final condCtrl = TextEditingController(
        text: _activeIncident?.patientCondition ??
            'ผู้ป่วยรู้สึกตัวดี สัญญาณชีพคงที่');
    final noteCtrl = TextEditingController(
        text: _activeIncident?.medicalNotes ??
            'ให้สารน้ำ IV และ On Oxygen Cannula 3 LPM');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.phone_in_talk_rounded,
                          color: Color(0xFF00A896), size: 24),
                      SizedBox(width: 8),
                      Text(
                        '📞 รายงานอาการคนไข้สู่ห้องฉุกเฉิน (ER)',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Text(
                'ข้อมูลจะแสดงขึ้นบนหน้าจอศูนย์สั่งการ รพ. แบบ Real-time',
                style: TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
              const SizedBox(height: 14),

              // Quick Vital Signs Preset Chips
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('🚨 วิกฤต (BP ต่ำ/SpO2 ตก)'),
                    backgroundColor: const Color(0xFFFEE2E2),
                    onPressed: () {
                      bpCtrl.text = 'BP: 80/50, HR: 125, SpO2: 86%';
                      condCtrl.text =
                          'ผู้ป่วยหมดสติ ปลุกไม่ตื่น หายใจหอบเหนื่อย (On Mask 10L)';
                    },
                  ),
                  ActionChip(
                    label: const Text('⚠️ ปานกลาง (บาดเจ็บกระดูกหัก)'),
                    backgroundColor: const Color(0xFFFEF3C7),
                    onPressed: () {
                      bpCtrl.text = 'BP: 130/85, HR: 95, SpO2: 97%';
                      condCtrl.text =
                          'ผู้ป่วยรู้สึกตัวดี สงสัยกระดูกขาขวาหัก ดาม Splint เรียบร้อย';
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextField(
                controller: bpCtrl,
                decoration: InputDecoration(
                  labelText: 'สัญญาณชีพ (Vital Signs: BP, HR, SpO2, RR)',
                  prefixIcon: const Icon(Icons.monitor_heart_rounded,
                      color: Color(0xFF00A896)),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: condCtrl,
                decoration: InputDecoration(
                  labelText: 'ระดับความรู้สึกตัว / อาการสำคัญ',
                  prefixIcon: const Icon(Icons.personal_injury_rounded,
                      color: Color(0xFF00A896)),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),

              TextField(
                controller: noteCtrl,
                decoration: InputDecoration(
                  labelText: 'การปฐมพยาบาลบนรถ / อุปกรณ์ที่ขอให้ ER เตรียม',
                  prefixIcon: const Icon(Icons.medical_services_rounded,
                      color: Color(0xFF00A896)),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    if (_activeIncident != null) {
                      await IncidentService().submitMedicalTeleReport(
                        id: _activeIncident!.id,
                        patientCondition: condCtrl.text.trim(),
                        vitalSigns: bpCtrl.text.trim(),
                        medicalNotes: noteCtrl.text.trim(),
                        callActive: true,
                      );
                    }
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                  },
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  label: const Text(
                    'ส่งรายงาน & เปิดสายสื่อสารกับแพทย์ ER',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A896),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _incidentSub?.cancel();
    _hospitalSub?.cancel();
    _broadcastTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int step = _activeIncident?.statusStep ?? 1;

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

                  // Target Capsule Header
                  Positioned(
                    top: 14,
                    left: 20,
                    right: 20,
                    child: _buildTargetHeaderBadge(step),
                  ),

                  // Bottom Action Card
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: _buildAmbulanceStatusCard(step),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetHeaderBadge(int step) {
    final isHeadingToHospital = step >= 3;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHeadingToHospital
              ? const Color(0xFF00A896)
              : const Color(0xFFEB5757),
          width: 1.5,
        ),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Row(
        children: [
          Icon(
            isHeadingToHospital
                ? Icons.local_hospital_rounded
                : Icons.location_on_rounded,
            color: isHeadingToHospital
                ? const Color(0xFF00A896)
                : const Color(0xFFEB5757),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isHeadingToHospital
                  ? '🎯 เป้าหมาย: โรงพยาบาลปลายทาง (นำส่งผู้ป่วย)'
                  : '🎯 เป้าหมาย: จุดเกิดเหตุ (${_activeIncident?.type ?? "ผู้ป่วยฉุกเฉิน"})',
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.phone_in_talk_rounded,
                color: Color(0xFF00A896), size: 20),
            tooltip: 'รายงานอาการคนไข้สู่ ER',
            onPressed: _showTeleReportDialog,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
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
            'RouteAlert Ambulance',
            style: TextStyle(
              fontSize: 18,
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
    final int step = _activeIncident?.statusStep ?? 1;
    final LatLng targetDestination =
        step >= 3 ? _hospitalLocation : _incidentLocation;

    final displayPoints = _routePoints.isNotEmpty
        ? _routePoints
        : [_ambulanceLocation, targetDestination];

    return FlutterMap(
      options: MapOptions(
        initialCenter: _ambulanceLocation,
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
              points: displayPoints,
              strokeWidth: 5.5,
              color: step >= 3
                  ? const Color(0xFF00A896)
                  : const Color(0xFFEB5757),
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            // 1. Ambulance Marker
            Marker(
              point: _ambulanceLocation,
              width: 48,
              height: 48,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: const Color(0xFFEB5757), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(0xFFEB5757).withValues(alpha: 0.4),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('🚑', style: TextStyle(fontSize: 24)),
                ),
              ),
            ),

            // 2. Incident Location Marker
            Marker(
              point: _incidentLocation,
              width: 38,
              height: 38,
              child: const Icon(
                Icons.location_on_rounded,
                color: Color(0xFFEB5757),
                size: 38,
              ),
            ),

            // 3. Pinned Hospital Marker
            Marker(
              point: _hospitalLocation,
              width: 44,
              height: 44,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: const Color(0xFF00A896), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(0xFF00A896).withValues(alpha: 0.4),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.local_hospital_rounded,
                      color: Color(0xFF00A896), size: 24),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- การ์ดแสดงสถานะและปุ่มกดเปลี่ยนสเตตัส ---
  Widget _buildAmbulanceStatusCard(int step) {
    String stepLabel = 'กำลังเดินทางไปรับเคส';
    if (step == 2) stepLabel = 'ถึงจุดเกิดเหตุแล้ว (ปฐมพยาบาล)';
    if (step == 3) stepLabel = 'กำลังนำส่งกลับโรงพยาบาล';
    if (step == 4) stepLabel = '🚨 ใกล้ถึง รพ. แล้ว (เตือน ER)';
    if (step >= 5) stepLabel = 'นำส่งถึง รพ. เรียบร้อยแล้ว';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: step >= 3
              ? const Color(0xFF00A896)
              : const Color(0xFFEB5757),
          width: 2,
        ),
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
        children: [
          _buildStatusRow('สถานะปัจจุบัน', '(Mission Step)', stepLabel),
          const SizedBox(height: 6),
          _buildStatusRow('เส้นทางนำทาง', '(Turn Intent)', _turnInstruction),
          const SizedBox(height: 6),
          _buildStatusRow(
              'ระยะทางคงเหลือ', '(Distance)', '${_distanceKm.toStringAsFixed(2)} กม.'),
          const SizedBox(height: 6),
          _buildStatusRow('เวลาที่คาดว่าจะถึง', '(ETA)', '$_etaMinutes นาที'),
          const SizedBox(height: 10),

          // Operational Step Buttons
          if (step <= 1)
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () async {
                  if (_activeIncident != null) {
                    await IncidentService()
                        .reportAmbulanceAtScene(_activeIncident!.id);
                    HapticFeedback.heavyImpact();
                  }
                },
                icon: const Icon(Icons.place_rounded,
                    color: Colors.white, size: 20),
                label: const Text(
                  '📍 กดเมื่อ: ถึงจุดเกิดเหตุแล้ว',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            )
          else if (step == 2)
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () async {
                  if (_activeIncident != null) {
                    await IncidentService()
                        .reportAmbulanceTransporting(_activeIncident!.id);
                    HapticFeedback.heavyImpact();
                  }
                },
                icon: const Icon(Icons.local_hospital_rounded,
                    color: Colors.white, size: 20),
                label: const Text(
                  '🚑 กดเมื่อ: กำลังนำส่งผู้ป่วยกลับ รพ.',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A896),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            )
          else if (step >= 3 && step < 5)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showTeleReportDialog,
                    icon: const Icon(Icons.phone_in_talk_rounded,
                        color: Colors.white, size: 18),
                    label: const Text(
                      '📞 โทรรายงาน ER',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      if (_activeIncident != null) {
                        await IncidentService()
                            .resolveIncident(_activeIncident!.id);
                        HapticFeedback.heavyImpact();
                      }
                    },
                    icon: const Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 18),
                    label: const Text(
                      '🏁 ถึง รพ. เรียบร้อย',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '✅ ภารกิจเสร็จสิ้นสมบูรณ์ นำส่งผู้ป่วยถึงมือแพทย์แล้ว',
                style: TextStyle(
                    color: Color(0xFF047857),
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),

          const SizedBox(height: 8),

          // Toggle Siren Switch
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ส่งสัญญาณเตือน',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    '(Notification alert)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFEB5757),
                    ),
                  ),
                ],
              ),
              Transform.scale(
                scale: 0.9,
                child: Switch(
                  value: _isNotificationAlert,
                  activeThumbColor: Colors.white,
                  activeTrackColor: const Color(0xFFEB5757),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: Colors.grey.shade400,
                  onChanged: (value) {
                    setState(() => _isNotificationAlert = value);
                    _broadcastCurrentLocation();
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
          width: 155,
          child: Row(
            children: [
              Text(
                labelTH,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  labelEN,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFEB5757),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Text(
          ':',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}