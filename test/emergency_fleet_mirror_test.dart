import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_alert/core/services/emergency_mqtt_service.dart';

import 'support/scenario_result.dart';

bool _hasNestedList(Object? v) {
  if (v is Map) return v.values.any(_hasNestedList);
  if (v is List) return v.any((e) => e is List || _hasNestedList(e));
  return false;
}

void main() {
  EmergencyVehicleData vehicle(int points) => EmergencyVehicleData(
        id: 'AMB-1',
        callSign: 'กู้ชีพ 1',
        latitude: 19.0,
        longitude: 99.9,
        speed: 40,
        heading: 90,
        plateNumber: 'กข 1',
        emergencyType: 'x',
        sirenActive: true,
        timestamp: DateTime(2026, 9, 28),
        routePoints: [for (var i = 0; i < points; i++) LatLng(19 + i * 1e-4, 99.9)],
      );

  test('[G20] Firestore mirror never contains arrays of arrays (native crash on iOS)', () {
    final map = EmergencyMqttService.firestoreMapFor(vehicle(1500));
    expect(_hasNestedList(map), isFalse);
    final route = map['routePoints'] as List;
    expect(route.length, lessThanOrEqualTo(201));
    expect((route.last as Map)['lat'], closeTo(19 + 1499 * 1e-4, 1e-9));
    scenarioResult(condition: 'รถส่งเส้นทาง 1,500 จุดขึ้น Firestore (ให้เว็บโรงพยาบาลอ่าน)',
        expected: 'ไม่มี array ซ้อน (ทำ iOS เด้ง), ลดจุดไม่เกิน ~200, จุดปลายตรง',
        actual: 'array ซ้อน: ${_hasNestedList(map) ? 'มี' : 'ไม่มี'} · เหลือ ${route.length} จุด · จุดปลาย lat ${(route.last as Map)['lat']}');
  });

  test('[G20] Firestore route format reads back into the same points', () {
    final data = vehicle(10);
    final back = EmergencyVehicleData.fromMap(EmergencyMqttService.firestoreMapFor(data));
    expect(back.routePoints!.length, 10);
    expect(back.routePoints!.first.latitude, closeTo(19.0, 1e-9));
    // MQTT keeps the compact [lat, lng] format and still parses
    expect(EmergencyVehicleData.fromMap(data.toMap()).routePoints!.length, 10);
  });
}
