import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/incident_report.dart';
import '../../../core/services/emergency_mqtt_service.dart';
import '../../../core/services/hospital_location_service.dart';
import '../../../core/services/incident_service.dart';

class AgencyIncidentDetailScreen extends StatefulWidget {
  final IncidentReport? incident;
  final Map<String, dynamic>? incidentData;
  // เปิดมาจากปุ่ม "ส่งรถพยาบาล" บนแจ้งเตือน — มอบหมายรถใกล้สุดให้ทันทีที่หน้าจอพร้อม
  final bool autoDispatch;

  const AgencyIncidentDetailScreen({
    super.key,
    this.incident,
    this.incidentData,
    this.autoDispatch = false,
  });

  @override
  State<AgencyIncidentDetailScreen> createState() =>
      _AgencyIncidentDetailScreenState();
}

class _AgencyIncidentDetailScreenState
    extends State<AgencyIncidentDetailScreen> {
  late IncidentReport _currentIncident;
  late bool _isPrepared;
  bool _isDispatching = false;
  StreamSubscription<List<IncidentReport>>? _incidentSub;

  @override
  void initState() {
    super.initState();
    if (widget.incident != null) {
      _currentIncident = widget.incident!;
    } else {
      _currentIncident = IncidentReport.fromMap(widget.incidentData ?? {});
    }
    _isPrepared = _currentIncident.isErPrepared;

    // Listen to real-time updates for this specific incident
    _incidentSub = IncidentService().incidentsStream.listen((list) {
      if (!mounted) return;
      final found = list.firstWhere(
        (i) => i.id == _currentIncident.id,
        orElse: () => _currentIncident,
      );
      if (found.id == _currentIncident.id) {
        setState(() {
          _currentIncident = found;
          _isPrepared = found.isErPrepared;
        });
      }
    });

    if (widget.autoDispatch) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoDispatch());
    }
  }

  Future<void> _autoDispatch() async {
    if (!mounted) return;
    if (_currentIncident.status != 'pending' ||
        _currentIncident.vehicleCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เคสนี้มีรถพยาบาลรับแล้ว')),
      );
      return;
    }
    // เปิดแอปจากแจ้งเตือนตอนปิดสนิท รายชื่อรถจาก MQTT อาจยังมาไม่ถึง รอสักครู่ก่อน
    if (EmergencyMqttService().activeFleet.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กำลังค้นหารถพยาบาลที่ใกล้ที่สุด...'),
          duration: Duration(seconds: 3),
        ),
      );
      try {
        await EmergencyMqttService()
            .activeFleetStream
            .firstWhere((fleet) => fleet.isNotEmpty)
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    if (!mounted || _isDispatching) return;
    if (_currentIncident.status != 'pending' ||
        _currentIncident.vehicleCount > 0) {
      return;
    }
    await _handleDispatchCase();
  }

  @override
  void dispose() {
    _incidentSub?.cancel();
    super.dispose();
  }

  /// [additional] = ส่งรถเพิ่มให้เคสที่มีรถอยู่แล้ว (เคสเดียวรับได้หลายคัน)
  /// ไม่ใช่ additional = ส่งคันแรก ถ้ามีรถรับตัดหน้าไปแล้วจะไม่ส่งซ้อนโดยไม่ตั้งใจ
  Future<void> _handleDispatchCase({bool additional = false}) async {
    setState(() => _isDispatching = true);
    final hospital = HospitalLocationService().currentProfile;

    // เลือกรถพยาบาลที่ "ใกล้จุดเกิดเหตุที่สุดจริง" จากกองเรือที่ออนไลน์อยู่ตอนนี้
    // (ก่อนหน้านี้เป็นการยิง ID ตายตัวเดียวเสมอ ไม่มีการคำนวณระยะเลย)
    final incidentLocation =
        LatLng(_currentIncident.latitude, _currentIncident.longitude);

    final onlineFleet = EmergencyMqttService().activeFleet;

    if (onlineFleet.isEmpty) {
      if (mounted) {
        setState(() => _isDispatching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '⚠️ ไม่พบรถพยาบาลที่ออนไลน์อยู่ในขณะนี้ กรุณารอให้หน่วยกู้ชีพเปิดสถานะปฏิบัติงานก่อน'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
      return;
    }

    // ตัดรถพยาบาลที่กำลังมีเคส active อยู่แล้วออกก่อนหาคันที่ใกล้ที่สุด — กันไม่ให้
    // รถคันเดียวถูกมอบหมาย 2 เคสพร้อมกัน (เดิมไม่มีการเช็คนี้เลย)
    // (รวมรถที่อยู่ในเคสนี้แล้ว และอีกบัญชีบนรถคันเดียวกัน = ทะเบียนเดียวกัน)
    final busyIds = await IncidentService().getBusyAmbulanceIds();
    final busyKeys = await IncidentService().getBusyVehicleKeys();
    final fleet = onlineFleet
        .where((a) =>
            !busyIds.contains(a.id) &&
            !busyKeys.contains(AssignedUnit.vehicleKeyFor(a.plateNumber, a.id)))
        .toList();

    if (fleet.isEmpty) {
      if (mounted) {
        setState(() => _isDispatching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '⚠️ รถพยาบาลที่ออนไลน์อยู่ตอนนี้กำลังปฏิบัติภารกิจอื่นอยู่ทั้งหมด กรุณารอสักครู่แล้วลองใหม่'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
      return;
    }

    EmergencyVehicleData nearest = fleet.first;
    double nearestDistMeters = EmergencyMqttService.calculateDistanceInMeters(
      incidentLocation,
      LatLng(nearest.latitude, nearest.longitude),
    );
    for (final amb in fleet.skip(1)) {
      final dist = EmergencyMqttService.calculateDistanceInMeters(
        incidentLocation,
        LatLng(amb.latitude, amb.longitude),
      );
      if (dist < nearestDistMeters) {
        nearest = amb;
        nearestDistMeters = dist;
      }
    }

    final result = await IncidentService().assignAmbulance(
      id: _currentIncident.id,
      ambulanceId: nearest.id,
      // ทะเบียนจริง (ว่างได้) — ใช้นับ "รถ 1 คัน" และล็อกรถ ต้องตรงกับที่รถกดรับเอง
      ambulancePlate: nearest.plateNumber,
      ambulanceCallSign: nearest.callSign,
      onlyIfUnassigned: !additional,
      // ไม่ส่ง hospitalName/lat/lng อีกต่อไป — targetHospitalId ที่ระบบเลือกไว้
      // ถูกต้องแล้วตอนสร้างเคส (ดูคอมเมนต์ที่ dispatchIncidentByHospital) ส่งแค่
      // hospitalId ของ agency นี้ไว้เตือน (log) เฉยๆ ถ้าไม่ตรงกับที่ระบบเลือกไว้
      callingHospitalId: hospital.hospitalId,
    );

    if (!mounted) return;
    setState(() => _isDispatching = false);
    final distKm = (nearestDistMeters / 1000).toStringAsFixed(1);
    final count = result.incident?.vehicleCount ?? 0;
    final (String text, bool good) = switch (result.outcome) {
      DispatchOutcome.assigned => (
          '✅ ยืนยันรับเคสและส่งต่อให้ ${nearest.callSign} (ใกล้ที่สุด $distKm กม.) เรียบร้อยแล้ว',
          true
        ),
      DispatchOutcome.joined => (
          '✅ ส่ง ${nearest.callSign} ($distKm กม.) เพิ่มแล้ว — ตอนนี้มี $count คันกำลังดำเนินเคส',
          true
        ),
      DispatchOutcome.alreadyMine => ('${nearest.callSign} อยู่ในเคสนี้แล้ว', true),
      DispatchOutcome.alreadyHasVehicles => (
          'เคสนี้มีรถพยาบาลรับไปแล้ว $count คัน — ถ้าต้องการรถเพิ่มให้กด "ส่งรถเพิ่ม"',
          false
        ),
      DispatchOutcome.vehicleBusy => (
          '${nearest.callSign} เพิ่งรับเคสอื่นไป กรุณากดส่งใหม่เพื่อเลือกคันถัดไป',
          false
        ),
      DispatchOutcome.caseClosed => ('เคสนี้ปิดหรือจบไปแล้ว', false),
      DispatchOutcome.notJoinable => ('เคสนี้เริ่มนำส่งผู้ป่วยแล้ว ไม่ต้องส่งรถเพิ่ม', false),
      DispatchOutcome.notFound => ('ไม่พบเคสนี้ในระบบแล้ว', false),
      // เดิม dispatchIncidentByHospital คืนค่า true เสมอแม้ Firestore ล้มเหลว — ต้องบอกให้กดใหม่
      DispatchOutcome.failed => (
          '⚠️ ส่งมอบหมายเคสไม่สำเร็จ (เช็คสัญญาณอินเทอร์เน็ต) กรุณาลองกดใหม่อีกครั้ง',
          false
        ),
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: good ? const Color(0xFF00A896) : const Color(0xFFDC2626),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hospitalLocation = HospitalLocationService().hospitalLocation;
    final LatLng incidentLocation =
        LatLng(_currentIncident.latitude, _currentIncident.longitude);

    final isPending = _currentIncident.status == 'pending';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // แผนที่เส้นทางนำส่ง รพ.
                    SizedBox(
                      height: 210,
                      child: Stack(
                        children: [
                          FlutterMap(
                            options: MapOptions(
                              initialCenter: incidentLocation,
                              initialZoom: 14.2,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.routealert.app',
                              ),
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: [incidentLocation, hospitalLocation],
                                    strokeWidth: 4.5,
                                    color: const Color(0xFF00A896),
                                  ),
                                ],
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: incidentLocation,
                                    width: 46,
                                    height: 46,
                                    child: const Center(
                                        child: Text('📍',
                                            style: TextStyle(fontSize: 28))),
                                  ),
                                  Marker(
                                    point: hospitalLocation,
                                    width: 48,
                                    height: 48,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                            Icons.local_hospital_rounded,
                                            color: Color(0xFF00A896),
                                            size: 32),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Positioned(
                            top: 14,
                            left: 14,
                            child: CircleAvatar(
                              backgroundColor: Colors.white,
                              radius: 20,
                              child: IconButton(
                                icon: const Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    color: Colors.black87,
                                    size: 18),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Case ID & Status Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0F2FE),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _currentIncident.id,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0369A1),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _currentIncident.statusColor
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _currentIncident.statusText,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _currentIncident.statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // เคสมีรถแล้วแต่ยังไม่เริ่มนำส่ง — ส่งรถเพิ่มได้ (เช่น ผู้บาดเจ็บหลายคน)
                    if (!isPending && _currentIncident.isJoinable)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 6),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                                color: const Color(0xFF3B82F6), width: 1.2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🚑 ตอนนี้มี ${_currentIncident.vehicleCount} คันกำลังดำเนินเคส',
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E3A8A)),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _currentIncident.vehiclesLabel,
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF1D4ED8)),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                height: 40,
                                child: OutlinedButton.icon(
                                  onPressed: _isDispatching
                                      ? null
                                      : () => _handleDispatchCase(additional: true),
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                  label: Text(_isDispatching
                                      ? 'กำลังสั่งการ...'
                                      : 'ส่งรถเพิ่มอีก 1 คัน (คันว่างที่ใกล้ที่สุด)'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF1D4ED8),
                                    side: const BorderSide(color: Color(0xFF3B82F6)),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // 1. Dispatch Button If Case is Pending!
                    if (isPending)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 6),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                                color: const Color(0xFFEF4444), width: 1.5),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.notification_important_rounded,
                                      color: Color(0xFFEF4444), size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'เคสใหม่จากประชาชน — รอยืนยันการสั่งการ',
                                    style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF991B1B)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'กดยืนยันเพื่อมอบหมายงานให้รถพยาบาลกู้ชีพที่พร้อมปฏิบัติการทันที',
                                style: TextStyle(
                                    fontSize: 12, color: Color(0xFFB91C1C)),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      _isDispatching ? null : _handleDispatchCase,
                                  icon: _isDispatching
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white),
                                        )
                                      : const Icon(Icons.send_rounded,
                                          color: Colors.white, size: 18),
                                  label: Text(
                                    _isDispatching
                                        ? 'กำลังสั่งการ...'
                                        : '📋 ยืนยันรับเคส & ส่งรถพยาบาลออกปฏิบัติการ',
                                    style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFEF4444),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // 2. Live 5-Step Operational Progress Timeline
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      child: _buildProgressTimeline(),
                    ),


                    // 4. Case Details
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            labelTH: 'สถานะห้องฉุกเฉิน',
                            labelEN: '(ER Status)',
                            value: _isPrepared
                                ? 'เตรียมเตียงและทีมแพทย์เรียบร้อย'
                                : 'กำลังรอยืนยันความพร้อม',
                            valueColor: _isPrepared
                                ? const Color(0xFF10B981)
                                : const Color(0xFFE65100),
                            isBold: true,
                          ),
                          _buildDetailRow(
                            labelTH: 'ประเภทอุบัติเหตุ',
                            labelEN: '(Type of incident)',
                            value: _currentIncident.type,
                          ),
                          _buildDetailRow(
                            labelTH: 'ระดับความรุนแรง',
                            labelEN: '(Severity)',
                            value: _currentIncident.severity,
                          ),
                          _buildDetailRow(
                            labelTH: 'สถานที่เกิดเหตุ',
                            labelEN: '(Location)',
                            value: _currentIncident.address,
                          ),
                          _buildDetailRow(
                            labelTH: 'คาดการณ์ถึง รพ.',
                            labelEN: '(Estimated ETA)',
                            value: _currentIncident.eta,
                            valueColor: const Color(0xFFEB5757),
                            isBold: true,
                          ),
                          _buildDetailRow(
                            labelTH: 'รถกู้ชีพที่รับเคส',
                            labelEN: '(Assigned Vehicles)',
                            value: _currentIncident.vehicleCount == 0
                                ? 'ยังไม่ได้มอบหมาย'
                                : '${_currentIncident.vehicleCount} คัน · ${_currentIncident.vehiclesLabel}',
                            valueColor: const Color(0xFF00A896),
                            isBold: true,
                          ),
                          if (_currentIncident.description.isNotEmpty &&
                              _currentIncident.description != '-')
                            _buildDetailRow(
                              labelTH: 'รายละเอียดจากผู้แจ้ง',
                              labelEN: '(Reporter Notes)',
                              value: _currentIncident.description,
                            ),
                          _buildDetailRow(
                            labelTH: 'ผู้แจ้งเหตุ',
                            labelEN: '(Reporter)',
                            value:
                                '${_currentIncident.reporterName} (${_currentIncident.reporterPhone.isNotEmpty ? _currentIncident.reporterPhone : "ไม่มีเบอร์"})',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // รูปถ่ายจากจุดเกิดเหตุ
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Text('รูปภาพที่ส่งมาจากที่เกิดเหตุ',
                                  style: TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.bold)),
                              SizedBox(width: 4),
                              Text('(Attached Photos)',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF2E7D32),
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_currentIncident.photoBase64 != null &&
                              _currentIncident.photoBase64!.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.memory(
                                base64Decode(_currentIncident.photoBase64!),
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            Container(
                              height: 80,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: const Center(
                                child: Text('ไม่มีรูปภาพแนบมากับเคสนี้',
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 12)),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ปุ่มยืนยันเตรียมเตียง ER
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            final newStatus = !_isPrepared;
                            setState(() => _isPrepared = newStatus);
                            final messenger = ScaffoldMessenger.of(context);
                            final ok = await IncidentService()
                                .setErPrepared(_currentIncident.id, newStatus);
                            if (!mounted) return;
                            if (!ok) {
                              // Firestore ล้มเหลวจริง — ย้อน UI กลับให้ตรงกับ
                              // สถานะจริงที่ยังไม่ถูกบันทึก แทนที่จะค้างค่าที่ผิด
                              setState(() => _isPrepared = !newStatus);
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(!ok
                                    ? '⚠️ บันทึกไม่สำเร็จ เช็คสัญญาณอินเทอร์เน็ตแล้วลองใหม่'
                                    : newStatus
                                        ? '✅ ยืนยันการเตรียมเตียงห้องฉุกเฉิน (ER Ready) สำเร็จ'
                                        : '⚪ ยกเลิกสถานะเตรียมเตียง'),
                                backgroundColor: !ok
                                    ? const Color(0xFFDC2626)
                                    : newStatus
                                        ? const Color(0xFF10B981)
                                        : Colors.black87,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isPrepared
                                ? const Color(0xFF10B981)
                                : const Color(0xFF00A896),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 2,
                          ),
                          child: Text(
                            _isPrepared
                                ? '✓ ยืนยันเตียง ER เรียบร้อยแล้ว (Ready)'
                                : 'ยืนยันเตียง ER พร้อมรับผู้ป่วย',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressTimeline() {
    final int step = _currentIncident.statusStep;

    final steps = [
      {'title': 'รับแจ้ง', 'sub': 'รอยืนยัน', 'active': step >= 0},
      {'title': 'เดินทาง', 'sub': 'ไปจุดเกิดเหตุ', 'active': step >= 1},
      {'title': 'ถึงที่เกิดเหตุ', 'sub': 'ปฐมพยาบาล', 'active': step >= 2},
      {'title': 'กำลังนำส่ง', 'sub': 'มุ่งหน้ามา รพ.', 'active': step >= 3},
      {'title': 'ใกล้ถึง รพ.', 'sub': 'เตรียมทีม ER', 'active': step >= 4},
      {'title': 'ถึง รพ.', 'sub': 'เสร็จสิ้น', 'active': step >= 5},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: steps.map((s) {
          final bool active = s['active'] as bool;
          return Column(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor:
                    active ? const Color(0xFF00A896) : Colors.grey.shade300,
                child: Icon(
                  active ? Icons.check_rounded : Icons.circle,
                  size: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s['title'] as String,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active ? const Color(0xFF00A896) : Colors.grey,
                ),
              ),
            ],
          );
        }).toList(),
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
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4,
              offset: const Offset(0, 2)),
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
                        size: 9, color: Colors.redAccent.shade700)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Text('RouteAlert ER Command',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required String labelTH,
    required String labelEN,
    required String value,
    Color valueColor = Colors.black87,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                    Text(
                      labelEN,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Text(':', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              Expanded(
                flex: 6,
                child: Text(
                  value,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                      color: valueColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Divider(color: Colors.grey.shade200, thickness: 1),
        ],
      ),
    );
  }
}