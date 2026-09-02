import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final String nextTurnInstruction;

  const RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.nextTurnInstruction,
  });
}

/// Service to fetch real road-network navigation routes using OpenStreetMap OSRM API
class OsrmRoutingService {
  static final OsrmRoutingService _instance = OsrmRoutingService._internal();
  factory OsrmRoutingService() => _instance;
  OsrmRoutingService._internal();

  // Simple in-memory cache to avoid duplicate network calls
  final Map<String, RouteResult> _routeCache = {};

  /// Fetches curved road polyline and turn steps between start and destination
  Future<RouteResult> getDrivingRoute({
    required LatLng start,
    required LatLng destination,
  }) async {
    final cacheKey =
        '${start.latitude.toStringAsFixed(4)},${start.longitude.toStringAsFixed(4)}->${destination.latitude.toStringAsFixed(4)},${destination.longitude.toStringAsFixed(4)}';

    if (_routeCache.containsKey(cacheKey)) {
      return _routeCache[cacheKey]!;
    }

    final url = Uri.parse(
      'http://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson&steps=true',
    );

    try {
      final response =
          await http.get(url).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final primaryRoute = routes[0];
          final geometry = primaryRoute['geometry'];
          final coordinates = geometry['coordinates'] as List?;

          final List<LatLng> points = [];
          if (coordinates != null) {
            for (var coord in coordinates) {
              final lon = (coord[0] as num).toDouble();
              final lat = (coord[1] as num).toDouble();
              points.add(LatLng(lat, lon));
            }
          }

          final double distance =
              (primaryRoute['distance'] as num?)?.toDouble() ?? 0.0;
          final double duration =
              (primaryRoute['duration'] as num?)?.toDouble() ?? 0.0;

          // Parse next turn step
          String turnInstruction = 'มุ่งหน้าตามเส้นทางหลัก';
          final legs = primaryRoute['legs'] as List?;
          if (legs != null && legs.isNotEmpty) {
            final steps = legs[0]['steps'] as List?;
            if (steps != null && steps.length > 1) {
              final nextStep = steps[1];
              final maneuver = nextStep['maneuver'];
              final type = maneuver?['type'] ?? '';
              final modifier = maneuver?['modifier'] ?? '';
              final streetName = nextStep['name'] ?? '';

              if (type == 'turn' || type == 'end of road') {
                if (modifier.contains('right')) {
                  turnInstruction =
                      'เตรียมเลี้ยวขวา ${streetName.isNotEmpty ? "เข้า $streetName" : ""}';
                } else if (modifier.contains('left')) {
                  turnInstruction =
                      'เตรียมเลี้ยวซ้าย ${streetName.isNotEmpty ? "เข้า $streetName" : ""}';
                }
              } else if (type == 'fork') {
                turnInstruction = 'ชิดขวาตามทางแยก';
              } else if (type == 'roundabout') {
                turnInstruction = 'เข้าสู่วงเวียน';
              }
            }
          }

          final result = RouteResult(
            points: points.isNotEmpty ? points : [start, destination],
            distanceMeters: distance,
            durationSeconds: duration,
            nextTurnInstruction: turnInstruction,
          );

          _routeCache[cacheKey] = result;
          return result;
        }
      }
    } catch (e) {
      debugPrint('OSRM Route fetch fallback: $e');
    }

    // Fallback: Generate interpolated linear route points if offline
    final fallbackPoints = _generateFallbackInterpolation(start, destination);
    return RouteResult(
      points: fallbackPoints,
      distanceMeters: const Distance().as(LengthUnit.Meter, start, destination),
      durationSeconds: 120,
      nextTurnInstruction: 'กำลังนำทางตามเส้นทางตรง',
    );
  }

  /// Generates smooth interpolated waypoints between two points
  List<LatLng> _generateFallbackInterpolation(LatLng p1, LatLng p2) {
    final List<LatLng> res = [];
    const int steps = 12;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final lat = p1.latitude + (p2.latitude - p1.latitude) * t;
      final lon = p1.longitude + (p2.longitude - p1.longitude) * t;
      res.add(LatLng(lat, lon));
    }
    return res;
  }
}
