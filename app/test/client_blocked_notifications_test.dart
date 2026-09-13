@Tags(['short'])
library;

import 'package:endlessnet/client_deadline_notifications.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'client_deadline_notifications_test.dart' as fixtures;

void main() {
  late ClientDeadlineNotifications planner;
  setUp(() => planner = ClientDeadlineNotifications());
  List<ClientDeadlineNotice> observe({
    api.CredentialState state = api.CredentialState.CREDENTIAL_STATE_BLOCKED,
    String? deadline,
    bool enabled = true,
    bool observer = false,
  }) => planner.observe(
    snapshot: fixtures.snapshot(
      session: api.SessionState.SESSION_STATE_ACTIVE,
      credential: state,
      deadline: deadline,
      observer: observer,
    ),
    ready: true,
    enabled: enabled,
  );

  test('blocked is independent of active session and is not expiry', () {
    final notice = observe().single;
    expect(notice.kind, ClientDeadlineNoticeKind.credentialBlocked);
    expect(observe(), [notice]);
    expect(observe(observer: true), isEmpty);
    expect(planner.acknowledge(notice), isFalse);
    expect(observe(enabled: false), isEmpty);
  });
  test('blocked dedup survives reconnect and changed deadline', () {
    final notice = observe(deadline: '2026-10-01T00:00:00Z').single;
    expect(planner.acknowledge(notice), isTrue);
    planner.observe(snapshot: null, ready: false, enabled: true);
    expect(observe(deadline: '2026-11-01T00:00:00Z'), isEmpty);
    expect(observe(), isEmpty);
  });
  for (final enabled in [true, false]) {
    test(
      'authoritative valid ends blocked episode even when enabled=$enabled',
      () {
        planner.acknowledge(observe().single);
        expect(
          observe(
            state: api.CredentialState.CREDENTIAL_STATE_VALID,
            enabled: enabled,
          ),
          isEmpty,
        );
        final next = observe().single;
        expect(next.kind, ClientDeadlineNoticeKind.credentialBlocked);
        planner.acknowledge(next);
        expect(observe(), isEmpty);
      },
    );
  }
  test('unknown and renewing do not manufacture a new blocked episode', () {
    planner.acknowledge(observe().single);
    for (final state in [
      api.CredentialState.CREDENTIAL_STATE_UNSPECIFIED,
      api.CredentialState.CREDENTIAL_STATE_RENEWING,
      api.CredentialState.CREDENTIAL_STATE_ABSENT,
    ]) {
      expect(observe(state: state), isEmpty);
      expect(observe(), isEmpty);
    }
  });
  test('in-flight blocked receipt cannot acknowledge a later episode', () {
    final old = observe().single;
    observe(state: api.CredentialState.CREDENTIAL_STATE_VALID);
    final fresh = observe().single;
    expect(planner.acknowledge(old), isFalse);
    expect(identical(old, fresh), isFalse);
    expect(planner.acknowledge(fresh), isTrue);
  });
  for (final locale in ClientLocale.values) {
    test('blocked $locale body is fixed and contains no private context', () {
      final notice = observe().single;
      expect(notice.title(locale), 'EndlessNet');
      expect(
        notice.body(locale),
        locale == ClientLocale.en
            ? 'Device credentials are blocked. Open EndlessNet to review the required action.'
            : 'Учётные данные устройства заблокированы. Откройте EndlessNet, чтобы проверить требуемое действие.',
      );
      expect(notice.body(locale), isNot(contains('private')));
      expect(notice.body(locale), isNot(contains('secret')));
      expect(notice.body(locale), isNot(contains('https:')));
    });
  }
}
