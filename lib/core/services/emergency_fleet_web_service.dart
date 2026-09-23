import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'emergency_mqtt_service.dart' show EmergencyVehicleData;

/// อ่านตำแหน่งรถพยาบาลสำหรับเว็บแดชบอร์ดโดยเฉพาะ — เบราว์เซอร์เชื่อม MQTT
/// (TCP socket ตรง) แบบที่ [EmergencyMqttService] ใช้บนมือถือไม่ได้เลย (ข้อจำกัด
/// ของแซนด์บ็อกซ์เบราว์เซอร์เอง) จึงอ่านจาก Firestore collection 'emergency_fleet'
/// แทน ซึ่งฝั่งมือถือ (รถพยาบาล) เขียนสะท้อนไว้ให้แบบหน่วงเวลา ~4 วิ/ครั้ง
/// (ดู `_mirrorToFirestore` ใน emergency_mqtt_service.dart) — คนละ stream คนละ
/// service กับของมือถือโดยสิ้นเชิง ไม่แตะโค้ด MQTT เดิมเลย
class EmergencyFleetWebService {
  static final EmergencyFleetWebService _instance =
      EmergencyFleetWebService._internal();
  factory EmergencyFleetWebService() => _instance;
  EmergencyFleetWebService._internal();

  // รถที่ไม่มีการอัปเดตนานเกินนี้ถือว่าออฟไลน์ไปแล้ว (เช่น แอปมือถือถูกปิดไป
  // โดยไม่ทันส่ง sirenActive:false ครั้งสุดท้าย) — ค่าเดียวกับที่ EmergencyMqttService
  // ใช้ตรวจสอบฝั่งมือถือ ให้พฤติกรรมสอดคล้องกัน
  static const Duration _staleTimeout = Duration(seconds: 15);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  final StreamController<List<EmergencyVehicleData>> _controller =
      StreamController<List<EmergencyVehicleData>>.broadcast();

  Stream<List<EmergencyVehicleData>> get fleetStream => _controller.stream;

  void initialize() {
    _sub ??= FirebaseFirestore.instance
        .collection('emergency_fleet')
        .snapshots()
        .listen((snapshot) {
      final now = DateTime.now();
      final fleet = <EmergencyVehicleData>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final updatedAtStr = data['updatedAt'] as String?;
        final updatedAt =
            updatedAtStr != null ? DateTime.tryParse(updatedAtStr) : null;
        if (updatedAt != null && now.difference(updatedAt) > _staleTimeout) {
          continue; // เอกสารเก่าเกินไป (ไม่ทันถูกลบ) ไม่นับว่าออนไลน์อยู่
        }
        try {
          fleet.add(EmergencyVehicleData.fromMap(data));
        } catch (_) {
          // เอกสารรูปแบบผิดปกติ ข้ามไปเฉยๆ ไม่ให้ล้มทั้ง stream
        }
      }
      _controller.add(fleet);
    });
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _controller.close();
  }
}
