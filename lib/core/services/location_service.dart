import 'dart:async';
import 'dart:io' show Platform;
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
  static Stream<LatLng> getLiveLocationStream() {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      // Return a safe empty stream on desktop to avoid Windows non-platform thread crashes
      return const Stream.empty();
    }

    try {
      const LocationSettings locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3, // อัปเดตเมื่อขยับเกิน 3 เมตร
      );

      return Geolocator.getPositionStream(locationSettings: locationSettings).map(
        (Position pos) => LatLng(pos.latitude, pos.longitude),
      ).handleError((_) => defaultLocation);
    } catch (_) {
      return const Stream.empty();
    }
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
}