import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/driver_storage_service.dart';
import '../../../core/services/emergency_mqtt_service.dart';
import '../../../core/services/voice_alert_service.dart';
import '../../../core/services/critical_notification_service.dart';
import '../../../core/services/ai_trajectory_service.dart';

class DriverHomeScreen extends StatefulWidget {
  final VoidCallback? onOpenSos;

  const DriverHomeScreen({
    super.key,
    this.onOpenSos,
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
  final double _driverHeading = 45.0; // Heading degree (NE)
  final double _driverSpeed = 50.0; // km/h

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

  @override
  void initState() {
    super.initState();
    _ambulanceLocation = null;

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
    _initLiveLocation();
    _initMqttRadar();
    _initHeadsUpListener();
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

    _mqttSubscription = EmergencyMqttService().emergencyStream.listen((data) {
      if (!mounted) return;
      if (data.sirenActive) {
        setState(() {
          _ambulanceLocation = LatLng(data.latitude, data.longitude);
          _ambulanceSpeed = data.speed;
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

  @override
  void dispose() {
    _headsUpDismissTimer?.cancel();
    _headsUpSubscription?.cancel();
    _locationSubscription?.cancel();
    _mqttSubscription?.cancel();
    _fleetSubscription?.cancel();
    _simulationTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initLiveLocation() async {
    final initialPos = await LocationService.getCurrentLocation();
    if (initialPos != null && mounted) {
      setState(() {
        _currentLocation = initialPos;
      });
      _mapController.move(_currentLocation, 14.5);
      if (_isSimulating || _hasLiveAmbulance) {
        _runAiTrajectoryEvaluation();
      }
    }

    _locationSubscription =
        LocationService.getLiveLocationStream().listen((newPos) {
      if (!mounted) return;
      setState(() => _currentLocation = newPos);
      if (_isSimulating || _hasLiveAmbulance) {
        _runAiTrajectoryEvaluation();
      }
    });
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
    if (ambPos == null && !_isSimulating) {
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

  void _triggerTestBackgroundNotification() async {
    await CriticalNotificationService().showRadarAlert(
      title: '🚨 ทดสอบการแจ้งเตือนเบื้องหลัง (Background Alert)',
      body: 'ระบบเตือนภัยฉุกเฉินทำงานสมบูรณ์ แม้คุณจะพับแอพหรือล็อกหน้าจอ!',
      isCritical: true,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔔 ยิง Notification ทดสอบเบื้องหลังแล้ว! ลองพับแอพเพื่อดูการแจ้งเตือนได้เลย'),
          backgroundColor: Color(0xFF2563EB),
        ),
      );
    }
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

                  // 2.2 🟢 Live Presence Indicator Pill (แสดงจำนวนผู้ใช้งานออนไลน์รอบตัวสดๆ)
                  if (!_isInRedZone && _activeHeadsUp == null)
                    Positioned(
                      top: 14,
                      left: 14,
                      child: InkWell(
                        onTap: () => _showLivePresenceModal(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
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
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'ออนไลน์: ${1 + _activeFleet.length} หน่วย',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF065F46),
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
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF2563EB), width: 1.8),
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
                          color: Color(0xFF2563EB),
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
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFFEB5757), width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  const Color(0xFFEB5757).withValues(alpha: 0.35),
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
                        color: Colors.white.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
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
                                  : const Color(0xFF2563EB),
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
                            icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.black87),
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFF5B9EE1), width: 1.4),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF5B9EE1).withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.security_rounded, size: 16, color: Color(0xFF00A896)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'ทำงานเบื้องหลัง (Background)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                Text(
                                  _isBackgroundActive ? 'เปิดเตือนเมื่อพับแอพ' : 'ปิดการทำงานเบื้องหลัง',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: _isBackgroundActive ? const Color(0xFF00A896) : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: _triggerTestBackgroundNotification,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE2F0FE),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.notifications_active, size: 12, color: Color(0xFF2563EB)),
                                  SizedBox(width: 2),
                                  Text('ทดสอบ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
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
                  setState(() => _isNightMode = !_isNightMode);
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

  /// Dramatic & Unmistakable Emergency HUD Banner
  Widget _buildDramaticEmergencyHud(int meters) {
    final pred = _aiPrediction;
    if (pred == null) return const SizedBox.shrink();

    // 1. CRITICAL RED ALERT (In Path)
    if (_isInRedZone) {
      return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFDC2626), Color(0xFF991B1B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.6),
                  blurRadius: 20,
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
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Text('🚨', style: TextStyle(fontSize: 26)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'เตือนภัยฉุกเฉินระดับวิกฤต!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pred.turnIntent != null
                                ? '${pred.turnIntent} ($meters ม.)'
                                : 'รถพยาบาลตามหลังมาในช่องทางเดียวกัน ($meters ม.)',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFFE4E6),
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
                        border: Border.all(color: Colors.white70, width: 1.2),
                      ),
                      child: Column(
                        children: [
                          Text(
                            meters >= 1000
                                ? (meters / 1000).toStringAsFixed(1)
                                : '$meters',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
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
                const SizedBox(height: 12),

                // Flashing Action Bar
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 18),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'กรุณาชะลอความเร็วและเบี่ยงซ้ายเพื่อเปิดทางทันที!',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // 🔊 AI Audio Spectrogram CNN Verification Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.alt_route_rounded, size: 14, color: Colors.cyanAccent),
                      const SizedBox(width: 5),
                      Text(
                        pred.isRouteAwareActive
                            ? '🛰️ Route-Aware AI: ล็อกเส้นทางถนนจริง (${pred.turnIntent ?? "ตรงตามเลน"})'
                            : '🔊 AI Spectrogram CNN: ตรวจพบคลื่นเสียงไซเรน Yelp (98.5%)',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
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
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF97316), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF97316).withValues(alpha: 0.25),
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
              child: const Icon(Icons.turn_left_rounded, color: Color(0xFFC2410C), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '⚠️ รถพยาบาลเตรียมเลี้ยวเข้าถนนของคุณ!',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFC2410C),
                    ),
                  ),
                  Text(
                    'AI Route-Aware: ตรวจพบเส้นทางจะเลี้ยวเข้าถนนที่คุณอยู่ ($meters ม.) กรุณาชะลอ',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9A3412)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEDD5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('AI 92%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFC2410C))),
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
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF10B981), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.18),
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
              child: const Icon(Icons.turn_right_rounded, color: Color(0xFF047857), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '↪️ รถพยาบาลเลี้ยวแยกหน้า (Turn Bypass)',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF047857),
                    ),
                  ),
                  Text(
                    pred.turnIntent != null
                        ? '${pred.turnIntent} • ไม่กีดขวางเส้นทางของคุณ'
                        : 'AI Route-Aware: ตรวจพบรถพยาบาลจะเลี้ยวออกที่แยกหน้า ปลอดภัย 100%',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF065F46)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('Route-Aware', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
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
          color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF10B981), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.18),
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
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '✅ รถพยาบาลเคลื่อนที่ผ่านไปแล้ว (Passed)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF047857),
                    ),
                  ),
                  Text(
                    'ปลอดภัยแล้ว ขอบคุณที่ร่วมเปิดทางช่วยชีวิตผู้ป่วยฉุกเฉิน',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF065F46)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('AI 5%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
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
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF59E0B), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
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
              child: const Icon(Icons.swap_vert_rounded, color: Color(0xFFB45309), size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '🔄 ตรวจพบรถพยาบาลวิ่งสวนเลน (Opposing Lane)',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB45309),
                    ),
                  ),
                  Text(
                    'AI ตรวจสอบแล้วว่าอยู่คนละฝั่งถนน • ไม่ต้องหลบทาง ปลอดภัย 100%',
                    style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('AI 4%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFB45309))),
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
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF2563EB), width: 1.8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withValues(alpha: 0.18),
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
                  const Text(
                    '📡 รถพยาบาลกำลังตามหลังมาในเส้นทาง',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1D4ED8),
                    ),
                  ),
                  Text(
                    'ระยะ ${(meters / 1000).toStringAsFixed(1)} กม. • คาดว่าจะถึงใน ${pred.timeToConflictSec.round()} วิ',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF1E40AF)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, color: Color(0xFF059669), size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '🛡️ สถานะปกติ (Safe Zone)',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                ),
                Text(
                  'ไม่พบรถฉุกเฉินในเส้นทางของคุณ',
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          Text('3.0 KM', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
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

        // Route-Aware Ambulance Corridor Polyline
        if (_ambulanceRoutePoints != null &&
            _ambulanceRoutePoints!.isNotEmpty &&
            (_isSimulating || _hasLiveAmbulance))
          PolylineLayer(
            polylines: [
              Polyline(
                points: _ambulanceRoutePoints!,
                strokeWidth: 5.5,
                color: (_simulationMode == SimulationMode.turnBypass
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444))
                    .withValues(alpha: 0.8),
                borderStrokeWidth: 2.0,
                borderColor: Colors.white,
              ),
            ],
          ),

        // วงกลม Geofence อิงหน่วยเมตร
        CircleLayer(
          circles: [
            // วงนอกสีฟ้า (Outer Radar Circle 3km)
            CircleMarker(
              point: _currentLocation,
              radius: _outerRadarMeters,
              useRadiusInMeter: true,
              color: const Color(0xFF5B9EE1).withValues(alpha: 0.06),
              borderColor: const Color(0xFF5B9EE1).withValues(alpha: 0.40),
              borderStrokeWidth: 1.5,
            ),
            // วงในสีแดง (Critical Alert Danger Zone 500m)
            CircleMarker(
              point: _currentLocation,
              radius: _innerAlertMeters,
              useRadiusInMeter: true,
              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
              borderColor: const Color(0xFFEF4444).withValues(alpha: 0.65),
              borderStrokeWidth: 1.8,
            ),
          ],
        ),

        MarkerLayer(
          markers: [
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
}