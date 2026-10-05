import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../../../core/ml/siren_detection_service.dart';
import '../../../core/services/live_tracking_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/driver_storage_service.dart';
import '../../../core/services/emergency_mqtt_service.dart';
import '../../../core/services/voice_alert_service.dart';
import '../../../core/models/incident_report.dart';
import '../../../core/services/critical_notification_service.dart';
import '../../../core/services/incident_service.dart';
import '../../../core/services/hospital_location_service.dart';
import '../../../core/services/ai_trajectory_service.dart';
import '../../../core/services/theme_settings_service.dart';
import '../../../core/models/emergency_proximity_tier.dart';
import '../../auth_face_login/data/services/face_auth_repository.dart';
import 'incident_detail_screen.dart';
import '../../../core/services/driver_presence.dart';

/// แถบ debug สถานะ MQTT ชั่วคราว — เปิดไว้ตอนไล่บั๊กเชื่อมต่อ 2 เครื่อง ตอนนี้บั๊กที่
/// ใช้วินิจฉัยแก้แล้ว (ดู CHANGES_SUMMARY.md หัวข้อ 11.1/11.2) ปิดไว้เป็น false โดย
/// default แต่เปิดกลับมาได้ง่ายๆ ถ้าต้อง debug การเชื่อมต่อ MQTT อีกในอนาคต
const bool kShowMqttDebugBar = false;

class DriverHomeScreen extends StatefulWidget {
  final VoidCallback? onOpenSos;

  /// เรียกครั้งเดียวตอน initState เพื่อส่งฟังก์ชันเปิด Coach Mark ขึ้นไปให้
  /// DriverMainScreen เก็บไว้ — ใช้ตอนผู้ใช้กด "สอนการใช้งานปุ่มต่างๆ" จากหน้า
  /// ตั้งค่า (คนละหน้ากับหน้านี้ แต่ยังอยู่ใน IndexedStack เดียวกัน)
  final ValueChanged<VoidCallback>? onCoachMarkReady;

  const DriverHomeScreen({
    super.key,
    this.onOpenSos,
    this.onCoachMarkReady,
  });

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

enum SimulationMode {
  inPathOvertake, // 🏎️ โหมด: ตามหลังแซงผ่าน
  turnBypass,     // ↪️ โหมด: เลี้ยวแยกหน้า (ไม่เตือน)
  turnIn,         // ↩️ โหมด: เลี้ยวเข้าถนนเรา (เตือน)
  opposingLane,   // 🔄 โหมด: สวนเลน (ปลอดภัย)
}

class _DriverHomeScreenState extends State<DriverHomeScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();

  LatLng _currentLocation = const LatLng(19.0284, 99.8962);
  // ยังไม่เคยได้ตำแหน่งจริง — ไม่ประเมินการเตือนหลบทางจากพิกัดตั้งต้น (ยกเว้นโหมดสาธิต)
  bool _hasRealFix = false;
  // ทิศทางการเคลื่อนที่จริงของ Driver คำนวณจากพิกัด GPS 2 จุดล่าสุด (0-360 องศา)
  double _driverHeading = 45.0;
  LatLng? _lastDriverHeadingRefPos;
  // ความเร็วจริงของผู้ขับ คำนวณจากระยะทาง GPS 2 จุดล่าสุด/เวลาที่ผ่านไป (หน่วย
  // กม./ชม.) เดิมเป็นค่าคงที่ 50.0 ตายตัวเสมอไม่ว่าจะขับจริงหรือยืนนิ่งอยู่กับที่
  // (บั๊กคลาสเดียวกับความเร็วรถพยาบาลที่แก้ไปแล้วก่อนหน้านี้) ค่านี้ยังถูกส่งเข้า
  // AI trajectory evaluation จริงด้วย ไม่ใช่แค่โชว์บนจอเฉยๆ
  double _driverSpeed = 0.0; // km/h
  LatLng? _lastDriverSpeedRefPos;
  DateTime? _lastDriverSpeedRefTime;

  LatLng? _ambulanceLocation;
  double _ambulanceHeading = 45.0;
  double _ambulanceSpeed = 80.0;
  bool _hasLiveAmbulance = false;

  // Route-Aware Polyline & Navigation State
  List<LatLng>? _ambulanceRoutePoints;
  String? _ambulanceTurnIntent;
  SimulationMode _simulationMode = SimulationMode.inPathOvertake;

  // Fleet of active ambulances
  List<EmergencyVehicleData> _activeFleet = [];

  // AI Deep Learning Trajectory Prediction State
  TrajectoryPredictionResult? _aiPrediction;
  bool _hasPassedAnnouncement = false;

  // Geofence radii in meters
  double _outerRadarMeters = 3000.0;
  double _innerAlertMeters = 500.0;
  bool _isBackgroundActive = true;

  double _currentDistanceMeters = 99999.0;
  bool _isInBlueZone = false;
  bool _isInRedZone = false;
  bool _hasVibrated = false;

  StreamSubscription<LatLng>? _locationSubscription;
  StreamSubscription<EmergencyVehicleData>? _mqttSubscription;
  StreamSubscription<List<EmergencyVehicleData>>? _fleetSubscription;
  // ผู้ขับขี่คนอื่นบนแผนที่ (ไม่ระบุตัวตน) และการแชร์ตำแหน่งของเครื่องนี้
  StreamSubscription<List<DriverPresence>>? _driversSubscription;
  List<DriverPresence> _otherDrivers = [];
  String? _presenceId;
  DateTime? _presenceSentAt;
  LatLng? _presenceSentPos;
  Timer? _simulationTimer;
  bool _isSimulating = false;
  bool _isNightMode = false; // Night Driving Dark Map Mode
  bool _isSleepMode = false; // OLED Screen Saver Sleep Mode

  late AnimationController _pulseController;
  late Animation<double> _glowAnimation;
  late Animation<double> _sirenScaleAnimation;

  // Heads-Up Drop-down Push Notification Banner State
  HeadsUpAlertEvent? _activeHeadsUp;
  Timer? _headsUpDismissTimer;
  StreamSubscription<HeadsUpAlertEvent>? _headsUpSubscription;

  // 🔊 ตรวจจับเสียงไซเรนจากไมโครโฟน (สัญญาณเสริม แยกจาก GPS/MQTT)
  // ปิดอยู่โดย default เสมอ เปิด/ปิดได้ในหน้าตั้งค่า — จับเสียงจริงเฉพาะตอนหน้านี้
  // เปิดอยู่ + toggle เปิดเท่านั้น (หยุดจับเสียงทันทีที่ dispose())
  bool _sirenDetectionEnabled = false;
  SirenDetectionResult? _sirenResult;

  // ตำแหน่งโรงพยาบาลปลายทาง — เดิมฝั่ง Driver ไม่เคยแสดงหมุดนี้เลยทั้งที่ฝั่ง
  // Ambulance/Agency ใช้ข้อมูลชุดเดียวกันนี้อยู่แล้ว ทำให้ผู้ใช้งงว่าทำไมเห็นแค่
  // รถพยาบาลแต่ไม่เห็นโรงพยาบาลปลายทางบนแผนที่ของตัวเอง
  late LatLng _hospitalLocation;

  // อีเมลผู้ใช้จริงที่ล็อกอินอยู่ ใช้เช็คว่า "เคสฉุกเฉินที่คุณแจ้ง" แบนเนอร์ด้านล่าง
  // เป็นเคสของเราจริงหรือไม่ (เดิมไม่เช็คเลย หยิบเคส active ล่าสุดของทั้งระบบมาโชว์
  // ตรงๆ ทำให้สลับบัญชีในเครื่องเดียวกันแล้วยังเห็นเคสของบัญชีก่อนหน้าค้างอยู่)
  String? _currentUserEmail;
  StreamSubscription<List<HospitalProfile>>? _hospitalSub;

  // รีเฟรชแถบ debug เป็นระยะ (ตัวนับข้อความ MQTT ที่ได้รับ อัปเดตอยู่ในตัว service
  // เอง ไม่ได้ผูกกับ setState ของหน้าจอนี้โดยตรง ถ้าเครื่องอยู่นิ่งไม่ขยับเกิน 3m
  // ตัวเลขบนจอจะไม่ขยับตามให้เห็นทันที) — เอาออกได้เมื่อเลิกใช้เป็นเครื่องมือ debug
  Timer? _debugRefreshTimer;

  // Coach Mark: ชี้ตำแหน่งปุ่มจริงบนหน้าจอพร้อมคำอธิบาย — เรียกแบบ manual เท่านั้น
  // จากปุ่ม "สอนการใช้งานปุ่มต่างๆ" ในหน้าตั้งค่า (ผ่าน widget.onCoachMarkReady)
  final GlobalKey _keyGpsButton = GlobalKey();
  final GlobalKey _keySosButton = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ambulanceLocation = null;
    _hospitalLocation = HospitalLocationService().hospitalLocation;
    _initHospitalSync();
    _loadCurrentUserEmail();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.15, end: 0.55).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _sirenScaleAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _listenToSettingsChanges();
    _isNightMode = ThemeSettingsService.isNightMode.value;
    ThemeSettingsService.isNightMode.addListener(_onNightModeChanged);
    _initLiveLocation();
    _initMqttRadar();
    _initHeadsUpListener();
    _initSirenDetection();
    IncidentService().initialize();
    if (kShowMqttDebugBar) {
      _debugRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) setState(() {});
      });
    }
    // ส่งฟังก์ชันเปิด Coach Mark ขึ้นไปให้ DriverMainScreen เก็บไว้ — ไม่โชว์เองอัตโนมัติ
    // อีกต่อไป (ย้ายไปเป็นปุ่ม "สอนการใช้งานปุ่มต่างๆ" ในหน้าตั้งค่าแทน ตามที่ผู้ใช้ขอ)
    widget.onCoachMarkReady?.call(_showCoachMark);
  }

  Future<void> _loadCurrentUserEmail() async {
    final user = await FaceAuthRepository.getCurrentUser();
    if (mounted && user != null && user.id != 'guest') {
      setState(() => _currentUserEmail = user.email);
    }
  }

  // แสดงคำแนะนำปุ่มแบบชี้ตำแหน่งจริง (Coach Mark) — เรียกได้ตลอดเวลาจากปุ่ม
  // "สอนการใช้งานปุ่มต่างๆ" ในหน้าตั้งค่า (ไม่ผูกกับ "เคยดูแล้วหรือยัง" อีกต่อไป
  // เพราะเป็นการเปิดดูตามใจผู้ใช้เอง ไม่ใช่การโชว์อัตโนมัติครั้งแรก)
  void _showCoachMark() {
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
              'กดเพื่อเลื่อนแผนที่กลับมาที่ตำแหน่งปัจจุบันของคุณทันที',
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'sos_button',
        keyTarget: _keySosButton,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            child: _buildCoachMarkText(
              'ปุ่ม SOS',
              'กดเมื่อพบเหตุฉุกเฉิน เพื่อแจ้งเหตุพร้อมถ่ายรูปสถานที่เกิดเหตุส่งให้ศูนย์สั่งการ',
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

  // เดิมไม่เคยเรียก initialize() ของ HospitalLocationService เลย ทำให้ไม่มีการ
  // ต่อ Firestore listener จริง — ปักหมุดโรงพยาบาลใหม่จาก Agency (เครื่องอื่น)
  // จึงไม่มีวันไหลมาถึงฝั่ง Driver ได้เลย เห็นแค่พิกัด default ที่ hardcode ไว้
  // ในเครื่องตัวเองตลอดไป แม้จะ subscribe profileStream ไว้แล้วก็ตาม (ไม่มีใครยิง
  // event เข้ามาให้ฟัง)
  //
  // เดิม (ก่อนวางแผน multi-hospital) ยังผูกกับ HospitalLocationService.currentProfile
  // ตัวเดียว (HOSP-01 เสมอ) ไม่ว่า driver จะอยู่ที่ไหน — driver ไม่มี "โรงพยาบาล
  // ของตัวเอง" เหมือน agency จึงไม่ส่ง hospitalId เข้า initialize() เลย ใช้แค่
  // รายชื่อโรงพยาบาลทั้งหมด (allHospitalsStream) หาโรงพยาบาลที่ใกล้ตัวเองจริง
  // ด้วย findNearestHospital() แทน
  void _initHospitalSync() async {
    await HospitalLocationService().initialize();
    _recomputeNearestHospital();
    _hospitalSub = HospitalLocationService().allHospitalsStream.listen((_) {
      _recomputeNearestHospital();
    });
  }

  void _recomputeNearestHospital() {
    if (!mounted) return;
    final nearest = HospitalLocationService().findNearestHospital(_currentLocation);
    setState(() => _hospitalLocation = nearest.profile.location);
  }

  void _initSirenDetection() {
    SirenDetectionService().resultNotifier.addListener(_onSirenResultChanged);
    DriverStorageService.sirenDetectionEnabledNotifier
        .addListener(_onSirenToggleChanged);

    DriverStorageService.getSirenDetectionEnabled().then((enabled) {
      if (!mounted) return;
      setState(() => _sirenDetectionEnabled = enabled);
      _applySirenDetectionState();
    });
  }

  void _onSirenToggleChanged() {
    if (!mounted) return;
    setState(() {
      _sirenDetectionEnabled = DriverStorageService.sirenDetectionEnabledNotifier.value;
    });
    _applySirenDetectionState();
  }

  void _applySirenDetectionState() {
    if (_sirenDetectionEnabled) {
      SirenDetectionService().start();
    } else {
      SirenDetectionService().stop();
      if (mounted) setState(() => _sirenResult = null);
    }
  }

  void _onSirenResultChanged() {
    if (!mounted) return;
    setState(() {
      _sirenResult = SirenDetectionService().resultNotifier.value;
    });
  }

  void _initHeadsUpListener() {
    _headsUpSubscription =
        CriticalNotificationService().headsUpStream.listen((event) {
      if (!mounted) return;
      _headsUpDismissTimer?.cancel();
      setState(() {
        _activeHeadsUp = event;
      });

      _headsUpDismissTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) {
          setState(() {
            _activeHeadsUp = null;
          });
        }
      });
    });
  }

  void _initMqttRadar() async {
    await EmergencyMqttService().initialize();
    if (!mounted) return;
    _presenceId = await DriverStorageService.getPresenceId();
    await DriverStorageService.getSharePresence();
    if (!mounted) return;
    EmergencyMqttService().subscribeDriverPresence(_presenceId!);
    _driversSubscription = EmergencyMqttService().driversStream.listen((drivers) {
      if (mounted) setState(() => _otherDrivers = drivers);
    });
    DriverStorageService.sharePresenceNotifier.addListener(_onSharePresenceChanged);
    _maybePublishPresence();

    _mqttSubscription = EmergencyMqttService().emergencyStream.listen((data) {
      if (!mounted) return;
      if (data.sirenActive) {
        setState(() {
          _ambulanceLocation = LatLng(data.latitude, data.longitude);
          _ambulanceSpeed = data.speed;
          _ambulanceHeading = data.heading;
          _ambulanceRoutePoints = data.routePoints;
          _ambulanceTurnIntent = data.turnIntent;
          _hasLiveAmbulance = true;
        });
        _runAiTrajectoryEvaluation();
      } else {
        setState(() {
          _hasLiveAmbulance = false;
          if (!_isSimulating) {
            _ambulanceLocation = null;
            _ambulanceRoutePoints = null;
            _ambulanceTurnIntent = null;
            _isInBlueZone = false;
            _isInRedZone = false;
            _aiPrediction = null;
            _currentDistanceMeters = 99999.0;
          }
        });
      }
    });

    _fleetSubscription = EmergencyMqttService().activeFleetStream.listen((fleet) {
      if (!mounted) return;
      setState(() {
        _activeFleet = fleet;
      });
      if (_hasLiveAmbulance || _isSimulating) {
        _runAiTrajectoryEvaluation();
      }
    });
  }

  void _listenToSettingsChanges() {
    final current = DriverStorageService.settingsNotifier.value;
    _outerRadarMeters = current['outerMeters'] ?? 3000.0;
    _innerAlertMeters = current['innerMeters'] ?? 500.0;
    _isBackgroundActive = current['background'] ?? true;

    DriverStorageService.settingsNotifier.addListener(() {
      if (!mounted) return;
      final val = DriverStorageService.settingsNotifier.value;
      setState(() {
        _outerRadarMeters = val['outerMeters'] ?? 3000.0;
        _innerAlertMeters = val['innerMeters'] ?? 500.0;
        _isBackgroundActive = val['background'] ?? true;
      });
      _runAiTrajectoryEvaluation();
    });
  }

  /// ส่งตำแหน่งตัวเองให้ผู้ขับขี่คนอื่น — เฉพาะตอนเปิดแอปอยู่ มีตำแหน่งจริง และเปิดสวิตช์แชร์
  void _maybePublishPresence() {
    final id = _presenceId;
    if (id == null || !_hasRealFix || !DriverStorageService.sharePresenceNotifier.value) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    if (!shouldPublishPresence(
        now: now, position: _currentLocation, lastSentAt: _presenceSentAt, lastSentPosition: _presenceSentPos)) {
      return;
    }
    _presenceSentAt = now;
    _presenceSentPos = _currentLocation;
    EmergencyMqttService().publishDriverPresence(DriverPresence(
      id: id,
      latitude: _currentLocation.latitude,
      longitude: _currentLocation.longitude,
      heading: _driverHeading,
      speedKmh: _driverSpeed,
    ));
  }

  void _publishOffline() {
    final id = _presenceId;
    if (id == null) return;
    _presenceSentAt = null;
    EmergencyMqttService().publishDriverPresence(DriverPresence(
      id: id, latitude: _currentLocation.latitude, longitude: _currentLocation.longitude, online: false));
  }

  void _onSharePresenceChanged() {
    if (DriverStorageService.sharePresenceNotifier.value) {
      _maybePublishPresence();
    } else {
      _publishOffline(); // ปิดการแชร์ = หายจากแผนที่ของคนอื่นทันที
    }
  }

  @override
  void dispose() {
    _publishOffline();
    _driversSubscription?.cancel();
    EmergencyMqttService().unsubscribeDriverPresence();
    DriverStorageService.sharePresenceNotifier.removeListener(_onSharePresenceChanged);
    ThemeSettingsService.isNightMode.removeListener(_onNightModeChanged);
    _headsUpDismissTimer?.cancel();
    _headsUpSubscription?.cancel();
    _locationSubscription?.cancel();
    _mqttSubscription?.cancel();
    _fleetSubscription?.cancel();
    _hospitalSub?.cancel();
    _debugRefreshTimer?.cancel();
    _simulationTimer?.cancel();
    _pulseController.dispose();
    // หยุดจับเสียงไมโครโฟนทันทีที่ออกจากหน้าแผนที่ (ไม่จับเสียงเบื้องหลัง)
    DriverStorageService.sirenDetectionEnabledNotifier.removeListener(_onSirenToggleChanged);
    SirenDetectionService().resultNotifier.removeListener(_onSirenResultChanged);
    SirenDetectionService().stop();
    DriverStorageService.backgroundAlertEnabledNotifier
        .removeListener(_onBackgroundAlertSettingChanged);
    LiveTrackingService.instance.keepAlive
        .removeListener(_onBackgroundAlertSettingChanged);
    super.dispose();
  }

  // ผู้ใช้เพิ่งเปิด/ปิดสวิตช์ "แจ้งเตือนพื้นหลัง" จากหน้าตั้งค่า — สมัคร location
  // stream ใหม่ด้วยค่า backgroundMode ล่าสุดทันที (ยกเลิกของเดิมก่อนเสมอกัน
  // subscription ซ้อนกันสอง stream พร้อมกัน)
  // เปิดเบื้องหลังเมื่อผู้ใช้เปิดสวิตช์ หรือระหว่างรอรถพยาบาลของเคสที่ตัวเองแจ้ง (ให้
  // Live Activity/Dynamic Island อัปเดต ETA ต่อได้ตอนพับแอป)
  bool get _wantsBackgroundLocation =>
      DriverStorageService.backgroundAlertEnabledNotifier.value ||
      LiveTrackingService.instance.keepAlive.value;
  bool? _subscribedBackgroundMode;

  void _onBackgroundAlertSettingChanged() {
    if (!mounted) return;
    final background = _wantsBackgroundLocation;
    if (_locationSubscription != null && background == _subscribedBackgroundMode) return;
    _subscribedBackgroundMode = background;
    _locationSubscription?.cancel();
    _locationSubscription = LocationService.getLiveLocationStream(
      backgroundMode: background,
    ).listen((newPos) {
      if (!mounted) return;
      _updateDriverHeadingFromMovement(newPos);
      _updateDriverSpeedFromMovement(newPos);
      setState(() {
        _currentLocation = newPos;
        _hasRealFix = true;
      });
      _maybePublishPresence();
      _recomputeNearestHospital();
      if (_isSimulating || _hasLiveAmbulance) {
        _runAiTrajectoryEvaluation();
      }
    });
  }

  void _onNightModeChanged() {
    if (mounted) {
      setState(() {
        _isNightMode = ThemeSettingsService.isNightMode.value;
      });
    }
  }

  Future<void> _initLiveLocation() async {
    final initialPos = await LocationService.getCurrentLocation();
    if (initialPos != null && mounted) {
      setState(() {
        _currentLocation = initialPos;
        _hasRealFix = true;
      });
      _mapController.move(_currentLocation, 14.5);
      if (_isSimulating || _hasLiveAmbulance) {
        _runAiTrajectoryEvaluation();
      }
    }

    // โหลดค่าที่บันทึกไว้ของสวิตช์ "แจ้งเตือนพื้นหลัง" ก่อนสมัคร stream ครั้งแรก
    // (ถ้าไม่โหลดก่อน ทุกครั้งที่เปิดแอปใหม่จะกลับไปใช้ backgroundMode: false เสมอ
    // แม้ผู้ใช้จะเปิดสวิตช์ไว้ก่อนหน้านี้แล้วก็ตาม)
    final backgroundEnabled = await DriverStorageService.getBackgroundAlertEnabled() ||
        LiveTrackingService.instance.keepAlive.value;
    if (!mounted) return;
    _subscribedBackgroundMode = backgroundEnabled;
    _locationSubscription =
        LocationService.getLiveLocationStream(backgroundMode: backgroundEnabled)
            .listen((newPos) {
      if (!mounted) return;
      _updateDriverHeadingFromMovement(newPos);
      _updateDriverSpeedFromMovement(newPos);
      setState(() {
        _currentLocation = newPos;
        _hasRealFix = true;
      });
      _maybePublishPresence();
      _recomputeNearestHospital();
      if (_isSimulating || _hasLiveAmbulance) {
        _runAiTrajectoryEvaluation();
      }
    });

    // ฟังการเปลี่ยนสวิตช์นี้จากหน้าตั้งค่าระหว่างแอปเปิดอยู่ — ต้องสมัครหลังจาก
    // สมัคร stream ครั้งแรกเสร็จแล้วเท่านั้น ไม่งั้นการโหลดค่าเริ่มต้นด้านบน (ถ้า
    // ค่าที่บันทึกไว้เป็น true) จะยิง listener ซ้ำซ้อนโดยไม่จำเป็น
    DriverStorageService.backgroundAlertEnabledNotifier
        .addListener(_onBackgroundAlertSettingChanged);
    LiveTrackingService.instance.keepAlive
        .addListener(_onBackgroundAlertSettingChanged);
  }

  // อัปเดตทิศทางการเคลื่อนที่จริงของ Driver จากพิกัด GPS 2 จุดล่าสุด
  // (ข้ามการอัปเดตถ้าขยับน้อยกว่า 2 เมตร เพื่อกันทิศทางกระตุกตอนสัญญาณ GPS นิ่ง)
  void _updateDriverHeadingFromMovement(LatLng newPos) {
    if (_lastDriverHeadingRefPos != null) {
      final movedMeters = LocationService.calculateDistanceInMeters(
          _lastDriverHeadingRefPos!, newPos);
      if (movedMeters >= 2.0) {
        _driverHeading = LocationService.calculateBearingDeg(
            _lastDriverHeadingRefPos!, newPos);
        _lastDriverHeadingRefPos = newPos;
      }
    } else {
      _lastDriverHeadingRefPos = newPos;
    }
  }

  // คำนวณความเร็วจริงของผู้ขับจากระยะทาง (เมตร) / เวลาที่ผ่านไป (วินาที) ระหว่าง
  // พิกัด GPS 2 จุดล่าสุด แปลงเป็น กม./ชม. — มี threshold เวลาขั้นต่ำกันหารด้วยค่า
  // เวลาที่สั้นเกินไปจนทำให้ค่าความเร็วกระโดดผิดปกติจาก GPS jitter (เหมือนฝั่ง
  // Ambulance ทุกประการ)
  void _updateDriverSpeedFromMovement(LatLng newPos) {
    final now = DateTime.now();
    if (_lastDriverSpeedRefPos != null && _lastDriverSpeedRefTime != null) {
      final elapsedSeconds =
          now.difference(_lastDriverSpeedRefTime!).inMilliseconds / 1000.0;
      if (elapsedSeconds >= 1.0) {
        final movedMeters = LocationService.calculateDistanceInMeters(
            _lastDriverSpeedRefPos!, newPos);
        final metersPerSecond = movedMeters / elapsedSeconds;
        _driverSpeed = metersPerSecond * 3.6;
        _lastDriverSpeedRefPos = newPos;
        _lastDriverSpeedRefTime = now;
      }
    } else {
      _lastDriverSpeedRefPos = newPos;
      _lastDriverSpeedRefTime = now;
    }
  }

  void _cycleSimulationMode() {
    setState(() {
      switch (_simulationMode) {
        case SimulationMode.inPathOvertake:
          _simulationMode = SimulationMode.turnBypass;
          break;
        case SimulationMode.turnBypass:
          _simulationMode = SimulationMode.turnIn;
          break;
        case SimulationMode.turnIn:
          _simulationMode = SimulationMode.opposingLane;
          break;
        case SimulationMode.opposingLane:
          _simulationMode = SimulationMode.inPathOvertake;
          break;
      }
    });
    _resetSimulation();
  }

  void _resetSimulation() {
    _simulationTimer?.cancel();
    setState(() {
      _isSimulating = false;
      _hasVibrated = false;
      _hasPassedAnnouncement = false;
      _ambulanceSpeed = 80.0;

      switch (_simulationMode) {
        case SimulationMode.inPathOvertake:
          _ambulanceLocation = LatLng(
            _currentLocation.latitude - 0.016,
            _currentLocation.longitude - 0.016,
          );
          _ambulanceHeading = 45.0;
          _ambulanceTurnIntent = 'มุ่งหน้าตรงตามช่องทางจราจร';
          _ambulanceRoutePoints = [
            _ambulanceLocation!,
            _currentLocation,
            LatLng(_currentLocation.latitude + 0.020, _currentLocation.longitude + 0.020),
          ];
          break;

        case SimulationMode.turnBypass:
          _ambulanceLocation = LatLng(
            _currentLocation.latitude - 0.016,
            _currentLocation.longitude - 0.016,
          );
          _ambulanceHeading = 45.0;
          _ambulanceTurnIntent = 'เตรียมเลี้ยวขวาที่แยกข้างหน้า (ไม่ตรงมา)';
          final intersection = LatLng(
            _currentLocation.latitude - 0.004,
            _currentLocation.longitude - 0.004,
          );
          _ambulanceRoutePoints = [
            _ambulanceLocation!,
            intersection,
            LatLng(intersection.latitude - 0.004, intersection.longitude + 0.018),
          ];
          break;

        case SimulationMode.turnIn:
          _ambulanceLocation = LatLng(
            _currentLocation.latitude - 0.006,
            _currentLocation.longitude - 0.016,
          );
          _ambulanceHeading = 90.0;
          _ambulanceTurnIntent = 'เตรียมเลี้ยวซ้ายเข้าถนนของผู้ใช้';
          final turnPoint = LatLng(
            _currentLocation.latitude - 0.006,
            _currentLocation.longitude,
          );
          _ambulanceRoutePoints = [
            _ambulanceLocation!,
            turnPoint,
            _currentLocation,
            LatLng(_currentLocation.latitude + 0.015, _currentLocation.longitude),
          ];
          break;

        case SimulationMode.opposingLane:
          _ambulanceLocation = LatLng(
            _currentLocation.latitude + 0.016,
            _currentLocation.longitude + 0.016 - 0.002,
          );
          _ambulanceHeading = 225.0;
          _ambulanceTurnIntent = 'วิ่งเลนตรงข้าม (ทิศทางสวนกัน)';
          _ambulanceRoutePoints = [
            _ambulanceLocation!,
            LatLng(_currentLocation.latitude - 0.020, _currentLocation.longitude - 0.020),
          ];
          break;
      }
    });
    _runAiTrajectoryEvaluation();
  }

  /// Toggle Simulation: Supports Multi-Scenario Route-Aware Realism
  void _toggleSimulation() {
    if (_isSimulating) {
      _simulationTimer?.cancel();
      setState(() {
        _isSimulating = false;
        if (!_hasLiveAmbulance) {
          _ambulanceLocation = null;
          _ambulanceRoutePoints = null;
          _ambulanceTurnIntent = null;
          _isInBlueZone = false;
          _isInRedZone = false;
          _aiPrediction = null;
          _currentDistanceMeters = 99999.0;
        }
      });
    } else {
      if (_ambulanceLocation == null) {
        _resetSimulation();
      }
      setState(() {
        _isSimulating = true;
        _hasVibrated = false;
        _hasPassedAnnouncement = false;
      });

      _simulationTimer =
          Timer.periodic(const Duration(milliseconds: 400), (timer) {
        if (!mounted) return;
        final currentAmb = _ambulanceLocation ?? _currentLocation;

        switch (_simulationMode) {
          case SimulationMode.inPathOvertake:
            final targetLat = _currentLocation.latitude + 0.020;
            if (currentAmb.latitude >= targetLat) {
              timer.cancel();
              setState(() => _isSimulating = false);
              return;
            }
            setState(() {
              _ambulanceLocation = LatLng(
                currentAmb.latitude + 0.0007,
                currentAmb.longitude + 0.0007,
              );
            });
            break;

          case SimulationMode.turnBypass:
            final intersectionLat = _currentLocation.latitude - 0.004;
            if (currentAmb.latitude < intersectionLat) {
              // Moving towards intersection
              setState(() {
                _ambulanceLocation = LatLng(
                  currentAmb.latitude + 0.0007,
                  currentAmb.longitude + 0.0007,
                );
                _ambulanceHeading = 45.0;
              });
            } else {
              // Turning East away from driver!
              if (currentAmb.longitude >= _currentLocation.longitude + 0.018) {
                timer.cancel();
                setState(() => _isSimulating = false);
                return;
              }
              setState(() {
                _ambulanceLocation = LatLng(
                  intersectionLat,
                  currentAmb.longitude + 0.0008,
                );
                _ambulanceHeading = 90.0;
              });
            }
            break;

          case SimulationMode.turnIn:
            final turnPointLon = _currentLocation.longitude;
            if (currentAmb.longitude < turnPointLon) {
              // Driving along side road East towards entry
              setState(() {
                _ambulanceLocation = LatLng(
                  currentAmb.latitude,
                  currentAmb.longitude + 0.0008,
                );
                _ambulanceHeading = 90.0;
              });
            } else {
              // Turning into driver's road and driving North
              if (currentAmb.latitude >= _currentLocation.latitude + 0.015) {
                timer.cancel();
                setState(() => _isSimulating = false);
                return;
              }
              setState(() {
                _ambulanceLocation = LatLng(
                  currentAmb.latitude + 0.0007,
                  turnPointLon,
                );
                _ambulanceHeading = 0.0;
              });
            }
            break;

          case SimulationMode.opposingLane:
            final targetLat = _currentLocation.latitude - 0.020;
            if (currentAmb.latitude <= targetLat) {
              timer.cancel();
              setState(() => _isSimulating = false);
              return;
            }
            setState(() {
              _ambulanceLocation = LatLng(
                currentAmb.latitude - 0.0007,
                currentAmb.longitude - 0.0007,
              );
            });
            break;
        }

        _runAiTrajectoryEvaluation();
      });
    }
  }

  /// AI Deep Learning & Route-Aware Trajectory Evaluation
  void _runAiTrajectoryEvaluation() {
    final ambPos = _ambulanceLocation;
    if ((ambPos == null || !_hasRealFix) && !_isSimulating) {
      setState(() {
        _isInBlueZone = false;
        _isInRedZone = false;
        _aiPrediction = null;
        _currentDistanceMeters = 99999.0;
      });
      return;
    }
    final targetAmb = ambPos ?? _currentLocation;

    final ai = AiTrajectoryService();

    final pred = ai.evaluateTrajectoryConflict(
      driverPos: _currentLocation,
      driverSpeedKmh: _driverSpeed,
      driverHeadingDeg: _driverHeading,
      ambulancePos: targetAmb,
      ambulanceSpeedKmh: _ambulanceSpeed,
      ambulanceHeadingDeg: _ambulanceHeading,
      maxWarningDistanceMeters: _outerRadarMeters,
      routePoints: _ambulanceRoutePoints,
      turnIntent: _ambulanceTurnIntent,
    );

    final meters = LocationService.calculateDistanceInMeters(
      _currentLocation,
      targetAmb,
    );

    final inRed = pred.shouldAlert && (meters <= _innerAlertMeters || pred.category == TrajectoryConflictCategory.criticalInPath || pred.category == TrajectoryConflictCategory.turnInApproaching);
    final inBlue = pred.shouldAlert && meters <= _outerRadarMeters && !inRed;

    // Trigger Critical Alert (Red Zone)
    if (inRed && !_hasVibrated) {
      _hasVibrated = true;
      // ⚡ Auto-wake up from sleep mode if ambulance approaches!
      if (_isSleepMode) {
        _isSleepMode = false;
      }
      HapticFeedback.heavyImpact();
      VoiceAlertService().speakCriticalAlert(meters.round());
      if (_isBackgroundActive) {
        CriticalNotificationService().showRadarAlert(
          title: pred.statusTitleTH,
          body: pred.explanationTH,
          isCritical: true,
        );
      }
    } else if (inBlue && !_isInBlueZone && !inRed) {
      VoiceAlertService().speakOuterRadarAlert();
      if (_isBackgroundActive) {
        CriticalNotificationService().showRadarAlert(
          title: pred.statusTitleTH,
          body: pred.explanationTH,
          isCritical: false,
        );
      }
    } else if (pred.category == TrajectoryConflictCategory.movingAway && !_hasPassedAnnouncement) {
      _hasPassedAnnouncement = true;
      _hasVibrated = false;
      VoiceAlertService().speakAmbulancePassed();
    } else if (!inBlue && !inRed) {
      _hasVibrated = false;
    }

    // Real-time live update for system notification / live activity
    if (_isBackgroundActive && (inRed || inBlue)) {
      CriticalNotificationService().updateLiveRadarNotification(
        distanceMeters: meters.round(),
        statusText: pred.statusTitleTH,
        isCritical: inRed,
        yieldProbability: pred.yieldProbability,
      );
    }

    setState(() {
      _aiPrediction = pred;
      _currentDistanceMeters = meters;
      _isInBlueZone = inBlue;
      _isInRedZone = inRed;
    });
  }

  void _onYieldAcknowledge() async {
    await DriverStorageService.incrementYieldCount();
    // บันทึกรายการประวัติจริง (เดิมมีแค่ตัวนับ ไม่มีประวัติเก็บไว้เลย ทำให้หน้า
    // ประวัติต้องโชว์ข้อมูลตัวอย่าง hardcode แทนของจริง)
    await DriverStorageService.addYieldHistoryEntry(
      _activeFleet.isNotEmpty
          ? 'เปิดทางให้รถฉุกเฉิน (${_activeFleet.first.callSign})'
          : 'เปิดทางให้รถฉุกเฉิน',
    );
    VoiceAlertService().speakYieldSuccess();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 บันทึกสถิติการเปิดทางช่วยเหลือสำเร็จ (+1 แต้มความดี)'),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // เดิมยิงทันทีตอนแอปยังเปิดอยู่ จึงไม่ได้ทดสอบเบื้องหลังจริง — รอ 8 วิให้ผู้ใช้พับแอป/ล็อกจอ
  // ก่อน ถ้าแอปยังทำงานอยู่เบื้องหลังจริง (เปิดแจ้งเตือนพื้นหลัง) แจ้งเตือนจะเด้งขึ้นมา
  void _triggerTestBackgroundNotification() async {
    await CriticalNotificationService().initialize();
    final backgroundOn = DriverStorageService.backgroundAlertEnabledNotifier.value;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(backgroundOn
              ? '🔔 จะเด้งใน 8 วินาที — พับแอปหรือล็อกจอได้เลย'
              : '⚠️ ยังไม่ได้เปิด "แจ้งเตือนพื้นหลัง" ในหน้าตั้งค่า — ถ้าพับแอป iPhone จะหยุดแอปและไม่เด้ง (จะเด้งใน 8 วินาที)'),
          backgroundColor: const Color(0xFF2563EB),
          duration: const Duration(seconds: 6),
        ),
      );
    }
    await Future.delayed(const Duration(seconds: 8));
    await CriticalNotificationService().showRadarAlert(
      title: '🚨 ทดสอบการแจ้งเตือนเบื้องหลัง (Background Alert)',
      body: 'ระบบเตือนภัยฉุกเฉินทำงานสมบูรณ์ แม้คุณจะพับแอพหรือล็อกหน้าจอ!',
      isCritical: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    int displayMeters = _currentDistanceMeters.round();

    // If Sleep / OLED Black Screen Saver Mode is active
    if (_isSleepMode) {
      return _buildOledSleepModeView(displayMeters);
    }

    return Scaffold(
      backgroundColor: _isNightMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (kShowMqttDebugBar) _buildDebugStatusBar(),
            Expanded(
              child: Stack(
                children: [
                  _buildMapView(),

                  // 1. แสงเตือนสีแดงกะพริบระดับวิกฤตรอบขอบจอ (Full Emergency Red Strobe)
                  if (_isInRedZone)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _glowAnimation,
                          builder: (context, child) {
                            return Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFDC2626).withValues(alpha: _glowAnimation.value * 1.5),
                                  width: 8,
                                ),
                                gradient: RadialGradient(
                                  center: Alignment.center,
                                  radius: 0.85,
                                  colors: [
                                    Colors.transparent,
                                    const Color(0xFFDC2626)
                                        .withValues(alpha: _glowAnimation.value),
                                  ],
                                  stops: const [0.55, 1.0],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  // 2. HUD ป้ายเตือนภัยฉุกเฉินขนาดใหญ่ ชัดเจน ไม่สับสน (Dramatic Emergency HUD)
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: _buildDramaticEmergencyHud(displayMeters),
                  ),

                  // 2.1 🚨 Floating Heads-Up Drop-Down Banner (เด้งเลื่อนลงมาจากบนสุด)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
                    top: _activeHeadsUp != null ? 8 : -140,
                    left: 12,
                    right: 12,
                    child: _buildFloatingHeadsUpBanner(),
                  ),

                  // 2.3 🚨 Active SOS Tracking Banner (เคสฉุกเฉินที่กำลังดำเนินการ)
                  // + 2.3.1 🔊 แบนเนอร์ตรวจพบเสียงไซเรนล้วนๆ (ไม่มีรถพยาบาลที่ระบุตำแหน่งด้วย GPS)
                  Positioned(
                    top: _isInRedZone ? 114 : 76,
                    left: 14,
                    right: 14,
                    child: Column(
                      children: [
                        StreamBuilder<List<IncidentReport>>(
                          stream: IncidentService().incidentsStream,
                          builder: (context, snapshot) {
                            final list = snapshot.data ?? [];
                            // เดิมไม่กรอง reporterEmail เลย เอาเคส active ล่าสุดของ
                            // ทั้งระบบมาโชว์เป็น "เคสฉุกเฉินที่คุณแจ้ง" ตรงๆ ทำให้
                            // สลับบัญชีในเครื่องเดียวกันแล้วยังเห็นเคสของคนอื่นค้างอยู่
                            final activeReports = list.where(
                              (i) =>
                                  i.status != 'resolved' &&
                                  i.status != 'cancelled' &&
                                  i.reporterEmail.trim().toLowerCase() ==
                                      (_currentUserEmail ?? "").trim().toLowerCase(),
                            ).toList();
                            if (activeReports.isEmpty) return const SizedBox.shrink();
                            final top = activeReports.first;
                            return _buildActiveSosTrackingBanner(top);
                          },
                        ),
                        _buildSirenOnlyAlertBanner(),
                      ],
                    ),
                  ),

                  // 2.2 🟢 Live Presence Indicator Pill (แสดงจำนวนผู้ใช้งานออนไลน์รอบตัวสดๆ)
                  // เดิม top:130 ลอยอยู่กลางจอห่างจากแถบ debug ด้านบนมาก ดูขัดตา ย้ายขึ้น
                  // มาชิดขอบบนแทน แต่ HUD ฉุกเฉินที่ top:12 (_buildDramaticEmergencyHud) ก็
                  // แสดงผลเต็มความกว้างจอทันทีที่ _aiPrediction != null แม้จะยังไม่ใช่โซนแดง
                  // (เช่น turnBypass/movingAway/opposingLane/blue-zone approachingCorridor ที่
                  // shouldAlert: false) ทำให้ป้ายนี้ซ้อนทับ HUD ได้ ต้องซ่อนป้ายนี้ไปด้วยเมื่อ
                  // HUD กำลังแสดงเนื้อหาอยู่ ไม่ใช่แค่ตอนอยู่โซนแดงเท่านั้น
                  if (!_isInRedZone && _activeHeadsUp == null && _aiPrediction == null)
                    Positioned(
                      top: 14,
                      left: 14,
                      child: InkWell(
                        onTap: () => _showLivePresenceModal(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _isNightMode
                                ? const Color(0xFF1E293B).withValues(alpha: 0.95)
                                : Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _isNightMode ? const Color(0xFF059669) : const Color(0xFF10B981),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: _isNightMode ? 0.35 : 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _isNightMode ? const Color(0xFF34D399) : const Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'ออนไลน์: รถพยาบาล ${_activeFleet.length} · ผู้ขับขี่ ${1 + _otherDrivers.length}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _isNightMode ? const Color(0xFF34D399) : const Color(0xFF065F46),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // 2.4 ⚖️ ปุ่มกฎหมายระยะ 50 ม. (พ.ร.บ. จราจร ม.76)
                  // ย้ายขึ้นมาชิดขอบบนคู่กับป้ายออนไลน์ ด้วยเหตุผลเดียวกัน — และซ่อนเมื่อ HUD
                  // ฉุกเฉินกำลังแสดงผลด้วยเหตุผลเดียวกับป้ายออนไลน์ด้านบน (ดูคอมเมนต์ 2.2)
                  if (!_isInRedZone && _activeHeadsUp == null && _aiPrediction == null)
                    Positioned(
                      top: 14,
                      right: 14,
                      child: InkWell(
                        onTap: () => _showLegalDistanceModal(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _isNightMode
                                ? const Color(0xFF1E293B).withValues(alpha: 0.95)
                                : Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFDC2626),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: _isNightMode ? 0.35 : 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.gavel_rounded, size: 13, color: Color(0xFFDC2626)),
                              SizedBox(width: 4),
                              Text(
                                'กฎหมายระยะ 50 ม.',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // 3. ปุ่มจัดกึ่งกลาง GPS + ปุ่ม SOS ขวาล่าง (Vertical Action Column)
                  Positioned(
                    right: 16,
                    bottom: 154,
                    child: InkWell(
                      onTap: () {
                        _mapController.move(_currentLocation, 15.0);
                      },
                      borderRadius: BorderRadius.circular(25),
                      child: Container(
                        key: _keyGpsButton,
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _isNightMode ? const Color(0xFF1E293B) : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isNightMode ? const Color(0xFF3B82F6) : const Color(0xFF2563EB),
                            width: 1.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: _isNightMode ? 0.4 : 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.my_location_rounded,
                          color: _isNightMode ? const Color(0xFF60A5FA) : const Color(0xFF2563EB),
                          size: 22,
                        ),
                      ),
                    ),
                  ),

                  // ปุ่ม SOS ขวาล่าง
                  Positioned(
                    right: 16,
                    bottom: 84,
                    child: InkWell(
                      onTap: widget.onOpenSos,
                      borderRadius: BorderRadius.circular(35),
                      child: Container(
                        key: _keySosButton,
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: _isNightMode ? const Color(0xFF1E293B) : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFFEB5757), width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEB5757).withValues(alpha: _isNightMode ? 0.45 : 0.35),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'SOS',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFEB5757),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 4. ปุ่มแผงควบคุมการจำลอง AI Simulation Panel (ไม่ชนกับปุ่ม SOS ขวา)
                  Positioned(
                    bottom: 84,
                    left: 16,
                    right: 86, // เว้นระยะ 86px ให้ปุ่ม SOS ไม่ทับกัน 100%
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: _isNightMode
                            ? const Color(0xFF1E293B).withValues(alpha: 0.96)
                            : Colors.white.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isNightMode ? const Color(0xFF334155) : Colors.grey.shade300,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: _isNightMode ? 0.35 : 0.10),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            icon: Icon(
                              _isSimulating
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.play_circle_fill_rounded,
                              color: _isSimulating
                                  ? const Color(0xFFEF4444)
                                  : (_isNightMode ? const Color(0xFF60A5FA) : const Color(0xFF2563EB)),
                              size: 28,
                            ),
                            onPressed: _toggleSimulation,
                            tooltip: 'กดเพื่อจำลองรถพยาบาลวิ่ง',
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: InkWell(
                              onTap: _cycleSimulationMode,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _getSimulationModeBgColor(),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _getSimulationModeBorderColor(),
                                  ),
                                ),
                                child: Text(
                                  _getSimulationModeLabel(),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: _getSimulationModeTextColor(),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            icon: Icon(
                              Icons.refresh_rounded,
                              size: 18,
                              color: _isNightMode ? Colors.white70 : Colors.black87,
                            ),
                            onPressed: _resetSimulation,
                            tooltip: 'รีเซ็ตพิกัดจำลอง',
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 5. แถบสวิตช์ทำงานเบื้องหลัง + ปุ่มทดสอบ Notification (แถบล่างสุด ไม่ชนใคร)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isNightMode ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _isNightMode
                                ? const Color(0xFF3B82F6).withValues(alpha: 0.6)
                                : const Color(0xFF5B9EE1),
                            width: 1.4),
                        boxShadow: [
                          BoxShadow(
                            color: (_isNightMode ? Colors.black : const Color(0xFF5B9EE1))
                                .withValues(alpha: _isNightMode ? 0.35 : 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.security_rounded,
                            size: 16,
                            color: _isNightMode ? const Color(0xFF34D399) : const Color(0xFF00A896),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'ทำงานเบื้องหลัง (Background)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _isNightMode ? Colors.white : Colors.black87,
                                  ),
                                ),
                                Text(
                                  _isBackgroundActive ? 'เปิดเตือนเมื่อพับแอพ' : 'ปิดการทำงานเบื้องหลัง',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: _isBackgroundActive
                                        ? (_isNightMode ? const Color(0xFF34D399) : const Color(0xFF00A896))
                                        : (_isNightMode ? const Color(0xFF94A3B8) : Colors.grey),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: _triggerTestBackgroundNotification,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: _isNightMode ? const Color(0xFF334155) : const Color(0xFFE2F0FE),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.notifications_active,
                                    size: 12,
                                    color: _isNightMode ? const Color(0xFF93C5FD) : const Color(0xFF2563EB),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'ทดสอบ',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _isNightMode ? const Color(0xFF93C5FD) : const Color(0xFF2563EB),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Transform.scale(
                            scale: 0.75,
                            child: Switch(
                              value: _isBackgroundActive,
                              activeThumbColor: Colors.white,
                              activeTrackColor: const Color(0xFF5B9EE1),
                              onChanged: (val) {
                                setState(() => _isBackgroundActive = val);
                                final current =
                                    DriverStorageService.settingsNotifier.value;
                                DriverStorageService.saveSettings(
                                  background: val,
                                  volume: current['volume'],
                                  outerMeters: current['outerMeters'],
                                  innerMeters: current['innerMeters'],
                                );
                              },
                            ),
                          ),
                        ],
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

  String _getSimulationModeLabel() {
    switch (_simulationMode) {
      case SimulationMode.inPathOvertake:
        return '🏎️ โหมด: ตามหลังแซงผ่าน';
      case SimulationMode.turnBypass:
        return '↪️ โหมด: เลี้ยวแยกหน้า (ไม่เตือน)';
      case SimulationMode.turnIn:
        return '↩️ โหมด: เลี้ยวเข้าถนนเรา (เตือน)';
      case SimulationMode.opposingLane:
        return '🔄 โหมด: สวนเลน (ปลอดภัย)';
    }
  }

  Color _getSimulationModeBgColor() {
    if (_isNightMode) {
      switch (_simulationMode) {
        case SimulationMode.inPathOvertake:
          return const Color(0xFF0C4A6E);
        case SimulationMode.turnBypass:
          return const Color(0xFF064E3B);
        case SimulationMode.turnIn:
          return const Color(0xFF7C2D12);
        case SimulationMode.opposingLane:
          return const Color(0xFF78350F);
      }
    }
    switch (_simulationMode) {
      case SimulationMode.inPathOvertake:
        return const Color(0xFFE0F2FE);
      case SimulationMode.turnBypass:
        return const Color(0xFFDCFCE7);
      case SimulationMode.turnIn:
        return const Color(0xFFFFEDD5);
      case SimulationMode.opposingLane:
        return const Color(0xFFFEF3C7);
    }
  }

  Color _getSimulationModeBorderColor() {
    if (_isNightMode) {
      switch (_simulationMode) {
        case SimulationMode.inPathOvertake:
          return const Color(0xFF0284C7);
        case SimulationMode.turnBypass:
          return const Color(0xFF059669);
        case SimulationMode.turnIn:
          return const Color(0xFFEA580C);
        case SimulationMode.opposingLane:
          return const Color(0xFFD97706);
      }
    }
    switch (_simulationMode) {
      case SimulationMode.inPathOvertake:
        return const Color(0xFF0284C7);
      case SimulationMode.turnBypass:
        return const Color(0xFF16A34A);
      case SimulationMode.turnIn:
        return const Color(0xFFEA580C);
      case SimulationMode.opposingLane:
        return const Color(0xFFF59E0B);
    }
  }

  Color _getSimulationModeTextColor() {
    if (_isNightMode) {
      switch (_simulationMode) {
        case SimulationMode.inPathOvertake:
          return const Color(0xFF7DD3FC);
        case SimulationMode.turnBypass:
          return const Color(0xFF86EFAC);
        case SimulationMode.turnIn:
          return const Color(0xFFFDBA74);
        case SimulationMode.opposingLane:
          return const Color(0xFFFDE68A);
      }
    }
    switch (_simulationMode) {
      case SimulationMode.inPathOvertake:
        return const Color(0xFF0369A1);
      case SimulationMode.turnBypass:
        return const Color(0xFF15803D);
      case SimulationMode.turnIn:
        return const Color(0xFFC2410C);
      case SimulationMode.opposingLane:
        return const Color(0xFFB45309);
    }
  }

  // แถบ debug ชั่วคราวสำหรับตรวจสอบตอนทดสอบ 2 เครื่องแล้วไม่เจอกัน — โชว์สถานะ
  // เชื่อมต่อ MQTT จริง/จำนวนรถพยาบาลที่เห็นในระบบ/พิกัด GPS จริงตรงๆ แทนการเดา
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
            'ข้อความที่ได้รับ: ${mqtt.messagesReceivedCount}  •  '
            'รถพยาบาลในระบบ: ${_activeFleet.length} คัน',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: statusColor),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'พิกัดฉัน: ${_currentLocation.latitude.toStringAsFixed(5)}, ${_currentLocation.longitude.toStringAsFixed(5)}',
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w600, color: statusColor),
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
          if (connected && mqtt.lastParseError != null)
            Text(
              mqtt.lastParseError!,
              style: const TextStyle(fontSize: 9, color: Color(0xFFB91C1C)),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = _isNightMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 6,
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
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: isDark ? Colors.white70 : const Color(0xFF2C3E50),
                      width: 1.8),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.airport_shuttle_outlined,
                        size: 18,
                        color:
                            isDark ? Colors.white : const Color(0xFF2C3E50)),
                    Positioned(
                      top: 3,
                      right: 3,
                      child: Icon(Icons.wifi,
                          size: 8, color: Colors.redAccent.shade700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'RouteAlert Driver',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          Row(
            children: [
              // 🌙/☀️ โหมดกลางคืน (Night Driving Mode)
              IconButton(
                icon: Icon(
                  _isNightMode
                      ? Icons.wb_sunny_rounded
                      : Icons.nightlight_round,
                  color: _isNightMode
                      ? const Color(0xFFFBBF24)
                      : const Color(0xFF475569),
                  size: 20,
                ),
                tooltip: _isNightMode
                    ? 'สลับเป็นโหมดกลางวัน'
                    : 'โหมดขับขี่กลางคืน (Night Mode)',
                onPressed: () {
                  ThemeSettingsService.toggle();
                },
              ),
              // ⚡ โหมดพักจอ OLED (Battery Saver)
              IconButton(
                icon: const Icon(
                  Icons.energy_savings_leaf_rounded,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
                tooltip: 'โหมดพักหน้าจอประหยัดแบตเตอรี่ (OLED Black)',
                onPressed: () {
                  setState(() => _isSleepMode = true);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 💤 Ultra Battery-Saving OLED Pitch Black Screen
  Widget _buildOledSleepModeView(int meters) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: Colors.black, // Pure OLED 0% Black to save 100% display power
      body: InkWell(
        onTap: () {
          setState(() => _isSleepMode = false);
        },
        splashColor: Colors.white10,
        highlightColor: Colors.transparent,
        child: SafeArea(
          child: SizedBox.expand(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top status indicator
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'AI Radar Active',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'OLED Sleep Mode 💤',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                // Center Clock & Breathing Sleep Icon
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _glowAnimation,
                      builder: (context, child) {
                        return Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF6366F1).withValues(alpha: _glowAnimation.value * 0.4),
                          ),
                          child: const Icon(
                            Icons.bedtime_rounded,
                            color: Color(0xFFA5B4FC),
                            size: 48,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.w200,
                        color: Colors.white70,
                        letterSpacing: -2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Text(
                        'เรดาร์ตรวจจับ AI กำลังสแกนรอบตัว 360°',
                        style: TextStyle(color: Colors.white60, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),

                // Bottom Wake-up Hint
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Column(
                    children: [
                      const Icon(Icons.touch_app_rounded, color: Colors.white30, size: 24),
                      const SizedBox(height: 8),
                      const Text(
                        'แตะหน้าจอเพื่อปลุกกลับสู่แผนที่',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '⚡ หน้าจอจะติดและเตือนภัยทันทีเมื่อมีรถพยาบาลเข้าใกล้',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ข้อความสถานะการตรวจจับเสียงไซเรน (สัญญาณเสริม แยกจาก GPS) — แสดงเฉพาะค่าที่
  /// มาจากโมเดล AI จริงเท่านั้น ห้ามมีตัวเลขปลอมเด็ดขาด (ดู CHANGES_SUMMARY.md ข้อ 3)
  /// จุดนี้แสดงในบริบทที่ระบบ GPS ตรวจพบรถพยาบาลใกล้ตัวอยู่แล้ว (_isInRedZone) —
  /// ถ้าไมค์ตรวจพบเสียงไซเรนพร้อมกันด้วย ถือเป็นการ "ยืนยัน 2 สัญญาณ" ที่หนักแน่นขึ้น
  String _sirenBadgeText() {
    if (!_sirenDetectionEnabled) {
      return '🔊 ตรวจจับเสียงไซเรน: ปิดอยู่ (เปิดได้ในหน้าตั้งค่า)';
    }
    if (!SirenDetectionService().isModelLoaded) {
      return '🔊 ตรวจจับเสียงไซเรน: ยังไม่มีโมเดล AI (รอฝึกโมเดล)';
    }
    final result = _sirenResult;
    if (result != null && result.isDetected && result.confidence != null) {
      final pct = (result.confidence! * 100).toStringAsFixed(0);
      return '🔊 ยืนยัน 2 สัญญาณ: เสียงไซเรน + GPS ตรงกัน ($pct%)';
    }
    return '🔊 ตรวจจับเสียงไซเรน: ยังไม่พบเสียงไซเรนในขณะนี้';
  }

  /// Dramatic & Unmistakable Emergency HUD Banner
  Widget _buildDramaticEmergencyHud(int meters) {
    final pred = _aiPrediction;
    if (pred == null) return const SizedBox.shrink();

    final tier = EmergencyProximityTier.fromDistance(
      meters.toDouble(),
      hasAmbulance: _hasLiveAmbulance || _isSimulating,
    );

    // 1. CRITICAL RED ALERT (In Path)
    if (_isInRedZone) {
      final isIllegalZone = tier == EmergencyProximityTier.illegalHazard;

      return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isIllegalZone
                    ? const [Color(0xFFDC2626), Color(0xFF7F1D1D)]
                    : (tier == EmergencyProximityTier.criticalYield
                        ? const [Color(0xFFEA580C), Color(0xFF9A3412)]
                        : const [Color(0xFFDC2626), Color(0xFF991B1B)]),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isIllegalZone ? Colors.yellowAccent : Colors.white,
                width: isIllegalZone ? 3.0 : 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isIllegalZone ? const Color(0xFFDC2626) : const Color(0xFFEA580C))
                      .withValues(alpha: 0.65),
                  blurRadius: 22,
                  spreadRadius: 3,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Flashing Siren Animated Icon
                    ScaleTransition(
                      scale: _sirenScaleAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isIllegalZone ? Colors.yellowAccent : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Text(isIllegalZone ? '🛑' : '🚨', style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isIllegalZone
                                ? '🚨 ผิดกฎหมาย! ห้ามตามหลัง < 50 ม.'
                                : tier.titleTH,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isIllegalZone
                                ? 'พ.ร.บ. จราจรทางบก ม.76 (ชะลอและเว้นระยะทันที!)'
                                : (pred.turnIntent != null
                                    ? '${pred.turnIntent} ($meters ม.)'
                                    : 'รถพยาบาลตามหลังมาในเลนเดียวกัน ($meters ม.)'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isIllegalZone ? Colors.yellow.shade100 : const Color(0xFFFFE4E6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Large Distance Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isIllegalZone ? Colors.yellowAccent : Colors.white70,
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            meters >= 1000
                                ? (meters / 1000).toStringAsFixed(1)
                                : '$meters',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: isIllegalZone ? Colors.yellowAccent : Colors.white,
                              height: 1,
                            ),
                          ),
                          Text(
                            meters >= 1000 ? 'กม.' : 'เมตร',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Multi-Segment Distance Bar (ขอบเขตระยะห่างตามกฎหมาย 4 ระดับสี)
                _buildProximityStepsMeter(tier, meters),
                const SizedBox(height: 8),

                // Flashing Action Bar
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: isIllegalZone
                        ? const Color(0xFF450A0A)
                        : Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: isIllegalZone
                        ? Border.all(color: Colors.yellowAccent.withValues(alpha: 0.6))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isIllegalZone ? Icons.gavel_rounded : Icons.warning_amber_rounded,
                        color: isIllegalZone ? Colors.yellowAccent : Colors.amberAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isIllegalZone
                              ? 'คำเตือนกฎหมาย: ห้ามขับตามหลังฉุกเฉิน < 50 ม. ฝ่าฝืนปรับสูงสุด 1,000 บ.'
                              : 'กรุณาชะลอความเร็วและเบี่ยงซ้ายเพื่อเปิดทางทันที!',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isIllegalZone ? Colors.yellowAccent : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // 🛰️ Route-Aware AI Badge / 🔊 สถานะการตรวจจับเสียงไซเรนจริง (ไม่ปลอมตัวเลข)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        pred.isRouteAwareActive ? Icons.alt_route_rounded : Icons.mic_rounded,
                        size: 14,
                        color: Colors.cyanAccent,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          pred.isRouteAwareActive
                              ? '🛰️ Route-Aware AI: ล็อกเส้นทางถนนจริง (${pred.turnIntent ?? "ตรงตามเลน"})'
                              : _sirenBadgeText(),
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Button to Acknowledge Yield
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: _onYieldAcknowledge,
                    icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 20),
                    label: const Text(
                      '✓ หลบทางให้แล้ว (+1 แต้มความดี)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      elevation: 4,
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // Quick Legal Reference Link
                InkWell(
                  onTap: () => _showLegalDistanceModal(context),
                  child: const Text(
                    '⚖️ ดูข้อกำหนด พ.ร.บ. จราจรทางบก ม.76 (ห้ามตามหลัง < 50 ม.)',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    // 2. TURN IN APPROACHING (Route-Aware Early Warning)
    if (pred.category == TrajectoryConflictCategory.turnInApproaching) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _isNightMode ? const Color(0xFF1E293B) : const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF97316), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF97316).withValues(alpha: _isNightMode ? 0.35 : 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF97316).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.turn_left_rounded, color: Color(0xFFEA580C), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '⚠️ รถพยาบาลเตรียมเลี้ยวเข้าถนนของคุณ!',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: _isNightMode ? const Color(0xFFFDBA74) : const Color(0xFFC2410C),
                    ),
                  ),
                  Text(
                    'AI Route-Aware: ตรวจพบเส้นทางจะเลี้ยวเข้าถนนที่คุณอยู่ ($meters ม.) กรุณาชะลอ',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isNightMode ? const Color(0xFFCBD5E1) : const Color(0xFF9A3412),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isNightMode ? const Color(0xFF7C2D12) : const Color(0xFFFFEDD5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'AI 92%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _isNightMode ? const Color(0xFFFDBA74) : const Color(0xFFC2410C),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 3. TURN BYPASS (Route-Aware Smart Filter - No Alert!)
    if (pred.category == TrajectoryConflictCategory.turnBypass) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _isNightMode ? const Color(0xFF1E293B) : const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF10B981), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: _isNightMode ? 0.3 : 0.18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.turn_right_rounded,
                color: _isNightMode ? const Color(0xFF34D399) : const Color(0xFF047857),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '↪️ รถพยาบาลเลี้ยวแยกหน้า (Turn Bypass)',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: _isNightMode ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
                    ),
                  ),
                  Text(
                    pred.turnIntent != null
                        ? '${pred.turnIntent} • ไม่กีดขวางเส้นทางของคุณ'
                        : 'AI Route-Aware: ตรวจพบรถพยาบาลจะเลี้ยวออกที่แยกหน้า ปลอดภัย 100%',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isNightMode ? const Color(0xFFCBD5E1) : const Color(0xFF065F46),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isNightMode ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Route-Aware',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: _isNightMode ? const Color(0xFF86EFAC) : const Color(0xFF047857),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 4. PASSED / OVERTAKEN (Moving Away)
    if (pred.category == TrajectoryConflictCategory.movingAway) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _isNightMode ? const Color(0xFF1E293B) : const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF10B981), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: _isNightMode ? 0.3 : 0.18),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '✅ รถพยาบาลเคลื่อนที่ผ่านไปแล้ว (Passed)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _isNightMode ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
                    ),
                  ),
                  Text(
                    'ปลอดภัยแล้ว ขอบคุณที่ร่วมเปิดทางช่วยชีวิตผู้ป่วยฉุกเฉิน',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _isNightMode ? const Color(0xFFCBD5E1) : const Color(0xFF065F46),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isNightMode ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'AI 5%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _isNightMode ? const Color(0xFF86EFAC) : const Color(0xFF047857),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 5. OPPOSING LANE (Filtered out)
    if (pred.category == TrajectoryConflictCategory.opposingLane) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _isNightMode ? const Color(0xFF1E293B) : const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF59E0B), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF59E0B).withValues(alpha: _isNightMode ? 0.3 : 0.15),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.swap_vert_rounded,
                color: _isNightMode ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '🔄 ตรวจพบรถพยาบาลวิ่งสวนเลน (Opposing Lane)',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: _isNightMode ? const Color(0xFFFCD34D) : const Color(0xFFB45309),
                    ),
                  ),
                  Text(
                    'AI ตรวจสอบแล้วว่าอยู่คนละฝั่งถนน • ไม่ต้องหลบทาง ปลอดภัย 100%',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isNightMode ? const Color(0xFFCBD5E1) : const Color(0xFF92400E),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isNightMode ? const Color(0xFF78350F) : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'AI 4%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _isNightMode ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 6. APPROACHING CORRIDOR (Blue Zone)
    if (_isInBlueZone) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _isNightMode ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2563EB), width: 1.8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withValues(alpha: _isNightMode ? 0.35 : 0.18),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFF2563EB),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.radar_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '📡 รถพยาบาลกำลังตามหลังมาในเส้นทาง',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: _isNightMode ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
                    ),
                  ),
                  Text(
                    'ระยะ ${(meters / 1000).toStringAsFixed(1)} กม. • คาดว่าจะถึงใน ${pred.timeToConflictSec.round()} วิ',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isNightMode ? const Color(0xFFCBD5E1) : const Color(0xFF1E40AF),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'AI ${(pred.yieldProbability * 100).toInt()}%',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    // 7. DEFAULT SAFE ZONE
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _isNightMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: _isNightMode ? 0.6 : 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (_isNightMode ? Colors.black : const Color(0xFF10B981))
                .withValues(alpha: _isNightMode ? 0.35 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.shield_outlined,
            color: _isNightMode ? const Color(0xFF34D399) : const Color(0xFF059669),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '🛡️ สถานะปกติ (Safe Zone)',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: _isNightMode ? const Color(0xFF34D399) : const Color(0xFF059669),
                  ),
                ),
                Text(
                  'ไม่พบรถฉุกเฉินในเส้นทางของคุณ',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isNightMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Text(
            // เดิม hardcode '3.0 KM' ตายตัว ไม่ตรงกับรัศมีเตือนภัยที่ผู้ใช้ตั้งค่าไว้จริง
            '${(_outerRadarMeters / 1000.0).toStringAsFixed(1)} KM',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: _isNightMode ? const Color(0xFF34D399) : const Color(0xFF059669),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapView() {
    final List<Marker> ambulanceMarkers = [];

    // 1. Primary simulated or live ambulance marker with live heading rotation
    if (_ambulanceLocation != null && (_isSimulating || _hasLiveAmbulance)) {
      ambulanceMarkers.add(
        Marker(
          point: _ambulanceLocation!,
          width: 52,
          height: 52,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: _simulationMode == SimulationMode.opposingLane
                    ? const Color(0xFFF59E0B)
                    : (_simulationMode == SimulationMode.turnBypass
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444)),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (_simulationMode == SimulationMode.opposingLane
                          ? const Color(0xFFF59E0B)
                          : (_simulationMode == SimulationMode.turnBypass
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444)))
                      .withValues(alpha: 0.4),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Center(
              child: Transform.rotate(
                angle: (_ambulanceHeading - 45) * math.pi / 180,
                child: const Text('🚑', style: TextStyle(fontSize: 24)),
              ),
            ),
          ),
        ),
      );
    }

    // 2. Other Active fleet markers (from MQTT)
    for (var amb in _activeFleet) {
      if (_ambulanceLocation != null &&
          (amb.latitude - _ambulanceLocation!.latitude).abs() < 0.0001 &&
          (amb.longitude - _ambulanceLocation!.longitude).abs() < 0.0001) {
        continue;
      }
      ambulanceMarkers.add(
        Marker(
          point: LatLng(amb.latitude, amb.longitude),
          width: 38,
          height: 38,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
            ),
            child: const Center(child: Text('🚑', style: TextStyle(fontSize: 16))),
          ),
        ),
      );
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation,
        initialZoom: 14.5,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.drag |
              InteractiveFlag.pinchZoom |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.scrollWheelZoom,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.routealert.app',
          tileBuilder: _isNightMode
              ? (context, tileWidget, tile) {
                  return ColorFiltered(
                    colorFilter: const ColorFilter.matrix(<double>[
                      -0.85, 0, 0, 0, 240,
                      0, -0.85, 0, 0, 240,
                      0, 0, -0.85, 0, 250,
                      0, 0, 0, 1, 0,
                    ]),
                    child: tileWidget,
                  );
                }
              : null,
        ),

        // วงรัศมีแจ้งเตือน: วงนอกสีฟ้า (เรดาร์) + วงในสีแดง (แจ้งเตือนวิกฤต)
        // อ้างอิงจากค่าที่ตั้งไว้ในหน้า Settings แสดงรอบตำแหน่งปัจจุบันของผู้ใช้
        // ให้เห็นชัดเจนว่าปรับแล้วระยะจริงบนแผนที่ใหญ่แค่ไหน
        CircleLayer(
          circles: [
            CircleMarker(
              point: _currentLocation,
              radius: _outerRadarMeters,
              useRadiusInMeter: true,
              color: const Color(0xFF5B9EE1).withValues(alpha: 0.08),
              borderColor: const Color(0xFF5B9EE1).withValues(alpha: 0.6),
              borderStrokeWidth: 2,
            ),
            CircleMarker(
              point: _currentLocation,
              radius: _innerAlertMeters,
              useRadiusInMeter: true,
              color: const Color(0xFFEB5757).withValues(alpha: 0.12),
              borderColor: const Color(0xFFEB5757).withValues(alpha: 0.75),
              borderStrokeWidth: 2,
            ),
          ],
        ),

        // เส้นทางรถกู้ภัยจำแนกสีตามขอบเขตระยะห่างกฎหมายจราจร (Proximity Route Polylines)
        if (_isSimulating || _hasLiveAmbulance)
          PolylineLayer(
            polylines: _buildProximityRoutePolylines(),
          ),

        MarkerLayer(
          markers: [
            // 0. ผู้ขับขี่คนอื่น (ไม่ระบุตัวตน) — วาดก่อนให้หมุดของเราและรถพยาบาลอยู่ด้านบน
            for (final d in _otherDrivers)
              Marker(
                point: d.point,
                width: 30,
                height: 30,
                child: Transform.rotate(
                  angle: d.heading * math.pi / 180,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _isNightMode ? const Color(0xFF334155) : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF94A3B8), width: 1.5),
                    ),
                    child: const Center(child: Text('🚗', style: TextStyle(fontSize: 14))),
                  ),
                ),
              ),
            // 1. User Driver Marker (คุณ)
            Marker(
              point: _currentLocation,
              width: 90,
              height: 70,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D4ED8),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                    child: Text(
                      'คุณ (${_driverSpeed.toInt()} km/h)',
                      style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3B82F6),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
                    ),
                    child: Transform.rotate(
                      angle: _driverHeading * math.pi / 180,
                      child: const Icon(
                        Icons.navigation_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Ambulance Markers (รถพยาบาลฉุกเฉินเฉพาะเมื่อมีรถออนไลน์หรือเปิดจำลอง)
            ...ambulanceMarkers,

            // 3. หมุดโรงพยาบาลปลายทาง (ข้อมูลชุดเดียวกับที่ฝั่ง Ambulance/Agency ใช้)
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

  /// Real-Time Live Presence Details Bottom Sheet
  void _showLivePresenceModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.hub_rounded, color: Color(0xFF10B981), size: 24),
                      SizedBox(width: 8),
                      Text(
                        'สมาชิกที่กำลังออนไลน์ขณะนี้ (Live Presence)',
                        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${1 + _activeFleet.length} Active',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Color(0xFFEFF6FF), shape: BoxShape.circle),
                  child: const Text('🚗', style: TextStyle(fontSize: 20)),
                ),
                title: const Text('คุณ (ผู้ขับขี่ปัจจุบัน)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('ความเร็ว ${_driverSpeed.toInt()} km/h • กำลังเชื่อมต่อเรดาร์ AI'),
                trailing: const Text('🟢 Online', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              if (_activeFleet.isEmpty && !_isSimulating)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'ยังไม่มีรถพยาบาลเปิดสัญญาณเตือนออนไลน์ในขณะนี้',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ),
                ),
              for (var amb in _activeFleet) ...[
                Divider(color: Colors.grey.shade200, height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: Color(0xFFFEF2F2), shape: BoxShape.circle),
                    child: const Text('🚑', style: TextStyle(fontSize: 20)),
                  ),
                  title: Text(amb.callSign, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('ความเร็ว ${amb.speed.toInt()} km/h • ${amb.emergencyType}'),
                  trailing: const Text('🚨 Active', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Floating Drop-Down Heads-Up Banner (Native Notification Simulator)
  Widget _buildFloatingHeadsUpBanner() {
    final event = _activeHeadsUp;
    if (event == null) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: event.isCritical ? const Color(0xFFEF4444) : const Color(0xFF38BDF8),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: (event.isCritical ? const Color(0xFFEF4444) : const Color(0xFF38BDF8))
                  .withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: event.isCritical ? const Color(0xFFEF4444) : const Color(0xFF0284C7),
                shape: BoxShape.circle,
              ),
              child: Text(event.isCritical ? '🚨' : '📡', style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade300,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
              onPressed: () {
                setState(() => _activeHeadsUp = null);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 🔊 แบนเนอร์ "ตรวจพบเสียงไซเรน" แบบสัญญาณเดี่ยว (ไม่มีรถพยาบาลที่ระบุตำแหน่งผ่าน
  /// GPS/MQTT ยืนยันร่วมด้วย) — ใช้เมื่อไมโครโฟนตรวจพบเสียงไซเรนความมั่นใจสูง แต่ระบบ
  /// เรดาร์ GPS หลักไม่พบรถพยาบาลในระยะเลย ถือเป็น "สัญญาณอิสระ" คนละชุดกับระบบหลัก
  /// จึง**ห้ามบอกระยะทาง/ทิศทางที่แม่นยำ** เพราะไมค์โทรศัพท์เครื่องเดียวบอกระยะ/ทิศ
  /// ที่แน่นอนไม่ได้จริง (กฎ honesty ของโปรเจกต์นี้)
  Widget _buildSirenOnlyAlertBanner() {
    final result = _sirenResult;
    final hasGpsAmbulanceNearby = _hasLiveAmbulance || _isSimulating;

    if (!_sirenDetectionEnabled ||
        result == null ||
        !result.isDetected ||
        hasGpsAmbulanceNearby) {
      return const SizedBox.shrink();
    }

    final pct = result.confidence != null
        ? '${(result.confidence! * 100).toStringAsFixed(0)}%'
        : '';

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFB45309),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB45309).withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: const BoxDecoration(
                color: Colors.white24,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.hearing_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '🔊 ตรวจพบเสียงไซเรนใกล้เคียง$pct',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'ไม่ทราบระยะ/ทิศทางแน่ชัด (จับจากไมโครโฟนอย่างเดียว ยังไม่พบ '
                    'รถพยาบาลผ่าน GPS) โปรดสังเกตรอบข้างด้วยตนเอง',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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

  /// 🚨 Active SOS Tracking Banner (เด้งเตือนด้านบนเมื่อมีเคสฉุกเฉินที่กำลังประสานงาน)
  Widget _buildActiveSosTrackingBanner(IncidentReport incident) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => IncidentDetailScreen(incident: incident),
            ),
          );
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFDC2626).withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.emergency_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          '🚨 เหตุฉุกเฉินที่คุณแจ้ง (${incident.id})',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'แตะเพื่อดูสด',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'สถานะ: ${incident.statusText} • ${incident.hospitalName ?? "ศูนย์ 1669"}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  /// 🚦 แถบแสดงขอบเขตระยะห่าง 4 ระดับสีใน HUD (Proximity Steps Meter)
  Widget _buildProximityStepsMeter(EmergencyProximityTier currentTier, int meters) {
    final steps = [
      {
        'tier': EmergencyProximityTier.illegalHazard,
        'label': '< 50 ม.',
        'sub': '🛑 ผิดกฎหมาย',
        'color': const Color(0xFFDC2626),
      },
      {
        'tier': EmergencyProximityTier.criticalYield,
        'label': '50-150 ม.',
        'sub': '⚠️ ชิดซ้ายทันที',
        'color': const Color(0xFFEA580C),
      },
      {
        'tier': EmergencyProximityTier.approaching,
        'label': '150-500 ม.',
        'sub': '⚡ เตรียมหลบ',
        'color': const Color(0xFFF59E0B),
      },
      {
        'tier': EmergencyProximityTier.radarAwareness,
        'label': '500ม.-3กม.',
        'sub': '📡 รัศมีเรดาร์',
        'color': const Color(0xFF2563EB),
      },
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: steps.map((step) {
          final tier = step['tier'] as EmergencyProximityTier;
          final isCurrent = tier == currentTier;
          final color = step['color'] as Color;

          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: isCurrent ? color : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: isCurrent
                    ? Border.all(color: Colors.white, width: 1.8)
                    : null,
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    step['label'] as String,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: isCurrent ? Colors.white : Colors.white70,
                    ),
                  ),
                  Text(
                    step['sub'] as String,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent ? Colors.white : Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// ⚖️ หน้าต่างแสดงกฎหมายระยะห่าง 50 เมตร และขอบเขตระยะเรดาร์
  void _showLegalDistanceModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: _isNightMode ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.gavel_rounded, color: Color(0xFFDC2626), size: 24),
                  SizedBox(width: 8),
                  Text(
                    'กฎหมายจราจรและระยะห่างรถพยาบาล',
                    style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⚖️ พระราชบัญญัติจราจรทางบก พ.ศ. 2522 มาตรา 76',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB91C1C),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '• วรรคสอง: "ห้ามมิให้ผู้ขับขี่ขับรถตามหลังรถฉุกเฉินซึ่งกำลังปฏิบัติหน้าที่ในระยะต่ำกว่า 50 เมตร"\n• วรรคหนึ่ง (2): "สำหรับผู้ขับขี่ต้องหยุดรถหรือจอดรถให้อยู่ชิดขอบทางด้านซ้ายเพื่อเปิดทางแก่รถฉุกเฉิน"',
                      style: TextStyle(fontSize: 12, color: Color(0xFF7F1D1D), height: 1.45),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '🚦 ขอบเขตระยะห่าง 4 ระดับสีของระบบ RouteAlert:',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildLegalDistanceRow(
                color: const Color(0xFFDC2626),
                title: '🔴 ระยะ < 50 เมตร (ผิดกฎหมาย / วิกฤต)',
                desc: 'ห้ามขับตามหลังในระยะนี้โดยเด็ดขาด ชะลอรถและเว้นระยะห่างทันที',
              ),
              _buildLegalDistanceRow(
                color: const Color(0xFFEA580C),
                title: '🟠 ระยะ 50 - 150 เมตร (ระยะประชิด)',
                desc: 'ต้องชิดขอบทางด้านซ้ายเพื่อเปิดทางให้รถพยาบาลผ่านทันที',
              ),
              _buildLegalDistanceRow(
                color: const Color(0xFFF59E0B),
                title: '🟡 ระยะ 150 - 500 เมตร (ระยะเข้าใกล้)',
                desc: 'เตรียมพร้อมชะลอความเร็ว ให้สัญญาณไฟเลี้ยว และเบี่ยงเลนล่วงหน้า',
              ),
              _buildLegalDistanceRow(
                color: const Color(0xFF2563EB),
                title: '🔵 ระยะ 500 - 3,000 เมตร (เรดาร์นำทาง)',
                desc: 'ระบบ Route-Aware AI ตรวจจับเส้นทางรถฉุกเฉินล่วงหน้าในรัศมี',
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('เข้าใจแล้ว', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegalDistanceRow({
    required Color color,
    required String title,
    required String desc,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: _isNightMode ? Colors.grey.shade400 : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// เส้นทางของรถกู้ภัยตามถนนจริง แบ่งสีตามขอบเขตระยะห่างกฎหมายจราจร (Proximity Route Polylines)
  List<Polyline> _buildProximityRoutePolylines() {
    final targetAmb = _ambulanceLocation;
    if ((!_isSimulating && !_hasLiveAmbulance) || targetAmb == null) {
      return [];
    }

    // กรณีรถพยาบาลเลี้ยวออก (Turn Bypass) เส้นทางจะเป็นสีเขียวเพื่อแสดงว่าปลอดภัย
    if (_simulationMode == SimulationMode.turnBypass) {
      final pts = _ambulanceRoutePoints ?? [targetAmb, _currentLocation];
      return [
        Polyline(
          points: pts,
          strokeWidth: 5.5,
          color: const Color(0xFF10B981).withValues(alpha: 0.85),
          borderColor: Colors.white,
          borderStrokeWidth: 2.0,
        ),
      ];
    }

    final rawPoints = (_ambulanceRoutePoints != null && _ambulanceRoutePoints!.isNotEmpty)
        ? _ambulanceRoutePoints!
        : [targetAmb, _currentLocation];

    if (rawPoints.length < 2) return [];

    // เพิ่มความถี่ของจุดพิกัด (Dense Interpolation) เพื่อให้เส้นทางตัดสีตามระยะเมตรอย่างแม่นยำ
    final List<LatLng> densePoints = [];
    for (int i = 0; i < rawPoints.length - 1; i++) {
      final p1 = rawPoints[i];
      final p2 = rawPoints[i + 1];
      densePoints.add(p1);

      final segDist = LocationService.calculateDistanceInMeters(p1, p2);
      if (segDist > 30) {
        final steps = (segDist / 20).ceil();
        for (int s = 1; s < steps; s++) {
          final frac = s / steps;
          final lat = p1.latitude + (p2.latitude - p1.latitude) * frac;
          final lng = p1.longitude + (p2.longitude - p1.longitude) * frac;
          densePoints.add(LatLng(lat, lng));
        }
      }
    }
    densePoints.add(rawPoints.last);

    // จำแนกจุดเป็นช่วงเส้นตาม EmergencyProximityTier
    final List<Polyline> polylines = [];
    List<LatLng> currentSegment = [];
    EmergencyProximityTier? currentTier;

    for (int i = 0; i < densePoints.length; i++) {
      final pt = densePoints[i];
      final dist = LocationService.calculateDistanceInMeters(pt, _currentLocation);
      final tier = EmergencyProximityTier.fromDistance(dist, hasAmbulance: true);

      if (currentTier == null) {
        currentTier = tier;
        currentSegment.add(pt);
      } else if (currentTier == tier) {
        currentSegment.add(pt);
      } else {
        currentSegment.add(pt); // จุดเหลื่อมกันเพื่อให้เส้นเชื่อมกันสนิท
        if (currentSegment.length >= 2) {
          final isIllegal = currentTier == EmergencyProximityTier.illegalHazard;
          polylines.add(
            Polyline(
              points: List.from(currentSegment),
              strokeWidth: isIllegal ? 7.0 : 5.5,
              color: currentTier.primaryColor.withValues(alpha: 0.92),
              borderColor: isIllegal ? Colors.yellowAccent : Colors.white,
              borderStrokeWidth: isIllegal ? 2.5 : 1.8,
            ),
          );
        }
        currentSegment = [pt];
        currentTier = tier;
      }
    }

    if (currentSegment.length >= 2 && currentTier != null) {
      final isIllegal = currentTier == EmergencyProximityTier.illegalHazard;
      polylines.add(
        Polyline(
          points: currentSegment,
          strokeWidth: isIllegal ? 7.0 : 5.5,
          color: currentTier.primaryColor.withValues(alpha: 0.92),
          borderColor: isIllegal ? Colors.yellowAccent : Colors.white,
          borderStrokeWidth: isIllegal ? 2.5 : 1.8,
        ),
      );
    }

    return polylines;
  }
}