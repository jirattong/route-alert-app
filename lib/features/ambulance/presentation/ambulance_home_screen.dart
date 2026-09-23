import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../../../core/models/incident_report.dart';
import '../../../core/services/ambulance_storage_service.dart';
import '../../../core/services/emergency_mqtt_service.dart';
import '../../../core/services/hospital_location_service.dart';
import '../../../core/services/incident_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/osrm_routing_service.dart';
import '../../../core/widgets/status_confirm_dialog.dart';

class AmbulanceHomeScreen extends StatefulWidget {
  /// เรียกครั้งเดียวตอน initState เพื่อส่งฟังก์ชันเปิด Coach Mark ขึ้นไปให้
  /// AmbulanceMainScreen เก็บไว้ — ใช้ตอนผู้ใช้กด "สอนการใช้งานปุ่มต่างๆ" จากหน้า
  /// ตั้งค่า (คนละหน้ากับหน้านี้ แต่ยังอยู่ใน IndexedStack เดียวกัน)
  final ValueChanged<VoidCallback>? onCoachMarkReady;

  const AmbulanceHomeScreen({super.key, this.onCoachMarkReady});

  @override
  State<AmbulanceHomeScreen> createState() => _AmbulanceHomeScreenState();
}

class _AmbulanceHomeScreenState extends State<AmbulanceHomeScreen> {
  // เดิมแผนที่ฝั่งนี้ไม่มี MapController เลย กดจัดกึ่งกลางกลับมาที่ตำแหน่งตัวเองไม่ได้
  // เลยทั้งที่ฝั่ง Driver มีปุ่มนี้อยู่แล้ว (ถ้าเลื่อน/ซูมแผนที่ดูจุดอื่นแล้วอยากกลับมา
  // ที่ตำแหน่งรถตัวเอง ต้องรอ GPS อัปเดตขยับแผนที่เองเท่านั้น)
  final MapController _mapController = MapController();

  // ควบคุม/ติดตามขนาดปัจจุบันของแผ่นสถานะที่ลากขึ้น-ลงได้ (DraggableScrollableSheet)
  // เดิมปุ่มจัดกึ่งกลาง GPS คำนวณตำแหน่งครั้งเดียวจากค่าคงที่ 0.12 (ขนาดย่อสุด)
  // ทำให้พอแผ่นเปิดที่ค่าเริ่มต้นจริง (0.24) หรือถูกลากขึ้นไปถึง 0.65 ปุ่มจะจมอยู่
  // ใต้/ในแผ่นสถานะทันที ต้องฟัง controller แล้วคำนวณตำแหน่งใหม่ทุกครั้งที่ลาก
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  // สถานะเปิด/ปิดส่งสัญญาณเตือนฉุกเฉิน
  bool _isNotificationAlert = true;

  // แบนเนอร์เด่นชัดตอนเพิ่งได้รับมอบหมายเคสใหม่ — เดิมมีแค่เปลี่ยนสี badge เงียบๆ
  // ไม่มีอะไรบอกชัดเจนเลยว่าได้รับเคสแล้ว auto-dismiss เองหลัง 6 วิ
  IncidentReport? _newAssignmentBanner;
  Timer? _newAssignmentBannerTimer;

  // โหมดทดสอบในห้อง: ข้ามการจับคู่เส้นทางถนนจริง (Route-Aware Corridor)
  // ใช้ตอนสาธิตในห้อง/ระยะใกล้ที่ไม่ได้เดินตามถนนจริงไปโรงพยาบาล/จุดเกิดเหตุ
  bool _isIndoorTestMode = false;

  // ข้อมูลพิกัดรถพยาบาล
  LatLng _ambulanceLocation = const LatLng(19.0350, 99.8962);
  LatLng _incidentLocation = const LatLng(19.0284, 99.8962);
  late LatLng _hospitalLocation;

  // ทิศทางการเคลื่อนที่จริง คำนวณจากพิกัด GPS 2 จุดล่าสุด (0-360 องศา)
  double _ambulanceHeading = 0.0;
  LatLng? _lastHeadingRefPos;

  // ความเร็วจริง คำนวณจากระยะทาง GPS 2 จุดล่าสุด / เวลาที่ผ่านไป (หน่วย กม./ชม.
  // เหมือนกับที่ฝั่ง Driver แสดงผล) แทนค่าคงที่ 65.0 เดิมที่ไม่ใช่ความเร็วจริง
  // และถูกใช้คำนวณ trajectory-conflict ฝั่ง Driver จริงๆ
  double _ambulanceSpeedKmh = 0.0;
  LatLng? _lastSpeedRefPos;
  DateTime? _lastSpeedRefTime;

  // ข้อมูลประจำหน่วยจริง (โหลดจาก AmbulanceStorageService แทนค่า hardcode)
  String _ambulanceUnitId = 'AMB-0000';
  String _ambulancePlateNumber = 'ยังไม่ระบุทะเบียน';
  String _ambulanceCallSign = 'หน่วยกู้ชีพ';

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

  // Coach Mark: ชี้ตำแหน่งปุ่มจริงบนหน้าจอพร้อมคำอธิบาย โชว์แค่ครั้งแรกที่เข้าหน้านี้
  final GlobalKey _keyGpsButton = GlobalKey();
  final GlobalKey _keySirenSwitch = GlobalKey();
  final GlobalKey _keyIndoorTestSwitch = GlobalKey();

  @override
  void initState() {
    super.initState();
    _hospitalLocation = HospitalLocationService().hospitalLocation;

    _loadAmbulanceProfile();
    _initAmbulanceTracking();
    _initHospitalListener();
    _initIncidentListener();

    // รีบิลด์ทุกครั้งที่ผู้ใช้ลากแผ่นสถานะ เพื่อคำนวณตำแหน่งปุ่มจัดกึ่งกลาง GPS ใหม่
    // ให้ตรงกับขนาดแผ่นจริง ณ ขณะนั้น (ดู _buildGpsRecenterButtonBottom)
    _sheetController.addListener(() {
      if (mounted) setState(() {});
    });

    // ส่งฟังก์ชันเปิด Coach Mark ขึ้นไปให้ AmbulanceMainScreen เก็บไว้ — ไม่โชว์เอง
    // อัตโนมัติอีกต่อไป (ย้ายไปเป็นปุ่ม "สอนการใช้งานปุ่มต่างๆ" ในหน้าตั้งค่าแทน
    // ตามที่ผู้ใช้ขอ)
    widget.onCoachMarkReady?.call(_showCoachMark);
  }

  // แสดงคำแนะนำปุ่มแบบชี้ตำแหน่งจริง (Coach Mark) — เรียกได้ตลอดเวลาจากปุ่ม
  // "สอนการใช้งานปุ่มต่างๆ" ในหน้าตั้งค่า (ไม่ผูกกับ "เคยดูแล้วหรือยัง" อีกต่อไป
  // เพราะเป็นการเปิดดูตามใจผู้ใช้เอง ไม่ใช่การโชว์อัตโนมัติครั้งแรก) — สวิตช์ทั้ง 2
  // ตัวอยู่ในแผ่นสถานะที่ลากได้ ต้องขยายแผ่นให้เห็นก่อน ไม่งั้นตำแหน่งที่ชี้จะผิดเพราะ
  // widget ยังไม่ได้อยู่ในมุมมองที่เห็นจริง
  Future<void> _showCoachMark() async {
    if (!mounted) return;
    if (_sheetController.isAttached) {
      await _sheetController.animateTo(
        0.65,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;

    final targets = [
      TargetFocus(
        identify: 'gps_button',
        keyTarget: _keyGpsButton,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: _buildCoachMarkText(
              'ปุ่มจัดกึ่งกลาง GPS',
              'กดเพื่อเลื่อนแผนที่กลับมาที่ตำแหน่งรถพยาบาลของคุณทันที',
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'siren_switch',
        keyTarget: _keySirenSwitch,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: _buildCoachMarkText(
              'ส่งสัญญาณเตือน',
              'เปิดสวิตช์นี้เพื่อกระจายตำแหน่ง/ทิศทาง/ความเร็วของคุณให้ผู้ใช้ถนนใกล้เคียงเห็นแบบเรียลไทม์',
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'indoor_test_switch',
        keyTarget: _keyIndoorTestSwitch,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: _buildCoachMarkText(
              'โหมดทดสอบในห้อง',
              'เปิดใช้ตอนสาธิต/ทดสอบในอาคาร ข้ามการจับคู่เส้นทางถนนจริงที่ไม่ตรงกับตำแหน่งจำลอง',
            ),
          ),
        ],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.85,
    ).show(context: context);
  }

  Widget _buildCoachMarkText(String title, String description) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
  }

  // โหลดรหัสหน่วย/ทะเบียน/ชื่อเรียกขานจริงของเครื่องนี้ แทนค่า hardcode เดิม
  Future<void> _loadAmbulanceProfile() async {
    final profile = await AmbulanceStorageService.loadProfile();
    await AmbulanceStorageService.loadOnDuty();
    if (!mounted) return;
    setState(() {
      _ambulanceUnitId = profile['ambulanceId']!;
      _ambulancePlateNumber = profile['plateNumber']!;
      _ambulanceCallSign = profile['callSign']!;
    });
  }

  void _initHospitalListener() async {
    // เดิมไม่เคยเรียก initialize() เลย ทำให้ไม่มีการต่อ Firestore listener
    // ของหน่วยงานนี้จริง — ปักหมุดโรงพยาบาลใหม่จาก Agency (เครื่องอื่น) จึงไม่มีวัน
    // ไหลมาถึงฝั่ง Ambulance ได้เลย (profileStream ไม่เคยมีใครยิง event เข้ามา)
    // เห็นแค่พิกัด default ที่ hardcode ไว้ในเครื่องตัวเองตลอดไป
    await HospitalLocationService().initialize();
    if (!mounted) return;
    setState(() {
      _hospitalLocation = HospitalLocationService().hospitalLocation;
    });
    _updateRoute();

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
      // Find active incident assigned to THIS ambulance unit specifically.
      // เดิม: ใช้ OR ทำให้เคสของหน่วยอื่นที่ status เป็น assigned/at_scene/
      // transporting/approaching_er ก็ match ได้หมด (คุมเคสของรถคันอื่นได้ทั้งที่
      // ไม่ใช่หน่วยของตัวเอง) — ตอนนี้ต้องเป็นเคสที่ assignedAmbulanceId ตรงกับ
      // หน่วยนี้เท่านั้นถึงจะถือเป็นภารกิจของหน่วยนี้
      // ไม่มีเคสจริงมอบหมายให้หน่วยนี้ = ไม่มีภารกิจ (null) ไม่ใช่เคสปลอมที่แต่งขึ้นมา
      // เดิม orElse คืนค่า IncidentReport ปลอมเสมอ ทำให้ UI โชว์ "เป้าหมาย"/สถานะ
      // ภารกิจเป็นข้อมูลปลอมตลอดเวลาแม้ยังไม่เคยได้รับเคสจริงเลยสักครั้ง
      final assigned = list.cast<IncidentReport?>().firstWhere(
            (i) =>
                i!.status != 'resolved' &&
                i.status != 'cancelled' &&
                i.assignedAmbulanceId == _ambulanceUnitId,
            orElse: () => null,
          );

      // เปิดสัญญาณเตือนอัตโนมัติทันทีที่มีเคสมอบหมายให้หน่วยนี้จริง (เดิมต้องกดเปิดเอง
      // เสมอ แม้จะมีเคสมาแล้วก็ตาม) — เช็คจาก transition ว่าเพิ่งได้รับมอบหมายเคสใหม่
      final wasAssignedToThisUnit =
          _activeIncident?.assignedAmbulanceId == _ambulanceUnitId;
      final isNowAssignedToThisUnit =
          assigned?.assignedAmbulanceId == _ambulanceUnitId;

      setState(() {
        if (isNowAssignedToThisUnit && !wasAssignedToThisUnit) {
          _isNotificationAlert = true;
          // เพิ่งได้รับมอบหมายเคสใหม่ — เดิมแค่เปลี่ยนสี badge เงียบๆ มองไม่ทัน
          // ว่าได้รับเคสแล้ว เพิ่ม haptic + แบนเนอร์เด่นชัด auto-dismiss เอง
          HapticFeedback.heavyImpact();
          _newAssignmentBanner = assigned;
          _newAssignmentBannerTimer?.cancel();
          _newAssignmentBannerTimer = Timer(const Duration(seconds: 6), () {
            if (mounted) setState(() => _newAssignmentBanner = null);
          });
        }
        _activeIncident = assigned;
        if (assigned != null) {
          _incidentLocation = LatLng(assigned.latitude, assigned.longitude);
        }
      });
      _updateRoute();
      if (_isNotificationAlert) {
        _broadcastCurrentLocation();
      }
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
      _updateHeadingFromMovement(newPos);
      _updateSpeedFromMovement(newPos);
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

  // อัปเดตทิศทางการเคลื่อนที่จริงจากพิกัด GPS 2 จุดล่าสุด
  // (ข้ามการอัปเดตถ้าขยับน้อยกว่า 2 เมตร เพื่อกันทิศทางกระตุกตอนสัญญาณ GPS นิ่ง)
  void _updateHeadingFromMovement(LatLng newPos) {
    if (_lastHeadingRefPos != null) {
      final movedMeters = LocationService.calculateDistanceInMeters(
          _lastHeadingRefPos!, newPos);
      if (movedMeters >= 2.0) {
        _ambulanceHeading =
            LocationService.calculateBearingDeg(_lastHeadingRefPos!, newPos);
        _lastHeadingRefPos = newPos;
      }
    } else {
      _lastHeadingRefPos = newPos;
    }
  }

  // คำนวณความเร็วจริงจากระยะทาง (เมตร) / เวลาที่ผ่านไป (วินาที) ระหว่างพิกัด GPS
  // 2 จุดล่าสุด แล้วแปลงเป็น กม./ชม. — ใช้ threshold เวลาขั้นต่ำกันหารด้วยค่าเวลาที่
  // สั้นเกินไปจนทำให้ค่าความเร็วกระโดดผิดปกติจาก GPS jitter
  void _updateSpeedFromMovement(LatLng newPos) {
    final now = DateTime.now();
    if (_lastSpeedRefPos != null && _lastSpeedRefTime != null) {
      final elapsedSeconds =
          now.difference(_lastSpeedRefTime!).inMilliseconds / 1000.0;
      if (elapsedSeconds >= 1.0) {
        final movedMeters = LocationService.calculateDistanceInMeters(
            _lastSpeedRefPos!, newPos);
        final metersPerSecond = movedMeters / elapsedSeconds;
        _ambulanceSpeedKmh = metersPerSecond * 3.6;
        _lastSpeedRefPos = newPos;
        _lastSpeedRefTime = now;
      }
    } else {
      _lastSpeedRefPos = newPos;
      _lastSpeedRefTime = now;
    }
  }

  Future<void> _updateRoute() async {
    // ยังไม่มีเคสจริงมอบหมายให้หน่วยนี้ = ไม่มีปลายทางให้นำทาง เคลียร์เส้นทาง/ETA
    // ให้ตรงความจริง แทนที่จะคำนวณเส้นทางไปยังพิกัดเคสปลอมที่ไม่มีอยู่จริง
    if (_activeIncident == null) {
      if (!mounted) return;
      setState(() {
        _routePoints = [];
        _turnInstruction = 'รอรับเคสจากศูนย์สั่งการ';
        _distanceKm = 0.0;
        _etaMinutes = 0;
      });
      return;
    }

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
    // พักเวร (Off Duty) จริง = ไม่ broadcast พิกัด/ไซเรน เลย เพื่อไม่ให้ฝั่ง Agency
    // เลือกรถคันนี้เป็น "รถพยาบาลที่ใกล้ที่สุด" ระหว่างพักเวรอยู่
    if (!AmbulanceStorageService.onDutyNotifier.value) return;

    final int step = _activeIncident?.statusStep ?? 1;
    // ยังไม่มีเคสจริง = บอกตรงๆ ว่ากำลังลาดตระเวน ไม่ใช่มุ่งหน้าไปเคสปลอม
    final destName = _activeIncident == null
        ? 'ลาดตระเวน (ยังไม่มีเคส)'
        : (step >= 3
            ? 'โรงพยาบาลมหาราชนคร (ER)'
            : (_activeIncident?.address ?? 'จุดเกิดเหตุ'));

    EmergencyMqttService().broadcastAmbulanceLocation(
      EmergencyVehicleData(
        id: _ambulanceUnitId,
        callSign: _ambulanceCallSign,
        latitude: _ambulanceLocation.latitude,
        longitude: _ambulanceLocation.longitude,
        speed: _ambulanceSpeedKmh,
        heading: _ambulanceHeading,
        plateNumber: _ambulancePlateNumber,
        emergencyType:
            _activeIncident?.type ?? 'ผู้ป่วยวิกฤตฉุกเฉิน (Red Code)',
        sirenActive: _isNotificationAlert,
        timestamp: DateTime.now(),
        // โหมดทดสอบในห้อง หรือยังไม่มีเคสจริง: ไม่ส่งเส้นทางถนนจริง เพื่อให้ Driver
        // ฝั่งรับใช้การประเมินระยะ+ทิศทางแบบง่าย แทนการจับคู่กับถนนจริง/เคสปลอม
        routePoints: (_isIndoorTestMode || _activeIncident == null)
            ? null
            : (_routePoints.isNotEmpty
                ? _routePoints
                : [
                    _ambulanceLocation,
                    step >= 3 ? _hospitalLocation : _incidentLocation
                  ]),
        turnIntent: (_isIndoorTestMode || _activeIncident == null)
            ? null
            : _turnInstruction,
        destinationName: destName,
      ),
    );
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _incidentSub?.cancel();
    _hospitalSub?.cancel();
    _broadcastTimer?.cancel();
    _newAssignmentBannerTimer?.cancel();
    _sheetController.dispose();
    _mapController.dispose();
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
            _buildDebugStatusBar(),

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

                  // แบนเนอร์เด่นชัดตอนเพิ่งได้รับมอบหมายเคสใหม่ (auto-dismiss 6 วิ)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
                    top: _newAssignmentBanner != null ? 14 : -160,
                    left: 16,
                    right: 16,
                    child: _newAssignmentBanner != null
                        ? _buildNewAssignmentBanner(_newAssignmentBanner!)
                        : const SizedBox.shrink(),
                  ),

                  // Bottom Action Card — ทำเป็นแผ่นลากขึ้น/ย่อได้ (Draggable
                  // Sheet) แทนการ์ดสูงตายตัวเดิม เดิมสูงถึง 55% ของจอ+แถบเป้าหมาย
                  // ด้านบนรวมกันบังพื้นที่แผนที่เกือบหมด ผู้ใช้ไม่เห็นแผนที่จริงเลย
                  // ตอนนี้ลากลงให้เหลือแค่แถบเดียวเพื่อดูแผนที่เต็มๆ ได้ หรือลากขึ้น
                  // เพื่อดูรายละเอียดเต็มก็ได้
                  Positioned.fill(
                    child: _buildAmbulanceStatusCard(step),
                  ),

                  // ปุ่มจัดกึ่งกลาง GPS กลับมาที่ตำแหน่งรถตัวเอง (เดิมฝั่งนี้ไม่มี
                  // ปุ่มนี้เลยทั้งที่ฝั่ง Driver มีอยู่แล้ว) วางเหนือขอบบนของแผ่นสถานะ
                  // เสมอ โดยคำนวณจากขนาดแผ่นจริง ณ ขณะนั้น (ผ่าน _sheetController)
                  // แทนค่าคงที่ 0.12 เดิมซึ่งคำนวณจากขนาดตอนย่อสุดเท่านั้น — ถ้าแผ่น
                  // เปิดที่ค่าเริ่มต้นจริง (0.24) หรือถูกลากขึ้นไปถึง 0.65 ปุ่มเดิมจะจม
                  // อยู่ใต้/ในแผ่นสถานะทันที
                  Positioned(
                    right: 16,
                    bottom: (_sheetController.isAttached
                                ? _sheetController.size
                                : 0.24) *
                            MediaQuery.of(context).size.height +
                        16,
                    child: InkWell(
                      onTap: () {
                        _mapController.move(_ambulanceLocation, 15.0);
                      },
                      borderRadius: BorderRadius.circular(25),
                      child: Container(
                        key: _keyGpsButton,
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFEB5757),
                            width: 1.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.my_location_rounded,
                          color: Color(0xFFEB5757),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // แถบ debug ชั่วคราวสำหรับตรวจสอบตอนทดสอบ 2 เครื่องแล้วไม่เจอกัน — โชว์สถานะ
  // เชื่อมต่อ MQTT จริง/พิกัด GPS จริงตรงๆ แทนการเดา จะได้รู้ทันทีว่าติดขั้นตอนไหน
  Widget _buildDebugStatusBar() {
    final mqtt = EmergencyMqttService();
    final connected = mqtt.isConnected;
    final statusColor =
        connected ? const Color(0xFF047857) : const Color(0xFFB91C1C);
    return Container(
      width: double.infinity,
      color: connected ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'MQTT: ${connected ? "เชื่อมต่อแล้ว ✅" : "ยังไม่เชื่อมต่อ ❌"}  •  '
            'สัญญาณ: ${AmbulanceStorageService.onDutyNotifier.value ? (_isNotificationAlert ? "กำลังส่ง 🔴" : "ปิดอยู่") : "พักเวร (Off Duty)"}  •  '
            'พิกัด: ${_ambulanceLocation.latitude.toStringAsFixed(5)}, ${_ambulanceLocation.longitude.toStringAsFixed(5)}',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: statusColor),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (!connected && mqtt.lastError != null)
            Text(
              mqtt.lastError!,
              style: const TextStyle(fontSize: 9, color: Color(0xFFB91C1C)),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  // แบนเนอร์เด่นชัดตอนเพิ่งได้รับมอบหมายเคสใหม่ — ให้เห็นชัดว่าได้รับเคสแล้วและ
  // เป็นเคสไหน (ประเภทเหตุ+ที่อยู่) ต่างจาก badge บนหัวจอที่แค่เปลี่ยนสีเงียบๆ
  Widget _buildNewAssignmentBanner(IncidentReport incident) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEB5757), Color(0xFFC0392B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEB5757).withValues(alpha: 0.5),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '🚨 ได้รับมอบหมายเคสใหม่!',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${incident.type} • ${incident.address.isNotEmpty ? incident.address : incident.province}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetHeaderBadge(int step) {
    if (_activeIncident == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade400, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
        ),
        child: const Row(
          children: [
            Icon(Icons.hourglass_empty_rounded, color: Colors.grey, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '🎯 ยังไม่มีเคสที่ได้รับมอบหมาย — รอศูนย์สั่งการ',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

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
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
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
    final bool hasCase = _activeIncident != null;
    final int step = _activeIncident?.statusStep ?? 1;
    final LatLng? targetDestination =
        hasCase ? (step >= 3 ? _hospitalLocation : _incidentLocation) : null;

    // ยังไม่มีเคสจริง = ไม่วาดเส้นทาง/หมุดจุดเกิดเหตุปลอมบนแผนที่
    final displayPoints = hasCase
        ? (_routePoints.isNotEmpty
            ? _routePoints
            : [_ambulanceLocation, targetDestination!])
        : <LatLng>[];

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _ambulanceLocation,
        initialZoom: 15.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.routealert.app',
        ),
        if (displayPoints.isNotEmpty)
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

            // 2. Incident Location Marker (เฉพาะตอนมีเคสจริงเท่านั้น)
            if (hasCase)
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
                  border: Border.all(color: const Color(0xFF00A896), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00A896).withValues(alpha: 0.4),
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

    // แผ่นลากขึ้น/ย่อได้: เริ่มที่ 24% ของพื้นที่แผนที่ ลากลงต่ำสุดเหลือ 12% (เห็นแค่
    // หัวข้อ+มือจับ) หรือลากขึ้นสูงสุด 65% เพื่อดูรายละเอียดเต็ม ผู้ใช้เลือกเองได้ว่า
    // จะให้บังแผนที่มากแค่ไหน แทนการ์ดสูงตายตัว 55% เดิมที่บังแผนที่เกือบหมดจอเสมอ
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.24,
      minChildSize: 0.12,
      maxChildSize: 0.65,
      snap: true,
      snapSizes: const [0.12, 0.24, 0.65],
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color:
                  step >= 3 ? const Color(0xFF00A896) : const Color(0xFFEB5757),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 14,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // มือจับสำหรับลาก
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ยังไม่มีเคสจริงมอบหมายให้หน่วยนี้ = โชว์สถานะรอเคสตรงๆ แทนสถานะ/ปุ่ม
                      // ภารกิจปลอมที่อ้างอิงเคสที่ไม่มีอยู่จริง
                      if (_activeIncident == null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.hourglass_empty_rounded,
                                  color: Colors.grey, size: 26),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'รอรับเคสจากศูนย์สั่งการ',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey.shade700),
                                    ),
                                    Text(
                                      'ยังไม่มีภารกิจที่ได้รับมอบหมายในขณะนี้',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        _buildStatusRow(
                            'สถานะปัจจุบัน', '(Mission Step)', stepLabel),
                        const SizedBox(height: 6),
                        _buildStatusRow(
                            'เส้นทางนำทาง', '(Turn Intent)', _turnInstruction),
                        const SizedBox(height: 6),
                        _buildStatusRow('ระยะทางคงเหลือ', '(Distance)',
                            '${_distanceKm.toStringAsFixed(2)} กม.'),
                        const SizedBox(height: 6),
                        _buildStatusRow(
                            'เวลาที่คาดว่าจะถึง', '(ETA)', '$_etaMinutes นาที'),
                        const SizedBox(height: 10),

                        // Operational Step Buttons
                        if (step <= 1)
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton.icon(
                              // ปุ่มด่วนบนหน้าหลัก — เดิมกดครั้งเดียวทำงานทันที ไม่มี
                              // การยืนยัน ต่างจากหน้ารายละเอียดเคสที่มีคูลดาวน์กัน
                              // เผลอกด เพิ่มกล่องยืนยันชุดเดียวกันตรงนี้ด้วย
                              onPressed: () => showStatusConfirmDialog(
                                context: context,
                                nextTitle: 'ถึงจุดเกิดเหตุแล้ว',
                                nextDesc: 'กำลังปฐมพยาบาลและประเมินผู้ป่วย',
                                onConfirmed: () async {
                                  if (_activeIncident != null) {
                                    final ok = await IncidentService()
                                        .reportAmbulanceAtScene(
                                            _activeIncident!.id);
                                    HapticFeedback.heavyImpact();
                                    if (mounted && !ok) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                        content: Text(
                                            '⚠️ อัปเดตสถานะไม่สำเร็จ เช็คสัญญาณอินเทอร์เน็ตแล้วลองใหม่'),
                                        backgroundColor: Color(0xFFDC2626),
                                      ));
                                    }
                                  }
                                },
                              ),
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
                              onPressed: () => showStatusConfirmDialog(
                                context: context,
                                nextTitle: 'รับผู้ป่วยแล้ว - กำลังส่ง รพ.',
                                nextDesc: 'นำทางและแจ้งห้อง ER เตรียมรับสาย',
                                onConfirmed: () async {
                                  if (_activeIncident != null) {
                                    final ok = await IncidentService()
                                        .reportAmbulanceTransporting(
                                            _activeIncident!.id);
                                    HapticFeedback.heavyImpact();
                                    if (mounted && !ok) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                        content: Text(
                                            '⚠️ อัปเดตสถานะไม่สำเร็จ เช็คสัญญาณอินเทอร์เน็ตแล้วลองใหม่'),
                                        backgroundColor: Color(0xFFDC2626),
                                      ));
                                    }
                                  }
                                },
                              ),
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
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton.icon(
                              onPressed: () => showStatusConfirmDialog(
                                context: context,
                                nextTitle: 'ถึงโรงพยาบาล (เสร็จสิ้น)',
                                nextDesc: 'ส่งมอบผู้ป่วยและปิดภารกิจ',
                                onConfirmed: () async {
                                  if (_activeIncident != null) {
                                    final ok = await IncidentService()
                                        .resolveIncident(_activeIncident!.id);
                                    HapticFeedback.heavyImpact();
                                    if (mounted && !ok) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                        content: Text(
                                            '⚠️ อัปเดตสถานะไม่สำเร็จ เช็คสัญญาณอินเทอร์เน็ตแล้วลองใหม่'),
                                        backgroundColor: Color(0xFFDC2626),
                                      ));
                                    }
                                  }
                                },
                              ),
                              icon: const Icon(Icons.check_circle_rounded,
                                  color: Colors.white, size: 20),
                              label: const Text(
                                '🏁 ถึง รพ. เรียบร้อย',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
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
                      ],

                      const SizedBox(height: 8),

                      // Toggle Siren Switch
                      Row(
                        key: _keySirenSwitch,
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

                      const SizedBox(height: 8),

                      // Toggle Indoor Test Mode Switch
                      Row(
                        key: _keyIndoorTestSwitch,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'โหมดทดสอบในห้อง',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                '(ข้ามการจับคู่เส้นทางถนนจริง)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF5B9EE1),
                                ),
                              ),
                            ],
                          ),
                          Transform.scale(
                            scale: 0.9,
                            child: Switch(
                              value: _isIndoorTestMode,
                              activeThumbColor: Colors.white,
                              activeTrackColor: const Color(0xFF5B9EE1),
                              inactiveThumbColor: Colors.white,
                              inactiveTrackColor: Colors.grey.shade400,
                              onChanged: (value) {
                                setState(() => _isIndoorTestMode = value);
                                _broadcastCurrentLocation();
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
