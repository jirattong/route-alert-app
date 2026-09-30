import 'package:flutter_test/flutter_test.dart';
import 'package:route_alert/core/services/notification_intent.dart';

void main() {
  group('notificationIdForIncident', () {
    test('stable, in reserved range, and distinct per incident', () {
      final a = notificationIdForIncident('INC-1726000000000');
      expect(notificationIdForIncident('INC-1726000000000'), a);
      expect(a, inInclusiveRange(0x40000000, 0x7fffffff));
      expect(notificationIdForIncident('INC-1726000000001'), isNot(a));
      expect(a, isNot(anyOf(911, 1669)));
    });
  });

  group('NotificationIntent', () {
    test('payload round trip keeps fields and maps action id', () {
      const intent = NotificationIntent(
          incidentId: 'INC-1', kind: PushKind.newIncident, audience: PushAudience.ambulance);
      final tapped = NotificationIntent.fromPayload(intent.toPayload());
      expect(tapped!.sameAs(intent), isTrue);
      final accepted =
          NotificationIntent.fromPayload(intent.toPayload(), actionId: PushAction.accept);
      expect(accepted!.action, PushAction.accept);
    });

    test('rejects missing or malformed data', () {
      expect(NotificationIntent.fromPayload(null), isNull);
      expect(NotificationIntent.fromPayload('not json'), isNull);
      expect(NotificationIntent.fromData({'kind': 'resolved'}), isNull);
    });

    test('hub queues intents until a handler registers', () {
      final received = <NotificationIntent>[];
      NotificationIntentHub.dispatch(const NotificationIntent(
          incidentId: 'INC-9', kind: PushKind.resolved, audience: PushAudience.reporter));
      NotificationIntentHub.setHandler(received.add);
      expect(received.single.incidentId, 'INC-9');
      NotificationIntentHub.dispatch(NotificationIntent.fromData({'incidentId': 'INC-10'}));
      expect(received.length, 2);
    });
  });
}
