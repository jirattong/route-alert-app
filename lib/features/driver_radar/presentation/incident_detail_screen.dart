import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/incident_report.dart';
import '../../../core/services/incident_service.dart';

class IncidentDetailScreen extends StatelessWidget {
  final IncidentReport? incident;
  final Map<String, dynamic>? incidentData;

  const IncidentDetailScreen({
    super.key,
    this.incident,
    this.incidentData,
  });

  void _onCancelIncident(BuildContext context, String incidentId) {
    String selectedReason = 'แจ้งเหตุผิดพลาด / กดโดนโดยไม่ได้ตั้งใจ';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEE2E2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'ยกเลิกการแจ้งเหตุฉุกเฉิน (Cancel SOS)',
                      style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'คุณสามารถยกเลิกการแจ้งเหตุได้เฉพาะช่วงที่ "กำลังรอยืนยัน" ก่อนที่รถพยาบาลจะออกปฏิบัติการ',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                const Text('กรุณาระบุเหตุผลการยกเลิก:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 8),
                ...[
                  'แจ้งเหตุผิดพลาด / กดโดนโดยไม่ได้ตั้งใจ',
                  'ได้รับการช่วยเหลือจากหน่วยงานอื่นแล้ว',
                  'ผู้ป่วย/ผู้บาดเจ็บอาการดีขึ้นแล้ว',
                  'นำส่งโรงพยาบาลด้วยตนเอง',
                ].map(
                  (reason) => InkWell(
                    onTap: () => setModalState(() => selectedReason = reason),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          Icon(
                            selectedReason == reason
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_off_rounded,
                            color: selectedReason == reason
                                ? const Color(0xFFDC2626)
                                : Colors.grey.shade400,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              reason,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: selectedReason == reason
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: selectedReason == reason
                                    ? const Color(0xFFDC2626)
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('ไม่ยกเลิก', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final success = await IncidentService().cancelIncident(
                            incidentId,
                            reason: selectedReason,
                          );
                          if (context.mounted) {
                            if (success) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ ยกเลิกการแจ้งเหตุฉุกเฉินเรียบร้อยแล้ว'),
                                  backgroundColor: Color(0xFF10B981),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('⚠️ ไม่สามารถยกเลิกได้ เนื่องจากรถพยาบาลกำลังออกปฏิบัติการแล้ว'),
                                  backgroundColor: Color(0xFFDC2626),
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('ยืนยันยกเลิก', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String id = incident?.id ?? incidentData?['id'] ?? 'Case #AVCB00021';
    final String type = incident?.type ?? incidentData?['type'] ?? 'อุบัติเหตุทางรถยนต์';
    final String severity = incident?.severity ?? incidentData?['severity'] ?? 'วิกฤต (Code Red)';
    final String status = incident?.statusText ?? incidentData?['status'] ?? 'กำลังรอยืนยัน';
    final Color statusColor = incident?.statusColor ?? incidentData?['statusColor'] ?? const Color(0xFF5B9EE1);
    final String address = incident?.address ?? incidentData?['location'] ?? 'อ.ฝาง จ.เชียงใหม่';
    final String desc = incident?.description ?? incidentData?['description'] ?? '-';
    final String? photoBase64 = incident?.photoBase64;
    final String carPlate = incident?.assignedAmbulancePlate ?? incidentData?['carPlate'] ?? 'รอศูนย์จ่ายงาน';
    final bool canCancel = incident?.canBeCancelled ?? false;
    final bool isCancelled = incident?.status == 'cancelled';

    final LatLng incidentLocation = incident != null
        ? LatLng(incident!.latitude, incident!.longitude)
        : const LatLng(19.0284, 99.8962);
    final LatLng ambulanceLocation = LatLng(
      incidentLocation.latitude + 0.007,
      incidentLocation.longitude + 0.007,
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // แผนที่จุดเกิดเหตุ
                    SizedBox(
                      height: 240,
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
                                    points: [ambulanceLocation, incidentLocation],
                                    strokeWidth: 4.0,
                                    color: const Color(0xFFEB5757),
                                  ),
                                ],
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: ambulanceLocation,
                                    width: 44,
                                    height: 44,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(color: Colors.black26, blurRadius: 6)
                                        ],
                                      ),
                                      child: const Center(
                                          child: Text('🚑', style: TextStyle(fontSize: 22))),
                                    ),
                                  ),
                                  Marker(
                                    point: incidentLocation,
                                    width: 38,
                                    height: 38,
                                    child: const Icon(
                                      Icons.location_on_rounded,
                                      color: Color(0xFFEB5757),
                                      size: 40,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Positioned(
                            top: 14,
                            left: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: statusColor, width: 1.5),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black12, blurRadius: 6)
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // รหัสเคส
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFDE8E8),
                              shape: BoxShape.circle,
                            ),
                            child: const Text('🚨', style: TextStyle(fontSize: 20)),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                id,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const Text(
                                'แจ้งเหตุผ่าน RouteAlert SOS Network',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Divider(color: Colors.grey.shade300, thickness: 1),
                    ),
                    const SizedBox(height: 10),

                    // รูปภาพที่แนบมา (ถ้ามี)
                    if (photoBase64 != null && photoBase64.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(
                            base64Decode(photoBase64),
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // รายละเอียดเคส
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        children: [
                          _buildDetailRow(
                            labelTH: 'สถานะ',
                            labelEN: '(Status)',
                            value: status,
                            valueColor: statusColor,
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
                          if (desc.isNotEmpty && desc != '-')
                            _buildDetailRow(
                              labelTH: 'รายละเอียดเพิ่มเติม',
                              labelEN: '(Description)',
                              value: desc,
                            ),
                          _buildDetailRow(
                            labelTH: 'รถกู้ชีพที่รับเคส',
                            labelEN: '(Assigned Ambulance)',
                            value: carPlate,
                            valueColor: const Color(0xFF00A896),
                            isBold: true,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ปุ่มยกเลิกการแจ้งเหตุ (เฉพาะตอนกำลังรอยืนยัน)
                    if (incident != null && canCancel) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _onCancelIncident(context, incident!.id),
                            icon: const Icon(Icons.cancel_outlined, color: Color(0xFFDC2626), size: 20),
                            label: const Text(
                              '❌ ขอยกเลิกการแจ้งเหตุนี้ (Cancel SOS)',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Text(
                          '* สามารถกดยกเลิกได้เฉพาะก่อนที่รถพยาบาลจะกดรับเคสและออกเดินทาง',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ] else if (isCancelled) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.grey, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'เหตุนี้ถูกยกเลิกแล้ว (ไม่มีการส่งรถพยาบาล)',
                                  style: TextStyle(fontSize: 12.5, color: Colors.black54, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else if (incident != null && !canCancel && incident!.status != 'resolved') ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF93C5FD)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.lock_clock_rounded, color: Color(0xFF2563EB), size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '🔒 รถพยาบาลกำลังออกปฏิบัติการ (ไม่สามารถยกเลิกผ่านแอพได้ หากต้องการติดต่อกรุณาโทร 1669)',
                                  style: TextStyle(fontSize: 11.5, color: Color(0xFF1E40AF), fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
            'RouteAlert Incident',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
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
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    Text(
                      labelEN,
                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF5B9EE1), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Text(':', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black54)),
              const SizedBox(width: 10),
              Expanded(
                flex: 6,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                    color: valueColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.grey.shade200, thickness: 1),
        ],
      ),
    );
  }
}