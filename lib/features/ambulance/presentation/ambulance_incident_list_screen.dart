import 'package:flutter/material.dart';
import '../../../core/models/incident_report.dart';
import '../../../core/services/incident_service.dart';
import 'ambulance_incident_detail_screen.dart';

class AmbulanceIncidentListScreen extends StatefulWidget {
  const AmbulanceIncidentListScreen({super.key});

  @override
  State<AmbulanceIncidentListScreen> createState() =>
      _AmbulanceIncidentListScreenState();
}

class _AmbulanceIncidentListScreenState
    extends State<AmbulanceIncidentListScreen> {
  String _selectedDistrict = 'ทั้งหมดในโซน';
  final List<String> _districts = [
    'ทั้งหมดในโซน',
    'อ.เมืองเชียงใหม่',
    'อ.ฝาง จ.เชียงใหม่',
    'อ.แม่ริม',
    'อ.หางดง',
  ];

  @override
  void initState() {
    super.initState();
    IncidentService().initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildAreaSelectorBar(),
            const SizedBox(height: 16),
            Text(
              'เหตุในบริเวณพื้นที่ (Dispatched Incidents)',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),

            // ลิสต์รายการเคสแบบ Real-Time จาก IncidentService
            Expanded(
              child: StreamBuilder<List<IncidentReport>>(
                stream: IncidentService().incidentsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFFEB5757)),
                    );
                  }

                  final allList = snapshot.data ?? [];
                  final list = allList.where((i) {
                    if (i.status == 'cancelled') return false;
                    if (_selectedDistrict == 'ทั้งหมดในโซน') return true;
                    return i.address.contains(_selectedDistrict) || i.province.contains(_selectedDistrict);
                  }).toList();

                  if (list.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              color: Colors.grey.shade400, size: 56),
                          const SizedBox(height: 12),
                          Text(
                            'ไม่มีเคสฉุกเฉินในโซน $_selectedDistrict ในขณะนี้',
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
                      return _buildAmbulanceIncidentCard(list[index]);
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
                const Icon(Icons.airport_shuttle_outlined, size: 20, color: Color(0xFF2C3E50)),
                Positioned(top: 4, right: 4, child: Icon(Icons.wifi, size: 9, color: Colors.redAccent.shade700)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Text('RouteAlert Ambulance', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildAreaSelectorBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(Icons.location_on, color: Color(0xFFEB5757), size: 22),
              SizedBox(width: 6),
              Text('พื้นที่แสดงเหตุ:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedDistrict,
                isDense: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF5B9EE1)),
                items: _districts
                    .map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedDistrict = val);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmbulanceIncidentCard(IncidentReport item) {
    bool isAccepted = item.status != 'pending';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isAccepted ? const Color(0xFF10B981) : const Color(0xFFEB5757),
          width: 1.8,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEB5757).withValues(alpha: 0.08),
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
              Text(
                item.assignedAmbulancePlate != null && item.assignedAmbulancePlate!.isNotEmpty
                    ? 'เลขรถที่รับเคส : ${item.assignedAmbulancePlate}'
                    : 'เลขรถที่รับเคส : ยังไม่มีรถรับหมาย',
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Text(
                    item.statusText,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: item.statusColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('🚑', style: TextStyle(fontSize: 17)),
                  const SizedBox(width: 4),
                  const Text('🚓', style: TextStyle(fontSize: 17)),
                ],
              ),
              const SizedBox(height: 16),

              // ปุ่มกดรับเคส (ยืนยันรับหมาย)
              Center(
                child: SizedBox(
                  width: 170,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: isAccepted
                        ? null
                        : () async {
                            await IncidentService().acceptIncidentByAmbulance(
                              id: item.id,
                              ambulancePlate: 'กขค123 (รถของเรา)',
                              ambulanceId: 'AMB-1669-01',
                            );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('🔴 ยืนยันรับเคสและบันทึกหมายเรียบร้อยแล้ว!'),
                                  backgroundColor: Color(0xFFEB5757),
                                ),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEB5757),
                      disabledBackgroundColor: const Color(0xFFA3A3A3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      elevation: isAccepted ? 0 : 3,
                    ),
                    child: Text(
                      isAccepted ? 'ยืนยันรับเคสแล้ว' : 'ยืนยันรับเคส',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ปุ่มลูกศร > มุมขวาบน เพื่อกดเข้าดูหน้ารายละเอียดเคสฉุกเฉิน
          Positioned(
            right: 0,
            top: 20,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AmbulanceIncidentDetailScreen(incident: item),
                  ),
                );
              },
              child: const Icon(
                Icons.chevron_right_rounded,
                color: Colors.black54,
                size: 36,
              ),
            ),
          ),
        ],
      ),
    );
  }
}