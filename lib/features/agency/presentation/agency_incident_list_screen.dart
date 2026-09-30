import 'package:flutter/material.dart';
import '../../../core/models/incident_report.dart';
import '../../../core/services/incident_service.dart';
import '../../../core/services/agency_storage_service.dart';
import '../../auth_face_login/data/services/face_auth_repository.dart';
import 'agency_incident_detail_screen.dart';
import '../../../core/services/agency_case_filter.dart';

class AgencyIncidentListScreen extends StatefulWidget {
  const AgencyIncidentListScreen({super.key});

  @override
  State<AgencyIncidentListScreen> createState() =>
      _AgencyIncidentListScreenState();
}

class _AgencyIncidentListScreenState extends State<AgencyIncidentListScreen> {
  // ค่าตั้งค่าจริงจากหน้า Settings (เดิมหน้านี้ไม่เคยอ่านค่าพวกนี้เลย ตั้งค่าแล้วไม่มีผลอะไร)
  bool _criticalOnly = false;
  double _alertDistanceKm = 15.0;

  // เคสที่ agency กด "ลบออกจากหน้าจอ" เอง (ซ่อนแค่ฝั่ง UI เครื่องนี้ ข้อมูลจริงยัง
  // อยู่ครบใน Firestore) — โหลดจาก SharedPreferences ตอนเปิดหน้าเพื่อให้จำค่าไว้
  // แม้ปิดแอปแล้วเปิดใหม่
  Set<String> _dismissedIds = {};

  // โรงพยาบาลของบัญชี agency ที่ล็อกอินอยู่ (เพิ่มตอนทำ multi-hospital) — null
  // หมายถึงบัญชีเก่าที่ยังไม่มี hospitalId จะไม่กรองอะไรเลย (เห็นเหมือนเดิม)
  String? _myHospitalId;

  @override
  void initState() {
    super.initState();
    IncidentService().initialize();
    AgencyStorageService.loadSettings();
    _applySettings(AgencyStorageService.settingsNotifier.value);
    AgencyStorageService.settingsNotifier.addListener(_onSettingsChanged);
    _loadDismissedIds();
    _loadMyHospitalId();
  }

  Future<void> _loadMyHospitalId() async {
    final currentUser = await FaceAuthRepository.getCurrentUser();
    if (mounted) setState(() => _myHospitalId = currentUser?.hospitalId);
  }

  Future<void> _loadDismissedIds() async {
    final ids = await AgencyStorageService.loadDismissedIncidentIds();
    if (mounted) setState(() => _dismissedIds = ids);
  }

  // กด X บนเคส: ยืนยันก่อนเสมอ — ปิดเคสให้หายจากทุกฝั่ง หรือซ่อนเฉพาะเครื่องนี้
  Future<void> _confirmRemoveIncident(IncidentReport item) async {
    final hasAmbulance = item.vehicleCount > 0;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('ปิดเคสนี้?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item.type} · ${item.address.isNotEmpty ? item.address : item.province}'),
            const SizedBox(height: 10),
            const Text('ปิดเคส = ยกเลิกเคสนี้ในระบบ โรงพยาบาลและรถพยาบาลทุกคันจะไม่เห็นเคสนี้อีก '
                'ผู้แจ้งจะเห็นว่าเคสถูกยกเลิก'),
            if (hasAmbulance) ...[
              const SizedBox(height: 10),
              Text(
                '⚠️ มีรถพยาบาล ${item.vehicleCount} คัน (${item.vehiclesLabel}) กำลังรับเคสนี้อยู่ — '
                'ปิดเคสแล้วรถทุกคันจะหยุดภารกิจนี้ทันที',
                style: const TextStyle(color: Color(0xFFB45309), fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'hide'),
            child: const Text('ซ่อนเฉพาะเครื่องนี้'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'close'),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: const Text('ปิดเคส (ทุกฝั่ง)'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'hide') {
      await _dismissIncident(item);
    } else if (choice == 'close') {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await IncidentService()
          .closeIncidentByHospital(item.id, reason: 'โรงพยาบาลปิดเคส');
      messenger.showSnackBar(SnackBar(
        content: Text(ok
            ? 'ปิดเคสแล้ว ทุกฝั่งจะไม่เห็นเคสนี้อีก'
            : '⚠️ ปิดเคสไม่สำเร็จ (เช็คสัญญาณอินเทอร์เน็ต) กรุณาลองใหม่'),
        backgroundColor: ok ? Colors.grey.shade800 : const Color(0xFFDC2626),
      ));
    }
  }

  Future<void> _dismissIncident(IncidentReport item) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final next = {..._dismissedIds, item.id};
    setState(() => _dismissedIds = next);
    await AgencyStorageService.setDismissedIncidentIds(next);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: const Text('ซ่อนเคสนี้จากหน้าจอแล้ว (ข้อมูลยังเก็บไว้ในระบบครบ)'),
        backgroundColor: Colors.grey.shade800,
        action: SnackBarAction(
          label: 'เลิกทำ',
          textColor: Colors.white,
          onPressed: () async {
            final undo = {..._dismissedIds}..remove(item.id);
            setState(() => _dismissedIds = undo);
            await AgencyStorageService.setDismissedIncidentIds(undo);
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    AgencyStorageService.settingsNotifier.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    _applySettings(AgencyStorageService.settingsNotifier.value);
  }

  void _applySettings(Map<String, dynamic> settings) {
    setState(() {
      _criticalOnly = settings['criticalOnly'] as bool? ?? false;
      _alertDistanceKm = (settings['alertDistanceKm'] as num?)?.toDouble() ?? 15.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 16),

            Text(
              'เคสที่กำลังมุ่งหน้ามา (Incoming ER)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),

            // ลิสต์รายการการ์ดจาก IncidentService แบบ Real-Time
            Expanded(
              child: StreamBuilder<List<IncidentReport>>(
                stream: IncidentService().incidentsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFF00A896)),
                    );
                  }

                  final rawList = snapshot.data ?? [];
                  // กรองเคสที่จบ/ยกเลิก/ซ่อนเอง, เฉพาะเคสของโรงพยาบาลนี้, ตัวกรองวิกฤต และระยะ
                  // (ดู agencyCaseVisible — เคสที่ส่งมาที่ รพ. นี้ไม่ถูกซ่อนเพราะระยะ)
                  final activeList = rawList
                      .where((i) =>
                          !i.isClosed &&
                          !_dismissedIds.contains(i.id) &&
                          (_myHospitalId == null || i.targetHospitalId == _myHospitalId))
                      .toList();
                  final list = activeList
                      .where((i) => agencyCaseVisible(
                            i,
                            myHospitalId: _myHospitalId,
                            criticalOnly: _criticalOnly,
                            alertDistanceKm: _alertDistanceKm,
                            dismissedIds: _dismissedIds,
                          ))
                      .toList();

                  if (list.isEmpty) {
                    final hiddenByFilter = activeList.isNotEmpty;
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              color: Colors.grey.shade400, size: 56),
                          const SizedBox(height: 12),
                          Text(
                            hiddenByFilter
                                ? 'ไม่มีเคสที่ตรงกับตัวกรองการแจ้งเตือนปัจจุบัน\n(ปรับได้ที่หน้าตั้งค่า)'
                                : 'ไม่มีเคสฉุกเฉินที่กำลังนำส่งในขณะนี้',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      return _buildAgencyIncidentCard(list[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- การ์ดขอบสีเขียวแบบ Figma ---
  Widget _buildAgencyIncidentCard(IncidentReport item) {
    bool isPrepared = item.isErPrepared;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isPrepared ? const Color(0xFF10B981) : const Color(0xFF69F0AE),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF69F0AE).withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.address.isNotEmpty ? item.address : item.province,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 2),
              Text(
                item.id,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 4),
              Text(
                item.type,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87),
              ),
              const SizedBox(height: 4),
              if (item.vehicleCount > 0)
                Text(
                  '🚑 กำลังดำเนินเคส ${item.vehicleCount} คัน : ${item.vehiclesLabel}',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: item.vehicleCount > 1 ? const Color(0xFF1D4ED8) : Colors.grey.shade700,
                    fontWeight: item.vehicleCount > 1 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Text(
                    isPrepared ? 'เตรียม ER เรียบร้อย' : item.statusText,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: isPrepared ? const Color(0xFF10B981) : const Color(0xFF2E7D32),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('🚑', style: TextStyle(fontSize: 17)),
                  const SizedBox(width: 4),
                  const Text('🚓', style: TextStyle(fontSize: 17)),
                ],
              ),
              const SizedBox(height: 16),

              // ปุ่มยืนยันเตรียมเตียง ER
              Center(
                child: SizedBox(
                  width: 170,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () async {
                      final newValue = !isPrepared;
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      final ok =
                          await IncidentService().setErPrepared(item.id, newValue);
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(!ok
                              ? '⚠️ บันทึกไม่สำเร็จ เช็คสัญญาณอินเทอร์เน็ตแล้วลองใหม่'
                              : newValue
                                  ? '✅ ยืนยันเตียง ER เรียบร้อยแล้ว'
                                  : 'ยกเลิกการยืนยันเตียง ER แล้ว'),
                          backgroundColor: !ok
                              ? const Color(0xFFDC2626)
                              : newValue
                                  ? const Color(0xFF00A896)
                                  : Colors.grey.shade700,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isPrepared ? Colors.grey.shade300 : const Color(0xFF69F0AE),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      elevation: isPrepared ? 0 : 3,
                    ),
                    child: Text(
                      isPrepared ? '✓ ยืนยันเรียบร้อย' : 'ยืนยันเตียง ER',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: isPrepared ? Colors.grey.shade700 : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ปุ่มลูกศรเข้าดูรายละเอียดเคส (พร้อมรูปถ่าย)
          Positioned(
            right: 0,
            top: 20,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AgencyIncidentDetailScreen(incident: item),
                  ),
                );
              },
              child: const Icon(Icons.chevron_right_rounded, color: Colors.black54, size: 36),
            ),
          ),

          // ปุ่มลบเคสนี้ออกจากหน้าจอ (ซ่อนแค่ฝั่งนี้ ข้อมูลใน database ไม่หาย) —
          // ตอบโจทย์เคสที่ agency ต้องการเคลียร์การ์ดที่ไม่อยากเห็นแล้วออกจากลิสต์เอง
          Positioned(
            right: 0,
            top: -4,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _confirmRemoveIncident(item),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close_rounded,
                    color: Colors.grey.shade400, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2)),
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
          const Text('RouteAlert ER Agency', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }
}