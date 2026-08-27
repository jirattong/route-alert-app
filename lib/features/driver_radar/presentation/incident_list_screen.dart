import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/incident_report.dart';
import '../../../core/services/incident_service.dart';
import '../../../core/services/location_service.dart';
import 'incident_detail_screen.dart';

class IncidentListScreen extends StatefulWidget {
  final VoidCallback? onOpenSos;

  const IncidentListScreen({super.key, this.onOpenSos});

  @override
  State<IncidentListScreen> createState() => _IncidentListScreenState();
}

class _IncidentListScreenState extends State<IncidentListScreen> {
  double _selectedRadiusKm = 15.0; // ค่าเริ่มต้น: ไม่เกิน 15 กม. ตามที่ผู้ใช้ต้องการ
  int _selectedTab = 0; // 0 = เหตุในบริเวณพื้นที่, 1 = รายงานของฉัน (SOS)
  LatLng _userLocation = const LatLng(19.0284, 99.8962);

  @override
  void initState() {
    super.initState();
    IncidentService().initialize();
    _loadUserLocation();
  }

  Future<void> _loadUserLocation() async {
    try {
      final loc = await LocationService.getCurrentLocation();
      if (loc != null && mounted) {
        setState(() {
          _userLocation = loc;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 14),

                // ตัวเลือกรัศมีแสดงเหตุ (Proximity Filter)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.radar_rounded, color: Color(0xFF2563EB), size: 20),
                          SizedBox(width: 6),
                          Text(
                            'ขอบเขตแสดงเหตุ:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<double>(
                            value: _selectedRadiusKm,
                            isDense: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF2563EB)),
                            items: const [
                              DropdownMenuItem(value: 5.0, child: Text('📍 ไม่เกิน 5 กม. (รอบตัว)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold))),
                              DropdownMenuItem(value: 15.0, child: Text('📍 ไม่เกิน 15 กม. (แนะนำ)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)))),
                              DropdownMenuItem(value: 30.0, child: Text('📍 ไม่เกิน 30 กม. (ทั้งโซน)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold))),
                              DropdownMenuItem(value: 0.0, child: Text('🗺️ ทั้งหมด (ไม่จำกัดระยะ)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold))),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedRadiusKm = val);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // แท็บสลับประเภทเหตุ
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedTab = 0),
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _selectedTab == 0 ? const Color(0xFF5B9EE1) : Colors.transparent,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _selectedRadiusKm > 0
                                    ? 'เหตุใกล้ฉัน (≤ ${_selectedRadiusKm.toInt()} กม.)'
                                    : 'เหตุทั้งหมด',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: _selectedTab == 0 ? Colors.white : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedTab = 1),
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _selectedTab == 1 ? const Color(0xFF5B9EE1) : Colors.transparent,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'รายงานของฉัน (SOS)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: _selectedTab == 1 ? Colors.white : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // รายการเหตุแบบ Real-Time จาก IncidentService
                Expanded(
                  child: StreamBuilder<List<IncidentReport>>(
                    stream: IncidentService().incidentsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(color: Color(0xFF5B9EE1)),
                        );
                      }

                      final allList = snapshot.data ?? [];
                      // กรองตามระยะทาง & แท็บ
                      final filtered = allList.where((item) {
                        if (_selectedTab == 1) {
                          // My SOS reports
                          return true;
                        } else {
                          // Area incidents by radius
                          if (_selectedRadiusKm <= 0) return true;
                          final meters = LocationService.calculateDistanceInMeters(
                            _userLocation,
                            LatLng(item.latitude, item.longitude),
                          );
                          return (meters / 1000.0) <= _selectedRadiusKm;
                        }
                      }).toList();

                      if (filtered.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_outline_rounded,
                                    color: Colors.green.shade400, size: 56),
                                const SizedBox(height: 12),
                                Text(
                                  _selectedTab == 1
                                      ? 'คุณยังไม่มีประวัติแจ้งเหตุฉุกเฉิน'
                                      : 'ไม่มีเหตุฉุกเฉินในรัศมี ${_selectedRadiusKm.toInt()} กม. จากตำแหน่งคุณ',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'เส้นทางของคุณปลอดภัย ไร้สิ่งกีดขวาง 🎉',
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final meters = LocationService.calculateDistanceInMeters(
                            _userLocation,
                            LatLng(item.latitude, item.longitude),
                          );
                          final double km = meters / 1000.0;
                          return _buildIncidentCard(item, km);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),

            // ปุ่ม SOS ลอยขวาล่าง
            Positioned(
              right: 20,
              bottom: 20,
              child: InkWell(
                onTap: widget.onOpenSos,
                borderRadius: BorderRadius.circular(35),
                child: Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFEB5757), width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEB5757).withValues(alpha: 0.35),
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
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentCard(IncidentReport item, double distanceKm) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IncidentDetailScreen(incident: item),
          ),
        );
      },
      borderRadius: BorderRadius.circular(22),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: item.status == 'cancelled'
                ? Colors.grey.shade300
                : const Color(0xFF5B9EE1).withValues(alpha: 0.7),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5B9EE1).withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.address.isNotEmpty ? item.address : item.province,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '📏 ${distanceKm.toStringAsFixed(1)} กม.',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.id,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.type,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  if (item.assignedAmbulancePlate != null && item.assignedAmbulancePlate!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'รถกู้ชีพ: ${item.assignedAmbulancePlate}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: item.statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item.statusText,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: item.statusColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (item.canBeCancelled)
                        Text(
                          '• สามารถแตะเพื่อยกเลิกได้',
                          style: TextStyle(fontSize: 11, color: Colors.red.shade400, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
              ),
              child: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF5B9EE1), size: 16),
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
                const Icon(Icons.airport_shuttle_outlined, size: 18, color: Color(0xFF2C3E50)),
                Positioned(
                  top: 3,
                  right: 3,
                  child: Icon(Icons.wifi, size: 8, color: Colors.redAccent.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'RouteAlert',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
          ),
        ],
      ),
    );
  }
}