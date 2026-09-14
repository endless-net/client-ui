@Tags(['short'])
library;

import 'package:endlessnet/client_profiles.dart';
import 'package:endlessnet/client_networks.dart';
import 'package:endlessnet/client_resources.dart';
import 'package:endlessnet/client_resources_panel.dart';
import 'package:endlessnet/client_exit_nodes.dart';
import 'package:endlessnet/client_exit_panel.dart';
import 'package:endlessnet/client_update_info.dart';
import 'package:endlessnet/client_update_panel.dart';
import 'package:endlessnet/client_support_info.dart';
import 'package:endlessnet/client_support_panel.dart';
import 'package:endlessnet/client_networks_panel.dart';
import 'package:endlessnet/client_create_profile_panel.dart';
import 'dart:async';
import 'package:endlessnet/client_profiles_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:flutter/material.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'support/contract_test_scaffold.dart';

api.ListProfilesResponse page(
  String id, {
  String next = '',
  String revision = '7',
}) => api.ListProfilesResponse()
  ..mergeFromProto3Json({
    'activeProfileId': 'a',
    'profiles': [
      {'id': id, 'displayName': 'Profile $id', 'active': id == 'a'},
    ],
    'page': {
      'nextPageToken': next,
      'metadata': {'instanceId': 'runtime-a', 'revision': revision},
    },
  });

api.ListResourcesResponse _resourcePage(String suffix, {String next = ''}) =>
    api.ListResourcesResponse()..mergeFromProto3Json({
      'page': {
        'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
        'nextPageToken': next,
      },
      'resources': [
        {
          'id': 'host-$suffix',
          'displayName': 'Host $suffix',
          'networkId': 'network-a',
          'kind': 'RESOURCE_KIND_HOST',
          'host': {'hostname': 'host.example'},
          'enabled': {'effective': true, 'requested': false},
          'overlappingResourceIds': ['visible-outside-query'],
        },
        {
          'id': 'subnet-$suffix',
          'displayName': 'Subnet',
          'networkId': 'network-a',
          'kind': 'RESOURCE_KIND_SUBNET',
          'subnet': {'cidr': '192.0.2.0/24'},
        },
        {
          'id': 'service-$suffix',
          'displayName': 'Service',
          'networkId': 'network-a',
          'kind': 'RESOURCE_KIND_SERVICE',
          'service': {
            'hostname': 'service.example',
            'port': 443,
            'protocol': 'tcp',
          },
        },
        {
          'id': 'application-$suffix',
          'displayName': 'Application',
          'networkId': 'network-a',
          'kind': 'RESOURCE_KIND_APPLICATION',
          'application': {'browserUrl': 'https://application.example/'},
        },
      ],
    });

api.ListExitNodesResponse _exitPage() =>
    api.ListExitNodesResponse()..mergeFromProto3Json({
      'page': {
        'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
      },
      'exitNodes': [
        {
          'id': 'candidate-a',
          'displayName': 'Candidate',
          'peerId': 'peer-a',
          'allowedFamilyModes': ['EXIT_FAMILY_MODE_IPV4_ONLY'],
          'allowedLanAccess': ['LAN_ACCESS_BLOCK'],
        },
      ],
    });
api.GetExitNodeResponse _exitStatus() =>
    api.GetExitNodeResponse()..mergeFromProto3Json({
      'status': {
        'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
        'profileId': 'profile-a',
        'requestedExitNodeId': 'old-selection',
        'requestedFamilyMode': 'EXIT_FAMILY_MODE_DUAL_STACK',
        'applyState': 'APPLY_STATE_FAILED',
        'failure': {'code': 'ERROR_CODE_UNSUPPORTED'},
        'ipv4': {
          'requestedExitNodeId': 'old-selection',
          'effectiveExitNodeId': 'old-selection',
          'applyState': 'APPLY_STATE_APPLIED',
          'failClosed': true,
        },
        'ipv6': {
          'requestedExitNodeId': 'old-selection',
          'applyState': 'APPLY_STATE_FAILED',
          'failure': {'code': 'ERROR_CODE_UNSUPPORTED'},
        },
      },
    });

void main() {
  for (final scenario in [
    'open',
    'changed',
    'unsafe',
    'invalidated',
    'cancelled',
    'disposed-refresh',
    'disposed-help',
    'disposed-link',
  ]) {
    testWidgets('US-13: support UI $scenario', (tester) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      addTearDown(() async {
        await state.detach();
        await events.close();
        state.dispose();
      });
      var reads = 0;
      var opens = 0;
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: SingleChildScrollView(
              child: ClientSupportPanel(
                state: state,
                load: () async {
                  reads++;
                  if (reads == 2 && scenario == 'invalidated') {
                    await pending.future;
                  }
                  return api.SupportInfo()..mergeFromProto3Json({
                    'runtime': {},
                    'productName': 'EndlessNet',
                    'offlineHelpKey': '../../not-a-path',
                    'supportUrl': reads == 2 && scenario == 'changed'
                        ? 'https://changed.example/'
                        : reads == 2 && scenario == 'unsafe'
                        ? 'https://user:secret@example.test/'
                        : 'https://support.example/',
                  });
                },
                openBrowser: (uri, check) async {
                  check();
                  opens++;
                  expect(uri.toString(), 'https://support.example/');
                  return scenario != 'cancelled';
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('client-offline-help')));
      await tester.pump();
      expect(find.textContaining('Built-in help:'), findsOneWidget);
      expect(reads, 0);
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'runtime-a',
              'callerAccess': 'ACCESS_OBSERVER',
            },
            'status': {
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            },
          },
        }),
      );
      await tester.pump();
      final refresh = find.byKey(const Key('client-load-support'));
      await tester.ensureVisible(refresh);
      await tester.tap(refresh);
      await tester.pump();
      expect(reads, 1);
      expect(opens, 0);
      expect(
        find.textContaining('runtime-requested offline topic is not bundled'),
        findsOneWidget,
      );
      expect(find.textContaining('../../not-a-path'), findsNothing);
      expect(
        find.byKey(const Key('client-support-documentation')),
        findsNothing,
      );
      final button = find.byKey(const Key('client-support-support'));
      if (scenario.startsWith('disposed-')) {
        final target = scenario == 'disposed-refresh'
            ? refresh
            : scenario == 'disposed-help'
            ? find.byKey(const Key('client-offline-help'))
            : button;
        final callback = tester.widget<ButtonStyleButton>(target).onPressed!;
        await tester.pumpWidget(const SizedBox());
        callback();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(reads, 1);
        expect(opens, 0);
        return;
      }
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      if (scenario == 'invalidated') {
        events.add(
          api.WatchEventsResponse()..mergeFromProto3Json({
            'sequence': '2',
            'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            'invalidated': {'domain': 'DOMAIN_SUPPORT'},
          }),
        );
        await tester.pump();
        pending.complete();
        await tester.pump();
      }
      expect(reads, 2);
      expect(opens, scenario == 'open' || scenario == 'cancelled' ? 1 : 0);
      if (scenario != 'open') expect(button, findsNothing);
      expect(find.textContaining('user:secret'), findsNothing);
      expect(find.textContaining('Built-in help:'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test(
    'US-13: support projection preserves identity and rejects unsafe destinations',
    () async {
      final build = api.BuildIdentity(version: 'dev');
      api.GetSupportInfoResponse response() =>
          api.GetSupportInfoResponse()..mergeFromProto3Json({
            'info': {
              'runtime': build.toProto3Json(),
              'productName': 'EndlessNet',
              'documentationUrl': 'https://docs.example/',
              'supportUrl': 'https://support.example/',
              'privacyUrl': 'https://privacy.example/',
              'licenseUrl': 'https://license.example/',
              'offlineHelpKey': 'opaque-help-key',
            },
          });
      Future<api.SupportInfo> read(api.GetSupportInfoResponse value) =>
          readClientSupportInfo(
            installedRuntime: build,
            get: (request) async {
              expect(request.isFrozen, isTrue);
              return value;
            },
            checkContext: () {},
          );
      final source = response();
      final info = await read(source);
      expect(info.isFrozen, isTrue);
      expect(info.offlineHelpKey, 'opaque-help-key');
      source.info.productName = 'Changed';
      expect(info.productName, 'EndlessNet');
      for (final set in <void Function(api.SupportInfo, String)>[
        (i, v) => i.documentationUrl = v,
        (i, v) => i.supportUrl = v,
        (i, v) => i.privacyUrl = v,
        (i, v) => i.licenseUrl = v,
      ]) {
        for (final url in [
          'http://example.test/',
          'https://user:secret@example.test/',
          'file:///tmp/help',
          ' https://example.test/',
          'https://example.test/\n',
        ]) {
          final bad = response();
          set(bad.info, url);
          await expectLater(read(bad), throwsFormatException);
        }
        final absent = response();
        set(absent.info, '');
        await read(absent);
      }
      await expectLater(
        read(response()..info.runtime.version = 'other'),
        throwsFormatException,
      );
      await expectLater(
        read(api.GetSupportInfoResponse()),
        throwsFormatException,
      );
    },
  );
  for (final scenario in [
    'source-unavailable',
    'expires-later',
    'expired',
    'invalidated',
    'observer',
    'disposed-callback',
  ]) {
    testWidgets('US-13: update panel $scenario', (tester) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      addTearDown(() async {
        await state.detach();
        await events.close();
        state.dispose();
      });
      var calls = 0;
      final pending = Completer<void>();
      final build = api.BuildIdentity(version: 'ui-dev');
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: SingleChildScrollView(
              child: ClientUpdatePanel(
                state: state,
                uiBuild: build,
                load: (ui) async {
                  calls++;
                  expect(ui, build);
                  if (scenario == 'invalidated') await pending.future;
                  final info = api.UpdateInfo()
                    ..mergeFromProto3Json({
                      'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
                      'reportedUi': ui.toProto3Json(),
                      'installedPair': {
                        'state': 'COMPATIBILITY_STATE_INCOMPATIBLE',
                      },
                      'state': 'UPDATE_STATE_SOURCE_UNAVAILABLE',
                    });
                  if (scenario == 'expires-later') {
                    info.state = api.UpdateState.UPDATE_STATE_AVAILABLE;
                    info.ensureAvailable().mergeFromProto3Json({
                      'releaseId': 'release-a',
                      'classification': 'UPDATE_CLASSIFICATION_MANDATORY',
                      'expiresAt': DateTime.now()
                          .toUtc()
                          .add(const Duration(seconds: 2))
                          .toIso8601String(),
                    });
                  }
                  if (scenario == 'expired') {
                    info.state = api.UpdateState.UPDATE_STATE_AVAILABLE;
                    info.ensureAvailable().ensureExpiresAt().seconds =
                        info.metadata.revision; // Already expired.
                  }
                  return info..freeze();
                },
              ),
            ),
          ),
        ),
      );
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'runtime-a',
              'callerAccess': scenario == 'observer'
                  ? 'ACCESS_OBSERVER'
                  : 'ACCESS_OWNER',
              'build': {'version': 'core-dev'},
            },
            'status': {
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            },
          },
        }),
      );
      await tester.pump();
      expect(calls, 0);
      expect(find.textContaining('UI build: ui-dev'), findsOneWidget);
      expect(find.textContaining('Runtime build: core-dev'), findsOneWidget);
      final button = find.byKey(const Key('client-check-updates'));
      if (scenario == 'disposed-callback') {
        final callback = tester.widget<OutlinedButton>(button).onPressed!;
        await tester.pumpWidget(const SizedBox());
        callback();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(calls, 0);
        return;
      }
      if (scenario == 'observer') {
        expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      } else {
        await tester.tap(button);
        await tester.pump();
        if (scenario == 'invalidated') {
          events.add(
            api.WatchEventsResponse()..mergeFromProto3Json({
              'sequence': '2',
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
              'invalidated': {'domain': 'DOMAIN_UPDATES'},
            }),
          );
          await tester.pump();
          pending.complete();
          await tester.pump();
          expect(find.textContaining('Update source:'), findsNothing);
        } else if (scenario == 'expires-later') {
          expect(
            find.textContaining('; Mandatory'),
            findsOneWidget,
          );
          expect(
            find.textContaining('This notice does not install or disconnect.'),
            findsOneWidget,
          );
          await tester.pump(const Duration(seconds: 3));
          expect(
            find.text('Update metadata expired. Check again.'),
            findsOneWidget,
          );
          expect(find.text('Update source: Available'), findsNothing);
          expect(calls, 1);
        } else if (scenario == 'expired') {
          expect(
            find.text('Update information could not be confirmed.'),
            findsOneWidget,
          );
          expect(find.text('Update source: Available'), findsNothing);
        } else {
          expect(
            find.text('Update source: Source unavailable'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Installed pair: Incompatible'),
            findsOneWidget,
          );
          expect(find.text('Update source: Up to date'), findsNothing);
        }
        expect(calls, 1);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  test(
    'US-13: update source states stay distinct and results are immutable',
    () async {
      final build = api.BuildIdentity(
        version: 'dev',
        platform: api.Platform.PLATFORM_WINDOWS,
        architecture: 'amd64',
      );
      for (final state in api.UpdateState.values.where(
        (s) =>
            s != api.UpdateState.UPDATE_STATE_UNSPECIFIED &&
            s != api.UpdateState.UPDATE_STATE_AVAILABLE,
      )) {
        final response = api.GetUpdateInfoResponse()
          ..mergeFromProto3Json({
            'info': {
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
              'installedRuntime': build.toProto3Json(),
              'reportedUi': build.toProto3Json(),
              'installedPair': {'state': 'COMPATIBILITY_STATE_UNKNOWN'},
              'state': state.name,
            },
          });
        var checks = 0;
        final result = await readClientUpdateInfo(
          instanceId: 'runtime-a',
          installedRuntime: build,
          reportedUi: build,
          get: (request) async {
            expect(request.isFrozen, isTrue);
            expect(request.reportedUi, build);
            return response;
          },
          checkContext: () {
            checks++;
          },
          now: () => DateTime.utc(2026, 9, 13),
        );
        expect(result.state, state);
        expect(result.isFrozen, isTrue);
        expect(checks, 2);
        response.info.state = api.UpdateState.UPDATE_STATE_UP_TO_DATE;
        expect(result.state, state);
      }
    },
  );
  test(
    'US-13: verified update rejects stale, mismatched and unsafe projections',
    () async {
      final build = api.BuildIdentity(
        version: 'dev',
        platform: api.Platform.PLATFORM_WINDOWS,
        architecture: 'amd64',
      );
      api.GetUpdateInfoResponse response() =>
          api.GetUpdateInfoResponse()..mergeFromProto3Json({
            'info': {
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
              'installedRuntime': build.toProto3Json(),
              'reportedUi': build.toProto3Json(),
              'installedPair': {'state': 'COMPATIBILITY_STATE_COMPATIBLE'},
              'state': 'UPDATE_STATE_AVAILABLE',
              'available': {
                'releaseId': 'release-a',
                'manifestSha256': 'a' * 64,
                'signingKeyId': 'key-a',
                'verifiedAt': '2026-09-12T00:00:00Z',
                'expiresAt': '2026-09-14T00:00:00Z',
                'runtime': build.toProto3Json(),
                'pairedUiVersion': 'dev',
                'compatibility': {
                  'state': 'COMPATIBILITY_STATE_COMPATIBLE',
                  'acceptedContractSha256': [api.ClientContract.sha256],
                },
                'classification': 'UPDATE_CLASSIFICATION_MANDATORY',
                'channel': 'DISTRIBUTION_CHANNEL_VENDOR_PACKAGE',
                'actionUrl': 'https://distribution.example/',
              },
            },
          });
      Future<api.UpdateInfo> read(
        api.GetUpdateInfoResponse value, {
        bool invalidate = false,
      }) {
        var checks = 0;
        return readClientUpdateInfo(
          instanceId: 'runtime-a',
          installedRuntime: build,
          reportedUi: build,
          get: (_) async => value,
          now: () => DateTime.utc(2026, 9, 13),
          checkContext: () {
            if (++checks == 2 && invalidate) {
              throw StateError('Changed context');
            }
          },
        );
      }

      final valid = await read(response());
      expect(
        valid.available.classification,
        api.UpdateClassification.UPDATE_CLASSIFICATION_MANDATORY,
      );
      expect(valid.isFrozen, isTrue);
      for (final mutate in <void Function(api.UpdateInfo)>[
        (i) => i.clearAvailable(),
        (i) => i.state = api.UpdateState.UPDATE_STATE_VERIFICATION_FAILED,
        (i) => i.metadata.instanceId = 'runtime-b',
        (i) => i.reportedUi.version = 'another-ui',
        (i) => i.installedRuntime.version = 'another-runtime',
        (i) => i.available.expiresAt = i.available.verifiedAt,
        (i) => i.available.verifiedAt = i.available.expiresAt,
        (i) => i.available.expiresAt.nanos = -1,
        (i) => i.available.runtime.platform = api.Platform.PLATFORM_LINUX,
        (i) => i.available.runtime.architecture = 'arm64',
        (i) => i.available.manifestSha256 = 'invalid',
        (i) => i.available.actionUrl = 'https://user:secret@example.test/',
        (i) => i.available.releaseNotesUrl = 'http://example.test/',
      ]) {
        final value = response();
        mutate(value.info);
        await expectLater(read(value), throwsFormatException);
      }
      await expectLater(read(response(), invalidate: true), throwsStateError);
    },
  );
  for (final scenario in ['select', 'clear', 'invalidated', 'locked']) {
    testWidgets('US-05: explicit exit UI $scenario', (tester) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      addTearDown(() async {
        await state.detach();
        await events.close();
        state.dispose();
      });
      var selections = 0;
      var clears = 0;
      ClientOperation pending(api.OperationKind kind) =>
          ClientOperation.fromProto(
            api.Operation(
              id: 'operation-a',
              kind: kind,
              state: api.OperationState.OPERATION_STATE_PENDING,
            ),
          );
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: SingleChildScrollView(
              child: ClientExitPanel(
                state: state,
                load: () async {
                  final page = _exitPage();
                  page.exitNodes.single.ensureSelection().availability =
                      api.Availability.AVAILABILITY_AVAILABLE;
                  final status = _exitStatus();
                  status.status.ensureControl().locked = scenario == 'locked';
                  status.status.control.ensureMutation().availability =
                      api.Availability.AVAILABILITY_AVAILABLE;
                  return readClientExitNodes(
                    instanceId: 'runtime-a',
                    profileId: 'profile-a',
                    list: (_) async => page,
                    get: (_) async => status,
                    checkContext: () {},
                  );
                },
                select: (profile, node, mode, lan, check) async {
                  check();
                  selections++;
                  expect(profile, 'profile-a');
                  expect(node, 'candidate-a');
                  expect(mode, api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV4_ONLY);
                  expect(lan, api.LanAccess.LAN_ACCESS_BLOCK);
                  return pending(
                    api.OperationKind.OPERATION_KIND_SELECT_EXIT_NODE,
                  );
                },
                clear: (profile, check) async {
                  check();
                  clears++;
                  expect(profile, 'profile-a');
                  return pending(
                    api.OperationKind.OPERATION_KIND_CLEAR_EXIT_NODE,
                  );
                },
              ),
            ),
          ),
        ),
      );
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'runtime-a',
              'callerAccess': 'ACCESS_OWNER',
              'capabilities': [
                {
                  'capability': 'CAPABILITY_EXIT_NODE',
                  'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                },
              ],
            },
            'status': {
              'activeProfileId': 'profile-a',
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            },
          },
        }),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('client-load-exits')));
      await tester.pump();
      expect(
        find.text('IPv4: requested old-selection; effective old-selection'),
        findsOneWidget,
      );
      expect(
        find.text('IPv6: requested old-selection; effective No exit'),
        findsOneWidget,
      );
      final selectFinder = find.byKey(const Key('client-select-exit'));
      expect(tester.widget<FilledButton>(selectFinder).onPressed, isNull);
      final node = tester.widget<DropdownButton<String>>(
        find.byKey(const Key('client-exit-node')),
      );
      if (scenario == 'locked') {
        expect(node.onChanged, isNull);
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('client-clear-exit')),
              )
              .onPressed,
          isNull,
        );
      } else if (scenario == 'clear') {
        final clear = find.byKey(const Key('client-clear-exit'));
        await tester.ensureVisible(clear);
        await tester.tap(clear);
        await tester.pump();
        expect(clears, 0);
        final cancel = find.byKey(const Key('client-cancel-clear-exit'));
        await tester.ensureVisible(cancel);
        await tester.tap(cancel);
        await tester.pump();
        expect(clears, 0);
        expect(
          find.byKey(const Key('client-confirm-clear-exit')),
          findsNothing,
        );
        await tester.ensureVisible(clear);
        await tester.tap(clear);
        await tester.pump();
        final confirm = find.byKey(const Key('client-confirm-clear-exit'));
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await tester.pump();
        expect(clears, 1);
      } else {
        node.onChanged!('candidate-a');
        await tester.pump();
        final mode = tester.widget<DropdownButton<api.ExitFamilyMode>>(
          find.byKey(const Key('client-exit-mode')),
        );
        expect(mode.value, isNull);
        expect(mode.items!.map((item) => item.value), [
          api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV4_ONLY,
        ]);
        mode.onChanged!(api.ExitFamilyMode.EXIT_FAMILY_MODE_DUAL_STACK);
        await tester.pump();
        expect(tester.widget<FilledButton>(selectFinder).onPressed, isNull);
        mode.onChanged!(api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV4_ONLY);
        await tester.pump();
        expect(tester.widget<FilledButton>(selectFinder).onPressed, isNull);
        final lan = tester.widget<DropdownButton<api.LanAccess>>(
          find.byKey(const Key('client-exit-lan')),
        );
        expect(lan.value, isNull);
        lan.onChanged!(api.LanAccess.LAN_ACCESS_BLOCK);
        await tester.pump();
        expect(
          find.text('IPv6 will not be protected by this exit selection.'),
          findsOneWidget,
        );
        final submit = tester.widget<FilledButton>(selectFinder).onPressed!;
        if (scenario == 'invalidated') {
          events.add(
            api.WatchEventsResponse()..mergeFromProto3Json({
              'sequence': '2',
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
              'invalidated': {
                'domain': 'DOMAIN_EXIT_NODE',
                'profileId': 'profile-a',
              },
            }),
          );
          await tester.idle();
          // Invoke the callback retained from the old frame before repaint.
          submit();
          node.onChanged!('candidate-a');
          await tester.pump();
          expect(selectFinder, findsNothing);
          expect(selections, 0);
        } else {
          await tester.ensureVisible(selectFinder);
          await tester.tap(selectFinder);
          await tester.pump();
          expect(selections, 1);
        }
      }
      if (scenario == 'select' || scenario == 'clear') {
        expect(
          find.text(
            'Exit operation received. Recover its result and refresh both address families.',
          ),
          findsOneWidget,
        );
        expect(selectFinder, findsNothing);
      }
      expect(selections, scenario == 'select' ? 1 : 0);
      expect(clears, scenario == 'clear' ? 1 : 0);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test(
    'US-05: exit aggregate cannot claim partial apply or missing protection',
    () async {
      for (final change in <void Function(api.ExitNodeStatus)>[
        (s) => s.applyState = api.ApplyState.APPLY_STATE_APPLIED,
        (s) => s.applyState = api.ApplyState.APPLY_STATE_PENDING,
        (s) => s.effectiveExitNodeId = s.requestedExitNodeId,
        (s) => s.failClosed = true,
        (s) => s.requestedFamilyMode = api.ExitFamilyMode.EXIT_FAMILY_MODE_NONE,
        (s) => s.clearRequestedExitNodeId(),
        (s) => s.ipv4.requestedExitNodeId = 'another-exit',
        (s) => s.ipv4.effectiveExitNodeId = 'another-exit',
        (s) => s.ipv4.clearEffectiveExitNodeId(),
      ]) {
        final response = _exitStatus();
        change(response.status);
        await expectLater(
          readClientExitNodes(
            instanceId: 'runtime-a',
            profileId: 'profile-a',
            list: (_) async => _exitPage(),
            get: (_) async => response,
            checkContext: () {},
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'US-05: complete, single-family, LAN-pending and partial-clear statuses stay distinct',
    () async {
      for (final mode in [
        'dual',
        'v4',
        'v6',
        'lan-pending',
        'clear-pending',
        'cleared',
      ]) {
        final response = _exitStatus();
        final s = response.status;
        s.clearFailure();
        s.ipv6.clearFailure();
        s.ipv6.effectiveExitNodeId = s.requestedExitNodeId;
        s.ipv6.applyState = api.ApplyState.APPLY_STATE_APPLIED;
        s.ipv6.failClosed = true;
        s.effectiveExitNodeId = s.requestedExitNodeId;
        s.applyState = api.ApplyState.APPLY_STATE_APPLIED;
        s.requestedLanAccess = api.LanAccess.LAN_ACCESS_BLOCK;
        s.effectiveLanAccess = api.LanAccess.LAN_ACCESS_BLOCK;
        s.failClosed = true;
        if (mode == 'v4') {
          s.requestedFamilyMode = api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV4_ONLY;
          s.ipv6.clearRequestedExitNodeId();
          s.ipv6.clearEffectiveExitNodeId();
          s.ipv6.failClosed = false;
        }
        if (mode == 'v6') {
          s.requestedFamilyMode = api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV6_ONLY;
          s.ipv4.clearRequestedExitNodeId();
          s.ipv4.clearEffectiveExitNodeId();
          s.ipv4.failClosed = false;
        }
        if (mode == 'lan-pending') {
          s.applyState = api.ApplyState.APPLY_STATE_PENDING;
          s.effectiveLanAccess = api.LanAccess.LAN_ACCESS_ALLOW;
        }
        if (mode == 'clear-pending' || mode == 'cleared') {
          s.requestedFamilyMode = api.ExitFamilyMode.EXIT_FAMILY_MODE_NONE;
          s.clearRequestedExitNodeId();
          s.clearEffectiveExitNodeId();
          s.failClosed = false;
          s.ipv4.clearRequestedExitNodeId();
          s.ipv4.clearEffectiveExitNodeId();
          s.ipv4.failClosed = false;
          s.ipv6.clearRequestedExitNodeId();
          if (mode == 'clear-pending') {
            s.applyState = api.ApplyState.APPLY_STATE_PENDING;
            s.ipv6.applyState = api.ApplyState.APPLY_STATE_PENDING;
          } else {
            s.ipv6.clearEffectiveExitNodeId();
            s.ipv6.failClosed = false;
          }
        }
        final result = await readClientExitNodes(
          instanceId: 'runtime-a',
          profileId: 'profile-a',
          list: (_) async => _exitPage(),
          get: (_) async => response,
          checkContext: () {},
        );
        expect(result.status.writeToBuffer(), response.status.writeToBuffer());
        if (mode == 'lan-pending') {
          response.status.applyState = api.ApplyState.APPLY_STATE_APPLIED;
          await expectLater(
            readClientExitNodes(
              instanceId: 'runtime-a',
              profileId: 'profile-a',
              list: (_) async => _exitPage(),
              get: (_) async => response,
              checkContext: () {},
            ),
            throwsFormatException,
          );
        }
      }
    },
  );
  test(
    'US-05: exit pagination rejects cycles, duplicates and mixed revisions',
    () async {
      for (final variant in ['valid', 'cycle', 'duplicate', 'revision']) {
        var calls = 0;
        final reading = readClientExitNodes(
          instanceId: 'runtime-a',
          profileId: 'profile-a',
          list: (request) async {
            expect(request.page.pageToken, calls == 0 ? '' : 'opaque');
            final response = _exitPage();
            if (calls++ == 0) {
              response.page.nextPageToken = 'opaque';
            } else {
              if (variant != 'duplicate') {
                response.exitNodes.single.id = 'candidate-b';
              }
              if (variant == 'cycle') response.page.nextPageToken = 'opaque';
              if (variant == 'revision') response.page.metadata.revision += 1;
            }
            return response;
          },
          get: (_) async => _exitStatus(),
          checkContext: () {},
        );
        if (variant == 'valid') {
          expect((await reading).nodes, hasLength(2));
        } else {
          await expectLater(reading, throwsFormatException);
        }
        expect(calls, 2);
      }
    },
  );
  test(
    'US-05: exit catalog preserves partial family apply and unavailable selection',
    () async {
      final status = _exitStatus();
      final result = await readClientExitNodes(
        instanceId: 'runtime-a',
        profileId: 'profile-a',
        list: (request) async {
          expect(request.profile.profileId, 'profile-a');
          expect(request.page.pageSize, 100);
          return _exitPage();
        },
        get: (request) async {
          expect(request.profile.profileId, 'profile-a');
          return status;
        },
        checkContext: () {},
      );
      expect(result.nodes.single.allowedFamilyModes, [
        api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV4_ONLY,
      ]);
      expect(
        result.status.requestedFamilyMode,
        api.ExitFamilyMode.EXIT_FAMILY_MODE_DUAL_STACK,
      );
      expect(result.status.hasEffectiveExitNodeId(), isFalse);
      expect(result.status.ipv4.effectiveExitNodeId, 'old-selection');
      expect(result.status.ipv6.hasEffectiveExitNodeId(), isFalse);
      expect(result.status.ipv6.applyState, api.ApplyState.APPLY_STATE_FAILED);
      expect(result.status.ipv6.failClosed, isFalse);
      expect(result.status.failClosed, isFalse);
      status.status.ipv4.effectiveExitNodeId = 'changed';
      expect(result.status.ipv4.effectiveExitNodeId, 'old-selection');
      expect(result.status.isFrozen, isTrue);
      expect(result.nodes.single.isFrozen, isTrue);
    },
  );
  test(
    'US-05: exit reads reject missing families, mixed revision and invalid catalog modes',
    () async {
      for (final change in <void Function(api.GetExitNodeResponse)>[
        (r) => r.clearStatus(),
        (r) => r.status.clearIpv4(),
        (r) => r.status.clearIpv6(),
        (r) => r.status.profileId = 'other-profile',
        (r) => r.status.metadata.revision += 1,
        (r) => r.status.requestedFamilyMode =
            api.ExitFamilyMode.EXIT_FAMILY_MODE_UNSPECIFIED,
        (r) => r.status.ipv6.clearFailure(),
        (r) => r.status.ipv4.requestedExitNodeId = '',
      ]) {
        final response = _exitStatus();
        change(response);
        await expectLater(
          readClientExitNodes(
            instanceId: 'runtime-a',
            profileId: 'profile-a',
            list: (_) async => _exitPage(),
            get: (_) async => response,
            checkContext: () {},
          ),
          throwsFormatException,
        );
      }
      for (final change in <void Function(api.ListExitNodesResponse)>[
        (r) => r.clearPage(),
        (r) => r.page.metadata.instanceId = 'other-runtime',
        (r) => r.exitNodes.single.allowedFamilyModes.add(
          api.ExitFamilyMode.EXIT_FAMILY_MODE_NONE,
        ),
        (r) => r.exitNodes.single.allowedLanAccess.add(
          api.LanAccess.LAN_ACCESS_UNSPECIFIED,
        ),
        (r) => r.exitNodes.add(
          api.ExitNode.fromBuffer(r.exitNodes.single.writeToBuffer()),
        ),
      ]) {
        final response = _exitPage();
        change(response);
        await expectLater(
          readClientExitNodes(
            instanceId: 'runtime-a',
            profileId: 'profile-a',
            list: (_) async => response,
            get: (_) => throw TestFailure('Invalid catalog must stop'),
            checkContext: () {},
          ),
          throwsFormatException,
        );
      }
    },
  );
  for (final scenario in [
    'valid',
    'changed',
    'denied',
    'invalidated',
    'network-changed',
    'http',
    'credentials',
  ]) {
    testWidgets('US-11: application browser action $scenario', (tester) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      addTearDown(() async {
        await state.detach();
        await events.close();
        state.dispose();
      });
      var reads = 0;
      var opens = 0;
      final pending = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: SingleChildScrollView(
              child: ClientResourcesPanel(
                state: state,
                setEnabled: (_, _, _, _) =>
                    throw TestFailure('Opening is not a mutation'),
                openBrowser: (uri, check) async {
                  check();
                  opens++;
                  expect(uri.toString(), 'https://application.example/');
                  return true;
                },
                load: (search, kinds) async {
                  reads++;
                  if ((scenario == 'invalidated' ||
                          scenario == 'network-changed') &&
                      reads == 2) {
                    await pending.future;
                  }
                  final response = _resourcePage('a');
                  response.resources.removeWhere(
                    (r) => r.kind != api.ResourceKind.RESOURCE_KIND_APPLICATION,
                  );
                  final resource = response.resources.single;
                  resource.ensureAvailability().availability =
                      api.Availability.AVAILABILITY_AVAILABLE;
                  if (scenario == 'http') {
                    resource.application.browserUrl =
                        'http://application.example/';
                  }
                  if (scenario == 'credentials') {
                    resource.application.browserUrl =
                        'https://user:secret@application.example/';
                  }
                  if (scenario == 'changed' && reads == 2) {
                    resource.application.browserUrl =
                        'https://changed.example/';
                  }
                  if (scenario == 'denied' && reads == 2) {
                    resource.availability.availability =
                        api.Availability.AVAILABILITY_UNSPECIFIED;
                  }
                  return readClientResources(
                    (_) async => response,
                    instanceId: 'runtime-a',
                    profileId: 'profile-a',
                    search: search,
                    kinds: kinds,
                    checkContext: () {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'runtime-a',
              'callerAccess': 'ACCESS_OWNER',
              'capabilities': [
                {
                  'capability': 'CAPABILITY_RESOURCES',
                  'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                },
              ],
            },
            'status': {
              'activeProfileId': 'profile-a',
              'network': {'id': 'network-a'},
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            },
          },
        }),
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('client-load-resources')),
      );
      await tester.tap(find.byKey(const Key('client-load-resources')));
      await tester.pump();
      expect(opens, 0);
      expect(reads, 1);
      final button = find.byKey(const Key('open-resource-application-a'));
      if (scenario == 'http' || scenario == 'credentials') {
        expect(button, findsNothing);
      } else {
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        if (scenario == 'network-changed') {
          final status =
              api.Status.fromBuffer(state.snapshot!.status.writeToBuffer())
                ..network = api.Network(id: 'network-b')
                ..metadata.revision += 1;
          events.add(
            api.WatchEventsResponse()
              ..mergeFromProto3Json({'sequence': '2'})
              ..metadata = status.metadata
              ..statusChanged = status,
          );
          await tester.pump();
          expect(state.snapshot!.status.network.id, 'network-b');
          expect(button, findsNothing);
          pending.complete();
          await tester.pump();
        } else if (scenario == 'invalidated') {
          events.add(
            api.WatchEventsResponse()..mergeFromProto3Json({
              'sequence': '2',
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
              'invalidated': {
                'domain': 'DOMAIN_RESOURCES',
                'profileId': 'profile-a',
              },
            }),
          );
          await tester.pump();
          pending.complete();
          await tester.pump();
        }
        expect(reads, 2);
        expect(opens, scenario == 'valid' ? 1 : 0);
        if (scenario != 'valid') expect(button, findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  for (final lateRead in [false, true]) {
    testWidgets(
      'US-11: resource UI ${lateRead ? 'rejects late queries and stale callbacks' : 'submits an explicit disable and respects policy locks'}',
      (tester) async {
        final state = ClientStateController();
        final events = StreamController<api.WatchEventsResponse>();
        await state.attach(events.stream);
        addTearDown(() async {
          await state.detach();
          await events.close();
          state.dispose();
        });
        var reads = 0;
        var writes = 0;
        final pending = Completer<void>();
        await tester.pumpWidget(
          MaterialApp(
            home: ContractTestScaffold(
              body: SingleChildScrollView(
                child: ClientResourcesPanel(
                  state: state,
                  load: (search, kinds) async {
                    reads++;
                    if (lateRead && reads == 1) await pending.future;
                    return readClientResources(
                      (_) async {
                        final response = _resourcePage('a');
                        for (final resource in response.resources) {
                          resource.ensureAvailability().availability =
                              api.Availability.AVAILABILITY_AVAILABLE;
                          resource
                                  .ensureEnabled()
                                  .ensureControl()
                                  .ensureMutation()
                                  .availability =
                              api.Availability.AVAILABILITY_AVAILABLE;
                          resource.enabled.control.locked =
                              resource.kind ==
                              api.ResourceKind.RESOURCE_KIND_SERVICE;
                        }
                        response.resources.first.enabled.requested = true;
                        response.resources.first.enabled.effective = false;
                        return response;
                      },
                      instanceId: 'runtime-a',
                      profileId: 'profile-a',
                      search: search,
                      kinds: kinds,
                      checkContext: () {},
                    );
                  },
                  setEnabled: (profile, resource, enabled, check) async {
                    check();
                    writes++;
                    expect(profile, 'profile-a');
                    expect(resource, 'host-a');
                    expect(enabled, isFalse);
                    return ClientOperation.fromProto(
                      api.Operation(
                        id: 'resource-op',
                        requestId: 'resource-request',
                        kind: api
                            .OperationKind
                            .OPERATION_KIND_SET_RESOURCE_ENABLED,
                        state: api.OperationState.OPERATION_STATE_PENDING,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        events.add(
          api.WatchEventsResponse()..mergeFromProto3Json({
            'sequence': '1',
            'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            'snapshot': {
              'runtime': {
                'protocol': api.ClientContract.protocol,
                'contractSha256': api.ClientContract.sha256,
                'instanceId': 'runtime-a',
                'callerAccess': 'ACCESS_OWNER',
                'capabilities': [
                  {
                    'capability': 'CAPABILITY_RESOURCES',
                    'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                  },
                ],
              },
              'status': {
                'activeProfileId': 'profile-a',
                'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
              },
            },
          }),
        );
        await tester.pump();
        expect(reads, 0);
        expect(writes, 0);
        await tester.enterText(
          find.byKey(const Key('client-resource-search')),
          'first',
        );
        await tester.ensureVisible(
          find.byKey(const Key('client-load-resources')),
        );
        await tester.tap(find.byKey(const Key('client-load-resources')));
        await tester.pump();
        if (lateRead) {
          await tester.enterText(
            find.byKey(const Key('client-resource-search')),
            'second',
          );
          pending.complete();
          await tester.pump();
          expect(find.text('Host a'), findsNothing);
          await tester.tap(find.byKey(const Key('client-load-resources')));
          await tester.pump();
        }
        expect(find.text('Host a'), findsOneWidget);
        expect(find.text('Effective: No; requested: Yes'), findsOneWidget);
        expect(
          tester
              .widget<TextButton>(
                find.byKey(const Key('resource-service-a-true')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<TextButton>(find.byKey(const Key('resource-host-a-true')))
              .onPressed,
          isNull,
        );
        expect(writes, 0);
        final stale = tester
            .widget<TextButton>(find.byKey(const Key('resource-host-a-false')))
            .onPressed!;
        if (lateRead) {
          events.add(
            api.WatchEventsResponse()..mergeFromProto3Json({
              'sequence': '2',
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
              'invalidated': {
                'domain': 'DOMAIN_RESOURCES',
                'profileId': 'profile-a',
              },
            }),
          );
          await tester.pump();
          stale();
          await tester.pump();
          expect(writes, 0);
          expect(find.text('Host a'), findsNothing);
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const Key('client-resource-search')),
                )
                .controller!
                .text,
            isEmpty,
          );
        } else {
          await tester.ensureVisible(
            find.byKey(const Key('resource-host-a-false')),
          );
          await tester.tap(find.byKey(const Key('resource-host-a-false')));
          await tester.pump();
          expect(writes, 1);
          expect(find.text('Host a'), findsNothing);
          expect(
            find.text(
              'Resource operation received. Recover its result and refresh effective values.',
            ),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test(
    'US-11: resource pagination preserves typed targets and a fixed query',
    () async {
      final kinds = api.ResourceKind.values
          .where((k) => k != api.ResourceKind.RESOURCE_KIND_UNSPECIFIED)
          .toList();
      var calls = 0;
      final source = <api.Resource>[];
      final catalog = await readClientResources(
        (request) async {
          expect(request.isFrozen, isTrue);
          expect(request.profile.profileId, 'profile-a');
          expect(request.search, 'Мой ресурс');
          expect(request.kinds, hasLength(4));
          expect(request.page.pageSize, 100);
          expect(request.page.pageToken, calls == 0 ? '' : 'opaque');
          kinds.clear(); // The caller cannot change filters between pages.
          final response = _resourcePage(
            calls == 0 ? 'a' : 'b',
            next: calls++ == 0 ? 'opaque' : '',
          );
          source.addAll(response.resources);
          return response;
        },
        instanceId: 'runtime-a',
        profileId: 'profile-a',
        search: 'Мой ресурс',
        kinds: kinds,
        checkContext: () {},
      );
      expect(calls, 2);
      expect(catalog.resources, hasLength(8));
      expect(catalog.kinds, hasLength(4));
      source.first.displayName = 'changed';
      expect(catalog.resources.first.displayName, 'Host a');
      expect(catalog.resources.first.enabled.hasRequested(), isTrue);
      expect(catalog.resources.first.enabled.requested, isFalse);
      expect(catalog.resources.first.overlappingResourceIds, [
        'visible-outside-query',
      ]);
      expect(catalog.resources.every((r) => r.isFrozen), isTrue);
      expect(() => catalog.resources.clear(), throwsUnsupportedError);
    },
  );
  test(
    'US-11: invalid resources or mixed pages never publish a partial catalog',
    () async {
      for (final change in <void Function(api.ListResourcesResponse)>[
        (r) => r.clearPage(),
        (r) => r.page.clearMetadata(),
        (r) => r.page.metadata.instanceId = 'other-runtime',
        (r) => r.page.metadata.revision += 1,
        (r) => r.page.nextPageToken = 'opaque',
        (r) => r.resources.first.id = 'host-a',
        (r) => r.resources.first.displayName = '',
        (r) => r.resources.first.id = 'x' * 257,
        (r) => r.resources.first.networkId = '',
        (r) => r.resources.first.clearHost(),
        (r) => r.resources.first.kind = api.ResourceKind.RESOURCE_KIND_SERVICE,
        (r) => r.resources.first.overlappingResourceIds.add(''),
        (r) {
          while (r.resources.length <= 100) {
            r.resources.add(
              api.Resource.fromBuffer(r.resources.first.writeToBuffer()),
            );
          }
        },
      ]) {
        var calls = 0;
        await expectLater(
          readClientResources(
            (_) async {
              if (calls++ == 0) return _resourcePage('a', next: 'opaque');
              final invalid = _resourcePage('b');
              change(invalid);
              return invalid;
            },
            instanceId: 'runtime-a',
            profileId: 'profile-a',
            checkContext: () {},
          ),
          throwsFormatException,
        );
        expect(calls, 2);
      }
      await expectLater(
        readClientResources(
          (_) async => _resourcePage('a'),
          instanceId: 'runtime-a',
          profileId: 'profile-a',
          kinds: [api.ResourceKind.RESOURCE_KIND_HOST],
          checkContext: () {},
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'US-11: query bounds and invalidation stop without RPC retries',
    () async {
      for (final query in [
        (search: 'я' * 129, kinds: <api.ResourceKind>[]),
        (search: '', kinds: [api.ResourceKind.RESOURCE_KIND_UNSPECIFIED]),
        (
          search: '',
          kinds: [
            api.ResourceKind.RESOURCE_KIND_HOST,
            api.ResourceKind.RESOURCE_KIND_HOST,
          ],
        ),
      ]) {
        await expectLater(
          readClientResources(
            (_) => throw TestFailure('Invalid query must not call RPC'),
            instanceId: 'runtime-a',
            profileId: 'profile-a',
            search: query.search,
            kinds: query.kinds,
            checkContext: () {},
          ),
          throwsFormatException,
        );
      }
      var calls = 0;
      var checks = 0;
      await expectLater(
        readClientResources(
          (_) async {
            calls++;
            return _resourcePage('a', next: 'opaque');
          },
          instanceId: 'runtime-a',
          profileId: 'profile-a',
          checkContext: () {
            if (++checks == 2) throw StateError('Invalidated');
          },
        ),
        throwsStateError,
      );
      expect(calls, 1);
    },
  );
  testWidgets(
    'US-04: network selection uses fresh profile-bound IDs without optimistic state',
    (tester) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      final calls = <(String, String)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: SingleChildScrollView(
              child: ClientNetworksPanel(
                state: state,
                load: () => readClientNetworks(
                  (_) async => api.ListNetworksResponse()
                    ..mergeFromProto3Json({
                      'networks': [
                        {'id': 'network-a', 'name': 'A'},
                        {
                          'id': 'network-b',
                          'name': 'B',
                          'selection': {
                            'availability': 'AVAILABILITY_AVAILABLE',
                          },
                        },
                        {'id': 'network-c', 'name': 'C'},
                      ],
                      'selectedNetworkId': 'network-a',
                      'page': {
                        'metadata': {
                          'instanceId': 'runtime-a',
                          'revision': '7',
                        },
                      },
                    }),
                  instanceId: 'runtime-a',
                  profileId: 'profile-a',
                ),
                select: (profile, network) async {
                  calls.add((profile, network));
                  return ClientOperation.fromProto(
                    api.Operation(
                      id: 'network-selection',
                      kind: api.OperationKind.OPERATION_KIND_SELECT_NETWORK,
                      state: api.OperationState.OPERATION_STATE_PENDING,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      final snapshot = api.WatchEventsResponse()
        ..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'runtime-a',
              'callerAccess': 'ACCESS_OWNER',
            },
            'status': {
              'activeProfileId': 'profile-a',
              'network': {'id': 'network-a'},
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            },
          },
        });
      events.add(snapshot);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('client-load-networks')));
      await tester.tap(find.byKey(const Key('client-load-networks')));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const Key('select-network-network-c')),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const Key('select-network-network-b')),
      );
      await tester.tap(find.byKey(const Key('select-network-network-b')));
      await tester.pump();
      expect(calls, [('profile-a', 'network-b')]);
      expect(state.snapshot!.status.network.id, 'network-a');
      await tester.ensureVisible(find.byKey(const Key('client-load-networks')));
      await tester.tap(find.byKey(const Key('client-load-networks')));
      await tester.pump();
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '2',
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
          'invalidated': {
            'domain': 'DOMAIN_NETWORKS',
            'profileId': 'profile-a',
          },
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('select-network-network-b')), findsNothing);
      snapshot.sequence += 2;
      snapshot.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      snapshot.snapshot.status.clearActiveProfileId();
      snapshot.snapshot.status.clearNetwork();
      events.add(snapshot);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('client-load-networks')),
            )
            .onPressed,
        isNull,
      );
      await events.close();
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  for (final fault in [
    '',
    'revision',
    'selection',
    'duplicate',
    'token',
    'instance',
  ]) {
    test(
      'US-04: profile-bound network pagination ${fault.isEmpty ? 'succeeds immutably' : 'rejects $fault'}',
      () async {
        final requests = <api.ListNetworksRequest>[];
        final pages = [
          api.ListNetworksResponse()..mergeFromProto3Json({
            'networks': [
              {'id': 'network-a', 'name': 'A'},
            ],
            'selectedNetworkId': 'network-a',
            'page': {
              'nextPageToken': 'opaque-next',
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            },
          }),
          api.ListNetworksResponse()..mergeFromProto3Json({
            'networks': [
              {
                'id': fault == 'duplicate' ? 'network-a' : 'network-b',
                'name': 'B',
              },
            ],
            'selectedNetworkId': fault == 'selection'
                ? 'network-b'
                : 'network-a',
            'page': {
              'nextPageToken': fault == 'token' ? 'opaque-next' : '',
              'metadata': {
                'instanceId': fault == 'instance' ? 'other' : 'runtime-a',
                'revision': fault == 'revision' ? '8' : '7',
              },
            },
          }),
        ];
        final query = readClientNetworks(
          (request) async {
            requests.add(request);
            return pages[requests.length - 1];
          },
          instanceId: 'runtime-a',
          profileId: 'profile-a',
        );
        if (fault.isNotEmpty) {
          await expectLater(query, throwsFormatException);
        } else {
          final catalog = await query;
          expect(catalog.profileId, 'profile-a');
          expect(catalog.networks.map((n) => n.id), ['network-a', 'network-b']);
          expect(catalog.selectedNetworkId, 'network-a');
          pages.first.networks.first.name = 'changed';
          expect(catalog.networks.first.name, 'A');
          expect(() => catalog.networks.clear(), throwsUnsupportedError);
          expect(
            () => catalog.networks.first.name = 'mutate',
            throwsUnsupportedError,
          );
        }
        expect(requests.map((r) => r.profile.profileId), [
          'profile-a',
          'profile-a',
        ]);
        expect(requests.map((r) => r.page.pageToken), ['', 'opaque-next']);
      },
    );
  }
  testWidgets(
    'US-08: initial profile claim validates input and clears late result',
    (tester) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      final result = Completer<ClientOperation>();
      final calls = <(String, String)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: ClientCreateProfilePanel(
              state: state,
              create: (name, origin) {
                calls.add((name, origin));
                return result.future;
              },
            ),
          ),
        ),
      );
      final submit = find.byKey(const Key('create-profile-submit'));
      expect(tester.widget<OutlinedButton>(submit).onPressed, isNull);
      final snapshot = api.WatchEventsResponse()
        ..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'runtime-a',
              'callerAccess': 'ACCESS_OBSERVER',
            },
            'status': {
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            },
          },
        });
      events.add(snapshot);
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('create-profile-name')),
        ' New profile ',
      );
      for (final origin in [
        'http://example.test',
        'https://user@example.test',
        'https://example.test/api',
        'https://example.test?q=1',
        'https://example.test#x',
      ]) {
        await tester.enterText(
          find.byKey(const Key('create-profile-origin')),
          origin,
        );
        await tester.pump();
        expect(tester.widget<OutlinedButton>(submit).onPressed, isNull);
      }
      await tester.enterText(
        find.byKey(const Key('create-profile-origin')),
        'https://example.test',
      );
      // Complete editable-text focus/scroll animations before native hit
      // testing. Keep the real tap: never bypass it by invoking onPressed.
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(submit).onPressed, isNotNull);
      expect(submit.hitTestable(), findsOneWidget);
      await tester.tap(submit);
      await tester.pump();
      expect(calls, [('New profile', 'https://example.test')]);
      expect(tester.widget<OutlinedButton>(submit).onPressed, isNull);
      snapshot.sequence += 1;
      snapshot.snapshot.runtime.callerAccess = api.Access.ACCESS_OWNER;
      events.add(snapshot);
      await tester.pump();
      result.complete(
        ClientOperation.fromProto(
          api.Operation(
            id: 'create',
            kind: api.OperationKind.OPERATION_KIND_CREATE_PROFILE,
            state: api.OperationState.OPERATION_STATE_PENDING,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text(
          'Creation accepted. Recover the operation to see its result.',
        ),
        findsNothing,
      );
      expect(find.text('New profile'), findsNothing);
      await events.close();
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'US-08: profile mutations use IDs and require fresh catalog and confirmation',
    (tester) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      final selected = <String>[];
      final renamed = <(String, String)>[];
      final removed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: SingleChildScrollView(
              child: ClientProfilesPanel(
                state: state,
                remove: (id) async {
                  removed.add(id);
                  return ClientOperation.fromProto(
                    api.Operation(
                      id: 'removal',
                      kind: api.OperationKind.OPERATION_KIND_REMOVE_PROFILE,
                      state: api.OperationState.OPERATION_STATE_PENDING,
                    ),
                  );
                },
                rename: (id, name) async {
                  renamed.add((id, name));
                  return ClientOperation.fromProto(
                    api.Operation(
                      id: 'rename',
                      kind: api.OperationKind.OPERATION_KIND_RENAME_PROFILE,
                      state: api.OperationState.OPERATION_STATE_PENDING,
                    ),
                  );
                },
                load: () => readClientProfiles((_) async {
                  final response = page('a');
                  response.profiles.add(
                    api.Profile(
                      id: 'b',
                      displayName: 'Profile b',
                      state: api.ProfileState.PROFILE_STATE_EMPTY,
                      selection: api.Restriction(
                        availability: api.Availability.AVAILABILITY_AVAILABLE,
                      ),
                    ),
                  );
                  return response;
                }, instanceId: 'runtime-a'),
                select: (id) async {
                  selected.add(id);
                  return ClientOperation.fromProto(
                    api.Operation(
                      id: 'selection',
                      kind: api.OperationKind.OPERATION_KIND_SELECT_PROFILE,
                      state: api.OperationState.OPERATION_STATE_PENDING,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      final snapshot = api.WatchEventsResponse()
        ..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'runtime-a',
              'callerAccess': 'ACCESS_OWNER',
            },
            'status': {
              'activeProfileId': 'a',
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            },
          },
        });
      events.add(snapshot);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('client-load-profiles')));
      await tester.tap(find.byKey(const Key('client-load-profiles')));
      await tester.pump();
      expect(find.text('Profile b'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('remove-profile-a')))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byKey(const Key('remove-profile-b')));
      await tester.tap(find.byKey(const Key('remove-profile-b')));
      await tester.pump();
      expect(removed, isEmpty);
      await tester.ensureVisible(
        find.byKey(const Key('cancel-profile-removal')),
      );
      await tester.tap(find.byKey(const Key('cancel-profile-removal')));
      await tester.pump();
      expect(removed, isEmpty);
      await tester.ensureVisible(find.byKey(const Key('remove-profile-b')));
      await tester.tap(find.byKey(const Key('remove-profile-b')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('confirm-profile-removal')),
      );
      await tester.tap(find.byKey(const Key('confirm-profile-removal')));
      await tester.pump();
      expect(removed, ['b']);
      expect(find.text('Profile b'), findsNothing);
      expect(state.snapshot!.status.activeProfileId, 'a');
      await tester.ensureVisible(find.byKey(const Key('client-load-profiles')));
      await tester.tap(find.byKey(const Key('client-load-profiles')));
      await tester.pump();
      final renameButton = find.byKey(const Key('rename-profile-b'));
      expect(tester.widget<TextButton>(renameButton).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('client-profile-name')),
        'bad\u007fname',
      );
      await tester.pump();
      expect(tester.widget<TextButton>(renameButton).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('client-profile-name')),
        'я' * 65,
      );
      await tester.pump();
      expect(tester.widget<TextButton>(renameButton).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('client-profile-name')),
        'Новое имя',
      );
      await tester.pump();
      await tester.ensureVisible(renameButton);
      await tester.tap(renameButton);
      await tester.pump();
      expect(renamed, [('b', 'Новое имя')]);
      expect(find.text('Новое имя'), findsNothing);
      expect(find.text('Profile b'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('client-load-profiles')));
      await tester.tap(find.byKey(const Key('client-load-profiles')));
      await tester.pump();
      for (var repeat = 0; repeat < 2; repeat++) {
        await tester.ensureVisible(find.byKey(const Key('remove-profile-b')));
        await tester.tap(find.byKey(const Key('remove-profile-b')));
        await tester.pump();
        expect(
          find.byKey(const Key('confirm-profile-removal')),
          findsOneWidget,
        );
        snapshot.sequence += 1;
        events.add(
          api.WatchEventsResponse()..mergeFromProto3Json({
            'sequence': snapshot.sequence.toString(),
            'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            'invalidated': {'domain': 'DOMAIN_PROFILES'},
          }),
        );
        await tester.pump();
        expect(find.text('Profile b'), findsNothing);
        expect(find.byKey(const Key('confirm-profile-removal')), findsNothing);
        expect(removed, ['b']);
        expect(find.byKey(const Key('select-profile-b')), findsNothing);
        await tester.ensureVisible(
          find.byKey(const Key('client-load-profiles')),
        );
        await tester.tap(find.byKey(const Key('client-load-profiles')));
        await tester.pump();
        expect(find.text('Profile b'), findsOneWidget);
      }
      await tester.ensureVisible(find.byKey(const Key('select-profile-b')));
      await tester.tap(find.byKey(const Key('select-profile-b')));
      await tester.pump();
      expect(selected, ['b']);
      expect(state.snapshot!.status.activeProfileId, 'a');
      expect(find.text('Profile b'), findsNothing);
      snapshot.sequence += 1;
      snapshot.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      snapshot.snapshot.status.clearActiveProfileId();
      events.add(snapshot);
      await tester.pump();
      expect(
        find.text(
          'Selection accepted. Recover the operation to see its result.',
        ),
        findsNothing,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('client-load-profiles')),
            )
            .onPressed,
        isNull,
      );
      await events.close();
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  test(
    'US-08: complete catalog preserves opaque page tokens and freezes entries',
    () async {
      final requests = <String>[];
      final first = page('a', next: 'opaque-token');
      final catalog = await readClientProfiles((request) async {
        requests.add(request.page.pageToken);
        expect(request.page.pageSize, 100);
        return requests.length == 1 ? first : page('b');
      }, instanceId: 'runtime-a');
      expect(requests, ['', 'opaque-token']);
      first.profiles.first.displayName = 'changed';
      expect(catalog.profiles.first.displayName, 'Profile a');
      expect(catalog.activeProfileId, 'a');
      expect(() => catalog.profiles.clear(), throwsUnsupportedError);
      expect(() => catalog.profiles.first.clearId(), throwsUnsupportedError);
    },
  );
  for (final fault in [
    'revision',
    'duplicate',
    'token-loop',
    'active',
    'instance',
  ]) {
    test(
      'US-08: $fault rejects the catalog without partial publication',
      () async {
        var calls = 0;
        await expectLater(
          readClientProfiles((request) async {
            calls++;
            if (calls == 1) return page('a', next: 'token');
            final response = page(fault == 'duplicate' ? 'a' : 'b');
            if (fault == 'revision') response.page.metadata.revision += 1;
            if (fault == 'token-loop') response.page.nextPageToken = 'token';
            if (fault == 'active') response.activeProfileId = 'b';
            if (fault == 'instance') {
              response.page.metadata.instanceId = 'runtime-b';
            }
            return response;
          }, instanceId: 'runtime-a'),
          throwsFormatException,
        );
        expect(calls, 2);
      },
    );
  }
}
