import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/models/incident_report.dart';

class IncidentDetailScreen extends StatelessWidget {
  final IncidentReport? incident;
  final Map<String, dynamic>? incidentData;

  const IncidentDetailScreen({
    super.key,
    this.incident,
    this.incidentData,
  });

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
                            left: 14,
                            child: CircleAvatar(
                              backgroundColor: Colors.white,
                              radius: 20,
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                                    color: Colors.black87, size: 18),
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
                        color: const Color(0xFF8BB7F0).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8BB7F0).withValues(alpha: 0.35),
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