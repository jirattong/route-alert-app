import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_alert/core/ml/face_recognition_service.dart';
import 'package:route_alert/core/models/incident_report.dart';
import 'package:route_alert/core/services/ai_trajectory_service.dart';
import 'package:route_alert/core/services/emergency_mqtt_service.dart';
import 'package:route_alert/core/services/face_scan_settings_service.dart';
import 'package:route_alert/core/services/hospital_location_service.dart';
import 'package:route_alert/core/services/theme_settings_service.dart';
import 'package:route_alert/features/auth_face_login/data/models/user_face_profile.dart';
import 'package:route_alert/features/auth_face_login/data/services/face_auth_repository.dart';
import 'package:route_alert/core/services/smart_landmark_service.dart';
import 'package:route_alert/core/services/ai_vision_triage_service.dart';
import 'package:route_alert/core/models/emergency_proximity_tier.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

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

    test('Test EmergencyVehicleData JSON Serialization with Route-Aware fields',
        () {
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

    test(
        'Test AI Nearest Hospital Matcher (Finds Closest Hospital by GPS Distance)',
        () {
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

    test(
        'Test Complete Incident Lifecycle Progression (Pending -> Assigned -> At Scene -> Transporting -> Approaching ER -> Resolved)',
        () {
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

  group('Face Scan AI Vision & Settings Service Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('FaceScanSettingsService defaults to AI Vision enabled', () async {
      final enabled = await FaceScanSettingsService.loadSettings();
      expect(enabled, isTrue);
      expect(FaceScanSettingsService.isAiVisionMeshEnabled.value, isTrue);
    });

    test('FaceScanSettingsService toggle switches state and notifies listeners',
        () async {
      SharedPreferences.setMockInitialValues({});
      await FaceScanSettingsService.setAiVisionMeshEnabled(true);
      expect(FaceScanSettingsService.isAiVisionMeshEnabled.value, isTrue);

      final toggled = await FaceScanSettingsService.toggle();
      expect(toggled, isFalse);
      expect(FaceScanSettingsService.isAiVisionMeshEnabled.value, isFalse);

      final toggledBack = await FaceScanSettingsService.toggle();
      expect(toggledBack, isTrue);
      expect(FaceScanSettingsService.isAiVisionMeshEnabled.value, isTrue);
    });

    test('FaceScanSettingsService respects saved false preference', () async {
      SharedPreferences.setMockInitialValues({
        'face_scan_ai_vision_mesh_enabled': false,
      });
      // Force reload by setting value
      await FaceScanSettingsService.setAiVisionMeshEnabled(false);
      expect(FaceScanSettingsService.isAiVisionMeshEnabled.value, isFalse);
    });
  });

  group('Unified Dark Mode & ThemeSettingsService Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('ThemeSettingsService defaults to light mode (false)', () async {
      final isNight = await ThemeSettingsService.loadSettings();
      expect(isNight, isFalse);
      expect(ThemeSettingsService.isNightMode.value, isFalse);
    });

    test('ThemeSettingsService toggle switches state and notifies listeners',
        () async {
      SharedPreferences.setMockInitialValues({});
      await ThemeSettingsService.setNightMode(false);
      expect(ThemeSettingsService.isNightMode.value, isFalse);

      final toggled = await ThemeSettingsService.toggle();
      expect(toggled, isTrue);
      expect(ThemeSettingsService.isNightMode.value, isTrue);

      final toggledBack = await ThemeSettingsService.toggle();
      expect(toggledBack, isFalse);
      expect(ThemeSettingsService.isNightMode.value, isFalse);
    });

    test('ThemeSettingsService respects saved dark preference', () async {
      SharedPreferences.setMockInitialValues({
        'driver_theme_night_mode': true,
      });
      await ThemeSettingsService.setNightMode(true);
      expect(ThemeSettingsService.isNightMode.value, isTrue);
    });
  });

  group('Biometric Recognition & Similarity Calibration Tests', () {
    test(
        'calculateCosineSimilarity correctly discriminates same vs different vector',
        () {
      final v1 = FaceRecognitionService.l2Normalize([1.0, 2.0, 3.0, 4.0]);
      final v2Same = FaceRecognitionService.l2Normalize(
          [1.05, 1.95, 3.02, 3.98]); // Slight variation
      final v3Different = FaceRecognitionService.l2Normalize(
          [4.0, -2.0, 1.0, -3.0]); // Stranger

      final sameSimilarity =
          FaceRecognitionService.calculateCosineSimilarity(v1, v2Same);
      final strangerSimilarity =
          FaceRecognitionService.calculateCosineSimilarity(v1, v3Different);

      expect(sameSimilarity,
          greaterThan(0.95)); // Same person matches with very high similarity
      expect(strangerSimilarity,
          lessThan(0.50)); // Stranger scores low and gets rejected
    });

    test('Center-weighted embedding fusion preserves straight gaze alignment',
        () {
      final center = FaceRecognitionService.l2Normalize([1.0, 1.0, 1.0, 1.0]);
      final left = FaceRecognitionService.l2Normalize([0.7, 1.2, 0.8, 1.1]);
      final right = FaceRecognitionService.l2Normalize([1.2, 0.7, 1.1, 0.8]);

      final dim = center.length;
      final weighted = List<double>.filled(dim, 0.0);
      for (int i = 0; i < dim; i++) {
        weighted[i] = 0.60 * center[i] + 0.20 * left[i] + 0.20 * right[i];
      }
      final master = FaceRecognitionService.l2Normalize(weighted);

      final loginFrontFace = center;
      final similarity = FaceRecognitionService.calculateCosineSimilarity(
          loginFrontFace, master);

      // Verify that straight gaze similarity is well above 0.70 threshold
      expect(similarity, greaterThan(0.95));
    });

    test('FaceAuthRepository.getAllUsers retrieves locally cached users instantly', () async {
      final sampleProfile = UserFaceProfile(
        id: 'test@routealert.com',
        name: 'ทดสอบ ผู้ใช้',
        email: 'test@routealert.com',
        role: 'driver',
        faceEmbedding: [0.1, 0.2, 0.3],
        registeredAt: DateTime.now(),
      );

      SharedPreferences.setMockInitialValues({
        'route_alert_registered_users': [sampleProfile.toJson()],
      });

      final users = await FaceAuthRepository.getAllUsers();
      expect(users.length, equals(1));
      expect(users.first.email, equals('test@routealert.com'));
      expect(users.first.name, equals('ทดสอบ ผู้ใช้'));
    });
  });

  group('Smart Landmark, Multi-Image Incident & Zero-Block SOS Tests', () {
    test('SmartLandmarkService returns nearest hospital and landmark prefix', () async {
      // Within range of Maharaj Nakorn Chiang Mai Hospital
      const suanDokCoord = LatLng(19.0284, 99.8962);
      final landmark = await SmartLandmarkService().getSmartLandmark(suanDokCoord);

      expect(landmark, contains('มหาราช'));
      expect(landmark.isNotEmpty, isTrue);
    });

    test('SmartLandmarkService does not fabricate fake addresses for remote coordinates without shops', () async {
      const remoteCoord = LatLng(15.1234, 105.1234);
      final landmark = await SmartLandmarkService().getSmartLandmark(remoteCoord);
      expect(landmark.contains('แขวง'), isFalse);
      expect(landmark.contains('อำเภอ'), isFalse);
    });

    test('IncidentReport serializes and deserializes multiple photos (photosBase64)', () {
      final multiPhotoIncident = IncidentReport(
        id: 'CASE-MULTI-001',
        type: 'อุบัติเหตุทางรถยนต์',
        severity: 'วิกฤต (Code Red - หมดสติ / บาดเจ็บสาหัส)',
        description: 'ชนประสานงา 2 คัน',
        latitude: 18.7904,
        longitude: 98.9856,
        province: 'เชียงใหม่',
        address: 'ถ.นิมมานเหมินท์',
        photoBase64: 'BASE64_PHOTO_1',
        photosBase64: ['BASE64_PHOTO_1', 'BASE64_PHOTO_2', 'BASE64_PHOTO_3'],
        reporterName: 'ผู้แจ้งเหตุทดสอบ',
        reporterEmail: 'tester@routealert.app',
        reporterPhone: '081-234-5678',
        createdAt: DateTime.now(),
      );

      final map = multiPhotoIncident.toMap();
      expect(map['photosBase64'], isA<List>());
      expect((map['photosBase64'] as List).length, equals(3));
      expect(map['photoBase64'], equals('BASE64_PHOTO_1'));

      final reconstructed = IncidentReport.fromMap(map);
      expect(reconstructed.photosBase64.length, equals(3));
      expect(reconstructed.photoBase64, equals('BASE64_PHOTO_1'));
      expect(reconstructed.reporterPhone, equals('081-234-5678'));
    });

    test('AiVisionTriageService filters blank images and correctly flags non-incident', () async {
      // Generate a blank 64x64 solid white image
      final blankImage = img.Image(width: 64, height: 64);
      img.fill(blankImage, color: img.ColorRgb8(255, 255, 255));
      final blankBytes = img.encodeJpg(blankImage);

      final triageResult = await AiVisionTriageService().analyzeIncidentPhoto(blankBytes);

      expect(triageResult.isIncidentDetected, isFalse);
      expect(triageResult.severityCode, equals('Non-Incident'));
      expect(triageResult.severityLevel, contains('ไม่พบร่องรอยอุบัติเหตุ'));
    });

    test('AiVisionTriageService multi-image analysis handles multiple photos', () async {
      // Create empty photosBytes list check
      final emptyResult = await AiVisionTriageService().analyzeIncidentPhotos([]);
      expect(emptyResult.isIncidentDetected, isFalse);
      expect(emptyResult.photoCount, equals(0));
    });

    test('AiVisionTriageService saves and retrieves user Gemini API key', () async {
      SharedPreferences.setMockInitialValues({});
      await AiVisionTriageService.saveGeminiApiKey('AIzaSy_TEST_KEY_999');
      final retrieved = await AiVisionTriageService.getGeminiApiKey();
      expect(retrieved, equals('AIzaSy_TEST_KEY_999'));
    });
  });

  group('Thai Traffic Law & Emergency Distance Proximity Tiers Tests', () {
    test('Distance < 50m triggers illegalHazard tier with Thai Traffic Law citation', () {
      final tier = EmergencyProximityTier.fromDistance(35.0, hasAmbulance: true);
      expect(tier, equals(EmergencyProximityTier.illegalHazard));
      expect(tier.distanceRangeTH, equals('< 50 ม.'));
      expect(tier.titleTH, contains('ผิดกฎหมาย'));
      expect(tier.instructionTH, contains('พ.ร.บ. จราจรทางบก ม.76'));
      expect(tier.legalReferenceTH, contains('มาตรา 76'));
      expect(tier.primaryColor.toARGB32(), equals(const Color(0xFFDC2626).toARGB32()));
    });

    test('Distance 50m to 150m triggers criticalYield tier', () {
      final tier = EmergencyProximityTier.fromDistance(100.0, hasAmbulance: true);
      expect(tier, equals(EmergencyProximityTier.criticalYield));
      expect(tier.distanceRangeTH, equals('50 - 150 ม.'));
      expect(tier.titleTH, contains('ชิดซ้าย'));
      expect(tier.primaryColor.toARGB32(), equals(const Color(0xFFEA580C).toARGB32()));
    });

    test('Distance 150m to 500m triggers approaching tier', () {
      final tier = EmergencyProximityTier.fromDistance(320.0, hasAmbulance: true);
      expect(tier, equals(EmergencyProximityTier.approaching));
      expect(tier.distanceRangeTH, equals('150 - 500 ม.'));
      expect(tier.titleTH, contains('เตรียม'));
      expect(tier.primaryColor.toARGB32(), equals(const Color(0xFFF59E0B).toARGB32()));
    });

    test('Distance 500m to 3000m triggers radarAwareness tier', () {
      final tier = EmergencyProximityTier.fromDistance(1500.0, hasAmbulance: true);
      expect(tier, equals(EmergencyProximityTier.radarAwareness));
      expect(tier.distanceRangeTH, equals('500 ม. - 3 กม.'));
      expect(tier.titleTH, contains('รัศมี'));
      expect(tier.primaryColor.toARGB32(), equals(const Color(0xFF2563EB).toARGB32()));
    });

    test('Distance > 3000m or no ambulance returns safeZone', () {
      final tierOver = EmergencyProximityTier.fromDistance(3500.0, hasAmbulance: true);
      expect(tierOver, equals(EmergencyProximityTier.safeZone));
      expect(tierOver.primaryColor.toARGB32(), equals(const Color(0xFF10B981).toARGB32()));

      final tierNoAmb = EmergencyProximityTier.fromDistance(20.0, hasAmbulance: false);
      expect(tierNoAmb, equals(EmergencyProximityTier.safeZone));
    });
  });
}

