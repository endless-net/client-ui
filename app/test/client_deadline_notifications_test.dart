@Tags(['short'])
library;

import 'package:endlessnet/client_deadline_notifications.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_runtime_snapshot.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

ClientRuntimeSnapshot snapshot({
  api.SessionState session = api.SessionState.SESSION_STATE_EXPIRING,
  api.CredentialState credential =
      api.CredentialState.CREDENTIAL_STATE_EXPIRING,
  String? deadline,
  String profile = 'private-profile',
  bool observer = false,
  int revision = 1,
  String instance = 'runtime-instance',
}) {
  final value = fixtures.snapshot(revision);
  value.snapshot.runtime.instanceId = instance;
  value.metadata.instanceId = instance;
  value.snapshot.status.metadata.instanceId = instance;
  value.snapshot.status.activeProfileId = profile;
  value.snapshot.runtime.callerAccess = observer
      ? api.Access.ACCESS_OBSERVER
      : api.Access.ACCESS_OWNER;
  value.snapshot.status.mergeFromProto3Json({
    'session': {'state': session.name, 'expiresAt': ?deadline},
    'credential': {'state': credential.name, 'expiresAt': ?deadline},
    'pendingAction': {'browserUrl': 'https://private.example/secret'},
  });
  return ClientRuntimeSnapshot.fromEvent(value, initial: false);
}

void main() {
  late ClientDeadlineNotifications planner;
  setUp(() => planner = ClientDeadlineNotifications());
  List<ClientDeadlineNotice> observe(
    ClientRuntimeSnapshot? value, {
    bool ready = true,
    bool enabled = true,
  }) => planner.observe(snapshot: value, ready: ready, enabled: enabled);

  test(
    'session and credential states are classified independently without a clock',
    () {
      for (final session in api.SessionState.values) {
        for (final credential in api.CredentialState.values) {
          planner.clear();
          final notices = observe(
            snapshot(
              session: session,
              credential: credential,
              deadline: '2000-01-01T00:00:00Z',
            ),
          );
          expect(notices.map((n) => n.kind), [
            if (session == api.SessionState.SESSION_STATE_EXPIRING)
              ClientDeadlineNoticeKind.sessionExpiring,
            if (session == api.SessionState.SESSION_STATE_EXPIRED)
              ClientDeadlineNoticeKind.sessionExpired,
            if (credential == api.CredentialState.CREDENTIAL_STATE_EXPIRING)
              ClientDeadlineNoticeKind.credentialExpiring,
            if (credential == api.CredentialState.CREDENTIAL_STATE_EXPIRED)
              ClientDeadlineNoticeKind.credentialExpired,
            if (credential == api.CredentialState.CREDENTIAL_STATE_BLOCKED)
              ClientDeadlineNoticeKind.credentialBlocked,
          ]);
        }
      }
    },
  );
  test(
    'delivery must be acknowledged, then reconnect does not duplicate it',
    () {
      final value = snapshot();
      final pending = observe(value);
      expect(observe(value), pending);
      expect(planner.acknowledge(pending.first), isTrue);
      expect(observe(value), [pending.last]);
      expect(planner.acknowledge(pending.last), isTrue);
      expect(observe(null, ready: false), isEmpty);
      expect(observe(snapshot(revision: 2)), isEmpty);
    },
  );
  test(
    'transport loss invalidates an in-flight acknowledgement without losing delivered dedup',
    () {
      final pending = observe(snapshot());
      planner.acknowledge(pending.first);
      observe(null, ready: false);
      expect(planner.acknowledge(pending.last), isFalse);
      final fresh = observe(snapshot());
      expect(fresh.single.kind, ClientDeadlineNoticeKind.credentialExpiring);
      expect(identical(fresh.single, pending.last), isFalse);
    },
  );
  test(
    'disabled notifications do not consume events or accept old receipts',
    () {
      final value = snapshot();
      expect(observe(value, enabled: false), isEmpty);
      final pending = observe(value);
      planner.acknowledge(pending.first);
      observe(value, enabled: false);
      expect(planner.acknowledge(pending.last), isFalse);
      expect(
        observe(value).single.kind,
        ClientDeadlineNoticeKind.credentialExpiring,
      );
    },
  );
  test('new deadline and expired transition generate distinct events', () {
    for (final notice in observe(snapshot(deadline: '2026-10-01T00:00:00Z'))) {
      planner.acknowledge(notice);
    }
    expect(observe(snapshot(deadline: '2026-10-01T00:00:00Z')), isEmpty);
    expect(observe(snapshot(deadline: '2026-11-01T00:00:00Z')).length, 2);
    final old = observe(snapshot());
    final expired = observe(
      snapshot(session: api.SessionState.SESSION_STATE_EXPIRED),
    );
    expect(expired.map((n) => n.kind), [
      ClientDeadlineNoticeKind.credentialExpiring,
      ClientDeadlineNoticeKind.sessionExpired,
    ]);
    expect(planner.acknowledge(old.first), isFalse);
  });
  test(
    'observer and absent profile discard owner context and old receipts',
    () {
      for (final value in [snapshot(observer: true), snapshot(profile: '')]) {
        final pending = observe(snapshot());
        expect(observe(value), isEmpty);
        expect(planner.acknowledge(pending.first), isFalse);
        expect(observe(snapshot()).length, 2);
      }
    },
  );
  test('profile switch and ABA cannot acknowledge another delivery', () {
    final pending = observe(snapshot(profile: 'a'));
    observe(snapshot(profile: 'b'));
    observe(snapshot(profile: 'a'));
    expect(planner.acknowledge(pending.first), isFalse);
  });
  test(
    'runtime restart starts a new delivery context and rejects old receipts',
    () {
      final pending = observe(snapshot(instance: 'first'));
      planner.acknowledge(pending.first);
      final fresh = observe(snapshot(instance: 'second'));
      expect(fresh.length, 2);
      expect(planner.acknowledge(pending.last), isFalse);
      for (final notice in fresh) {
        expect(planner.acknowledge(notice), isTrue);
      }
      expect(observe(snapshot(instance: 'second', revision: 2)), isEmpty);
    },
  );
  test(
    'explicit context cleanup invalidates receipts and delivery history',
    () {
      final pending = observe(snapshot());
      planner.acknowledge(pending.first);
      planner.clear();
      expect(planner.acknowledge(pending.last), isFalse);
      expect(observe(snapshot()).length, 2);
    },
  );
  for (final locale in ClientLocale.values) {
    test('four fixed notification bodies in $locale contain no private context', () {
      final notices = [
        ...observe(snapshot()),
        ...observe(
          snapshot(
            session: api.SessionState.SESSION_STATE_EXPIRED,
            credential: api.CredentialState.CREDENTIAL_STATE_EXPIRED,
          ),
        ),
      ];
      expect(
        notices.map((n) => n.body(locale)),
        locale == ClientLocale.ru
            ? [
                'Срок сессии истекает. Откройте EndlessNet, чтобы проверить варианты продления.',
                'Срок учётных данных устройства истекает. Откройте EndlessNet, чтобы проверить их состояние.',
                'Срок сессии истёк. Откройте EndlessNet, чтобы проверить требуемое действие.',
                'Срок учётных данных устройства истёк. Откройте EndlessNet, чтобы проверить варианты восстановления.',
              ]
            : [
                'Your session is expiring. Open EndlessNet to review renewal options.',
                'Device credentials are expiring. Open EndlessNet to review their status.',
                'Your session has expired. Open EndlessNet to review the required action.',
                'Device credentials have expired. Open EndlessNet to review recovery options.',
              ],
      );
      for (final notice in notices) {
        expect(notice.title(locale), 'EndlessNet');
        expect(notice.body(locale), isNot(contains('private')));
        expect(notice.body(locale), isNot(contains('secret')));
      }
    });
  }
}
