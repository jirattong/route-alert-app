import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/incident_report.dart';
import '../../../core/services/incident_service.dart';

class AgencyIncidentDetailScreen extends StatefulWidget {
  final IncidentReport? incident;
  final Map<String, dynamic>? incidentData;

  const AgencyIncidentDetailScreen({
    super.key,
    this.incident,
    this.incidentData,
  });

  @override
  State<AgencyIncidentDetailScreen> createState() =>
      _AgencyIncidentDetailScreenState();
}

class _AgencyIncidentDetailScreenState
    extends State<AgencyIncidentDetailScreen> {
  late bool _isPrepared;

  @override
  void initState() {
    super.initState();
    _isPrepared = widget.incident?.isErPrepared ?? widget.incidentData?['isErPrepared'] ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final String id = widget.incident?.id ?? widget.incidentData?['id'] ?? 'Case #AVCB00021';
    final String type = widget.incident?.type ?? widget.incidentData?['type'] ?? 'อุบัติเหตุทางรถยนต์';
    final String severity = widget.incident?.severity ?? widget.incidentData?['severity'] ?? 'วิกฤต (Critical)';
    final String address = widget.incident?.address ?? widget.incidentData?['location'] ?? 'อ.ฝาง จ.เชียงใหม่';
    final String vehiclePlate = widget.incident?.assignedAmbulancePlate ?? widget.incidentData?['vehiclePlate'] ?? 'รอจ่ายงาน';
    final String eta = widget.incident?.eta ?? widget.incidentData?['eta'] ?? '4 นาที';
    final String desc = widget.incident?.description ?? widget.incidentData?['description'] ?? '-';
    final String? photoBase64 = widget.incident?.photoBase64;

    const LatLng hospitalLocation = LatLng(19.0284, 99.8962);
    final LatLng incidentLocation = widget.incident != null
        ? LatLng(widget.incident!.latitude, widget.incident!.longitude)
        : const LatLng(19.0350, 99.8962);

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
                      height: 200,
                      child: Stack(
                        children: [
                          FlutterMap(
                            options: MapOptions(
                              initialCenter: incidentLocation,
                              initialZoom: 14.5,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.routealert.app',
                              ),
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: [incidentLocation, hospitalLocation],
                                    strokeWidth: 4.5,
                                    color: const Color(0xFF10B981),
                                  ),
                                ],
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: incidentLocation,
                                    width: 44,
                                    height: 44,
                                    child: const Center(child: Text('🚑', style: TextStyle(fontSize: 26))),
                                  ),
                                  const Marker(
                                    point: hospitalLocation,
                                    width: 44,
                                    height: 44,
                                    child: Center(
                                      child: Icon(Icons.local_hospital_rounded, color: Color(0xFF2E7D32), size: 38),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Positioned(
                            top: 16,
                            left: 16,
                            child: CircleAvatar(
                              backgroundColor: Colors.white,
                              radius: 20,
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87, size: 20),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // Case ID Capsule Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF69F0AE).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF69F0AE).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Text(
                        id,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Divider(color: Colors.grey.shade300, thickness: 1),
                    ),
                    const SizedBox(height: 10),

                    // รายละเอียดเคส
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            labelTH: 'สถานะห้องฉุกเฉิน',
                            labelEN: '(ER Status)',
                            value: _isPrepared ? 'เตรียมเตียงและทีมแพทย์เรียบร้อย' : 'กำลังรอยืนยันความพร้อม',
                            valueColor: _isPrepared ? const Color(0xFF10B981) : const Color(0xFFE65100),
                            isBold: true,
                          ),
                          _buildDetailRow(
                            labelTH: 'ประเภทอุบัติเหตุ',
                            labelEN: '(Type of incident)',
                            value: type,
                          ),
                          _buildDetailRow(
                            labelTH: 'ระดับความรุนแรง',
                            labelEN: '(Severity)',
                            value: severity,
                          ),
                          _buildDetailRow(
                            labelTH: 'สถานที่เกิดเหตุ',
                            labelEN: '(Location)',
                            value: address,
                          ),
                          _buildDetailRow(
                            labelTH: 'คาดการณ์ถึง รพ.',
                            labelEN: '(Estimated Time of Arrival)',
                            value: eta,
                            valueColor: const Color(0xFFEB5757),
                            isBold: true,
                          ),
                          _buildDetailRow(
                            labelTH: 'รถกู้ชีพที่รับเคส',
                            labelEN: '(Assigned Vehicle)',
                            value: vehiclePlate,
                            valueColor: const Color(0xFF00A896),
                            isBold: true,
                          ),
                          if (desc.isNotEmpty && desc != '-')
                            _buildDetailRow(
                              labelTH: 'รายละเอียดเพิ่มเติม',
                              labelEN: '(Description)',
                              value: desc,
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // รูปถ่ายจากจุดเกิดเหตุ (ส่งจาก Driver SOS)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Text('รูปภาพที่ส่งมาจากที่เกิดเหตุ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              SizedBox(width: 4),
                              Text('(Attached Photos)', style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (photoBase64 != null && photoBase64.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.memory(
                                base64Decode(photoBase64),
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            Container(
                              height: 100,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: const Center(
                                child: Text('ไม่มีรูปภาพแนบมากับเคสนี้', style: TextStyle(color: Colors.grey, fontSize: 13)),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ปุ่มยืนยันเตรียมเตียง ER
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            final newStatus = !_isPrepared;
                            setState(() => _isPrepared = newStatus);
                            final messenger = ScaffoldMessenger.of(context);
                            await IncidentService().setErPrepared(id, newStatus);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(newStatus
                                    ? '✅ ยืนยันการเตรียมเตียงห้องฉุกเฉิน (ER Ready) สำเร็จ'
                                    : '⚪ ยกเลิกสถานะเตรียมเตียง'),
                                backgroundColor: newStatus ? const Color(0xFF10B981) : Colors.black87,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isPrepared ? const Color(0xFF10B981) : const Color(0xFF69F0AE),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            elevation: 2,
                          ),
                          child: Text(
                            _isPrepared ? '✓ ยืนยันเตียง ER เรียบร้อยแล้ว' : 'ยืนยันเตียง ER พร้อมรับผู้ป่วย',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _isPrepared ? Colors.white : Colors.black87,
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

  Widget _buildDetailRow({
    required String labelTH,
    required String labelEN,
    required String value,
    Color valueColor = Colors.black87,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
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
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    Text(
                      labelEN,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF2E7D32), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Text(':', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Expanded(
                flex: 6,
                child: Text(
                  value,
                  style: TextStyle(fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: valueColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Divider(color: Colors.grey.shade200, thickness: 1),
        ],
      ),
    );
  }
}