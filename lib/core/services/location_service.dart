import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// ตำแหน่งมาจากไหน — ผู้แจ้งเหตุต้องรู้ว่าพิกัดเชื่อได้แค่ไหนก่อนส่งเคส
enum LocationSource { gps, lastKnown, unavailable }

class LocationFix {
  const LocationFix(this.point, this.source, {this.age});
  const LocationFix.unavailable() : point = null, source = LocationSource.unavailable, age = null;
  final LatLng? point;
  final LocationSource source;
  final Duration? age; // อายุของตำแหน่งล่าสุดที่รู้ (lastKnown)
  bool get hasPoint => point != null;
}

/// จุดจาก GPS 1 ค่า (ตัดมาจาก Position ให้ทดสอบได้โดยไม่ต้องมีเครื่องจริง)
typedef GpsSample = ({LatLng point, DateTime at});

class LocationService {
  /// ตำแหน่งล่าสุดที่รู้ใช้แทนได้ถ้าไม่เก่ากว่านี้ — เก่ากว่านี้คนอาจเดินทางไปไกลแล้ว
  static const Duration lastKnownMaxAge = Duration(minutes: 5);

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

  /// หาตำแหน่งปัจจุบัน: GPS → ตำแหน่งล่าสุดที่รู้ (ไม่เกิน 5 นาที) → หาไม่ได้
  /// เดิม getCurrentLocation() คืนพิกัดประตูท่าแพเมื่อหาไม่ได้ (ไม่มีสิทธิ์/ปิด GPS/เกิน 3 วิ)
  /// หน้าแจ้งเหตุจึงปักหมุดเคสไว้ที่ท่าแพโดยไม่เตือน และรถพยาบาล/ผู้ขับขี่ถูกวางไว้ที่จุดปลอม
  /// (เจอจากสถานการณ์ทดสอบ G02, G03)
  static Future<LocationFix> resolveFix({
    Duration timeLimit = const Duration(seconds: 8),
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      return Future.value(const LocationFix.unavailable());
    }
    GpsSample sample(Position p) => (point: LatLng(p.latitude, p.longitude), at: p.timestamp);
    return resolveFixWith(
      permission: handleLocationPermission,
      current: () async => sample(await Geolocator.getCurrentPosition(
            locationSettings: LocationSettings(accuracy: accuracy, timeLimit: timeLimit),
          )),
      lastKnown: () async {
        final p = await Geolocator.getLastKnownPosition();
        return p == null ? null : sample(p);
      },
    );
  }

  @visibleForTesting
  static Future<LocationFix> resolveFixWith({
    required Future<bool> Function() permission,
    required Future<GpsSample?> Function() current,
    required Future<GpsSample?> Function() lastKnown,
    DateTime Function()? clock,
  }) async {
    final now = (clock ?? DateTime.now)();
    bool allowed;
    try {
      allowed = await permission();
    } catch (_) {
      allowed = false;
    }
    if (!allowed) return const LocationFix.unavailable(); // ไม่มีสิทธิ์ = ห้ามเดาจาก cache เช่นกัน
    try {
      final fix = await current();
      if (fix != null && isPlausible(fix.point)) return LocationFix(fix.point, LocationSource.gps);
    } catch (_) {}
    try {
      final last = await lastKnown();
      if (last != null && isPlausible(last.point)) {
        final age = now.difference(last.at);
        if (age <= lastKnownMaxAge) return LocationFix(last.point, LocationSource.lastKnown, age: age);
      }
    } catch (_) {}
    return const LocationFix.unavailable();
  }

  /// พิกัดที่ใช้ได้จริง — GPS บางเครื่องรายงาน (0,0) หรือ NaN ตอนยังจับดาวเทียมไม่ได้
  static bool isPlausible(LatLng p) =>
      p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude.abs() <= 90 &&
      p.longitude.abs() <= 180 &&
      !(p.latitude.abs() < 1e-6 && p.longitude.abs() < 1e-6);

  /// ตำแหน่งปัจจุบัน หรือ null ถ้าหาไม่ได้ (ไม่คืนพิกัดปลอมอีกต่อไป)
  static Future<LatLng?> getCurrentLocation() async => (await resolveFix()).point;

  /// ตำแหน่งจริงของเครื่องตอนนี้ — คืน null ถ้าหาไม่ได้ ใช้กับปุ่ม "ไปตำแหน่งปัจจุบัน"
  static Future<LatLng?> getCurrentLocationOrNull() async =>
      (await resolveFix(timeLimit: const Duration(seconds: 10))).point;

  // สตรีมพิกัดสดแบบ Real-time (Position Stream)
  //
  // [backgroundMode] — ใช้เฉพาะฝั่ง Driver เท่านั้น (ดูฟีเจอร์ "แจ้งเตือนพื้นหลัง"
  // ใน CHANGES_SUMMARY.md): เมื่อเป็น true จะขอ LocationSettings แบบเฉพาะแพลตฟอร์ม
  // ที่ทำให้ระบบปฏิบัติการยังคงอัปเดตตำแหน่งต่อเนื่องแม้แอปถูกพับ/ล็อกหน้าจอ —
  // Android จะรันเป็น foreground service พร้อม notification ค้างไว้ (เชื่อถือได้)
  // ส่วน iOS จะขอ allowBackgroundLocationUpdates (เป็น best-effort เท่านั้น เพราะ
  // Apple ยังคงมีสิทธิ์ suspend แอปเบื้องหลังตามดุลพินิจของระบบปฏิบัติการเองได้เสมอ)
  // ค่า default เป็น false เพื่อไม่กระทบผู้เรียกเดิม (Ambulance/Agency ยังใช้ค่าเดิมทุกจุด)
  static Stream<LatLng> getLiveLocationStream({
    bool backgroundMode = false,
    String backgroundNotificationText =
        'กำลังตรวจสอบระยะรถพยาบาลฉุกเฉินใกล้เคียงอยู่เบื้องหลัง',
  }) {
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
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: 'RouteAlert',
            notificationText: backgroundNotificationText,
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
      return positionsToLocations(Geolocator.getPositionStream(locationSettings: locationSettings));
    } catch (_) {
      return const Stream.empty();
    }
  }

  /// แปลงสตรีม GPS ดิบเป็นพิกัดที่ใช้ได้: กรองความแม่นยำ (> 50 ม.) แบบไม่ค้างถาวร,
  /// ทิ้งพิกัดที่เป็นไปไม่ได้ (0,0 / NaN) และ **ไม่ส่งพิกัดปลอมเมื่อ GPS error**
  /// เดิม error → ส่งพิกัดประตูท่าแพเข้าไปในสตรีม: รถพยาบาลที่ GPS หลุดกลางทางกระโดดไปท่าแพ
  /// แล้วประกาศตำแหน่งนั้นให้ทุกเครื่อง (โรงพยาบาลเลือกรถผิดคัน ผู้ขับขี่แถวท่าแพได้เตือนผิด)
  /// ตอนนี้ error ถูกกลืนไว้ ตำแหน่งค้างที่จุดจริงล่าสุดจนกว่า GPS จะกลับมา (สถานการณ์ G07)
  @visibleForTesting
  static Stream<LatLng> positionsToLocations(Stream<Position> raw, {DateTime Function()? clock}) {
    return raw
        .transform(_accuracyFilterWithTimeout(clock: clock))
        .map((Position pos) => LatLng(pos.latitude, pos.longitude))
        .where(isPlausible)
        .transform(StreamTransformer<LatLng, LatLng>.fromHandlers(
          handleError: (Object error, StackTrace stackTrace, EventSink<LatLng> sink) {},
        ));
  }

  // ป้องกันไม่ให้ .where(accuracy<=50) กรองพิกัดทุกค่าทิ้งตลอดไปจนสตรีมค้างนิ่ง
  // (กรณีเครื่อง/สภาพแวดล้อมไม่เคยรายงาน accuracy ดีกว่า 50 เมตรเลย) — ยอมรับพิกัด
  // ถ้า accuracy ผ่านเกณฑ์ปกติ (<=50 เมตร) หรือถ้าผ่านมานานเกิน 15 วินาทีแล้วนับจาก
  // พิกัดที่ "ยอมรับ" ล่าสุด (เอาพิกัดล่าสุดที่มีมาใช้แทน ดีกว่าไม่อัปเดตอะไรเลยตลอด
  // ไป) ยังคงพฤติกรรมกรอง jitter แบบเดิมไว้เป็นเส้นทางหลัก แค่เพิ่ม fallback กันค้าง
  static StreamTransformer<Position, Position> _accuracyFilterWithTimeout({DateTime Function()? clock}) {
    DateTime? lastAcceptedTime;
    const Duration maxStaleDuration = Duration(seconds: 15);

    return StreamTransformer<Position, Position>.fromHandlers(
      handleData: (Position pos, EventSink<Position> sink) {
        final now = (clock ?? DateTime.now)();
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