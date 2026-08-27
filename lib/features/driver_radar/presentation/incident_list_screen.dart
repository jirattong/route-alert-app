import 'package:flutter/material.dart';
import '../../../core/models/incident_report.dart';
import '../../../core/services/incident_service.dart';
import 'incident_detail_screen.dart';

class IncidentListScreen extends StatefulWidget {
  final VoidCallback? onOpenSos;

  const IncidentListScreen({super.key, this.onOpenSos});

  @override
  State<IncidentListScreen> createState() => _IncidentListScreenState();
}

class _IncidentListScreenState extends State<IncidentListScreen> {
  String _selectedProvince = 'เชียงใหม่';
  int _selectedTab = 0; // 0 = เหตุในบริเวณพื้นที่, 1 = รายงานของฉัน (SOS)

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
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 14),

                // ตัวเลือกจังหวัด
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.location_on, color: Color(0xFFEB5757), size: 20),
                          SizedBox(width: 4),
                          Text(
                            'พื้นที่แสดงเหตุ:',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF5B9EE1), width: 1.5),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedProvince,
                            isDense: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF5B9EE1)),
                            items: ['เชียงใหม่', 'พะเยา', 'เชียงราย', 'ลำปาง']
                                .map((prov) => DropdownMenuItem(value: prov, child: Text(prov)))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedProvince = val);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // แท็บสลับประเภทเหตุ
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
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
                                'เหตุในบริเวณพื้นที่',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
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
                      // กรองตามแท็บ
                      final filtered = allList.where((item) {
                        if (_selectedTab == 1) {
                          // My SOS reports
                          return true;
                        } else {
                          // Area incidents
                          return item.province.contains(_selectedProvince);
                        }
                      }).toList();

                      if (filtered.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline_rounded,
                                  color: Colors.grey.shade400, size: 56),
                              const SizedBox(height: 12),
                              Text(
                                _selectedTab == 1
                                    ? 'คุณยังไม่มีประวัติแจ้งเหตุฉุกเฉิน'
                                    : 'ไม่มีรายงานเหตุฉุกเฉินในพื้นที่ $_selectedProvince',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) => _buildIncidentCard(filtered[index]),
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

  Widget _buildIncidentCard(IncidentReport item) {
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
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF5B9EE1), width: 1.8),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5B9EE1).withValues(alpha: 0.12),
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
                  Text(
                    item.address.isNotEmpty ? item.address : item.province,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.id,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.type,
                    style: const TextStyle(fontSize: 13.5, color: Colors.black87),
                  ),
                  if (item.assignedAmbulancePlate != null && item.assignedAmbulancePlate!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'เลขรถรับเคส : ${item.assignedAmbulancePlate}',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
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
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: item.statusColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (item.assignedAmbulancePlate != null)
                        const Text('🚑', style: TextStyle(fontSize: 15)),
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