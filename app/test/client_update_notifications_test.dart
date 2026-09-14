@Tags(['short'])
library;

import 'package:endlessnet/client_update_notifications.dart';
import 'package:endlessnet/client_runtime_snapshot.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'client_session_test.dart' as fixtures;

final clock = DateTime.utc(2026, 9, 14);
api.BuildIdentity build() => api.BuildIdentity(
  version: 'private-version',
  platform: api.Platform.PLATFORM_WINDOWS,
  architecture: 'amd64',
);
ClientRuntimeSnapshot snapshot({bool observer = false}) {
  final event = fixtures.snapshot();
  event.snapshot.runtime.build = build();
  if (observer) {
    event.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
  }
  return ClientRuntimeSnapshot.fromEvent(event);
}

api.UpdateInfo projection() => api.UpdateInfo()
  ..mergeFromProto3Json({
    'metadata': {'instanceId': 'runtime-a', 'revision': '100'},
    'installedRuntime': build().toProto3Json(),
    'reportedUi': build().toProto3Json(),
    'installedPair': {'state': 'COMPATIBILITY_STATE_COMPATIBLE'},
    'state': 'UPDATE_STATE_AVAILABLE',
    'available': {
      'releaseId': 'private-release',
      'manifestSha256': 'a' * 64,
      'signingKeyId': 'private-key',
      'verifiedAt': '2026-09-13T00:00:00Z',
      'expiresAt': '2026-09-15T00:00:00Z',
      'runtime': build().toProto3Json(),
      'pairedUiVersion': 'private-version',
      'compatibility': {'state': 'COMPATIBILITY_STATE_COMPATIBLE'},
      'classification': 'UPDATE_CLASSIFICATION_ORDINARY',
      'channel': 'DISTRIBUTION_CHANNEL_VENDOR_PACKAGE',
      'actionUrl': 'https://private.example/action',
    },
  });
void main() {
  late ClientUpdateNotifications planner;
  setUp(() => planner = ClientUpdateNotifications());
  ClientUpdateNotice? observe(
    api.UpdateInfo? info, {
    bool ready = true,
    bool enabled = true,
    bool observer = false,
    DateTime? now,
  }) => planner.observe(
    snapshot: snapshot(observer: observer),
    info: info,
    uiBuild: build(),
    ready: ready,
    enabled: enabled,
    now: now ?? clock,
  );
  test(
    'verified available update deduplicates after acknowledgment and reconnect',
    () {
      final notice = observe(projection())!;
      expect(observe(projection()), same(notice));
      expect(planner.acknowledge(notice, clock), isTrue);
      expect(observe(projection()), isNull);
      expect(observe(null, ready: false), isNull);
      expect(observe(projection()), isNull);
    },
  );
  test('disable, observer and stream loss invalidate pending receipts', () {
    for (final kind in ['disabled', 'observer', 'offline']) {
      final notice = observe(projection())!;
      observe(
        null,
        enabled: kind != 'disabled',
        observer: kind == 'observer',
        ready: kind != 'offline',
      );
      expect(planner.acknowledge(notice, clock), isFalse);
    }
  });
  test(
    'expired projection and late completion never notify or acknowledge',
    () {
      final notice = observe(projection())!;
      final expiry = DateTime.utc(2026, 9, 15);
      expect(planner.acknowledge(notice, expiry), isFalse);
      expect(observe(projection(), now: expiry), isNull);
    },
  );
  test(
    'unverified, malformed, wrong pairing and stale metadata are rejected',
    () {
      for (final corrupt in <void Function(api.UpdateInfo)>[
        (i) => i.state = api.UpdateState.UPDATE_STATE_VERIFICATION_FAILED,
        (i) => i.metadata.instanceId = 'other',
        (i) => i.metadata.clearRevision(),
        (i) => i.reportedUi.version = 'other',
        (i) => i.available.manifestSha256 = 'bad',
        (i) => i.available.actionUrl = 'http://private.example',
        (i) => i.ensureDiscovery().availability =
            api.Availability.AVAILABILITY_UNSUPPORTED,
      ]) {
        final info = projection();
        corrupt(info);
        expect(observe(info), isNull);
      }
    },
  );
  test('all non-available source states without metadata stay silent', () {
    for (final state in api.UpdateState.values) {
      final info = projection()
        ..state = state
        ..clearAvailable();
      expect(observe(info), isNull);
    }
  });
  test(
    'changed release or classification can notify, refreshed revision cannot',
    () {
      planner.acknowledge(observe(projection())!, clock);
      final sameRelease = projection()..metadata.revision += 1;
      expect(observe(sameRelease), isNull);
      final security = projection()
        ..available.classification =
            api.UpdateClassification.UPDATE_CLASSIFICATION_SECURITY;
      final notice = observe(security)!;
      planner.acknowledge(notice, clock);
      final newer = security.deepCopy()
        ..available.releaseId = 'another-release';
      expect(observe(newer), isNotNull);
    },
  );
  for (final locale in ClientLocale.values) {
    test('fixed $locale notification never carries private update data', () {
      final notice = observe(projection())!;
      expect(notice.title(locale), 'EndlessNet');
      expect(
        notice.body(locale),
        locale == ClientLocale.en
            ? 'A verified update is available. Open EndlessNet to review compatibility and update options.'
            : 'Доступно проверенное обновление. Откройте EndlessNet, чтобы проверить совместимость и варианты обновления.',
      );
      expect(notice.body(locale), isNot(contains('private')));
    });
  }
}
