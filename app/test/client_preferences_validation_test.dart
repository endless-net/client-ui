@Tags(['short'])
library;

import 'package:endlessnet/client_preferences.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const keep = api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_KEEP_INTENT;
  const disconnect = api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_DISCONNECT;
  const unspecified = api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_UNSPECIFIED;

  api.GetPreferencesResponse preferences() =>
      api.GetPreferencesResponse()..mergeFromProto3Json({
        'preferences': {
          'metadata': {'instanceId': 'runtime', 'revision': '7'},
          'profileId': 'profile',
          'lifecycle': {
            for (final name in [
              'runtimeStart',
              'uiQuit',
              'userLogoff',
              'suspend',
              'resume',
            ])
              name: {
                'effective': keep.name,
                'allowedValues': [keep.name, disconnect.name],
              },
          },
        },
      });

  api.ListManagedSettingsResponse policies() =>
      api.ListManagedSettingsResponse()..mergeFromProto3Json({
        'metadata': {'instanceId': 'runtime', 'revision': '7'},
        'settings': [
          {
            'key': 'PREFERENCE_KEY_UI_QUIT',
            'lifecycleValue': keep.name,
            'control': {'source': 'SETTING_SOURCE_DEFAULT'},
          },
        ],
      });

  final fields = <String, api.LifecycleSetting Function(api.RuntimeLifecycle)>{
    'runtimeStart': (l) => l.runtimeStart,
    'uiQuit': (l) => l.uiQuit,
    'userLogoff': (l) => l.userLogoff,
    'suspend': (l) => l.suspend,
    'resume': (l) => l.resume,
  };
  final invalid = <String, void Function(api.LifecycleSetting)>{
    'effective': (s) => s.effective = unspecified,
    'requested': (s) => s.requested = unspecified,
    'choice': (s) => s.allowedValues.add(unspecified),
    'duplicate choice': (s) => s.allowedValues.add(keep),
  };
  for (final field in fields.entries) {
    for (final change in invalid.entries) {
      test(
        'US-10 rejects ${field.key} ${change.key} before policy read',
        () async {
          final response = preferences();
          change.value(field.value(response.preferences.lifecycle));
          await expectLater(
            readClientPreferences(
              instanceId: 'runtime',
              profileId: 'profile',
              get: (_) async => response,
              listManaged: (_) =>
                  throw TestFailure('Invalid projection continued'),
              checkContext: () {},
            ),
            throwsFormatException,
          );
        },
      );
    }
  }

  test('US-10 rejects unspecified managed lifecycle value', () async {
    final response = policies();
    response.settings.single.lifecycleValue = unspecified;
    await expectLater(
      readClientPreferences(
        instanceId: 'runtime',
        profileId: 'profile',
        get: (_) async => preferences(),
        listManaged: (_) async => response,
        checkContext: () {},
      ),
      throwsFormatException,
    );
  });

  test(
    'US-10 retains unknown override and unavailable choices as absence',
    () async {
      final response = preferences();
      response.preferences.lifecycle.uiQuit.allowedValues.clear();
      final result = await readClientPreferences(
        instanceId: 'runtime',
        profileId: 'profile',
        get: (_) async => response,
        listManaged: (_) async => policies(),
        checkContext: () {},
      );
      expect(result.preferences.lifecycle.uiQuit.hasRequested(), isFalse);
      expect(result.preferences.lifecycle.uiQuit.allowedValues, isEmpty);
      expect(result.preferences.lifecycle.uiQuit.effective, keep);
    },
  );
}
