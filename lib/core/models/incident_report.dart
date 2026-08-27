import 'dart:convert';
import 'package:flutter/material.dart';

class IncidentReport {
  final String id;
  final String type;
  final String severity;
  final String description;
  final double latitude;
  final double longitude;
  final String province;
  final String address;
  final String? photoBase64;
  final String reporterName;
  final String reporterEmail;
  final String reporterPhone;
  final String status; // 'pending' | 'assigned' | 'in_progress' | 'at_scene' | 'transporting' | 'resolved'
  final int statusStep; // 0: รอยืนยัน, 1: กำลังไปรับเคส, 2: ถึงจุดเกิดเหตุ, 3: กำลังไป รพ., 4: ถึง รพ. เรียบร้อย
  final bool isErPrepared; // โรงพยาบาลเตรียมห้องฉุกเฉินแล้วหรือไม่
  final String eta; // e.g. "4 นาที"
  final String? assignedAmbulanceId;
  final String? assignedAmbulancePlate;
  final DateTime createdAt;

  IncidentReport({
    required this.id,
    required this.type,
    required this.severity,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.province,
    required this.address,
    this.photoBase64,
    required this.reporterName,
    required this.reporterEmail,
    this.reporterPhone = '',
    this.status = 'pending',
    this.statusStep = 0,
    this.isErPrepared = false,
    this.eta = '5 นาที',
    this.assignedAmbulanceId,
    this.assignedAmbulancePlate,
    required this.createdAt,
  });

  bool get canBeCancelled => status == 'pending' && statusStep == 0;

  Color get statusColor {
    switch (status) {
      case 'cancelled':
        return const Color(0xFF94A3B8); // Slate Grey
      case 'resolved':
        return const Color(0xFF10B981); // Emerald
      case 'transporting':
      case 'at_scene':
      case 'in_progress':
        return const Color(0xFFF59E0B); // Amber
      case 'assigned':
        return const Color(0xFF5B9EE1); // Blue
      case 'pending':
      default:
        return const Color(0xFFEB5757); // Red
    }
  }

  String get statusText {
    switch (status) {
      case 'cancelled':
        return 'ยกเลิกการแจ้งเหตุ';
      case 'resolved':
        return 'ช่วยเหลือเสร็จสิ้น';
      case 'transporting':
        return 'กำลังนำส่งโรงพยาบาล';
      case 'at_scene':
        return 'ถึงจุดเกิดเหตุแล้ว';
      case 'in_progress':
        return 'กำลังดำเนินการช่วยเหลือ';
      case 'assigned':
        return 'กำลังเดินทางไปยังที่เกิดเหตุ';
      case 'pending':
      default:
        return 'กำลังรอยืนยัน';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'severity': severity,
      'description': description,
      'latitude': latitude,
      'longitude': longitude,
      'province': province,
      'address': address,
      'photoBase64': photoBase64,
      'reporterName': reporterName,
      'reporterEmail': reporterEmail,
      'reporterPhone': reporterPhone,
      'status': status,
      'statusStep': statusStep,
      'isErPrepared': isErPrepared,
      'eta': eta,
      'assignedAmbulanceId': assignedAmbulanceId,
      'assignedAmbulancePlate': assignedAmbulancePlate,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory IncidentReport.fromMap(Map<String, dynamic> map) {
    return IncidentReport(
      id: map['id'] ?? '',
      type: map['type'] ?? 'อุบัติเหตุทางรถยนต์',
      severity: map['severity'] ?? 'วิกฤต (Code Red)',
      description: map['description'] ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 19.0284,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 99.8962,
      province: map['province'] ?? 'เชียงใหม่',
      address: map['address'] ?? '',
      photoBase64: map['photoBase64'],
      reporterName: map['reporterName'] ?? 'ผู้ใช้งาน RouteAlert',
      reporterEmail: map['reporterEmail'] ?? '',
      reporterPhone: map['reporterPhone'] ?? '',
      status: map['status'] ?? 'pending',
      statusStep: (map['statusStep'] as num?)?.toInt() ?? 0,
      isErPrepared: map['isErPrepared'] == true,
      eta: map['eta'] ?? '5 นาที',
      assignedAmbulanceId: map['assignedAmbulanceId'],
      assignedAmbulancePlate: map['assignedAmbulancePlate'],
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  String toJson() => json.encode(toMap());
  factory IncidentReport.fromJson(String str) =>
      IncidentReport.fromMap(json.decode(str));

  IncidentReport copyWith({
    String? id,
    String? type,
    String? severity,
    String? description,
    double? latitude,
    double? longitude,
    String? province,
    String? address,
    String? photoBase64,
    String? reporterName,
    String? reporterEmail,
    String? reporterPhone,
    String? status,
    int? statusStep,
    bool? isErPrepared,
    String? eta,
    String? assignedAmbulanceId,
    String? assignedAmbulancePlate,
    DateTime? createdAt,
  }) {
    return IncidentReport(
      id: id ?? this.id,
      type: type ?? this.type,
      severity: severity ?? this.severity,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      province: province ?? this.province,
      address: address ?? this.address,
      photoBase64: photoBase64 ?? this.photoBase64,
      reporterName: reporterName ?? this.reporterName,
      reporterEmail: reporterEmail ?? this.reporterEmail,
      reporterPhone: reporterPhone ?? this.reporterPhone,
      status: status ?? this.status,
      statusStep: statusStep ?? this.statusStep,
      isErPrepared: isErPrepared ?? this.isErPrepared,
      eta: eta ?? this.eta,
      assignedAmbulanceId: assignedAmbulanceId ?? this.assignedAmbulanceId,
      assignedAmbulancePlate:
          assignedAmbulancePlate ?? this.assignedAmbulancePlate,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
