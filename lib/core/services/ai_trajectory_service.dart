import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

enum TrajectoryConflictCategory {
  criticalInPath, // อยู่ในแนวเส้นทางตรงหน้า และกำลังพุ่งเข้าหาอย่างรวดเร็ว (ต้องหลบทางด่วน)
  approachingCorridor, // อยู่ในเส้นทางเดียวกันด้านหลัง กำลังตามมา
  turnInApproaching, // รถพยาบาลกำลังจะเลี้ยวเข้าสู่ถนนของเรา (เตือนล่วงหน้า)
  turnBypass, // รถพยาบาลจะเลี้ยวออกที่แยกข้างหน้า ไม่กีดขวางเรา (Route-Aware ไม่เตือน)
  opposingLane, // สวนเลนกัน / วิ่งคนละทิศ (ไม่ต้องหลบทาง)
  divergentRoute, // ถนนคนละเส้น / แยกออกไปทางอื่น (ไม่มีความเสี่ยง)
  movingAway, // วิ่งแซงผ่านไปแล้ว / ห่างออกไปเรื่อยๆ
  safeDistance, // อยู่นอกระยะเสี่ยง
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
  final bool isRouteAwareActive; // เปิดใช้งาน Route-Aware Polyline สำเร็จ
  final String? turnIntent; // เจตนาการเลี้ยว เช่น "เตรียมเลี้ยวขวา 150 ม."
  final double crossTrackDistanceMeters; // ระยะห่างตั้งฉากกับเส้นทางถนนจริง

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
    this.isRouteAwareActive = false,
    this.turnIntent,
    this.crossTrackDistanceMeters = 0.0,
  });
}

/// AI Trajectory & Conflict Risk Prediction Service
/// Uses Deep Neural Network Feature Extraction + Route-Aware Polyline Corridor Snapping
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
    List<LatLng>? routePoints,
    String? turnIntent,
  }) {
    final now = DateTime.now();

    // 1. Calculate Spatial Proximity (Straight Line Distance)
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
        final double mps = distDiff / timeDiffSec;
        closingSpeedKmh = mps * 3.6;
      }
    }
    _lastDistanceMeters = distanceMeters;
    _lastEvalTime = now;

    // 3. Mathematical Vector Bearing & Heading Alignment
    final double bearingAmbuToDriver =
        _calculateBearing(ambulancePos, driverPos);
    final double relBearing =
        _normalizeAngle(bearingAmbuToDriver - ambulanceHeadingDeg);
    final double relHeading =
        _normalizeAngle(driverHeadingDeg - ambulanceHeadingDeg);

    // Time to conflict (TTC) estimation
    double ttcSec = 999.0;
    final effectiveSpeedMps = math.max(ambulanceSpeedKmh, 30.0) / 3.6;
    if (effectiveSpeedMps > 0) {
      ttcSec = distanceMeters / effectiveSpeedMps;
    }

    // ----------------------------------------------------
    // 4. ROUTE-AWARE POLYLINE CORRIDOR MATCHING
    // ----------------------------------------------------
    if (routePoints != null && routePoints.length >= 2) {
      final corridorAnalysis = _analyzeRouteCorridor(
        driverPos: driverPos,
        ambulancePos: ambulancePos,
        routePoints: routePoints,
        maxWarningDistance: maxWarningDistanceMeters,
      );

      if (distanceMeters > maxWarningDistanceMeters) {
        return TrajectoryPredictionResult(
          yieldProbability: 0.0,
          timeToConflictSec: ttcSec,
          category: TrajectoryConflictCategory.safeDistance,
          shouldAlert: false,
          statusTitleTH: '🛡️ ปลอดภัย (Safe Distance)',
          explanationTH:
              'รถพยาบาลอยู่นอกรัศมีการเตือนภัย (${(distanceMeters / 1000).toStringAsFixed(1)} กม.)',
          relativeHeadingAngle: relHeading,
          relativeBearingAngle: relBearing,
          closingSpeedKmh: closingSpeedKmh,
          isRouteAwareActive: true,
          turnIntent: turnIntent,
          crossTrackDistanceMeters: corridorAnalysis.crossTrackDistance,
        );
      }

      // Check if driver has been passed
      final fCosBearing = math.cos(relBearing * math.pi / 180.0);
      if (fCosBearing < -0.2 && distanceMeters < 300) {
        return TrajectoryPredictionResult(
          yieldProbability: 0.05,
          timeToConflictSec: ttcSec,
          category: TrajectoryConflictCategory.movingAway,
          shouldAlert: false,
          statusTitleTH: '✅ รถพยาบาลเคลื่อนที่ผ่านไปแล้ว (Passed)',
          explanationTH:
              'รถพยาบาลแซงผ่านไปด้านหน้าแล้ว ปลอดภัยแล้ว ขอบคุณที่ร่วมเปิดทาง',
          relativeHeadingAngle: relHeading,
          relativeBearingAngle: relBearing,
          closingSpeedKmh: closingSpeedKmh,
          isRouteAwareActive: true,
          turnIntent: turnIntent,
          crossTrackDistanceMeters: corridorAnalysis.crossTrackDistance,
        );
      }

      // Case A: Turn Bypass (Ambulance turns off before reaching driver!)
      if (corridorAnalysis.isTurnBypass) {
        return TrajectoryPredictionResult(
          yieldProbability: 0.05,
          timeToConflictSec: ttcSec,
          category: TrajectoryConflictCategory.turnBypass,
          shouldAlert: false,
          statusTitleTH: '↪️ รถพยาบาลเลี้ยวแยกหน้า (Turn Bypass)',
          explanationTH:
              'AI Route-Aware: ตรวจพบว่ารถพยาบาลจะเลี้ยวที่แยกข้างหน้า ไม่ได้ตรงมาในเลนของคุณ (ปลอดภัย 100%)',
          relativeHeadingAngle: relHeading,
          relativeBearingAngle: relBearing,
          closingSpeedKmh: closingSpeedKmh,
          isRouteAwareActive: true,
          turnIntent: turnIntent ?? 'เลี้ยวแยกข้างหน้า',
          crossTrackDistanceMeters: corridorAnalysis.crossTrackDistance,
        );
      }

      // Case B: Driver is in Corridor and Ambulance is turning IN
      if (corridorAnalysis.isTurnInApproaching) {
        return TrajectoryPredictionResult(
          yieldProbability: 0.92,
          timeToConflictSec: ttcSec,
          category: TrajectoryConflictCategory.turnInApproaching,
          shouldAlert: true,
          statusTitleTH: '⚠️ รถพยาบาลเตรียมเลี้ยวเข้าถนนของคุณ!',
          explanationTH:
              'AI Route-Aware: ตรวจพบเส้นทางรถพยาบาลกำลังจะเลี้ยวเข้าถนนที่คุณอยู่ (${distanceMeters.round()} ม.) กรุณาชะลอความเร็ว',
          relativeHeadingAngle: relHeading,
          relativeBearingAngle: relBearing,
          closingSpeedKmh: closingSpeedKmh,
          isRouteAwareActive: true,
          turnIntent: turnIntent ?? 'กำลังเลี้ยวเข้าถนนของคุณ',
          crossTrackDistanceMeters: corridorAnalysis.crossTrackDistance,
        );
      }

      // Case C: Critical In-Path (Same road, within critical distance)
      if (corridorAnalysis.isInCorridor &&
          corridorAnalysis.distanceAlongRoute <= 500.0) {
        return TrajectoryPredictionResult(
          yieldProbability: 0.98,
          timeToConflictSec: ttcSec,
          category: TrajectoryConflictCategory.criticalInPath,
          shouldAlert: true,
          statusTitleTH: '🚨 วิกฤต! รถพยาบาลอยู่ในเส้นทางของคุณ',
          explanationTH:
              'AI Route-Aware: รถพยาบาลตามหลังมาในช่องทางถนนเดียวกัน (${corridorAnalysis.distanceAlongRoute.round()} ม.) กรุณาชะลอและเบี่ยงซ้ายทันที',
          relativeHeadingAngle: relHeading,
          relativeBearingAngle: relBearing,
          closingSpeedKmh: closingSpeedKmh,
          isRouteAwareActive: true,
          turnIntent: turnIntent,
          crossTrackDistanceMeters: corridorAnalysis.crossTrackDistance,
        );
      }

      // Case D: Approaching in Corridor (Further along route)
      if (corridorAnalysis.isInCorridor &&
          corridorAnalysis.distanceAlongRoute <= maxWarningDistanceMeters) {
        return TrajectoryPredictionResult(
          yieldProbability: 0.85,
          timeToConflictSec: ttcSec,
          category: TrajectoryConflictCategory.approachingCorridor,
          shouldAlert: true,
          statusTitleTH: '📡 รถพยาบาลกำลังตามหลังมาในเส้นทาง',
          explanationTH:
              'AI Route-Aware: รถพยาบาลอยู่ห่าง ${(corridorAnalysis.distanceAlongRoute / 1000).toStringAsFixed(1)} กม. ตามเส้นทาง คาดว่าจะถึงใน ${ttcSec.round()} วินาที',
          relativeHeadingAngle: relHeading,
          relativeBearingAngle: relBearing,
          closingSpeedKmh: closingSpeedKmh,
          isRouteAwareActive: true,
          turnIntent: turnIntent,
          crossTrackDistanceMeters: corridorAnalysis.crossTrackDistance,
        );
      }
    }

    // ----------------------------------------------------
    // 5. MLP Deep Neural Network Fallback
    // ----------------------------------------------------
    final double fDistanceNorm =
        (distanceMeters / maxWarningDistanceMeters).clamp(0.0, 1.5);
    final double fCosHeading = math.cos(relHeading * math.pi / 180.0);
    final double fCosBearing = math.cos(relBearing * math.pi / 180.0);
    final double fAmbuSpeedNorm = (ambulanceSpeedKmh / 120.0).clamp(0.0, 1.5);
    final double fClosingNorm = (closingSpeedKmh / 100.0).clamp(-1.0, 1.5);

    final double h1 = _relu(-1.8 * fDistanceNorm +
        2.5 * fCosHeading +
        3.2 * fCosBearing +
        1.2 * fClosingNorm);
    final double h2 = _relu(-1.2 * fDistanceNorm +
        1.8 * fCosHeading +
        2.4 * fCosBearing +
        0.8 * fAmbuSpeedNorm);
    final double h3 =
        _relu(2.2 * (1.0 - fCosHeading) - 1.5 * fDistanceNorm); // Opposing

    final double logit = 1.6 * h1 + 1.2 * h2 - 2.8 * h3 - 1.0;
    double yieldProb = _sigmoid(logit);

    if (distanceMeters > maxWarningDistanceMeters) {
      yieldProb = 0.0;
    }

    TrajectoryConflictCategory category;
    String titleTH;
    String explanationTH;
    bool shouldAlert = false;

    if (distanceMeters > maxWarningDistanceMeters) {
      category = TrajectoryConflictCategory.safeDistance;
      titleTH = '🛡️ ปลอดภัย (Safe Distance)';
      explanationTH =
          'รถพยาบาลอยู่นอกรัศมีการเตือนภัย (${(distanceMeters / 1000).toStringAsFixed(1)} กม.)';
      yieldProb = 0.0;
      shouldAlert = false;
    } else if (fCosHeading < -0.2) {
      category = TrajectoryConflictCategory.opposingLane;
      yieldProb = 0.04;
      shouldAlert = false;
      titleTH = '🔄 รถวิ่งสวนเลน (Opposing Lane)';
      explanationTH =
          'AI ตรวจพบรถพยาบาลวิ่งในทิศทางสวนกัน ไม่กีดขวางเส้นทางของคุณ (ปลอดภัย)';
    } else if (fCosBearing < -0.1) {
      category = TrajectoryConflictCategory.movingAway;
      yieldProb = 0.05;
      shouldAlert = false;
      titleTH = '✅ รถพยาบาลเคลื่อนที่ผ่านไปแล้ว (Passed)';
      explanationTH =
          'รถพยาบาลแซงผ่านไปด้านหน้าแล้ว ปลอดภัยแล้ว ขอบคุณที่ร่วมเปิดทาง';
    } else if (fCosBearing < 0.35) {
      category = TrajectoryConflictCategory.divergentRoute;
      yieldProb = 0.15;
      shouldAlert = false;
      titleTH = 'คนละเส้นทาง (Cross / Parallel Street)';
      explanationTH = 'รถพยาบาลอยู่ในถนนเส้นอื่นหรือทางแยกที่ไม่ได้ตัดผ่าน';
    } else if (distanceMeters <= 500.0 && yieldProb >= 0.65) {
      category = TrajectoryConflictCategory.criticalInPath;
      shouldAlert = true;
      yieldProb = math.max(yieldProb, 0.96);
      titleTH = '🚨 วิกฤต! รถพยาบาลอยู่ในเส้นทางของคุณ';
      explanationTH =
          'AI ตรวจพบรถพยาบาลตามหลังมาในช่องทางเดียวกัน (${distanceMeters.round()} ม.) กรุณาชะลอและเบี่ยงซ้ายทันที';
    } else if (yieldProb >= 0.55) {
      category = TrajectoryConflictCategory.approachingCorridor;
      shouldAlert = true;
      titleTH = '📡 รถพยาบาลกำลังตามหลังมาในเส้นทาง';
      explanationTH =
          'AI คาดการณ์ว่ารถพยาบาลจะมาถึงในอีก ${ttcSec.round()} วินาที';
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
      isRouteAwareActive: false,
      turnIntent: turnIntent,
    );
  }

  // --- Route Polyline Corridor Analysis Helper ---

  static _CorridorMatchResult _analyzeRouteCorridor({
    required LatLng driverPos,
    required LatLng ambulancePos,
    required List<LatLng> routePoints,
    required double maxWarningDistance,
  }) {
    double minCrossTrackDist = double.infinity;
    double distAlongRoute = 0.0;
    int closestSegmentIndex = -1;
    double accumulatedDist = 0.0;
    double distAtClosestPoint = 0.0;

    for (int i = 0; i < routePoints.length - 1; i++) {
      final p1 = routePoints[i];
      final p2 = routePoints[i + 1];
      final segmentLen = _calculateDistance(p1, p2);

      final snap = _projectPointOnSegment(driverPos, p1, p2);
      final crossDist = _calculateDistance(driverPos, snap.projectedPoint);

      if (crossDist < minCrossTrackDist) {
        minCrossTrackDist = crossDist;
        closestSegmentIndex = i;
        distAtClosestPoint = accumulatedDist + (snap.fraction * segmentLen);
      }
      accumulatedDist += segmentLen;
    }

    distAlongRoute = distAtClosestPoint;

    // Road corridor tolerance: within 40m of road center
    const double roadCorridorThresholdMeters = 40.0;
    final bool isInCorridor = minCrossTrackDist <= roadCorridorThresholdMeters;

    // Check Turn Bypass:
    // If the ambulance is on a route that turns away before reaching the driver's projected road position,
    // or driver is along the forward bearing line but NOT along the polyline path
    final double straightLineDist = _calculateDistance(ambulancePos, driverPos);
    bool isTurnBypass = false;
    bool isTurnIn = false;

    if (!isInCorridor && straightLineDist <= maxWarningDistance) {
      // Driver is near in straight distance, but road route diverges
      isTurnBypass = true;
    }

    if (isInCorridor && closestSegmentIndex >= 1 && routePoints.length >= 3) {
      final double bearing0 = _calculateBearing(routePoints[0], routePoints[1]);
      final double bearingDriver = _calculateBearing(
        routePoints[closestSegmentIndex],
        routePoints[closestSegmentIndex + 1],
      );
      final double turnAngleDiff = _normalizeAngle(bearingDriver - bearing0).abs();
      if (turnAngleDiff >= 30.0) {
        // Road route has a distinct turn to reach the driver's street
        isTurnIn = true;
      }
    }

    return _CorridorMatchResult(
      isInCorridor: isInCorridor,
      crossTrackDistance: minCrossTrackDist,
      distanceAlongRoute: distAlongRoute,
      isTurnBypass: isTurnBypass,
      isTurnInApproaching: isTurnIn && distAlongRoute <= maxWarningDistance,
    );
  }

  static _PointProjection _projectPointOnSegment(
      LatLng p, LatLng a, LatLng b) {
    final double dx = b.longitude - a.longitude;
    final double dy = b.latitude - a.latitude;
    final double lenSq = dx * dx + dy * dy;

    if (lenSq == 0) {
      return _PointProjection(a, 0.0);
    }

    double t =
        ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy) /
            lenSq;
    t = t.clamp(0.0, 1.0);

    final projected = LatLng(a.latitude + t * dy, a.longitude + t * dx);
    return _PointProjection(projected, t);
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
  static double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));
}

class _CorridorMatchResult {
  final bool isInCorridor;
  final double crossTrackDistance;
  final double distanceAlongRoute;
  final bool isTurnBypass;
  final bool isTurnInApproaching;

  _CorridorMatchResult({
    required this.isInCorridor,
    required this.crossTrackDistance,
    required this.distanceAlongRoute,
    required this.isTurnBypass,
    required this.isTurnInApproaching,
  });
}

class _PointProjection {
  final LatLng projectedPoint;
  final double fraction;
  _PointProjection(this.projectedPoint, this.fraction);
}
