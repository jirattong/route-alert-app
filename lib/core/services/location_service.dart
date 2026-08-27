import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  // ตรวจสอบและขอสิทธิ์การเข้าถึงพิกัด GPS
  static Future<bool> handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // ผู้ใช้ปิด GPS ไว้
      return false;
    }

    permission = await Geolocator.checkPermission();
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
  }

  // ดึงตำแหน่งปัจจุบันครั้งแรก (One-time fetch)
  static Future<LatLng?> getCurrentLocation() async {
    final hasPermission = await handleLocationPermission();
    if (!hasPermission) return null;

    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      return null;
    }
  }

  // สตรีมพิกัดสดแบบ Real-time (Position Stream)
  static Stream<LatLng> getLiveLocationStream() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3, // อัปเดตเมื่อขยับเกิน 3 เมตร
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings).map(
      (Position pos) => LatLng(pos.latitude, pos.longitude),
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
}