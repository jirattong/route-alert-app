import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/driver_storage_service.dart';
import '../../../core/services/emergency_mqtt_service.dart';
import '../../../core/services/voice_alert_service.dart';
import '../../../core/services/critical_notification_service.dart';

class DriverHomeScreen extends StatefulWidget {
  final VoidCallback? onOpenSos;

  const DriverHomeScreen({
    super.key,
    this.onOpenSos,
  });

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();

  LatLng _currentLocation = const LatLng(19.0284, 99.8962);
  bool _isLoadingGps = true;

  late LatLng _ambulanceLocation;
  late LatLng _initialAmbulanceLocation;

  // หน่วยเมตรทั้งหมด
  double _outerRadarMeters = 1500.0;
  double _innerAlertMeters = 400.0;
  bool _isBackgroundActive = true;

  double _currentDistanceMeters = 99999.0;
  bool _isInBlueZone = false;
  bool _isInRedZone = false;
  bool _hasVibrated = false;

  StreamSubscription<LatLng>? _locationSubscription;
  StreamSubscription<EmergencyVehicleData>? _mqttSubscription;
  Timer? _simulationTimer;
  bool _isSimulating = false;

  late AnimationController _pulseController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _ambulanceLocation = const LatLng(19.0480, 99.9150);
    _initialAmbulanceLocation = _ambulanceLocation;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.12, end: 0.45).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _listenToSettingsChanges();
    _initLiveLocation();
    _initMqttRadar();
  }

  void _initMqttRadar() async {
    await EmergencyMqttService().initialize();
    _mqttSubscription = EmergencyMqttService().emergencyStream.listen((data) {
      if (!mounted) return;
      setState(() {
        _ambulanceLocation = LatLng(data.latitude, data.longitude);
      });
      _checkGeofence();
    });
  }

  void _listenToSettingsChanges() {
    final current = DriverStorageService.settingsNotifier.value;
    _outerRadarMeters = current['outerMeters'] ?? 1500.0;
    _innerAlertMeters = current['innerMeters'] ?? 400.0;
    _isBackgroundActive = current['background'] ?? true;

    DriverStorageService.settingsNotifier.addListener(() {
      if (!mounted) return;
      final val = DriverStorageService.settingsNotifier.value;
      setState(() {
        _outerRadarMeters = val['outerMeters'] ?? 1500.0;
        _innerAlertMeters = val['innerMeters'] ?? 400.0;
        _isBackgroundActive = val['background'] ?? true;
      });
      _checkGeofence();
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mqttSubscription?.cancel();
    _simulationTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initLiveLocation() async {
    final initialPos = await LocationService.getCurrentLocation();
    if (initialPos != null && mounted) {
      setState(() {
        _currentLocation = initialPos;
        _isLoadingGps = false;
        // จัดให้รถพยาบาลอยู่นอกวงเรดาร์เริ่มต้น
        _ambulanceLocation = LatLng(
          initialPos.latitude + 0.022,
          initialPos.longitude + 0.022,
        );
        _initialAmbulanceLocation = _ambulanceLocation;
      });
      _mapController.move(_currentLocation, 14.0);
      _checkGeofence();
    } else {
      if (mounted) setState(() => _isLoadingGps = false);
      _checkGeofence();
    }

    _locationSubscription =
        LocationService.getLiveLocationStream().listen((newPos) {
      if (!mounted) return;
      setState(() => _currentLocation = newPos);
      _checkGeofence();
    });
  }

  void _toggleSimulation() {
    if (_isSimulating) {
      _simulationTimer?.cancel();
      setState(() => _isSimulating = false);
    } else {
      setState(() {
        _isSimulating = true;
        _hasVibrated = false;
      });

      _simulationTimer =
          Timer.periodic(const Duration(milliseconds: 600), (timer) {
        if (!mounted) return;

        double latDiff =
            _currentLocation.latitude - _ambulanceLocation.latitude;
        double lngDiff =
            _currentLocation.longitude - _ambulanceLocation.longitude;

        if (latDiff.abs() < 0.00008 && lngDiff.abs() < 0.00008) {
          timer.cancel();
          setState(() => _isSimulating = false);
          return;
        }

        setState(() {
          _ambulanceLocation = LatLng(
            _ambulanceLocation.latitude + (latDiff * 0.07),
            _ambulanceLocation.longitude + (lngDiff * 0.07),
          );
        });

        _checkGeofence();
      });
    }
  }

  void _resetSimulation() {
    _simulationTimer?.cancel();
    setState(() {
      _isSimulating = false;
      _hasVibrated = false;
      _ambulanceLocation = _initialAmbulanceLocation;
    });
    _checkGeofence();
  }

  void _checkGeofence() {
    // คำนวณระยะห่างเป็นหน่วยเมตรอย่างแม่นยำ
    final meters = LocationService.calculateDistanceInMeters(
      _currentLocation,
      _ambulanceLocation,
    );

    final inBlue = meters <= _outerRadarMeters;
    final inRed = meters <= _innerAlertMeters;

    if (inRed && !_hasVibrated) {
      _hasVibrated = true;
      HapticFeedback.heavyImpact();
      VoiceAlertService().speakRedAlert();
      CriticalNotificationService().showRadarAlert(
        title: '🚨 คำเตือนฉุกเฉินระดับวิกฤต!',
        body: 'รถพยาบาลกำลังเข้าใกล้ในระยะ ${meters.toInt()} เมตร โปรดชะลอความเร็วและเปิดทาง',
        isCritical: true,
      );
    } else if (inBlue && !_isInBlueZone && !inRed) {
      VoiceAlertService().speakOuterRadarAlert();
      CriticalNotificationService().showRadarAlert(
        title: '📡 สัญญาณเรดาร์ตรวจพบรถฉุกเฉิน',
        body: 'มีรถพยาบาลปฏิบัติการในรัศมี ${(meters / 1000).toStringAsFixed(1)} กม.',
        isCritical: false,
      );
    } else if (!inBlue) {
      _hasVibrated = false;
    }

    setState(() {
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
          content: Text('🎉 บันทึกสถิติการเปิดทางช่วยเหลือสำเร็จ (+1 แต้ม)'),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 2),
        ),
      );
      _resetSimulation();
    }
  }

  @override
  Widget build(BuildContext context) {
    int displayMeters = _currentDistanceMeters.round();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Stack(
                children: [
                  _buildMapView(),

                  if (_isLoadingGps)
                    Container(
                      color: Colors.black26,
                      child: const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFF5B9EE1)),
                      ),
                    ),

                  // 1. แสงเตือนรอบขอบจอเมื่อเข้าสู่วงในสีแดง
                  if (_isInRedZone)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _glowAnimation,
                          builder: (context, child) {
                            return Container(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  center: Alignment.center,
                                  radius: 0.9,
                                  colors: [
                                    Colors.transparent,
                                    const Color(0xFFEB5757)
                                        .withValues(alpha: _glowAnimation.value),
                                  ],
                                  stops: const [0.6, 1.0],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  // 2. ป้ายแจ้งเตือนด้านบน (แสดงเมื่อเข้าสู่วงฟ้า)
                  if (_isInBlueZone)
                    Positioned(
                      top: 14,
                      left: 16,
                      right: 16,
                      child: _buildModernAlertBanner(
                          displayMeters, _isInRedZone),
                    ),

                  // 3. ปุ่ม SOS ขวาล่าง
                  Positioned(
                    right: 20,
                    bottom: 84,
                    child: InkWell(
                      onTap: widget.onOpenSos,
                      borderRadius: BorderRadius.circular(35),
                      child: Container(
                        width: 66,
                        height: 66,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFFEB5757), width: 3),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  const Color(0xFFEB5757).withValues(alpha: 0.35),
                              blurRadius: 14,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            'SOS',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFEB5757),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 4. แถบสวิตช์ทำงานเบื้องหลัง
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: const Color(0xFF5B9EE1), width: 1.6),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF5B9EE1).withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'ทำงานเบื้องหลัง',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              Text(
                                '(Background)',
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

                  // 5. ปุ่มจำลองรถพยาบาลวิ่ง
                  Positioned(
                    top: 14,
                    right: 14,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _isSimulating
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_fill,
                              color: _isSimulating
                                  ? const Color(0xFFEF4444)
                                  : Colors.orange,
                              size: 30,
                            ),
                            onPressed: _toggleSimulation,
                            tooltip: 'จำลองรถวิ่งเข้าหา',
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded, size: 22),
                            onPressed: _resetSimulation,
                            tooltip: 'รีเซ็ตพิกัดรถพยาบาล',
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF2C3E50), width: 1.8),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.airport_shuttle_outlined,
                    size: 18, color: Color(0xFF2C3E50)),
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
          const Text(
            'RouteAlert',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernAlertBanner(int meters, bool isCritical) {
    Color themeColor =
        isCritical ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
    Color bgColor =
        isCritical ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB);

    return InkWell(
      onTap: _onYieldAcknowledge,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: themeColor.withValues(alpha: 0.8), width: 1.8),
          boxShadow: [
            BoxShadow(
              color: themeColor.withValues(alpha: 0.25),
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: themeColor.withValues(alpha: 0.3)),
              ),
              child: Icon(
                isCritical
                    ? Icons.warning_rounded
                    : Icons.notifications_active_rounded,
                color: themeColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isCritical
                        ? 'มีรถพยาบาลฉุกเฉินใกล้ถึง!'
                        : 'ตรวจพบรถพยาบาลในรัศมี',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: themeColor,
                    ),
                  ),
                  const Text(
                    'แตะเมื่อหลบทางแล้ว (+1 แต้ม)',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: themeColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    meters >= 1000
                        ? (meters / 1000).toStringAsFixed(1)
                        : '$meters',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                  Text(
                    meters >= 1000 ? 'KM' : 'M',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                      height: 1,
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

  Widget _buildMapView() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation,
        initialZoom: 14.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.routealert.app',
        ),

        // วงกลม Geofence อิงหน่วยเมตร (useRadiusInMeter: true)
        CircleLayer(
          circles: [
            // วงนอกสีฟ้า
            CircleMarker(
              point: _currentLocation,
              radius: _outerRadarMeters,
              useRadiusInMeter: true,
              color: const Color(0xFF5B9EE1).withValues(alpha: 0.08),
              borderColor: const Color(0xFF5B9EE1).withValues(alpha: 0.45),
              borderStrokeWidth: 1.6,
            ),
            // วงในสีแดง
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
            Marker(
              point: _currentLocation,
              width: 44,
              height: 44,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF5B9EE1).withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3B82F6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.navigation_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ),
            Marker(
              point: _ambulanceLocation,
              width: 44,
              height: 44,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFEF4444), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text('🚑', style: TextStyle(fontSize: 20)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}