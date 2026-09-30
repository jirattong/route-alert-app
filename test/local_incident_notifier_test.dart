import 'package:flutter_test/flutter_test.dart';
import 'package:route_alert/core/models/incident_report.dart';
import 'package:route_alert/core/services/incident_notification_presenter.dart';
import 'package:route_alert/core/services/local_incident_notifier.dart';
import 'package:route_alert/core/services/notification_intent.dart';
import 'package:route_alert/core/services/notification_router.dart';

void main() {
  final now = DateTime(2026, 9, 28, 10, 0);
  IncidentReport incident({
    String id = 'INC-1',
    String status = 'pending',
    String? target = 'H1',
    String? ambulance,
    String? assignedBy,
    String? callSign,
    DateTime? near,
    int? eta,
    String? hospitalName,
    bool archived = false,
    DateTime? createdAt,
    String address = 'ถ.ห้วยแก้ว',
    String severity = 'วิกฤต',
  }) =>
      IncidentReport(
        id: id,
        type: 'รถชน',
        severity: severity,
        description: '',
        latitude: 0,
        longitude: 0,
        province: 'เชียงใหม่',
        address: address,
        reporterName: 'ผู้แจ้ง',
        reporterEmail: 'Driver@X.com',
        status: status,
        targetHospitalId: target,
        assignedAmbulanceId: ambulance,
        assignedBy: assignedBy,
        assignedAmbulanceCallSign: callSign,
        ambulanceNearSceneAt: near,
        ambulanceNearEtaMinutes: eta,
        hospitalName: hospitalName,
        archived: archived,
        createdAt: createdAt ?? now.subtract(const Duration(minutes: 2)),
      );

  const agencyH1 = LocalNotifierUser(email: 'a1@x.com', role: 'agency', hospitalId: 'H1');
  const agencyH2 = LocalNotifierUser(email: 'a2@x.com', role: 'agency', hospitalId: 'H2');
  const agencyNoHospital = LocalNotifierUser(email: 'a0@x.com', role: 'agency');
  const amb1 = LocalNotifierUser(email: 'm1@x.com', role: 'ambulance', ambulanceUnitId: 'AMB-1');
  const amb3 = LocalNotifierUser(email: 'm3@x.com', role: 'ambulance', ambulanceUnitId: 'AMB-3');
  const reporter = LocalNotifierUser(email: 'driver@x.com', role: 'driver');

  List<String> kinds(LocalPlanResult r) => r.notifications.map((n) => n['kind']!).toList();

  group('LocalIncidentNotifier.plan', () {
    test('[S06][S19] new case goes to matching agency and every ambulance only', () {
      final inc = incident();
      final a1 = LocalIncidentNotifier.plan(inc, const {}, agencyH1, now);
      expect(a1.notifications.single, {
        'incidentId': 'INC-1',
        'kind': PushKind.newIncident,
        'audience': PushAudience.agency,
        'title': '🚨 เคสใหม่: รถชน',
        'body': 'วิกฤต · ถ.ห้วยแก้ว',
      });
      expect(LocalIncidentNotifier.plan(inc, const {}, agencyH2, now).notifications, isEmpty);
      expect(kinds(LocalIncidentNotifier.plan(inc, const {}, agencyNoHospital, now)),
          [PushKind.newIncident]);
      final m = LocalIncidentNotifier.plan(inc, const {}, amb1, now).notifications.single;
      expect(m['audience'], PushAudience.ambulance);
      expect(m['title'], '🚑 มีเคสใหม่รอรับ');
      expect(m['body'], 'รถชน · ถ.ห้วยแก้ว');
      expect(LocalIncidentNotifier.plan(inc, const {}, reporter, now).notifications, isEmpty);
    });

    test('[S19] same state twice does not notify again', () {
      final inc = incident();
      final first = LocalIncidentNotifier.plan(inc, const {}, amb1, now);
      final second = LocalIncidentNotifier.plan(inc, first.nextLog, amb1, now);
      expect(second.changed, isFalse);
      expect(second.notifications, isEmpty);
    });

    test('[S19] hospital assignment: assigned unit, cancel for others, reporter told once', () {
      final log = {'created': true};
      final inc = incident(
          status: 'assigned', ambulance: 'AMB-1', assignedBy: 'hospital', callSign: 'กู้ชีพ 1');
      final mine = LocalIncidentNotifier.plan(inc, log, amb1, now).notifications.single;
      expect(mine['kind'], PushKind.assignedToYou);
      expect(mine['title'], '🚑 ได้รับมอบหมายเคสใหม่');
      expect(kinds(LocalIncidentNotifier.plan(inc, log, amb3, now)), [PushKind.caseTaken]);
      final rep = LocalIncidentNotifier.plan(inc, log, reporter, now);
      expect(rep.notifications.single['body'], 'กู้ชีพ 1 รับเคสของคุณแล้ว');
      // reassigned to another unit later: reporter not told again
      final re = LocalIncidentNotifier.plan(
          incident(status: 'assigned', ambulance: 'AMB-3', assignedBy: 'hospital'),
          rep.nextLog, reporter, now);
      expect(re.notifications, isEmpty);
      expect(re.changed, isTrue);
    });

    test('[S19] self-accept clears the stale new-case notification on every ambulance', () {
      final inc = incident(status: 'assigned', ambulance: 'AMB-3', assignedBy: 'ambulance');
      final log = {'created': true};
      expect(kinds(LocalIncidentNotifier.plan(inc, log, amb3, now)), [PushKind.caseTaken]);
      expect(kinds(LocalIncidentNotifier.plan(inc, log, amb1, now)), [PushKind.caseTaken]);
    });

    test('[S19] ambulance near: reporter once, with and without eta', () {
      final log = {'created': true, 'assignedTo': 'AMB-1'};
      final withEta = LocalIncidentNotifier.plan(
          incident(status: 'assigned', ambulance: 'AMB-1', callSign: 'กู้ชีพ 1', near: now, eta: 2),
          log, reporter, now);
      expect(withEta.notifications.single['body'],
          'กู้ชีพ 1 อยู่ห่างไม่ถึง 500 ม. (อีกราว 2 นาที) เตรียมตัวรอที่จุดเกิดเหตุ');
      expect(withEta.notifications.single['title'], '📍 รถพยาบาลใกล้ถึงแล้ว');
      final again = LocalIncidentNotifier.plan(
          incident(status: 'assigned', ambulance: 'AMB-1', near: now), withEta.nextLog, reporter, now);
      expect(again.notifications, isEmpty);
      final noEta = LocalIncidentNotifier.plan(
          incident(status: 'assigned', ambulance: 'AMB-1', near: now), log, reporter, now);
      expect(noEta.notifications.single['body'],
          'หน่วยกู้ชีพ อยู่ห่างไม่ถึง 500 ม. เตรียมตัวรอที่จุดเกิดเหตุ');
      expect(LocalIncidentNotifier.plan(
              incident(status: 'assigned', ambulance: 'AMB-1', near: now), log, amb1, now)
          .notifications, isEmpty);
    });

    test('[S19] resolved: reporter once, hospital name in body', () {
      final log = {'created': true, 'assignedTo': 'AMB-1', 'nearScene': true};
      final r = LocalIncidentNotifier.plan(
          incident(status: 'resolved', ambulance: 'AMB-1', near: now, hospitalName: 'รพ.เชียงราย'),
          log, reporter, now);
      expect(r.notifications.single['body'], 'ผู้ป่วยถึง รพ.เชียงราย เรียบร้อยแล้ว');
      expect(LocalIncidentNotifier.plan(
              incident(status: 'resolved', ambulance: 'AMB-1', near: now), r.nextLog, reporter, now)
          .notifications, isEmpty);
    });

    test('old or archived incidents are recorded silently', () {
      final old = incident(
          status: 'assigned', ambulance: 'AMB-1', createdAt: now.subtract(const Duration(days: 3)));
      final r = LocalIncidentNotifier.plan(old, const {}, reporter, now);
      expect(r.notifications, isEmpty);
      expect(r.nextLog, {
        'created': true,
        'assignedTo': 'AMB-1',
        'assignedUnits': ['AMB-1'],
        'vehicleCount': 1,
      });
      expect(LocalIncidentNotifier.plan(incident(archived: true), const {}, amb1, now).notifications,
          isEmpty);
    });

    test('[S14][S19] more vehicles on one case: new crew notified, reporter told the new count once', () {
      const u1 = AssignedUnit(unitId: 'AMB-1', plate: 'กข 1', callSign: 'กู้ชีพ 1', assignedBy: 'ambulance');
      // บัญชีที่สองบนรถคันเดียวกัน (ทะเบียนเดียวกัน) ไม่ใช่รถเพิ่ม
      const u1b = AssignedUnit(unitId: 'AMB-9', plate: 'กข-1', callSign: 'กู้ชีพ 1', assignedBy: 'ambulance');
      const u3 = AssignedUnit(unitId: 'AMB-3', plate: 'ขค 3', callSign: 'กู้ชีพ 3', assignedBy: 'hospital');
      final one = incident(status: 'assigned', ambulance: 'AMB-1', assignedBy: 'ambulance', callSign: 'กู้ชีพ 1')
          .copyWith(assignedUnits: [u1]);
      final r1 = LocalIncidentNotifier.plan(one, const {'created': true}, reporter, now);
      expect(kinds(r1), [PushKind.ambulanceOnTheWay]);

      final crew = one.copyWith(assignedUnits: [u1, u1b]);
      final r2 = LocalIncidentNotifier.plan(crew, r1.nextLog, reporter, now);
      expect(r2.notifications, isEmpty);
      expect(r2.changed, isTrue);

      final two = one.copyWith(assignedUnits: [u1, u1b, u3]);
      final r3 = LocalIncidentNotifier.plan(two, r2.nextLog, reporter, now);
      expect(kinds(r3), [PushKind.ambulanceOnTheWay]);
      expect(r3.notifications.single['body'], contains('2 คัน'));
      expect(LocalIncidentNotifier.plan(two, r3.nextLog, reporter, now).notifications, isEmpty);

      // คันที่ รพ. สั่งเพิ่มได้ "ได้รับมอบหมาย", คันแรกไม่ได้อะไรซ้ำ
      final forAmb3 = LocalIncidentNotifier.plan(two, const {'created': true, 'assignedTo': 'AMB-1'}, amb3, now);
      expect(kinds(forAmb3), [PushKind.assignedToYou]);
      final forAmb1 = LocalIncidentNotifier.plan(
          two, const {'created': true, 'assignedTo': 'AMB-1', 'assignedUnits': ['AMB-1']}, amb1, now);
      expect(forAmb1.notifications, isEmpty);
    });

    test('empty severity/address fall back like the server', () {
      final r = LocalIncidentNotifier.plan(
          incident(severity: '', address: ''), const {}, agencyH1, now);
      expect(r.notifications.single['body'], 'เชียงใหม่');
    });
  });

  group('IncidentNotificationPresenter.specFor', () {
    Map<String, dynamic> data(String kind, String audience, {String title = 'T'}) =>
        {'incidentId': 'INC-7', 'kind': kind, 'audience': audience, 'title': title, 'body': 'B'};

    test('new case gets buttons per role on the emergency channel', () {
      final amb = IncidentNotificationPresenter.specFor(data(PushKind.newIncident, PushAudience.ambulance))!;
      expect(amb.emergency, isTrue);
      expect(amb.category, 'RA_NEW_AMBULANCE');
      final agency = IncidentNotificationPresenter.specFor(data(PushKind.newIncident, PushAudience.agency))!;
      expect(agency.category, 'RA_NEW_AGENCY');
      expect(agency.id, notificationIdForIncident('INC-7'));
    });

    test('status updates share the case id so they replace each other', () {
      final ids = [PushKind.ambulanceOnTheWay, PushKind.ambulanceNear, PushKind.resolved]
          .map((k) => IncidentNotificationPresenter.specFor(data(k, PushAudience.reporter))!)
          .toList();
      expect(ids.map((s) => s.id).toSet().length, 1);
      expect(ids.every((s) => !s.emergency && s.category == null), isTrue);
    });

    test('case_taken only cancels; empty title or missing id is skipped', () {
      final taken = IncidentNotificationPresenter.specFor(data(PushKind.caseTaken, PushAudience.ambulance, title: ''))!;
      expect(taken.cancelOnly, isTrue);
      expect(IncidentNotificationPresenter.specFor(data(PushKind.resolved, PushAudience.reporter, title: '')), isNull);
      expect(IncidentNotificationPresenter.specFor({'kind': 'resolved', 'title': 'x'}), isNull);
    });

    test('payload round-trips into the router intent', () {
      final spec = IncidentNotificationPresenter.specFor(data(PushKind.newIncident, PushAudience.ambulance))!;
      final intent = NotificationIntent.fromPayload(spec.payload, actionId: PushAction.accept)!;
      expect(intent.incidentId, 'INC-7');
      expect(intent.audience, PushAudience.ambulance);
      expect(intent.action, PushAction.accept);
    });
  });

  group('NotificationRouter.isAllowed', () {
    test('role and reporter checks', () {
      expect(NotificationRouter.isAllowed(
          audience: PushAudience.agency, userRole: 'agency', userEmail: 'a', reporterEmail: 'x'), isTrue);
      expect(NotificationRouter.isAllowed(
          audience: PushAudience.agency, userRole: 'ambulance', userEmail: 'a', reporterEmail: 'x'), isFalse);
      expect(NotificationRouter.isAllowed(
          audience: PushAudience.ambulance, userRole: 'ambulance', userEmail: 'a', reporterEmail: 'x'), isTrue);
      expect(NotificationRouter.isAllowed(
          audience: PushAudience.reporter, userRole: 'driver', userEmail: 'D@x.com ', reporterEmail: 'd@X.com'), isTrue);
      expect(NotificationRouter.isAllowed(
          audience: PushAudience.reporter, userRole: 'agency', userEmail: 'other@x.com', reporterEmail: 'd@x.com'), isFalse);
      expect(NotificationRouter.isAllowed(
          audience: PushAudience.reporter, userRole: 'driver', userEmail: '', reporterEmail: ''), isFalse);
    });
  });
}
