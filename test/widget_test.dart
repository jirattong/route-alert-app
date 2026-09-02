import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_alert/core/models/incident_report.dart';
import 'package:route_alert/core/services/ai_trajectory_service.dart';
import 'package:route_alert/core/services/emergency_mqtt_service.dart';
import 'package:route_alert/core/services/hospital_location_service.dart';

void main() {
  group('Route-Aware & AI Trajectory Engine Unit Tests', () {
    final aiService = AiTrajectoryService();

    test('Test In-Path Critical Conflict Detection', () {
      const driverPos = LatLng(19.0284, 99.8962);
      const ambuPos = LatLng(19.0250, 99.8962); // 378m behind

      final route = [
        ambuPos,
        driverPos,
        const LatLng(19.0350, 99.8962),
      ];

      final result = aiService.evaluateTrajectoryConflict(
        driverPos: driverPos,
        driverSpeedKmh: 50.0,
        driverHeadingDeg: 0.0,
        ambulancePos: ambuPos,
        ambulanceSpeedKmh: 80.0,
        ambulanceHeadingDeg: 0.0,
        maxWarningDistanceMeters: 3000.0,
        routePoints: route,
        turnIntent: 'ตรงไปตามถนนหลัก',
      );

      expect(result.shouldAlert, isTrue);
      expect(result.category, TrajectoryConflictCategory.criticalInPath);
      expect(result.isRouteAwareActive, isTrue);
      expect(result.yieldProbability, greaterThan(0.8));
    });

    test('Test Turn Bypass (No False Alarm When Ambulance Turns Away)', () {
      const driverPos = LatLng(19.0284, 99.8962);
      const ambuPos = LatLng(19.0240, 99.8962);
      const intersection = LatLng(19.0260, 99.8962);

      // Route turns right at intersection onto cross street away from driver
      final route = [
        ambuPos,
        intersection,
        const LatLng(19.0260, 99.9100), // Turns East
      ];

      final result = aiService.evaluateTrajectoryConflict(
        driverPos: driverPos,
        driverSpeedKmh: 50.0,
        driverHeadingDeg: 0.0,
        ambulancePos: ambuPos,
        ambulanceSpeedKmh: 80.0,
        ambulanceHeadingDeg: 0.0,
        maxWarningDistanceMeters: 3000.0,
        routePoints: route,
        turnIntent: 'เตรียมเลี้ยวขวาที่แยกข้างหน้า',
      );

      expect(result.shouldAlert, isFalse);
      expect(result.category, TrajectoryConflictCategory.turnBypass);
      expect(result.isRouteAwareActive, isTrue);
    });

    test('Test Turn-In Approaching Early Warning', () {
      const driverPos = LatLng(19.0284, 99.8962);
      const ambuPos = LatLng(19.0260, 99.8850); // West on side road
      const entryIntersection = LatLng(19.0260, 99.8962);

      // Route goes East then turns North onto driver's road towards driver
      final route = [
        ambuPos,
        entryIntersection,
        driverPos,
        const LatLng(19.0350, 99.8962),
      ];

      final result = aiService.evaluateTrajectoryConflict(
        driverPos: driverPos,
        driverSpeedKmh: 50.0,
        driverHeadingDeg: 0.0,
        ambulancePos: ambuPos,
        ambulanceSpeedKmh: 80.0,
        ambulanceHeadingDeg: 90.0,
        maxWarningDistanceMeters: 3000.0,
        routePoints: route,
        turnIntent: 'เตรียมเลี้ยวซ้ายเข้าถนนของผู้ใช้',
      );

      expect(result.shouldAlert, isTrue);
      expect(result.category, TrajectoryConflictCategory.turnInApproaching);
      expect(result.isRouteAwareActive, isTrue);
    });

    test('Test EmergencyVehicleData JSON Serialization with Route-Aware fields', () {
      final original = EmergencyVehicleData(
        id: 'AMB-TEST-01',
        callSign: 'กู้ชีพพายัพ 01',
        latitude: 19.0284,
        longitude: 99.8962,
        speed: 75.0,
        emergencyType: 'ผู้ป่วยฉุกเฉิน (Red Code)',
        sirenActive: true,
        timestamp: DateTime(2026, 9, 2, 21, 0, 0),
        routePoints: [
          const LatLng(19.0250, 99.8962),
          const LatLng(19.0284, 99.8962),
        ],
        turnIntent: 'เตรียมเลี้ยวขวา 200 ม.',
        destinationName: 'โรงพยาบาลศูนย์',
      );

      final jsonStr = original.toJson();
      final parsed = EmergencyVehicleData.fromJson(jsonStr);

      expect(parsed.id, equals('AMB-TEST-01'));
      expect(parsed.routePoints?.length, equals(2));
      expect(parsed.turnIntent, equals('เตรียมเลี้ยวขวา 200 ม.'));
      expect(parsed.destinationName, equals('โรงพยาบาลศูนย์'));
    });
  });

  group('End-to-End Hospital Command Center & Ambulance Lifecycle Tests', () {
    test('Test HospitalProfile Pinned Location Model & Serialization', () {
      final profile = HospitalProfile(
        hospitalId: 'HOSP-CHIANGMAI-01',
        hospitalName: 'โรงพยาบาลมหาราชนครเชียงใหม่',
        latitude: 19.0284,
        longitude: 99.8962,
        address: '110 ถ.อินทวโรรส ต.ศรีภูมิ อ.เมือง จ.เชียงใหม่',
        erPhone: '053-936150',
        lastUpdated: DateTime(2026, 9, 2, 21, 0, 0),
      );

      final jsonStr = profile.toJson();
      final parsed = HospitalProfile.fromJson(jsonStr);

      expect(parsed.hospitalId, equals('HOSP-CHIANGMAI-01'));
      expect(parsed.hospitalName, equals('โรงพยาบาลมหาราชนครเชียงใหม่'));
      expect(parsed.latitude, equals(19.0284));
      expect(parsed.longitude, equals(99.8962));
      expect(parsed.erPhone, equals('053-936150'));
    });

    test('Test AI Nearest Hospital Matcher (Finds Closest Hospital by GPS Distance)', () {
      final service = HospitalLocationService();

      // Location 1: Close to Suan Dok (Maharaj Hospital: 19.0284, 99.8962)
      const userNearMaharaj = LatLng(19.0290, 99.8970);
      final nearestMaharaj = service.findNearestHospital(userNearMaharaj);
      expect(nearestMaharaj.profile.hospitalId, equals('HOSP-01'));
      expect(nearestMaharaj.distanceKm, lessThan(1.0));

      // Location 2: Close to Mae Rim / Nakornping Hospital (18.8475, 98.9660)
      const userNearNakornping = LatLng(18.8500, 98.9680);
      final nearestNakornping = service.findNearestHospital(userNearNakornping);
      expect(nearestNakornping.profile.hospitalId, equals('HOSP-02'));
      expect(nearestNakornping.profile.hospitalName, contains('นครพิงค์'));
      expect(nearestNakornping.distanceKm, lessThan(2.0));
    });

    test('Test Complete Incident Lifecycle Progression (Pending -> Assigned -> At Scene -> Transporting -> Approaching ER -> Resolved)', () {
      final incident = IncidentReport(
        id: 'INC-2026-001',
        type: 'อุบัติเหตุทางรถยนต์',
        severity: 'วิกฤต (Code Red)',
        description: 'ผู้ป่วยหมดสติ 1 ราย',
        latitude: 19.0400,
        longitude: 99.8962,
        province: 'เชียงใหม่',
        address: 'แยกศรีทรายมูล',
        reporterName: 'นายสมชาย',
        reporterEmail: 'somchai@gmail.com',
        reporterPhone: '081-234-5678',
        status: 'pending',
        statusStep: 0,
        createdAt: DateTime.now(),
      );

      expect(incident.canBeCancelled, isTrue);
      expect(incident.status, equals('pending'));

      // Step 1: Hospital Confirms & Dispatches
      final assigned = incident.copyWith(
        status: 'assigned',
        statusStep: 1,
        assignedAmbulanceId: 'AMB-1669-01',
        assignedAmbulancePlate: 'กขค123 (เชียงใหม่)',
        assignedAmbulanceCallSign: 'หน่วยกู้ชีพนครพิงค์ 01',
        hospitalName: 'โรงพยาบาลมหาราชนคร',
        hospitalLatitude: 19.0284,
        hospitalLongitude: 99.8962,
      );
      expect(assigned.status, equals('assigned'));
      expect(assigned.statusStep, equals(1));
      expect(assigned.canBeCancelled, isFalse);

      // Step 2: Ambulance Arrived At Scene
      final atScene = assigned.copyWith(
        status: 'at_scene',
        statusStep: 2,
      );
      expect(atScene.status, equals('at_scene'));
      expect(atScene.statusStep, equals(2));

      // Step 3: Transporting + Medical Tele-Report (Vital Signs)
      final transporting = atScene.copyWith(
        status: 'transporting',
        statusStep: 3,
        patientCondition: 'ผู้ป่วยหมดสติ ปลุกไม่ตื่น SpO2 88%',
        vitalSigns: 'BP: 85/55, HR: 120, SpO2: 88%',
        medicalNotes: 'On Oxygen Mask with Bag 10 LPM',
        callSessionActive: true,
      );
      expect(transporting.status, equals('transporting'));
      expect(transporting.vitalSigns, contains('BP: 85/55'));
      expect(transporting.callSessionActive, isTrue);

      // Step 4: Approaching ER (< 1.5 km)
      final approaching = transporting.copyWith(
        status: 'approaching_er',
        statusStep: 4,
      );
      expect(approaching.status, equals('approaching_er'));
      expect(approaching.statusStep, equals(4));

      // Step 5: Mission Resolved
      final resolved = approaching.copyWith(
        status: 'resolved',
        statusStep: 5,
        callSessionActive: false,
      );
      expect(resolved.status, equals('resolved'));
      expect(resolved.statusStep, equals(5));

      // JSON Serialization check
      final jsonStr = resolved.toJson();
      final parsed = IncidentReport.fromJson(jsonStr);
      expect(parsed.id, equals('INC-2026-001'));
      expect(parsed.vitalSigns, equals('BP: 85/55, HR: 120, SpO2: 88%'));
      expect(parsed.hospitalLatitude, equals(19.0284));
    });
  });
}
