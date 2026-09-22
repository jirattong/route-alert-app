import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  // Default coordinates (Chiang Mai Center: Thapae Gate)
  static const LatLng defaultLocation = LatLng(18.7883, 98.9853);

  // ตรวจสอบและขอสิทธิ์การเข้าถึงพิกัด GPS
  static Future<bool> handleLocationPermission() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      return true;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  // ดึงตำแหน่งปัจจุบันครั้งแรก (One-time fetch)
  static Future<LatLng?> getCurrentLocation() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      return defaultLocation;
    }

    try {
      final hasPermission = await handleLocationPermission();
      if (!hasPermission) return defaultLocation;

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 3),
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      return defaultLocation;
    }
  }

  // สตรีมพิกัดสดแบบ Real-time (Position Stream)
  //
  // [backgroundMode] — ใช้เฉพาะฝั่ง Driver เท่านั้น (ดูฟีเจอร์ "แจ้งเตือนพื้นหลัง"
  // ใน CHANGES_SUMMARY.md): เมื่อเป็น true จะขอ LocationSettings แบบเฉพาะแพลตฟอร์ม
  // ที่ทำให้ระบบปฏิบัติการยังคงอัปเดตตำแหน่งต่อเนื่องแม้แอปถูกพับ/ล็อกหน้าจอ —
  // Android จะรันเป็น foreground service พร้อม notification ค้างไว้ (เชื่อถือได้)
  // ส่วน iOS จะขอ allowBackgroundLocationUpdates (เป็น best-effort เท่านั้น เพราะ
  // Apple ยังคงมีสิทธิ์ suspend แอปเบื้องหลังตามดุลพินิจของระบบปฏิบัติการเองได้เสมอ)
  // ค่า default เป็น false เพื่อไม่กระทบผู้เรียกเดิม (Ambulance/Agency ยังใช้ค่าเดิมทุกจุด)
  static Stream<LatLng> getLiveLocationStream({bool backgroundMode = false}) {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      // Return a safe empty stream on desktop to avoid Windows non-platform thread crashes
      return const Stream.empty();
    }

    try {
      LocationSettings locationSettings;

      if (backgroundMode && !kIsWeb && Platform.isAndroid) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3, // อัปเดตเมื่อขยับเกิน 3 เมตร
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'RouteAlert',
            notificationText:
                'กำลังตรวจสอบระยะรถพยาบาลฉุกเฉินใกล้เคียงอยู่เบื้องหลัง',
            enableWakeLock: true,
          ),
        );
      } else if (backgroundMode && !kIsWeb && Platform.isIOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
          allowBackgroundLocationUpdates: true,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3, // อัปเดตเมื่อขยับเกิน 3 เมตร
        );
      }

      // เดิมไม่มีการกรองความแม่นยำเลย ทุกพิกัดดิบจาก GPS ถูกส่งต่อตรงๆ ทันที
      // — ตอนอยู่ในอาคาร/มีสิ่งกีดขวางสัญญาณดาวเทียม (เช่นทดสอบในห้องเรียน/ตึก)
      // เครื่องมักรายงานพิกัดที่ผิดเพี้ยนสลับไปมาหลายสิบเมตรในไม่กี่วินาที ทำให้
      // ตำแหน่งบนแผนที่ "วาปไปวาปมา" ทั้งที่คนไม่ได้ขยับจริง แก้โดยทิ้งพิกัดที่ระบบ
      // เองรายงานค่าความแม่นยำ (accuracy) แย่เกินไป (รัศมีความผิดพลาด > 50 เมตร)
      // ก่อนส่งต่อให้ UI ใช้งาน — ตัวเลข 50 เป็นค่ากลางๆ ที่ยังพอให้ทดสอบในอาคารได้
      // แต่กรองสัญญาณสะท้อนเพี้ยนรุนแรงออกไป ปรับได้ถ้าพบว่ายังหลวม/แน่นเกินไป
      //
      // แต่ .where() ตรงๆ แบบเดิมมีความเสี่ยง: ถ้าเครื่อง/สภาพแวดล้อมไม่เคยรายงาน
      // accuracy ดีกว่า 50 เมตรเลย (เช่น emulator บางตัว หรือโหมด network-based
      // location ในอาคาร) พิกัดทุกค่าจะถูกกรองทิ้งตลอดไป สตรีมจะไม่ยิง event อะไร
      // อีกเลย โดยไม่มีสัญญาณใดๆ ให้ UI รู้ (เห็นแค่หมุดค้างไม่ขยับ) จึงเปลี่ยนมาใช้
      // _accuracyFilterWithTimeout() แทน .where() ตรงๆ เพื่อกันสตรีมค้างแบบถาวร
      return Geolocator.getPositionStream(locationSettings: locationSettings)
          .transform(_accuracyFilterWithTimeout())
          .map((Position pos) => LatLng(pos.latitude, pos.longitude))
          // เดิมใช้ .handleError((_) => defaultLocation) ซึ่งเป็นข้อผิดพลาดที่พบบ่อย
          // ใน Dart: callback ของ Stream.handleError() เป็นแค่ side-effect handler
          // ค่าที่ return ออกมาจะถูกทิ้งเสมอ ไม่มีทางถูกแทรกเป็น data event เข้าไปใน
          // สตรีมได้จริง ผลคือเมื่อ Geolocator.getPositionStream() error ค่า fallback
          // defaultLocation ที่ตั้งใจไว้ไม่เคยถูกส่งออกไปจริงๆ สักครั้ง — error แค่ถูก
          // กลืนเงียบๆ สตรีมก็แค่ไม่ยิง event รอบนั้นไปเฉยๆ ไม่มีสัญญาณอะไรให้ UI เลย
          // แก้โดยใช้ StreamTransformer.fromHandlers พร้อม sink.add() ซึ่งเป็นวิธีที่
          // ถูกต้องในการแปลง error ให้กลายเป็น data event จริงๆ
          .transform(StreamTransformer<LatLng, LatLng>.fromHandlers(
            handleError: (Object error, StackTrace stackTrace,
                EventSink<LatLng> sink) {
              sink.add(defaultLocation);
            },
          ));
    } catch (_) {
      return const Stream.empty();
    }
  }

  // ป้องกันไม่ให้ .where(accuracy<=50) กรองพิกัดทุกค่าทิ้งตลอดไปจนสตรีมค้างนิ่ง
  // (กรณีเครื่อง/สภาพแวดล้อมไม่เคยรายงาน accuracy ดีกว่า 50 เมตรเลย) — ยอมรับพิกัด
  // ถ้า accuracy ผ่านเกณฑ์ปกติ (<=50 เมตร) หรือถ้าผ่านมานานเกิน 15 วินาทีแล้วนับจาก
  // พิกัดที่ "ยอมรับ" ล่าสุด (เอาพิกัดล่าสุดที่มีมาใช้แทน ดีกว่าไม่อัปเดตอะไรเลยตลอด
  // ไป) ยังคงพฤติกรรมกรอง jitter แบบเดิมไว้เป็นเส้นทางหลัก แค่เพิ่ม fallback กันค้าง
  static StreamTransformer<Position, Position> _accuracyFilterWithTimeout() {
    DateTime? lastAcceptedTime;
    const Duration maxStaleDuration = Duration(seconds: 15);

    return StreamTransformer<Position, Position>.fromHandlers(
      handleData: (Position pos, EventSink<Position> sink) {
        final now = DateTime.now();
        final bool goodAccuracy = pos.accuracy <= 50;
        final bool timedOut = lastAcceptedTime == null ||
            now.difference(lastAcceptedTime!) > maxStaleDuration;

        if (goodAccuracy || timedOut) {
          lastAcceptedTime = now;
          sink.add(pos);
        }
      },
    );
  }

  // คำนวณระยะห่างระหว่างพิกัด 2 จุด (คืนค่าเป็นกิโลเมตร)
  static double calculateDistanceInKm(LatLng start, LatLng end) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Kilometer, start, end);
  }

  // คำนวณระยะห่างระหว่างพิกัด 2 จุด (คืนค่าเป็นเมตร)
  static double calculateDistanceInMeters(LatLng start, LatLng end) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, start, end);
  }

  // คำนวณทิศทางการเคลื่อนที่จริง (Bearing) จากจุดก่อนหน้าไปจุดปัจจุบัน (0-360 องศา)
  static double calculateBearingDeg(LatLng start, LatLng end) {
    final double lat1 = start.latitude * math.pi / 180;
    final double lat2 = end.latitude * math.pi / 180;
    final double dLon = (end.longitude - start.longitude) * math.pi / 180;

    final double y = math.sin(dLon) * math.cos(lat2);
    final double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final double bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }
}