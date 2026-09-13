import 'dart:async';
import 'dart:io';
import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet/client_support_info.dart';
import 'package:endlessnet/client_update_info.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'support/scenario_host.dart';

const _runtimeBuild = {
  'version': 'runtime-dev',
  'platform': 'PLATFORM_WINDOWS',
  'architecture': 'amd64',
};
const _uiBuild = {
  'version': 'ui-dev',
  'platform': 'PLATFORM_WINDOWS',
  'architecture': 'amd64',
};
const _support = {
  'runtime': _runtimeBuild,
  'productName': 'EndlessNet',
  'supportUrl': 'https://support.example/',
  'offlineHelpKey': 'synthetic-help',
};
const _states = [
  'UNKNOWN',
  'UP_TO_DATE',
  'AVAILABLE',
  'EXTERNAL_MANAGER_REQUIRED',
  'SOURCE_UNAVAILABLE',
  'VERIFICATION_FAILED',
];

Map<String, Object> _update(String state) => {
  'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
  'installedRuntime': _runtimeBuild,
  'reportedUi': _uiBuild,
  'installedPair': {
    'state': 'COMPATIBILITY_STATE_INCOMPATIBLE',
    'reasonKey': 'pair.incompatible',
  },
  'state': 'UPDATE_STATE_$state',
  if (state == 'AVAILABLE')
    'available': {
      'releaseId': 'synthetic-release',
      'manifestSha256': 'a' * 64,
      'signingKeyId': 'synthetic-key',
      'verifiedAt': '2026-01-01T00:00:00Z',
      'expiresAt': '2099-01-01T00:00:00Z',
      'runtime': _runtimeBuild,
      'pairedUiVersion': 'ui-dev',
      'compatibility': {
        'state': 'COMPATIBILITY_STATE_COMPATIBLE',
        'acceptedContractSha256': [api.ClientContract.sha256],
      },
      'classification': 'UPDATE_CLASSIFICATION_SECURITY',
      'channel': 'DISTRIBUTION_CHANNEL_VENDOR_PACKAGE',
      'actionUrl': 'https://distribution.example/',
    },
};

void main() {
  final executable = Platform.environment['ENDLESSNET_TESTSERVER'];
  test(
    'US-13: information process fixtures satisfy typed reader validation',
    () async {
      final support = await readClientSupportInfo(
        installedRuntime: api.BuildIdentity()
          ..mergeFromProto3Json(_runtimeBuild),
        get: (_) async =>
            api.GetSupportInfoResponse()
              ..mergeFromProto3Json({'info': _support}),
        checkContext: () {},
      );
      expect(support.productName, 'EndlessNet');
      for (final state in _states) {
        final info = await readClientUpdateInfo(
          instanceId: 'runtime-a',
          installedRuntime: api.BuildIdentity()
            ..mergeFromProto3Json(_runtimeBuild),
          reportedUi: api.BuildIdentity()..mergeFromProto3Json(_uiBuild),
          get: (_) async =>
              api.GetUpdateInfoResponse()
                ..mergeFromProto3Json({'info': _update(state)}),
          checkContext: () {},
          now: () => DateTime.utc(2026, 9, 13),
        );
        expect(info.state.name, 'UPDATE_STATE_$state');
        expect(info.hasAvailable(), state == 'AVAILABLE');
      }
    },
  );
  for (final state in ['observer', ..._states]) {
    test(
      'US-13: producer information $state has no mutation side effects',
      () async {
        final directory = await Directory.systemTemp.createTemp('en-info-');
        addTearDown(() => directory.delete(recursive: true));
        final observer = state == 'observer';
        final runtime = {
          'protocol': api.ClientContract.protocol,
          'contractSha256': api.ClientContract.sha256,
          'instanceId': 'runtime-a',
          'build': _runtimeBuild,
          'callerAccess': observer ? 'ACCESS_OBSERVER' : 'ACCESS_OWNER',
        };
        final host = await ScenarioHost.start(executable!, [
          {
            'method': 'GetRuntimeInfo',
            'request': {},
            'responses': [
              {'runtime': runtime},
            ],
          },
          {
            'method': 'WatchEvents',
            'request': {},
            'hold_open': true,
            'responses': [
              {
                'sequence': '1',
                'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
                'snapshot': {
                  'runtime': runtime,
                  'status': {
                    'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
                  },
                },
              },
            ],
          },
          {
            'method': 'GetSupportInfo',
            'request': {},
            'responses': [
              {'info': _support},
            ],
          },
          if (!observer)
            {
              'method': 'GetUpdateInfo',
              'request': {'reportedUi': _uiBuild},
              'responses': [
                {'info': _update(state)},
              ],
            },
        ], observer: observer);
        final session = ClientSession(
          journal: ClientIntentJournal(directory),
          endpoint: host.endpoint,
        );
        try {
          final ready = Completer<void>();
          session.state.addListener(() {
            if (session.state.link == ClientLinkState.ready &&
                !ready.isCompleted) {
              ready.complete();
            }
          });
          await session.connect();
          await ready.future.timeout(const Duration(seconds: 10));
          final support = await session.getSupportInfo();
          expect(support.isFrozen, isTrue);
          expect(support.supportUrl, 'https://support.example/');
          expect(support.offlineHelpKey, 'synthetic-help');
          final ui = api.BuildIdentity()..mergeFromProto3Json(_uiBuild);
          if (observer) {
            await expectLater(session.getUpdateInfo(ui), throwsStateError);
          } else {
            final info = await session.getUpdateInfo(ui);
            expect(info.isFrozen, isTrue);
            expect(info.state.name, 'UPDATE_STATE_$state');
            expect(
              info.installedPair.state,
              api.CompatibilityState.COMPATIBILITY_STATE_INCOMPATIBLE,
            );
            expect(info.hasAvailable(), state == 'AVAILABLE');
            if (state == 'AVAILABLE') {
              expect(
                info.available.classification,
                api.UpdateClassification.UPDATE_CLASSIFICATION_SECURITY,
              );
            }
          }
          expect(session.state.link, ClientLinkState.ready);
          expect(session.state.snapshot!.status.activeProfileId, isEmpty);
          expect(await session.journal.pending(), isEmpty);
          await session.close();
          await host.verify();
        } finally {
          await session.close();
          await host.close();
        }
      },
      skip: executable == null
          ? 'Requires pinned producer host in desktop CI'
          : false,
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
