import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// URL ของ Cloudflare Worker (push-worker/) ที่ได้หลัง `npx wrangler deploy`
/// เช่น 'https://route-alert-push.<ชื่อบัญชี>.workers.dev' — เว้นว่างไว้ = ปิดใช้
/// (เช่นตอนใช้ Cloud Functions ใน functions/ แทน ห้ามเปิดทั้งสองพร้อมกัน จะได้แจ้งเตือนซ้ำ)
const String kPushWorkerUrl = '';

// true ถ้า deploy functions/ (Cloud Functions) แทน Worker — เซิร์ฟเวอร์ส่งให้เองทุกครั้งที่เคสเปลี่ยน
const bool kUsingCloudFunctions = false;

/// มีตัวส่ง push ฝั่งเซิร์ฟเวอร์เปิดอยู่ไหม — ถ้าไม่มี แอปใช้ตัวแจ้งเตือนสำรองในเครื่องแทน
const bool serverPushConfigured = kPushWorkerUrl != '' || kUsingCloudFunctions;

/// บอก Worker ว่าเคสนี้เพิ่งถูกบันทึก/เปลี่ยนแปลง — Worker อ่านข้อมูลจริงจาก
/// Firestore แล้วตัดสินใจเองว่าต้องแจ้งใคร ไม่ await ผล (ไม่ให้ UI ต้องรอ)
void notifyIncidentChanged(String incidentId) {
  if (kPushWorkerUrl.isEmpty) return;
  unawaited(() async {
    try {
      await http
          .post(
            Uri.parse(kPushWorkerUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'incidentId': incidentId}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('notifyIncidentChanged error: $e');
    }
  }());
}
