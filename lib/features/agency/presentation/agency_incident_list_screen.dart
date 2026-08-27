import 'package:flutter/material.dart';
import '../../../core/models/incident_report.dart';
import '../../../core/services/incident_service.dart';
import 'agency_incident_detail_screen.dart';

class AgencyIncidentListScreen extends StatefulWidget {
  const AgencyIncidentListScreen({super.key});

  @override
  State<AgencyIncidentListScreen> createState() =>
      _AgencyIncidentListScreenState();
}

class _AgencyIncidentListScreenState extends State<AgencyIncidentListScreen> {
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
                  final list = rawList.where((i) => i.status != 'cancelled').toList();
                  if (list.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              color: Colors.grey.shade400, size: 56),
                          const SizedBox(height: 12),
                          Text(
                            'ไม่มีเคสฉุกเฉินที่กำลังนำส่งในขณะนี้',
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
              if (item.assignedAmbulancePlate != null && item.assignedAmbulancePlate!.isNotEmpty)
                Text(
                  'เลขรถรับเคส : ${item.assignedAmbulancePlate}',
                  style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700),
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
                      await IncidentService().setErPrepared(item.id, !isPrepared);
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