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

  // เดิมเช็ค staleness เฉพาะตอนมี snapshot ใหม่เข้ามาเท่านั้น (ต่างจาก
  // EmergencyMqttService ฝั่งมือถือที่มี Timer.periodic คอยเช็คซ้ำเองอยู่แล้ว)
  // ถ้ารถคันหนึ่งแอปพังไปเฉยๆ (ไม่ทันส่ง sirenActive:false) แล้วไม่มีรถคันอื่น
  // อัปเดตอะไรอีกเลย เอกสารเก่านั้นจะค้างสถานะ "ออนไลน์" ตลอดไปไม่มีวันถูกกรอง
  // ออก เสี่ยงมากเพราะเว็บ Agency ใช้ fleet นี้เลือกรถไปมอบหมายเคสจริง (เจอจาก
  // code review) — เพิ่ม timer เช็คซ้ำเป็นระยะแทน โดยไม่ต้องรอ snapshot ใหม่
  static const Duration _recheckInterval = Duration(seconds: 5);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  Timer? _recheckTimer;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _lastDocs = [];
  final StreamController<List<EmergencyVehicleData>> _controller =
      StreamController<List<EmergencyVehicleData>>.broadcast();

  Stream<List<EmergencyVehicleData>> get fleetStream => _controller.stream;

  void initialize() {
    _sub ??= FirebaseFirestore.instance
        .collection('emergency_fleet')
        .snapshots()
        .listen((snapshot) {
      _lastDocs = snapshot.docs;
      _rebuildAndEmit();
    });
    _recheckTimer ??= Timer.periodic(_recheckInterval, (_) => _rebuildAndEmit());
  }

  void _rebuildAndEmit() {
    final now = DateTime.now();
    final fleet = <EmergencyVehicleData>[];
    for (final doc in _lastDocs) {
      final data = doc.data();
      final updatedAtStr = data['updatedAt'] as String?;
      final updatedAt =
          updatedAtStr != null ? DateTime.tryParse(updatedAtStr) : null;
      // เดิมถ้า updatedAt เป็น null (ไม่มี field/parse ไม่ขึ้น) เงื่อนไขนี้จะ
      // เป็น false ทันที เท่ากับถือว่า "ยังไม่เก่าเกิน" (ออนไลน์อยู่) ทั้งที่ควร
      // ระแวงไว้ก่อนมากกว่า — สลับให้ข้อมูลที่ไม่น่าเชื่อถือแบบนี้ถูกตัดออกไปเลย
      // (ปลอดภัยกว่าตอนใช้เลือกรถไปมอบหมายเคสจริง เจอจาก code review)
      if (updatedAt == null || now.difference(updatedAt) > _staleTimeout) {
        continue; // เอกสารเก่าเกินไป/ข้อมูลไม่น่าเชื่อถือ ไม่นับว่าออนไลน์อยู่
      }
      try {
        fleet.add(EmergencyVehicleData.fromMap(data));
      } catch (_) {
        // เอกสารรูปแบบผิดปกติ ข้ามไปเฉยๆ ไม่ให้ล้มทั้ง stream
      }
    }
    _controller.add(fleet);
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _recheckTimer?.cancel();
    _recheckTimer = null;
    _controller.close();
  }
}
