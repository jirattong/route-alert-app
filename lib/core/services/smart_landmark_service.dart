import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'hospital_location_service.dart';

/// Smart Landmark & POI Service
/// Identifies concise, real-world shop/restaurant/landmark names (e.g. "ใกล้ร้าน KFC", "ใกล้ร้านก๋วยเตี๋ยว...")
/// If no genuine shop or prominent landmark exists at the coordinates, returns empty string ""
/// without fabricating addresses or cluttering with long sub-district text.
class SmartLandmarkService {
  static final SmartLandmarkService _instance = SmartLandmarkService._internal();
  factory SmartLandmarkService() => _instance;
  SmartLandmarkService._internal();

  /// Identifies concise nearby shop or landmark name. Returns "" if none found.
  Future<String> getSmartLandmark(LatLng coords) async {
    // 1. If very close to a major hospital (within 300 meters)
    try {
      final nearestHospital = HospitalLocationService().findNearestHospital(coords);
      if (nearestHospital.distanceKm <= 0.3) {
        return 'หน้า ${nearestHospital.profile.hospitalName}';
      }
    } catch (_) {}

    // 2. Query OpenStreetMap Nominatim for exact POI (Shop, Restaurant, Amenity)
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${coords.latitude}&lon=${coords.longitude}&zoom=19&addressdetails=1&extratags=1',
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'RouteAlertEmergency/2.0 (dispatch@routealert.app)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(milliseconds: 2800));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final String name = (data['name'] ?? '').toString().trim();
        final String rawClass = (data['class'] ?? '').toString().trim().toLowerCase();
        final String rawType = (data['type'] ?? '').toString().trim().toLowerCase();
        final address = data['address'] as Map<String, dynamic>?;

        // A. Direct POI Name Found
        if (name.isNotEmpty && !_isGenericGeographicName(name, address)) {
          if (rawClass == 'shop' ||
              rawType == 'restaurant' ||
              rawType == 'cafe' ||
              rawType == 'fast_food' ||
              rawType == 'food_court' ||
              rawType == 'bakery' ||
              rawType == 'bar') {
            return 'ใกล้ร้าน $name';
          }
          if (rawType == 'fuel' || name.contains('ปั๊ม') || name.contains('ปตท') || name.contains('บางจาก') || name.contains('PTT')) {
            return name.contains('ปั๊ม') ? 'ใกล้ $name' : 'ใกล้ปั๊ม $name';
          }
          if (name.toLowerCase().contains('7-eleven') ||
              name.toLowerCase().contains('lotus') ||
              name.toLowerCase().contains('cj') ||
              name.toLowerCase().contains('big c') ||
              rawType == 'convenience' ||
              rawType == 'supermarket') {
            return 'ใกล้ $name';
          }
          if (rawClass == 'amenity' || rawClass == 'tourism' || rawClass == 'building' || rawClass == 'leisure') {
            return 'ใกล้ $name';
          }
        }

        // B. Check Address Specific Business Fields
        if (address != null) {
          final restaurant = address['restaurant']?.toString().trim();
          if (restaurant != null && restaurant.isNotEmpty) {
            return 'ใกล้ร้าน $restaurant';
          }
          final cafe = address['cafe']?.toString().trim();
          if (cafe != null && cafe.isNotEmpty) {
            return 'ใกล้ร้าน $cafe';
          }
          final fastFood = address['fast_food']?.toString().trim();
          if (fastFood != null && fastFood.isNotEmpty) {
            return 'ใกล้ร้าน $fastFood';
          }
          final shop = address['shop']?.toString().trim();
          if (shop != null && shop.isNotEmpty) {
            return 'ใกล้ร้าน $shop';
          }
          final fuel = address['fuel']?.toString().trim();
          if (fuel != null && fuel.isNotEmpty) {
            return 'ใกล้ปั๊ม $fuel';
          }
          final amenity = address['amenity']?.toString().trim();
          if (amenity != null && amenity.isNotEmpty && !_isGenericGeographicName(amenity, address)) {
            return 'ใกล้ $amenity';
          }
        }
      }
    } catch (e) {
      debugPrint('SmartLandmarkService POI search: $e');
    }

    // 3. If no specific shop or landmark is found, RETURN EMPTY STRING!
    // Do NOT guess, do NOT output long administrative districts or fake places.
    return '';
  }

  /// Filters out generic administrative/road strings from being mistaken for shop names
  bool _isGenericGeographicName(String val, Map<String, dynamic>? address) {
    final lower = val.toLowerCase();
    if (lower == 'thailand' ||
        lower == 'ประเทศไทย' ||
        lower.startsWith('ถนน') ||
        lower.startsWith('ถ.') ||
        lower.startsWith('ซอย') ||
        lower.startsWith('ซ.') ||
        lower.startsWith('ตำบล') ||
        lower.startsWith('ต.') ||
        lower.startsWith('อำเภอ') ||
        lower.startsWith('อ.') ||
        lower.startsWith('จังหวัด') ||
        lower.startsWith('จ.') ||
        lower.startsWith('แขวง')) {
      return true;
    }

    if (address != null) {
      if (val == address['road'] ||
          val == address['suburb'] ||
          val == address['city_district'] ||
          val == address['county'] ||
          val == address['province'] ||
          val == address['country']) {
        return true;
      }
    }

    return false;
  }
}
