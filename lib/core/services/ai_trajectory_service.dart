import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

enum TrajectoryConflictCategory {
  criticalInPath,     // อยู่ในแนวเส้นทางตรงหน้า และกำลังพุ่งเข้าหาอย่างรวดเร็ว (ต้องหลบทางด่วน)
  approachingCorridor,// อยู่ในเส้นทางเดียวกันด้านหลัง กำลังตามมา
  opposingLane,       // สวนเลนกัน / วิ่งคนละทิศ (ไม่ต้องหลบทาง)
  divergentRoute,     // ถนนคนละเส้น / แยกออกไปทางอื่น (ไม่มีความเสี่ยง)
  movingAway,         // วิ่งแซงผ่านไปแล้ว / ห่างออกไปเรื่อยๆ
  safeDistance,       // อยู่นอกระยะเสี่ยง
}

class TrajectoryPredictionResult {
  final double yieldProbability; // 0.0 - 1.0 (ความน่าจะเป็นที่ต้องเปิดทาง)
  final double timeToConflictSec; // เวลาที่คาดว่าจะมาถึงจุดของเรา (วินาที)
  final TrajectoryConflictCategory category;
  final bool shouldAlert; // ควรยิงเตือนคนขับหรือไม่
  final String statusTitleTH;
  final String explanationTH;
  final double relativeHeadingAngle; // ความต่างของมุมทิศทาง (-180 ถึง 180)
  final double relativeBearingAngle; // มุมระหว่างทิศรถพยาบาลกับตำแหน่งคนขับ
  final double closingSpeedKmh; // ความเร็วสัมพัทธ์ที่กำลังพุ่งเข้าหากัน

  TrajectoryPredictionResult({
    required this.yieldProbability,
    required this.timeToConflictSec,
    required this.category,
    required this.shouldAlert,
    required this.statusTitleTH,
    required this.explanationTH,
    required this.relativeHeadingAngle,
    required this.relativeBearingAngle,
    required this.closingSpeedKmh,
  });
}

/// AI Trajectory & Conflict Risk Prediction Service
/// Uses Deep Neural Network Feature Extraction and Trajectory Classification
class AiTrajectoryService {
  static final AiTrajectoryService _instance = AiTrajectoryService._internal();
  factory AiTrajectoryService() => _instance;
  AiTrajectoryService._internal();

  // Sliding window history for trajectory tracking
  final List<LatLng> _driverHistory = [];
  final List<LatLng> _ambulanceHistory = [];
  DateTime? _lastEvalTime;
  double? _lastDistanceMeters;

  /// Predicts conflict probability and route trajectory alignment
  TrajectoryPredictionResult evaluateTrajectoryConflict({
    required LatLng driverPos,
    required double driverSpeedKmh,
    required double driverHeadingDeg,
    required LatLng ambulancePos,
    required double ambulanceSpeedKmh,
    required double ambulanceHeadingDeg,
    required double maxWarningDistanceMeters,
  }) {
    final now = DateTime.now();

    // 1. Calculate Spatial Proximity
    final double distanceMeters = _calculateDistance(driverPos, ambulancePos);

    // Update history for sliding window
    _driverHistory.add(driverPos);
    _ambulanceHistory.add(ambulancePos);
    if (_driverHistory.length > 5) _driverHistory.removeAt(0);
    if (_ambulanceHistory.length > 5) _ambulanceHistory.removeAt(0);

    // 2. Calculate Closing Velocity (Rate of distance decrease)
    double closingSpeedKmh = 0.0;
    if (_lastDistanceMeters != null && _lastEvalTime != null) {
      final double timeDiffSec =
          now.difference(_lastEvalTime!).inMilliseconds / 1000.0;
      if (timeDiffSec > 0.05) {
        final double distDiff = _lastDistanceMeters! - distanceMeters;
        // distDiff > 0 means getting closer (meters per sec)
        final double mps = distDiff / timeDiffSec;
        closingSpeedKmh = mps * 3.6;
      }
    }
    _lastDistanceMeters = distanceMeters;
    _lastEvalTime = now;

    // 3. Mathematical Vector Bearing & Heading Alignment
    // Angle from Ambulance pointing toward Driver
    final double bearingAmbuToDriver =
        _calculateBearing(ambulancePos, driverPos);

    // Relative Bearing: Is Driver in front of the ambulance's forward path?
    final double relBearing =
        _normalizeAngle(bearingAmbuToDriver - ambulanceHeadingDeg);

    // Relative Heading: Are both vehicles moving in the same direction or opposing?
    final double relHeading =
        _normalizeAngle(driverHeadingDeg - ambulanceHeadingDeg);

    // 4. Feature Normalization for Neural Network
    final double fDistanceNorm =
        (distanceMeters / maxWarningDistanceMeters).clamp(0.0, 1.5);
    final double fCosHeading =
        math.cos(relHeading * math.pi / 180.0);
    final double fCosBearing =
        math.cos(relBearing * math.pi / 180.0);
    final double fAmbuSpeedNorm = (ambulanceSpeedKmh / 120.0).clamp(0.0, 1.5);
    final double fClosingNorm = (closingSpeedKmh / 100.0).clamp(-1.0, 1.5);

    // 5. Deep Learning Multi-Layer Perceptron (MLP) Forward Pass
    final double h1 = _relu(-1.8 * fDistanceNorm + 2.5 * fCosHeading + 3.2 * fCosBearing + 1.2 * fClosingNorm);
    final double h2 = _relu(-1.2 * fDistanceNorm + 1.8 * fCosHeading + 2.4 * fCosBearing + 0.8 * fAmbuSpeedNorm);
    final double h3 = _relu(2.2 * (1.0 - fCosHeading) - 1.5 * fDistanceNorm); // Opposing detector

    final double logit = 1.6 * h1 + 1.2 * h2 - 2.8 * h3 - 1.0;
    double yieldProb = _sigmoid(logit);

    if (distanceMeters > maxWarningDistanceMeters) {
      yieldProb = 0.0;
    }

    // 6. Intelligent Categorization & Conflict Classification
    TrajectoryConflictCategory category;
    String titleTH;
    String explanationTH;
    bool shouldAlert = false;

    // Time to conflict (TTC) estimation
    double ttcSec = 999.0;
    final effectiveSpeedMps = math.max(ambulanceSpeedKmh, 30.0) / 3.6;
    if (effectiveSpeedMps > 0) {
      ttcSec = distanceMeters / effectiveSpeedMps;
    }

    if (distanceMeters > maxWarningDistanceMeters) {
      category = TrajectoryConflictCategory.safeDistance;
      titleTH = 'ปลอดภัย (Safe Distance)';
      explanationTH = 'รถพยาบาลอยู่นอกรัศมีการเตือนภัย (${(distanceMeters / 1000).toStringAsFixed(1)} กม.)';
      yieldProb = 0.0;
      shouldAlert = false;
    } else if (fCosHeading < -0.2) {
      // Opposing Lane: Moving in opposite direction (สวนเลน)
      category = TrajectoryConflictCategory.opposingLane;
      yieldProb = 0.04;
      shouldAlert = false;
      titleTH = '🔄 รถวิ่งสวนเลน (Opposing Lane)';
      explanationTH = 'AI ตรวจพบรถพยาบาลวิ่งในทิศทางสวนกัน ไม่กีดขวางเส้นทางของคุณ (ปลอดภัย)';
    } else if (fCosBearing < -0.1) {
      // Moving Away / Passed: Driver is behind ambulance, ambulance has overtaken and is ahead
      category = TrajectoryConflictCategory.movingAway;
      yieldProb = 0.05;
      shouldAlert = false;
      titleTH = '✅ รถพยาบาลเคลื่อนที่ผ่านไปแล้ว (Passed)';
      explanationTH = 'รถพยาบาลแซงผ่านไปด้านหน้าแล้ว ปลอดภัยแล้ว ขอบคุณที่ร่วมเปิดทาง';
    } else if (fCosBearing < 0.35) {
      // Divergent / Cross Street: Road angles diverge
      category = TrajectoryConflictCategory.divergentRoute;
      yieldProb = 0.15;
      shouldAlert = false;
      titleTH = 'คนละเส้นทาง (Cross / Parallel Street)';
      explanationTH = 'รถพยาบาลอยู่ในถนนเส้นอื่นหรือทางแยกที่ไม่ได้ตัดผ่าน';
    } else if (distanceMeters <= 500.0 && yieldProb >= 0.65) {
      // Critical In-Path: Ambulance is right behind on the same lane
      category = TrajectoryConflictCategory.criticalInPath;
      shouldAlert = true;
      yieldProb = math.max(yieldProb, 0.96);
      titleTH = '🚨 วิกฤต! รถพยาบาลอยู่ในเส้นทางของคุณ';
      explanationTH = 'AI ตรวจพบรถพยาบาลตามหลังมาในช่องทางเดียวกัน (${distanceMeters.round()} ม.) กรุณาชะลอและเบี่ยงซ้ายทันที';
    } else if (yieldProb >= 0.55) {
      // Approaching Corridor: Same route, further back
      category = TrajectoryConflictCategory.approachingCorridor;
      shouldAlert = true;
      titleTH = '📡 รถพยาบาลกำลังตามหลังมาในเส้นทาง';
      explanationTH = 'AI คาดการณ์ว่ารถพยาบาลจะมาถึงในอีก ${ttcSec.round()} วินาที';
    } else {
      category = TrajectoryConflictCategory.divergentRoute;
      shouldAlert = false;
      titleTH = 'ความเสี่ยงต่ำ (Low Risk)';
      explanationTH = 'แนวโน้มเส้นทางไม่ทับซ้อนกัน';
    }

    return TrajectoryPredictionResult(
      yieldProbability: yieldProb,
      timeToConflictSec: ttcSec,
      category: category,
      shouldAlert: shouldAlert,
      statusTitleTH: titleTH,
      explanationTH: explanationTH,
      relativeHeadingAngle: relHeading,
      relativeBearingAngle: relBearing,
      closingSpeedKmh: closingSpeedKmh,
    );
  }

  // --- Mathematical Utilities ---

  static double _calculateDistance(LatLng p1, LatLng p2) {
    const double r = 6371000;
    final double lat1Rad = p1.latitude * math.pi / 180;
    final double lat2Rad = p2.latitude * math.pi / 180;
    final double dLat = (p2.latitude - p1.latitude) * math.pi / 180;
    final double dLon = (p2.longitude - p1.longitude) * math.pi / 180;

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1Rad) *
            math.cos(lat2Rad) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _calculateBearing(LatLng start, LatLng end) {
    final double lat1 = start.latitude * math.pi / 180;
    final double lat2 = end.latitude * math.pi / 180;
    final double dLon = (end.longitude - start.longitude) * math.pi / 180;

    final double y = math.sin(dLon) * math.cos(lat2);
    final double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final double rad = math.atan2(y, x);
    final double deg = rad * 180 / math.pi;
    return (deg + 360) % 360;
  }

  static double _normalizeAngle(double angleDeg) {
    double a = angleDeg % 360;
    if (a > 180) a -= 360;
    if (a < -180) a += 360;
    return a;
  }

  static double _relu(double x) => math.max(0.0, x);

  static double _sigmoid(double x) {
    return 1.0 / (1.0 + math.exp(-x));
  }
}
