import 'package:flutter_test/flutter_test.dart';
import 'package:route_alert/core/models/incident_report.dart';
import 'package:route_alert/core/services/live_tracking_service.dart';
import 'package:route_alert/core/services/notification_intent.dart';

import 'support/scenario_result.dart';

void main() {
  final now = DateTime(2026, 9, 28, 12, 0);
  IncidentReport incident({
    String id = 'Case #AVCB1',
    String status = 'assigned',
    int step = 1,
    String reporter = 'Me@X.com',
    String? callSign = 'กู้ชีพ 7',
    int? eta,
    int? meters,
    String? target,
    DateTime? etaAt,
    DateTime? near,
    String? hospitalName,
    DateTime? createdAt,
    bool archived = false,
  }) =>
      IncidentReport(
        id: id,
        type: 'รถชน',
        severity: 'วิกฤต',
        description: '',
        latitude: 0,
        longitude: 0,
        province: 'เชียงใหม่',
        address: 'ถ.ห้วยแก้ว',
        reporterName: 'ผู้แจ้ง',
        reporterEmail: reporter,
        status: status,
        statusStep: step,
        assignedAmbulanceCallSign: callSign,
        ambulanceEtaMinutes: eta,
        ambulanceDistanceMeters: meters,
        ambulanceEtaTarget: target,
        ambulanceEtaUpdatedAt: etaAt,
        ambulanceNearSceneAt: near,
        hospitalName: hospitalName,
        archived: archived,
        createdAt: createdAt ?? now.subtract(const Duration(minutes: 5)),
      );

  group('pickActive', () {
    test('newest open case reported by me, case-insensitive', () {
      final older = incident(id: 'A', createdAt: now.subtract(const Duration(hours: 2)));
      final newer = incident(id: 'B', createdAt: now.subtract(const Duration(minutes: 1)));
      final other = incident(id: 'C', reporter: 'someone@x.com', createdAt: now);
      expect(LiveTrackingService.pickActive([older, newer, other], 'me@x.com', now)!.id, 'B');
    });

    test('ignores closed, archived, and very old cases', () {
      final list = [
        incident(id: 'R', status: 'resolved'),
        incident(id: 'X', status: 'cancelled'),
        incident(id: 'Z', archived: true),
        incident(id: 'O', createdAt: now.subtract(const Duration(hours: 13))),
      ];
      expect(LiveTrackingService.pickActive(list, 'me@x.com', now), isNull);
      expect(LiveTrackingService.pickActive([incident()], '', now), isNull);
      // a pending case nobody picked up for hours is not tracked, an assigned one still is
      final oldPending = incident(status: 'pending', step: 0, createdAt: now.subtract(const Duration(hours: 3)));
      final oldAssigned = incident(createdAt: now.subtract(const Duration(hours: 3)));
      expect(LiveTrackingService.pickActive([oldPending], 'me@x.com', now), isNull);
      expect(LiveTrackingService.pickActive([oldAssigned], 'me@x.com', now), isNotNull);
    });
  });

  group('stateFor', () {
    test('pending case waits for hospital, no ETA', () {
      final s = LiveTrackingService.stateFor(incident(status: 'pending', step: 0), now);
      expect(s.phase, 'pending');
      expect(s.title, 'รอโรงพยาบาลยืนยันเคส');
      expect(s.etaMinutes, isNull);
    });

    test('[G18] en route shows fresh ETA, distance and progress against the leg start', () {
      final s = LiveTrackingService.stateFor(
        incident(eta: 4, meters: 1500, target: 'scene', etaAt: now.subtract(const Duration(seconds: 30))),
        now,
        legMaxMeters: 3000,
      );
      expect(s.phase, 'enroute');
      expect(s.title, 'รถพยาบาลกำลังมา');
      expect(s.subtitle, 'กู้ชีพ 7');
      expect(s.etaMinutes, 4);
      expect(s.distanceMeters, 1500);
      expect(s.progress, closeTo(0.5, 0.001));
      expect(s.detailLine, 'กู้ชีพ 7 · อีกราว 4 นาที · 1.5 กม.');
    });

    test('[G18] stale or wrong-leg ETA is hidden', () {
      final stale = LiveTrackingService.stateFor(
          incident(eta: 4, meters: 900, target: 'scene', etaAt: now.subtract(const Duration(minutes: 5))), now);
      expect(stale.etaMinutes, isNull);
      expect(stale.distanceMeters, isNull);
      final wrongLeg = LiveTrackingService.stateFor(
          incident(eta: 9, meters: 5000, target: 'hospital', etaAt: now), now);
      expect(wrongLeg.etaMinutes, isNull);
      scenarioResult(condition: 'ETA 4 นาที ที่รถส่งมาเมื่อ 5 นาทีก่อน (รถหยุดส่ง)', expected: 'ไม่แสดง ETA เก่า',
          actual: 'ETA ที่แสดง: ${stale.etaMinutes ?? 'ไม่แสดง'} · ระยะ: ${stale.distanceMeters ?? 'ไม่แสดง'}');
      scenarioResult(condition: 'ขณะรถไปจุดเกิดเหตุ ได้ ETA ช่วง "ไปโรงพยาบาล" (ผิดช่วงทาง)', expected: 'ไม่แสดง',
          actual: 'ETA ที่แสดง: ${wrongLeg.etaMinutes ?? 'ไม่แสดง'}');
    });

    test('near, arrived, transport and done phases', () {
      expect(LiveTrackingService.stateFor(incident(near: now), now).phase, 'near');
      expect(LiveTrackingService.stateFor(incident(near: now), now).title, 'รถพยาบาลใกล้ถึงแล้ว');
      final arrived = LiveTrackingService.stateFor(incident(status: 'at_scene', step: 2), now);
      expect(arrived.phase, 'arrived');
      expect(arrived.progress, 1);
      final transport = LiveTrackingService.stateFor(
          incident(status: 'transporting', step: 3, hospitalName: 'รพ.เชียงราย',
              eta: 12, meters: 8000, target: 'hospital', etaAt: now),
          now, legMaxMeters: 10000);
      expect(transport.phase, 'transport');
      expect(transport.title, 'กำลังนำส่ง รพ.เชียงราย');
      expect(transport.etaMinutes, 12);
      expect(transport.progress, closeTo(0.2, 0.001));
      final done = LiveTrackingService.stateFor(incident(status: 'resolved', step: 5, hospitalName: 'รพ.เชียงราย'), now);
      expect(done.ended, isTrue);
      expect(done.phase, 'done');
    });

    test('staleAt only for phases that should have an ETA', () {
      expect(LiveTrackingService.stateFor(incident(status: 'pending', step: 0), now).staleAt, isNull);
      expect(LiveTrackingService.stateFor(incident(status: 'at_scene', step: 2), now).staleAt, isNull);
      final at = now.subtract(const Duration(seconds: 40));
      expect(LiveTrackingService.stateFor(
              incident(eta: 3, meters: 800, target: 'scene', etaAt: at), now).staleAt,
          at.add(const Duration(minutes: 3)));
      // no fresh ETA while en route → already stale
      expect(LiveTrackingService.stateFor(incident(), now).staleAt, now);
      // ambulance clock ahead of ours: treated as just updated, not fresher than now
      final future = now.add(const Duration(minutes: 2));
      expect(LiveTrackingService.stateFor(
              incident(eta: 3, meters: 800, target: 'scene', etaAt: future), now).staleAt,
          now.add(const Duration(minutes: 3)));
    });

    test('[G18] eta of 0 is shown as 1 minute, never negative progress', () {
      final s = LiveTrackingService.stateFor(
          incident(eta: 0, meters: 5000, target: 'scene', etaAt: now), now, legMaxMeters: 3000);
      expect(s.etaMinutes, 1);
      expect(s.progress, greaterThanOrEqualTo(0.03));
    });

    test('equality ignores tiny progress jitter so the native side is not spammed', () {
      final a = LiveTrackingService.stateFor(
          incident(eta: 4, meters: 1500, target: 'scene', etaAt: now), now, legMaxMeters: 3000);
      final b = LiveTrackingService.stateFor(
          incident(eta: 4, meters: 1501, target: 'scene', etaAt: now), now, legMaxMeters: 3000);
      expect(a == b, isFalse); // distance text changes
      expect(a, LiveTrackingService.stateFor(
          incident(eta: 4, meters: 1500, target: 'scene', etaAt: now), now, legMaxMeters: 3000));
    });
  });

  test('tracking notification id never collides with the case notification id', () {
    final caseId = notificationIdForIncident('Case #AVCB1');
    final trackId = trackingNotificationIdForIncident('Case #AVCB1');
    expect(trackId, isNot(caseId));
    expect(trackId, inInclusiveRange(0x20000000, 0x3fffffff));
    // every case id lives in [2^30, 2^31) so no tracker can ever replace a case notification
    for (final id in ['INC-1', 'Case #AVCB9', 'เคส']) {
      expect(notificationIdForIncident(id), greaterThanOrEqualTo(0x40000000));
      expect(trackingNotificationIdForIncident(id), lessThan(0x40000000));
    }
    expect(trackId, isNot(anyOf(911, 1669)));
  });
}
