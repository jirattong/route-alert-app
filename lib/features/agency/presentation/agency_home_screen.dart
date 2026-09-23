import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../../../core/models/incident_report.dart';
import '../../../core/services/agency_storage_service.dart';
import '../../../core/services/emergency_mqtt_service.dart';
import '../../../core/services/hospital_location_service.dart';
import '../../../core/services/incident_service.dart';
import '../../../core/services/voice_alert_service.dart';
import 'agency_incident_detail_screen.dart';

class AgencyHomeScreen extends StatefulWidget {
  /// เรียกครั้งเดียวตอน initState เพื่อส่งฟังก์ชันเปิด Coach Mark ขึ้นไปให้
  /// AgencyMainScreen เก็บไว้ — ใช้ตอนผู้ใช้กด "สอนการใช้งานปุ่มต่างๆ" จากหน้า
  /// ตั้งค่า (คนละหน้ากับหน้านี้ แต่ยังอยู่ใน IndexedStack เดียวกัน)
  final ValueChanged<VoidCallback>? onCoachMarkReady;

  const AgencyHomeScreen({super.key, this.onCoachMarkReady});

  @override
  State<AgencyHomeScreen> createState() => _AgencyHomeScreenState();
}

class _AgencyHomeScreenState extends State<AgencyHomeScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  late LatLng _hospitalLocation;
  late HospitalProfile _hospitalProfile;

  // Active Ambulances List (with live MQTT sync)
  final List<Map<String, dynamic>> _activeAmbulances = [];
  Map<String, dynamic>? _selectedAmbulance;

  // Real-time Incidents list from Driver SOS
  List<IncidentReport> _incidents = [];
  bool _showHotspotHeatmap = false;

  // เคสที่ผู้ใช้กดปิดแบนเนอร์แจ้งเตือนไปแล้ว (ไม่ลบเคสออกจากระบบ แค่ไม่โผล่
  // แบนเนอร์เด่นซ้ำอีก ยังกดเข้าไปจัดการจากรายการเคสได้ตามปกติเสมอ — กันไม่ให้
  // แบนเนอร์ค้างบังหน้าจอตอนมีหลายเคสพร้อมกัน)
  final Set<String> _dismissedBannerIds = {};

  // เดิมการตั้งค่า "เสียงแจ้งเตือน"/"หน้าจอกะพริบแจ้งเตือน" ในหน้าตั้งค่าฝั่ง
  // agency บันทึกค่าได้จริง แต่ไม่มีอะไรอ่านไปใช้งานจริงเลยสักจุด (ตั้งค่าไว้ก็
  // ไม่มีผลอะไร) — เพิ่มการตรวจจับ "เคสใหม่ที่เพิ่งโผล่มา" ตรงนี้ แล้วเล่นเสียง/
  // กะพริบจอจริงตามค่าที่ตั้งไว้ ไม่ใช่แค่มีสวิตช์ประดับ
  Set<String> _knownIncidentIds = {};
  bool _hasLoadedInitialIncidents = false;
  late final AnimationController _flashController;

  StreamSubscription<HospitalProfile>? _profileSub;
  StreamSubscription<List<EmergencyVehicleData>>? _mqttSub;
  StreamSubscription<List<IncidentReport>>? _incidentSub;

  // Coach Mark: ชี้ตำแหน่งปุ่มจริงบนหน้าจอพร้อมคำอธิบาย — เรียกแบบ manual เท่านั้น
  // จากปุ่ม "สอนการใช้งานปุ่มต่างๆ" ในหน้าตั้งค่า (ผ่าน widget.onCoachMarkReady)
  final GlobalKey _keyHotspotToggle = GlobalKey();
  final GlobalKey _keyErToggle = GlobalKey();

  @override
  void initState() {
    super.initState();
    _hospitalProfile = HospitalLocationService().currentProfile;
    _hospitalLocation = _hospitalProfile.location;
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _initHospitalProfile();
    _initLiveMqttFleet();
    _initIncidentStream();
    // ส่งฟังก์ชันเปิด Coach Mark ขึ้นไปให้ AgencyMainScreen เก็บไว้ — ไม่โชว์เองอัตโนมัติ
    // อีกต่อไป (ย้ายไปเป็นปุ่ม "สอนการใช้งานปุ่มต่างๆ" ในหน้าตั้งค่าแทน ตามที่ผู้ใช้ขอ)
    widget.onCoachMarkReady?.call(_showCoachMark);
  }

  // แสดงคำแนะนำปุ่มแบบชี้ตำแหน่งจริง (Coach Mark) — เรียกได้ตลอดเวลาจากปุ่ม
  // "สอนการใช้งานปุ่มต่างๆ" ในหน้าตั้งค่า (ไม่ผูกกับ "เคยดูแล้วหรือยัง" อีกต่อไป
  // เพราะเป็นการเปิดดูตามใจผู้ใช้เอง ไม่ใช่การโชว์อัตโนมัติครั้งแรก)
  void _showCoachMark() {
    if (!mounted) return;
    final targets = [
      TargetFocus(
        identify: 'hotspot_toggle',
        keyTarget: _keyHotspotToggle,
        shape: ShapeLightFocus.Circle,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            child: _buildCoachMarkText(
              'จุดเสี่ยงอุบัติเหตุ (Hotspot)',
              'เปิด/ปิดแผนที่ความหนาแน่นจุดเกิดเหตุสะสม ช่วยดูพื้นที่เสี่ยงในภาพรวม',
            ),
          ),
        ],
      ),
      TargetFocus(
        identify: 'er_toggle',
        keyTarget: _keyErToggle,
        shape: ShapeLightFocus.RRect,
        radius: 12,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            child: _buildCoachMarkText(
              'สถานะห้องฉุกเฉิน (ER)',
              'กดเพื่ออัปเดตว่าห้อง ER พร้อมรับผู้ป่วยหรือเต็ม — มีผลต่อการเลือก รพ. ปลายทางของระบบจริง',
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

  void _initHospitalProfile() async {
    await HospitalLocationService().initialize();
    _profileSub = HospitalLocationService().profileStream.listen((profile) {
      if (!mounted) return;
      setState(() {
        _hospitalProfile = profile;
        _hospitalLocation = profile.location;
      });
    });
  }

  void _initIncidentStream() async {
    await IncidentService().initialize();
    final initial = await IncidentService().getLocalIncidents();
    // เคสที่มีอยู่แล้วตอนเปิดหน้าครั้งแรกไม่นับเป็น "เคสใหม่" (ไม่งั้นเปิดแอปทีไร
    // จะโดนแจ้งเตือนเสียง/กะพริบจอทุกเคสเก่าที่ค้างอยู่ในระบบทันที)
    _knownIncidentIds = initial.map((i) => i.id).toSet();
    _hasLoadedInitialIncidents = true;
    if (mounted) {
      setState(() => _incidents = initial);
    }
    _incidentSub = IncidentService().incidentsStream.listen((list) {
      if (!mounted) return;
      _handleNewIncidentAlerts(list);
      setState(() => _incidents = list);
    });
  }

  void _handleNewIncidentAlerts(List<IncidentReport> list) {
    if (!_hasLoadedInitialIncidents) return;
    final currentIds = list.map((i) => i.id).toSet();
    final newlyArrivedPending = list.where((i) =>
        i.status == 'pending' && !_knownIncidentIds.contains(i.id));
    _knownIncidentIds = currentIds;

    if (newlyArrivedPending.isEmpty) return;

    final settings = AgencyStorageService.settingsNotifier.value;
    if (settings['voiceAnnouncement'] as bool? ?? true) {
      VoiceAlertService().speakNewIncidentAlert();
    }
    if (settings['screenFlashAlert'] as bool? ?? true) {
      _flashController.forward(from: 0);
    }
  }

  // ใช้ activeFleetStream (Stream<List<EmergencyVehicleData>>) จาก
  // EmergencyMqttService แทนการฟัง emergencyStream ดิบแล้วสะสมเองทีละคัน
  // เพราะ activeFleetStream สะท้อนรายการกองเรือ "ปัจจุบันจริง" เสมอ —
  // เมื่อรถถูก purge ออก (ปิดสัญญาณไซเรน หรือหมดเวลา stale เกิน 12 วิ)
  // service จะตัดออกจากลิสต์ที่ส่งมาให้เอง ทำให้หน้านี้ไม่ต้องดูแล
  // การลบเองอีกต่อหนึ่ง (เดิมมีแต่ add/update ไม่เคย remove เลย)
  void _initLiveMqttFleet() async {
    await EmergencyMqttService().initialize();
    _mqttSub = EmergencyMqttService().activeFleetStream.listen((fleet) {
      if (!mounted) return;

      setState(() {
        // เก็บ isPrepared เดิมของแต่ละคันไว้ (local UI state ไม่ได้มาจาก MQTT)
        final previousPrepared = <String, bool>{
          for (final a in _activeAmbulances)
            a['id'] as String: (a['isPrepared'] ?? false) as bool,
        };

        _activeAmbulances
          ..clear()
          ..addAll(fleet.map((data) {
            final distanceMeters =
                EmergencyMqttService.calculateDistanceInMeters(
              _hospitalLocation,
              LatLng(data.latitude, data.longitude),
            );

            final distanceKm = (distanceMeters / 1000).toStringAsFixed(2);
            final estimatedMinutes =
                (distanceMeters / 600).clamp(1, 60).round();

            return {
              'id': data.id,
              'plate': data.callSign,
              'callSign': data.callSign,
              'location': LatLng(data.latitude, data.longitude),
              'status': data.sirenActive
                  ? 'เปิดสัญญาณไซเรนฉุกเฉิน (กำลังนำส่ง)'
                  : 'ปฏิบัติการปกติ',
              'distance': '$distanceKm KM',
              'distanceMeters': distanceMeters,
              'eta': '$estimatedMinutes นาที',
              'speed': '${data.speed.toStringAsFixed(0)} km/h',
              'emergencyType': data.emergencyType,
              'sirenActive': data.sirenActive,
              'routePoints': data.routePoints,
              'turnIntent': data.turnIntent,
              'isPrepared': previousPrepared[data.id] ?? false,
            };
          }));

        if (_selectedAmbulance != null) {
          final stillExists = _activeAmbulances.firstWhere(
            (a) => a['id'] == _selectedAmbulance!['id'],
            orElse: () => <String, dynamic>{},
          );
          _selectedAmbulance =
              stillExists.isNotEmpty ? stillExists : null;
        }
      });
    });
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _mqttSub?.cancel();
    _incidentSub?.cancel();
    _flashController.dispose();
    super.dispose();
  }

  // --- Modal สำหรับปักหมุดเลือก/แก้ไขตำแหน่งโรงพยาบาล ---
  void _showHospitalPinPickerModal() {
    LatLng tempPin = _hospitalLocation;
    final nameCtrl = TextEditingController(text: _hospitalProfile.hospitalName);
    final phoneCtrl = TextEditingController(text: _hospitalProfile.erPhone);
    final addrCtrl = TextEditingController(text: _hospitalProfile.address);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // Top Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '📍 ปักหมุดตำแหน่งโรงพยาบาล',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              'แตะบนแผนที่เพื่อย้ายจุดตั้งถาวร (ซิงค์ทุกเครื่อง)',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),

                  // Mini Map for Pinning
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        FlutterMap(
                          options: MapOptions(
                            initialCenter: tempPin,
                            initialZoom: 15.0,
                            onTap: (_, point) {
                              setModalState(() => tempPin = point);
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.routealert.app',
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: tempPin,
                                  width: 60,
                                  height: 60,
                                  child: const Center(
                                    child: Icon(
                                      Icons.location_on_rounded,
                                      size: 52,
                                      color: Color(0xFF00A896),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Positioned(
                          top: 12,
                          left: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              'พิกัดที่เลือก: ${tempPin.latitude.toStringAsFixed(5)}, ${tempPin.longitude.toStringAsFixed(5)}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Profile Input Fields
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: nameCtrl,
                          decoration: InputDecoration(
                            labelText: 'ชื่อโรงพยาบาล / ศูนย์สั่งการ',
                            prefixIcon: const Icon(Icons.local_hospital_rounded,
                                color: Color(0xFF00A896)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: phoneCtrl,
                          decoration: InputDecoration(
                            labelText: 'เบอร์สายด่วนห้องฉุกเฉิน (ER Hotline)',
                            prefixIcon: const Icon(Icons.phone_in_talk_rounded,
                                color: Color(0xFF00A896)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await HospitalLocationService().updatePinnedLocation(
                                newLocation: tempPin,
                                hospitalName: nameCtrl.text.trim(),
                                erPhone: phoneCtrl.text.trim(),
                                address: addrCtrl.text.trim(),
                              );
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('✅ บันทึกและซิงค์พิกัดโรงพยาบาลสู่ทุกเครื่องสำเร็จ'),
                                    backgroundColor: Color(0xFF00A896),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.save_rounded, color: Colors.white),
                            label: const Text(
                              '💾 บันทึกและซิงค์พิกัด รพ. ทันที',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00A896),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check for critical approaching ambulances (< 1.5 km and transporting)
    Map<String, dynamic>? approachingAmb;
    for (var a in _activeAmbulances) {
      final double distMeters = (a['distanceMeters'] as num?)?.toDouble() ?? 99999;
      if (distMeters <= 1500 && (a['sirenActive'] == true)) {
        approachingAmb = a;
        break;
      }
    }

    // Check for incoming pending incidents
    final pendingIncidents = _incidents.where((i) => i.status == 'pending').toList();
    // เคสที่ยังไม่ถูกกดปิดแบนเนอร์ — ตัวนับใน fleet stats bar ยังใช้ pendingIncidents
    // เต็มจำนวนเสมอ (ปิดแบนเนอร์ไม่ได้แปลว่าเคสหายไป) แต่แบนเนอร์เด่นด้านบนโชว์แค่
    // เคสที่ยังไม่ถูกปิดเท่านั้น
    final visiblePendingIncidents = pendingIncidents
        .where((i) => !_dismissedBannerIds.contains(i.id))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFleetStatsBar(pendingIncidents.length),
            Expanded(
              child: Stack(
                children: [
                  _buildMapView(),

                  // 1. Approaching Hospital Critical Alert Banner (< 1.5 km)
                  if (approachingAmb != null)
                    Positioned(
                      top: 14,
                      left: 16,
                      right: 16,
                      child: _buildApproachingErBanner(approachingAmb),
                    )
                  // 2. Incoming Driver SOS Notification
                  else if (visiblePendingIncidents.isNotEmpty)
                    Positioned(
                      top: 14,
                      left: 16,
                      right: 16,
                      child: _buildPendingIncidentAlertBanner(
                          visiblePendingIncidents.first),
                    )
                  else
                    Positioned(
                      top: 14,
                      left: 16,
                      right: 16,
                      child: _buildTopAlertBadge(),
                    ),

                  // 4. Selected Ambulance Card Bottom Sheet
                  if (_selectedAmbulance != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 16,
                      child: _buildSelectedAmbulanceCard(),
                    ),

                  // 5. หน้าจอกะพริบแจ้งเตือนตอนมีเคสใหม่ (ตามการตั้งค่า
                  // screenFlashAlert) — วาดทับบนสุด ไม่กันการแตะแผนที่ข้างล่าง
                  IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _flashController,
                      builder: (context, _) {
                        final t = _flashController.value;
                        // พีคตรงกลางแล้วจางไปทั้ง 2 ทาง (ขึ้นเร็ว ลงช้ากว่าเล็กน้อย)
                        // ให้ความรู้สึกเหมือนไฟกะพริบเตือนจริง ไม่ใช่กระพริบทื่อๆ
                        final opacity =
                            (t < 0.3 ? t / 0.3 : (1 - t) / 0.7).clamp(0.0, 1.0);
                        return Opacity(
                          opacity: opacity * 0.28,
                          child: Container(color: const Color(0xFFDC2626)),
                        );
                      },
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _hospitalProfile.hospitalName,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                  const Text(
                    'ศูนย์สั่งการและเฝ้าระวังฉุกเฉิน (Command Center)',
                    style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              // Button to Pin/Edit Hospital Location
              IconButton(
                icon: const Icon(Icons.pin_drop_rounded,
                    color: Color(0xFF00A896), size: 24),
                tooltip: 'ปักหมุดตำแหน่งโรงพยาบาล',
                onPressed: _showHospitalPinPickerModal,
              ),
              // Toggle Predictive Hotspot Heatmap (จุดเสี่ยงอุบัติเหตุจากเคสสะสม)
              IconButton(
                key: _keyHotspotToggle,
                icon: Icon(
                  Icons.local_fire_department_rounded,
                  color: _showHotspotHeatmap
                      ? const Color(0xFFD03B3B)
                      : Colors.grey.shade400,
                  size: 24,
                ),
                tooltip: 'จุดเสี่ยงอุบัติเหตุ (Hotspot)',
                onPressed: () =>
                    setState(() => _showHotspotHeatmap = !_showHotspotHeatmap),
              ),
              GestureDetector(
                key: _keyErToggle,
                onTap: () async {
                  final newValue = !_hospitalProfile.isErAvailable;
                  HapticFeedback.mediumImpact();
                  final success = await HospitalLocationService()
                      .updateErAvailability(newValue);
                  if (!mounted) return;
                  if (success) {
                    setState(() {
                      _hospitalProfile =
                          _hospitalProfile.copyWith(isErAvailable: newValue);
                    });
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success
                            ? (newValue
                                ? '✅ อัปเดตสถานะ: ห้องฉุกเฉินพร้อมรับผู้ป่วย'
                                : '🚨 อัปเดตสถานะ: ประกาศเตียงเต็ม (Divert)')
                            : '❌ อัปเดตสถานะไม่สำเร็จ กรุณาลองใหม่',
                      ),
                      backgroundColor: success
                          ? (newValue
                              ? const Color(0xFF00A896)
                              : Colors.redAccent)
                          : Colors.grey,
                    ),
                  );
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _hospitalProfile.isErAvailable
                        ? const Color(0xFF00A896).withValues(alpha: 0.15)
                        : Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _hospitalProfile.isErAvailable
                            ? Icons.check_circle
                            : Icons.warning_rounded,
                        size: 13,
                        color: _hospitalProfile.isErAvailable
                            ? const Color(0xFF00A896)
                            : Colors.redAccent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _hospitalProfile.isErAvailable ? 'ER ว่าง' : 'ER เต็ม',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: _hospitalProfile.isErAvailable
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
        ],
      ),
    );
  }

  Widget _buildFleetStatsBar(int pendingCases) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF0F172A),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('รถกู้ชีพในระบบ', '${_activeAmbulances.length} คัน',
              Icons.directions_car_rounded, const Color(0xFF5B9EE1)),
          Container(width: 1, height: 22, color: Colors.white12),
          _buildStatItem(
              'เคสรอยืนยัน',
              '$pendingCases เคส',
              Icons.warning_amber_rounded,
              pendingCases > 0 ? Colors.redAccent : Colors.white70),
          Container(width: 1, height: 22, color: Colors.white12),
          _buildStatItem('พิกัด รพ. ถาวร', 'ปักหมุดแล้ว', Icons.location_on,
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
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 5),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 9.5)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  Widget _buildApproachingErBanner(Map<String, dynamic> amb) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Text('🚨', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'รถพยาบาลใกล้ถึง รพ. ใน ${amb['eta']} (${amb['distance']})',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${amb['callSign']} • กรุณาเตรียมทีมแพทย์ห้องฉุกเฉิน (ER)',
                  style: const TextStyle(
                      color: Color(0xFFFFE4E6), fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final matchedIncident =
                  _incidents.cast<IncidentReport?>().firstWhere(
                (i) =>
                    i?.assignedAmbulanceId == amb['id'] &&
                    i?.status != 'resolved' &&
                    i?.status != 'cancelled',
                orElse: () => null,
              );
              if (matchedIncident == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('ไม่พบเคสที่กำลังดำเนินการของรถคันนี้'),
                    backgroundColor: Color(0xFFF59E0B),
                  ),
                );
                return;
              }
              final success = await IncidentService()
                  .setErPrepared(matchedIncident.id, true);
              if (success && mounted) {
                setState(() {
                  amb['isPrepared'] = true;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ ยืนยันทีม ER พร้อมรับผู้ป่วยทันที'),
                    backgroundColor: Color(0xFF10B981),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('ยืนยัน ER พร้อม',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingIncidentAlertBanner(IncidentReport incident) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AgencyIncidentDetailScreen(incident: incident),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
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
            const Icon(Icons.notification_important_rounded,
                color: Color(0xFFEF4444), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '🚨 มีเคสฉุกเฉินใหม่จากผู้ใช้: ${incident.type}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF991B1B)),
                  ),
                  Text(
                    '${incident.address} • แตะเพื่อยืนยันรับเคสและส่งรถพยาบาล',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFB91C1C)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('กดรับเคส',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
            // ปิดแบนเนอร์นี้ไปก่อนได้ — ไม่ได้ยกเลิก/ลบเคส แค่ไม่ให้บังหน้าจอ
            // ตอนมีหลายเคสพร้อมกัน (ยังจัดการเคสนี้ต่อได้จากหน้ารายการเสมอ)
            IconButton(
              icon: const Icon(Icons.close_rounded,
                  color: Color(0xFF991B1B), size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                setState(() => _dismissedBannerIds.add(incident.id));
              },
            ),
          ],
        ),
      ),
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
          Expanded(
            child: Text(
              'เรดาร์สด: ${_hospitalProfile.hospitalName} (ปักหมุดแล้ว)',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Live GPS',
            style: TextStyle(
              fontSize: 10.5,
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
      final LatLng loc = ambulance['location'];

      return Marker(
        point: loc,
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
        initialCenter: _hospitalLocation,
        initialZoom: 14.0,
        onTap: (_, __) => setState(() => _selectedAmbulance = null),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.routealert.app',
        ),

        // Route polyline for selected ambulance
        if (_selectedAmbulance != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _selectedAmbulance!['routePoints'] != null &&
                        (_selectedAmbulance!['routePoints'] as List).isNotEmpty
                    ? (_selectedAmbulance!['routePoints'] as List<LatLng>)
                    : [_selectedAmbulance!['location'], _hospitalLocation],
                strokeWidth: 4.5,
                color: const Color(0xFF00A896),
              ),
            ],
          ),

        // Predictive Hotspot: จุดที่เกิดเหตุบ่อยจากเคสสะสมในระบบ (real data, ไม่ใช่ ML
        // จริง แค่ clustering ตามกริดพิกัด) ช่วยหน่วยงานวางตำแหน่งรถพยาบาลล่วงหน้า
        if (_showHotspotHeatmap) CircleLayer(circles: _buildHotspotCircles()),

        MarkerLayer(
          markers: [
            // Pinned Hospital Location Marker
            Marker(
              point: _hospitalLocation,
              width: 54,
              height: 54,
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
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.local_hospital_rounded,
                      color: Color(0xFF00A896), size: 30),
                ),
              ),
            ),
            ...ambulanceMarkers,
          ],
        ),
      ],
    );
  }

  // จับกลุ่มเคสตามช่องกริดพิกัด (~1.1 กม./ช่อง) แล้ว plot เป็นวงกลมสีแดงความเข้ม
  // ตามจำนวนเคสสะสม (ยิ่งเยอะยิ่งเข้ม/ใหญ่) — ใช้ข้อมูลเคสจริงทั้งหมดในระบบ ไม่ใช่โมเดล ML
  List<CircleMarker> _buildHotspotCircles() {
    const double gridSize = 0.01; // ~1.1 กม. ที่ละติจูดของเชียงใหม่
    final Map<String, int> gridCounts = {};
    final Map<String, LatLng> gridCenters = {};

    for (final incident in _incidents) {
      if (incident.status == 'cancelled') continue;
      // 'archived' คือของใหม่ที่เว็บ "Data" (เครื่องมือแอดมิน) ตั้งได้ ให้ซ่อน
      // จากสถิติ/heatmap เหมือน cancelled แต่ resolved ยังนับรวมตามเดิม
      // (ตั้งใจเก็บไว้แสดงจุดเสี่ยงสะสม)
      if (incident.archived) continue;
      final gx = (incident.latitude / gridSize).round();
      final gy = (incident.longitude / gridSize).round();
      final key = '$gx:$gy';
      gridCounts[key] = (gridCounts[key] ?? 0) + 1;
      gridCenters[key] = LatLng(gx * gridSize, gy * gridSize);
    }

    if (gridCounts.isEmpty) return [];
    final maxCount = gridCounts.values.reduce((a, b) => a > b ? a : b);

    return gridCounts.entries.map((entry) {
      final count = entry.value;
      final intensity = (count / maxCount).clamp(0.15, 1.0);
      return CircleMarker(
        point: gridCenters[entry.key]!,
        radius: 400 + (intensity * 900), // เมตร: ยิ่งเคสเยอะวงยิ่งใหญ่
        useRadiusInMeter: true,
        color: const Color(0xFFD03B3B).withValues(alpha: intensity * 0.35),
        borderColor: const Color(0xFFD03B3B).withValues(alpha: intensity * 0.7),
        borderStrokeWidth: 1.5,
      );
    }).toList();
  }

  Widget _buildSelectedAmbulanceCard() {
    final amb = _selectedAmbulance!;
    final bool isPrepared = amb['isPrepared'] ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
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
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    amb['callSign'] ?? amb['id'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'สเตตัส: ${amb['status']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: Colors.grey.shade700),
                  ),
                ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() => _selectedAmbulance = null),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // หาเคสที่มอบหมายให้รถพยาบาลคันนี้จริง เพื่อบันทึกสถานะ ER
                    // ลงเคสนั้นจริง (ก่อนหน้านี้เป็นแค่ local state ไม่ persist)
                    final matchedIncident =
                        _incidents.cast<IncidentReport?>().firstWhere(
                      (i) =>
                          i?.assignedAmbulanceId == amb['id'] &&
                          i?.status != 'resolved' &&
                          i?.status != 'cancelled',
                      orElse: () => null,
                    );

                    if (matchedIncident == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'ยังไม่พบเคสที่มอบหมายให้รถพยาบาลคันนี้ในขณะนี้'),
                          backgroundColor: Colors.grey,
                        ),
                      );
                      return;
                    }

                    final success = await IncidentService()
                        .setErPrepared(matchedIncident.id, !isPrepared);

                    if (success && mounted) {
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
                    }
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
                fontSize: 13.5,
                color: Colors.black87)),
      ],
    );
  }
}