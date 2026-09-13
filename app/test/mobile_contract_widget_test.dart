import 'dart:async';

import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet/client_connection_panel.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_operation_details.dart';
import 'package:endlessnet/client_enrollment_panel.dart';
import 'package:endlessnet/client_cleanup_panel.dart';
import 'package:endlessnet/client_recovery_panel.dart';
import 'package:endlessnet/client_identity_panel.dart';
import 'package:endlessnet/client_diagnostics_panel.dart';
import 'package:endlessnet/client_bundle_chunks.dart';
import 'package:endlessnet/client_preferences.dart';
import 'package:endlessnet/client_preferences_panel.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/contract_test_scaffold.dart';

/// Reused by the native integration-test host; no desktop channel is imported.
Future<ClientPreferences> _preferenceEditorProjection({required bool locked}) =>
    readClientPreferences(
      instanceId: 'preferences-test',
      profileId: 'profile-a',
      checkContext: () {},
      get: (_) async => api.GetPreferencesResponse()
        ..mergeFromProto3Json({
          'preferences': {
            'metadata': {'instanceId': 'preferences-test', 'revision': '7'},
            'profileId': 'profile-a',
            for (final key in ['allowInbound', 'acceptDns', 'acceptRoutes'])
              key: {
                'effective': true,
                if (key != 'acceptRoutes') 'requested': key == 'acceptDns',
                'control': {
                  'source': 'SETTING_SOURCE_USER',
                  'mutation': {'availability': 'AVAILABILITY_AVAILABLE'},
                },
              },
            'lifecycle': {
              for (final key in [
                'runtimeStart',
                'uiQuit',
                'userLogoff',
                'suspend',
                'resume',
              ])
                key: {
                  'effective': 'LIFECYCLE_BEHAVIOR_KEEP_INTENT',
                  'allowedValues': ['LIFECYCLE_BEHAVIOR_DISCONNECT'],
                  'control': {
                    'source': 'SETTING_SOURCE_DEFAULT',
                    'mutation': {'availability': 'AVAILABILITY_AVAILABLE'},
                  },
                },
            },
          },
        }),
      listManaged: (_) async =>
          api.ListManagedSettingsResponse()..mergeFromProto3Json({
            'metadata': {'instanceId': 'preferences-test', 'revision': '7'},
            'settings': [
              {
                'key': 'PREFERENCE_KEY_ACCEPT_DNS',
                'booleanValue': true,
                'control': {
                  'locked': locked,
                  'source': 'SETTING_SOURCE_ACCOUNT_POLICY',
                  'mutation': {'availability': 'AVAILABILITY_AVAILABLE'},
                },
              },
            ],
          }),
    );

void main() {
  for (final locked in [false, true]) {
    testWidgets(
      'US-10: preference editor ${locked ? 'denies policy and clears invalidated drafts' : 'sends one explicit eight-field patch and a separate reset'}',
      (tester) async {
        final state = ClientStateController();
        final events = StreamController<api.WatchEventsResponse>();
        await state.attach(events.stream);
        addTearDown(() async {
          await state.detach();
          await events.close();
          state.dispose();
        });
        api.PreferencesPatch? sent;
        List<api.PreferenceKey>? reset;
        var reads = 0;
        final projection = await _preferenceEditorProjection(locked: locked);
        ClientOperation pending(api.OperationKind kind) =>
            ClientOperation.fromProto(
              api.Operation(
                id: 'preference-op',
                requestId: 'preference-request',
                kind: kind,
                state: api.OperationState.OPERATION_STATE_PENDING,
              ),
            );
        await tester.pumpWidget(
          MaterialApp(
            home: ContractTestScaffold(
              body: SingleChildScrollView(
                child: ClientPreferencesPanel(
                  state: state,
                  load: () async {
                    reads++;
                    return projection;
                  },
                  apply: (profile, patch, check) async {
                    check();
                    expect(profile, 'profile-a');
                    expect(patch.isFrozen, isTrue);
                    sent = patch;
                    return pending(
                      api.OperationKind.OPERATION_KIND_SET_PREFERENCES,
                    );
                  },
                  reset: (profile, keys, check) async {
                    check();
                    expect(profile, 'profile-a');
                    reset = keys;
                    return pending(
                      api.OperationKind.OPERATION_KIND_RESET_PREFERENCES,
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
            'metadata': {'instanceId': 'preferences-test', 'revision': '7'},
            'snapshot': {
              'runtime': {
                'protocol': api.ClientContract.protocol,
                'contractSha256': api.ClientContract.sha256,
                'instanceId': 'preferences-test',
                'callerAccess': 'ACCESS_OWNER',
                'capabilities': [
                  for (final capability in [
                    'CAPABILITY_PREFERENCES',
                    'CAPABILITY_MANAGED_SETTINGS',
                  ])
                    {
                      'capability': capability,
                      'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                    },
                ],
              },
              'status': {
                'activeProfileId': 'profile-a',
                'metadata': {'instanceId': 'preferences-test', 'revision': '7'},
              },
            },
          }),
        );
        await tester.pump();
        expect(reads, 0);
        await tester.tap(find.byKey(const Key('client-load-preferences')));
        await tester.pump();
        expect(reads, 1);
        expect(sent, isNull);
        expect(reset, isNull);
        expect(find.text('Effective: true; requested: false'), findsOneWidget);
        final dns = tester.widget<DropdownButton<Object>>(
          find.byKey(const Key('preference-2')),
        );
        if (locked) {
          final staleEdit = tester
              .widget<DropdownButton<Object>>(
                find.byKey(const Key('preference-1')),
              )
              .onChanged!;
          expect(dns.onChanged, isNull);
          expect(
            tester
                .widget<TextButton>(find.byKey(const Key('reset-preference-2')))
                .onPressed,
            isNull,
          );
          tester
              .widget<DropdownButton<Object>>(
                find.byKey(const Key('preference-1')),
              )
              .onChanged!(false);
          await tester.pump();
          events.add(
            api.WatchEventsResponse()..mergeFromProto3Json({
              'sequence': '2',
              'metadata': {'instanceId': 'preferences-test', 'revision': '7'},
              'invalidated': {
                'domain': 'DOMAIN_MANAGED_SETTINGS',
                'profileId': 'profile-a',
              },
            }),
          );
          await tester.pump();
          expect(
            find.byKey(const Key('client-apply-preferences')),
            findsNothing,
          );
          expect(sent, isNull);
          await tester.ensureVisible(
            find.byKey(const Key('client-load-preferences')),
          );
          await tester.tap(find.byKey(const Key('client-load-preferences')));
          await tester.pump();
          staleEdit(true);
          await tester.pump();
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('client-apply-preferences')),
                )
                .onPressed,
            isNull,
          );
        } else {
          for (var key = 1; key <= 8; key++) {
            final dropdown = tester.widget<DropdownButton<Object>>(
              find.byKey(Key('preference-$key')),
            );
            if (key > 3) {
              expect(dropdown.items!.map((item) => item.value), [
                api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_DISCONNECT,
              ]);
            }
            dropdown.onChanged!(
              key <= 3
                  ? false
                  : api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_DISCONNECT,
            );
            await tester.pump();
          }
          expect(sent, isNull);
          expect(
            find.text('Effective: true; requested: false'),
            findsOneWidget,
          );
          expect(
            tester
                .widget<TextButton>(find.byKey(const Key('reset-preference-1')))
                .onPressed,
            isNull,
          );
          await tester.ensureVisible(
            find.byKey(const Key('client-apply-preferences')),
          );
          await tester.tap(find.byKey(const Key('client-apply-preferences')));
          await tester.pump();
          expect(sent!.toProto3Json(), {
            'allowInbound': false,
            'acceptDns': false,
            'acceptRoutes': false,
            'runtimeStart': 'LIFECYCLE_BEHAVIOR_DISCONNECT',
            'uiQuit': 'LIFECYCLE_BEHAVIOR_DISCONNECT',
            'userLogoff': 'LIFECYCLE_BEHAVIOR_DISCONNECT',
            'suspend': 'LIFECYCLE_BEHAVIOR_DISCONNECT',
            'resume': 'LIFECYCLE_BEHAVIOR_DISCONNECT',
          });
          expect(
            find.text(
              'Preference operation received. Recover its result and refresh effective values.',
            ),
            findsOneWidget,
          );
          expect(find.byKey(const Key('preference-1')), findsNothing);
          expect(reset, isNull);
          await tester.ensureVisible(
            find.byKey(const Key('client-load-preferences')),
          );
          await tester.tap(find.byKey(const Key('client-load-preferences')));
          await tester.pump();
          await tester.ensureVisible(
            find.byKey(const Key('reset-preference-1')),
          );
          await tester.tap(find.byKey(const Key('reset-preference-1')));
          await tester.pump();
          expect(reset, [api.PreferenceKey.PREFERENCE_KEY_ALLOW_INBOUND]);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  test(
    'US-10: preference projection preserves presence and policy without writes',
    () async {
      final response = api.GetPreferencesResponse()
        ..mergeFromProto3Json({
          'preferences': {
            'metadata': {'instanceId': 'preferences-test', 'revision': '7'},
            'profileId': 'profile-a',
            'allowInbound': {'effective': true, 'requested': false},
            'acceptDns': {'effective': false},
            'lifecycle': {
              'uiQuit': {
                'effective': 'LIFECYCLE_BEHAVIOR_KEEP_INTENT',
                'requested': 'LIFECYCLE_BEHAVIOR_DISCONNECT',
                'allowedValues': [
                  'LIFECYCLE_BEHAVIOR_KEEP_INTENT',
                  'LIFECYCLE_BEHAVIOR_DISCONNECT',
                ],
              },
            },
          },
        });
      final policies = api.ListManagedSettingsResponse()
        ..mergeFromProto3Json({
          'metadata': {'instanceId': 'preferences-test', 'revision': '7'},
          'settings': [
            {
              'key': 'PREFERENCE_KEY_ALLOW_INBOUND',
              'booleanValue': false,
              'control': {
                'locked': true,
                'source': 'SETTING_SOURCE_ACCOUNT_POLICY',
                'policyId': 'policy-a',
              },
            },
          ],
        });
      var checks = 0;
      final result = await readClientPreferences(
        instanceId: 'preferences-test',
        profileId: 'profile-a',
        get: (request) async {
          expect(request.profile.profileId, 'profile-a');
          return response;
        },
        listManaged: (request) async {
          expect(request.profile.profileId, 'profile-a');
          response.preferences.allowInbound.requested = true;
          return policies;
        },
        checkContext: () {
          checks++;
        },
      );
      expect(checks, 3);
      expect(result.preferences.allowInbound.hasRequested(), isTrue);
      expect(result.preferences.allowInbound.requested, isFalse);
      expect(result.preferences.allowInbound.effective, isTrue);
      expect(result.preferences.acceptDns.hasRequested(), isFalse);
      expect(
        result.preferences.lifecycle.uiQuit.requested,
        api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_DISCONNECT,
      );
      expect(
        result.preferences.lifecycle.uiQuit.effective,
        api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_KEEP_INTENT,
      );
      policies.settings.single.control.locked = false;
      expect(result.managed.single.control.locked, isTrue);
      expect(result.managed.single.hasBooleanValue(), isTrue);
      expect(result.managed.single.booleanValue, isFalse);
      expect(result.preferences.isFrozen, isTrue);
      expect(result.managed.single.isFrozen, isTrue);
      expect(() => result.managed.clear(), throwsUnsupportedError);
    },
  );

  test(
    'US-10: mixed revisions and invalid policy entries never become a projection',
    () async {
      final response = api.GetPreferencesResponse()
        ..mergeFromProto3Json({
          'preferences': {
            'profileId': 'profile-a',
            'metadata': {'instanceId': 'preferences-test', 'revision': '7'},
          },
        });
      final policies = api.ListManagedSettingsResponse()
        ..mergeFromProto3Json({
          'metadata': {'instanceId': 'preferences-test', 'revision': '7'},
          'settings': [
            {
              'key': 'PREFERENCE_KEY_ACCEPT_DNS',
              'booleanValue': false,
              'control': {'source': 'SETTING_SOURCE_DEFAULT'},
            },
          ],
        });
      for (final change in <void Function(api.ListManagedSettingsResponse)>[
        (r) => r.clearMetadata(),
        (r) => r.metadata.instanceId = 'another-runtime',
        (r) => r.metadata.revision += 1,
        (r) => r.settings.add(
          api.ManagedSetting.fromBuffer(r.settings.single.writeToBuffer()),
        ),
        (r) => r.settings.single.clearControl(),
        (r) => r.settings.single.clearBooleanValue(),
        (r) => r.settings.single.key = api.PreferenceKey.PREFERENCE_KEY_UI_QUIT,
        (r) => r.settings.single.key =
            api.PreferenceKey.PREFERENCE_KEY_UNSPECIFIED,
      ]) {
        final invalid = api.ListManagedSettingsResponse.fromBuffer(
          policies.writeToBuffer(),
        );
        change(invalid);
        await expectLater(
          readClientPreferences(
            instanceId: 'preferences-test',
            profileId: 'profile-a',
            get: (_) async => response,
            listManaged: (_) async => invalid,
            checkContext: () {},
          ),
          throwsFormatException,
        );
      }
      for (final change in <void Function(api.GetPreferencesResponse)>[
        (r) => r.clearPreferences(),
        (r) => r.preferences.clearMetadata(),
        (r) => r.preferences.profileId = 'another-profile',
        (r) => r.preferences.metadata.instanceId = 'another-runtime',
        (r) => r.preferences.metadata.revision -= 7,
      ]) {
        final invalid = api.GetPreferencesResponse.fromBuffer(
          response.writeToBuffer(),
        );
        change(invalid);
        await expectLater(
          readClientPreferences(
            instanceId: 'preferences-test',
            profileId: 'profile-a',
            get: (_) async => invalid,
            listManaged: (_) =>
                throw TestFailure('Invalid first read must stop'),
            checkContext: () {},
          ),
          throwsFormatException,
        );
      }
      var checks = 0;
      await expectLater(
        readClientPreferences(
          instanceId: 'preferences-test',
          profileId: 'profile-a',
          get: (_) async => response,
          listManaged: (_) => throw TestFailure('Invalidated read must stop'),
          checkContext: () {
            if (++checks == 2) throw StateError('Invalidated');
          },
        ),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'US-07: export is explicit and cancellation retains the operation',
    (tester) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      var exports = 0;
      var lookups = 0;
      final operation = ClientOperation.fromProto(
        api.Operation()..mergeFromProto3Json({
          'id': 'bundle-op',
          'requestId': 'bundle-request',
          'kind': 'OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE',
          'state': 'OPERATION_STATE_SUCCEEDED',
          'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
          'bundle': {'bundleId': 'opaque', 'sizeBytes': '3'},
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: ClientRecoveryPanel(
              state: state,
              recover: () async {
                lookups++;
                return [operation];
              },
              acknowledge: (_) =>
                  throw TestFailure('Export must not acknowledge'),
              exportBundle: (id, check) async {
                check();
                expect(id, 'bundle-request');
                exports++;
                return false;
              },
            ),
          ),
        ),
      );
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'export-test', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'export-test',
              'callerAccess': 'ACCESS_OWNER',
            },
            'status': {
              'metadata': {'instanceId': 'export-test', 'revision': '1'},
            },
          },
        }),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('client-recover')));
      await tester.pump();
      expect(exports, 0);
      await tester.tap(find.byKey(const Key('export-bundle-request')));
      await tester.pump();
      expect(exports, 1);
      expect(lookups, 2);
      expect(
        find.text('Export cancelled. The operation is retained.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ack-bundle-request')), findsOneWidget);
      await events.close();
      await tester.pump();
      expect(find.byKey(const Key('export-bundle-request')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  test(
    'US-07: invalid bundle handles never read and chunk errors never retry',
    () async {
      api.BundleResult handle() => api.BundleResult()
        ..mergeFromProto3Json({
          'bundleId': 'opaque',
          'sizeBytes': '1',
          'expiresAt': '2030-01-01T00:00:00Z',
          'sha256': 'a' * 64,
        });
      DateTime now() => DateTime.utc(2029);
      for (final change in <void Function(api.BundleResult)>[
        (h) => h.bundleId = '',
        (h) => h.sizeBytes = h.sizeBytes * (5 * 1024 * 1024 + 1),
        (h) => h.clearExpiresAt(),
        (h) => h.expiresAt.nanos = -1,
        (h) => h.expiresAt.nanos = 1000000000,
        (h) => h.sha256 = 'not-a-checksum',
      ]) {
        final invalid = handle();
        change(invalid);
        await expectLater(
          readClientBundleChunks(
            invalid,
            (_) => throw TestFailure('Invalid handle called RPC'),
            checkContext: () {},
            now: now,
          ),
          throwsFormatException,
        );
      }
      var calls = 0;
      final failure = StateError('synthetic RPC denial');
      await expectLater(
        readClientBundleChunks(
          handle(),
          (_) async {
            calls++;
            throw failure;
          },
          checkContext: () {},
          now: now,
        ),
        throwsA(same(failure)),
      );
      expect(calls, 1);
      final large = handle()..sizeBytes *= 65537;
      calls = 0;
      await expectLater(
        readClientBundleChunks(
          large,
          (request) async {
            calls++;
            return api.ReadDiagnosticsBundleResponse(
              data: List.filled(65537, 0),
              nextOffset: large.sizeBytes,
              eof: true,
            );
          },
          checkContext: () {},
          now: now,
        ),
        throwsFormatException,
      );
      expect(calls, 1);
    },
  );

  test(
    'US-07: bundle chunks enforce bounds, offset, EOF, expiry and caller context',
    () async {
      api.BundleResult bundle() => api.BundleResult()
        ..mergeFromProto3Json({
          'bundleId': 'opaque-handle',
          'sizeBytes': '3',
          'expiresAt': '2030-01-01T00:00:00Z',
          'sha256':
              '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
        });
      DateTime now() => DateTime.utc(2029);
      var calls = 0;
      final bytes = await readClientBundleChunks(
        bundle(),
        (request) async {
          expect(request.bundleId, 'opaque-handle');
          expect(request.maxBytes, 65536);
          expect(request.offset.toInt(), calls == 0 ? 0 : 2);
          calls++;
          return api.ReadDiagnosticsBundleResponse()..mergeFromProto3Json(
            calls == 1
                ? {'data': 'AQI=', 'nextOffset': '2'}
                : {'data': 'Aw==', 'nextOffset': '3', 'eof': true},
          );
        },
        checkContext: () {},
        now: now,
      );
      expect(bytes, [1, 2, 3]);
      await expectLater(
        readClientBundleChunks(
          bundle(),
          (_) async => api.ReadDiagnosticsBundleResponse()
            ..mergeFromProto3Json({
              'data': 'AQIE',
              'nextOffset': '3',
              'eof': true,
            }),
          checkContext: () {},
          now: now,
        ),
        throwsFormatException,
      );
      for (final chunk in [
        {'data': 'AQI=', 'nextOffset': '1'},
        {'data': 'AQI=', 'nextOffset': '2', 'eof': true},
        {'nextOffset': '0'},
        {'data': 'AQIDBA==', 'nextOffset': '4', 'eof': true},
        {'data': 'AQID', 'nextOffset': '3'},
      ]) {
        await expectLater(
          readClientBundleChunks(
            bundle(),
            (_) async =>
                api.ReadDiagnosticsBundleResponse()..mergeFromProto3Json(chunk),
            checkContext: () {},
            now: now,
          ),
          throwsFormatException,
        );
      }
      await expectLater(
        readClientBundleChunks(
          bundle(),
          (_) => throw TestFailure('Expired handle must not call RPC'),
          checkContext: () {},
          now: () => DateTime.utc(2030),
        ),
        throwsStateError,
      );
      var current = true;
      await expectLater(
        readClientBundleChunks(
          bundle(),
          (_) async {
            current = false;
            return api.ReadDiagnosticsBundleResponse()..mergeFromProto3Json({
              'data': 'AQID',
              'nextOffset': '3',
              'eof': true,
            });
          },
          checkContext: () {
            if (!current) throw StateError('Caller changed');
          },
          now: now,
        ),
        throwsStateError,
      );
    },
  );

  testWidgets(
    'US-07: diagnostics preview is explicit, scoped and cleared on invalidation',
    (tester) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      var reads = 0;
      final creates = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: ClientDiagnosticsPanel(
              state: state,
              createBundle: (id) async {
                creates.add(id);
                return ClientOperation.fromProto(
                  api.Operation(
                    id: 'bundle-op',
                    kind: api
                        .OperationKind
                        .OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE,
                    state: api.OperationState.OPERATION_STATE_PENDING,
                  ),
                );
              },
              load: () async {
                reads++;
                return api.Diagnostics()..mergeFromProto3Json({
                  'metadata': {
                    'instanceId': 'diagnostic-test',
                    'revision': '1',
                  },
                  'osName': 'synthetic-os',
                  'truncated': true,
                  'status': {
                    'pendingAction': {
                      'browserUrl': 'https://private.example/action',
                    },
                  },
                });
              },
            ),
          ),
        ),
      );
      final load = find.byKey(const Key('load-client-diagnostics'));
      expect(reads, 0);
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'diagnostic-test', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'diagnostic-test',
              'callerAccess': 'ACCESS_OWNER',
              'capabilities': [
                {
                  'capability': 'CAPABILITY_DIAGNOSTICS',
                  'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                },
              ],
            },
            'status': {
              'activeProfileId': 'profile-a',
              'metadata': {'instanceId': 'diagnostic-test', 'revision': '1'},
            },
          },
        }),
      );
      await tester.pump();
      expect(reads, 0);
      await tester.tap(load);
      await tester.pump();
      expect(reads, 1);
      expect(find.textContaining('synthetic-os'), findsOneWidget);
      expect(find.textContaining('not a complete report'), findsOneWidget);
      expect(find.textContaining('private.example'), findsNothing);
      final create = find.byKey(const Key('create-client-bundle'));
      final confirmBundle = find.byKey(const Key('confirm-client-bundle'));
      expect(creates, isEmpty);
      await tester.tap(create);
      await tester.pump();
      await tester.tap(find.byKey(const Key('cancel-client-bundle')));
      await tester.pump();
      expect(creates, isEmpty);
      await tester.tap(create);
      await tester.pump();
      await tester.tap(confirmBundle);
      await tester.pump();
      expect(creates, ['profile-a']);
      expect(
        find.textContaining('archive readiness is not confirmed'),
        findsOneWidget,
      );
      await tester.tap(create);
      await tester.pump();
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '2',
          'metadata': {'instanceId': 'diagnostic-test', 'revision': '1'},
          'invalidated': {'domain': 'DOMAIN_PEERS', 'profileId': 'profile-a'},
        }),
      );
      await tester.pump();
      expect(find.textContaining('synthetic-os'), findsNothing);
      expect(confirmBundle, findsNothing);
      expect(creates, ['profile-a']);
      expect(reads, 1);
      await events.close();
      await tester.pump();
      expect(tester.widget<OutlinedButton>(load).onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'US-06: explicit trust compares fresh announcement and clears invalidated data',
    (tester) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      var announcement = 'announcement-a';
      Completer<api.GetServerIdentityResponse>? pendingRead;
      final sent = <api.ServerIdentity>[];
      api.GetServerIdentityResponse response() =>
          api.GetServerIdentityResponse()..mergeFromProto3Json({
            'identity': {
              'profileId': 'profile-a',
              'controlOrigin': 'https://control.example',
              'trustedKeyId': 'old-key',
              'announcedKeyId': 'new-key',
              'announcementId': announcement,
              'changed': true,
            },
            'metadata': {'instanceId': 'identity-test', 'revision': '1'},
          });
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: ClientIdentityPanel(
              state: state,
              load: () async =>
                  pendingRead == null ? response() : await pendingRead.future,
              trust: (identity) async {
                sent.add(identity);
                return ClientOperation.fromProto(
                  api.Operation(
                    id: 'trust-a',
                    kind:
                        api.OperationKind.OPERATION_KIND_TRUST_SERVER_IDENTITY,
                    state: api.OperationState.OPERATION_STATE_PENDING,
                  ),
                );
              },
            ),
          ),
        ),
      );
      var sequence = 0;
      void snapshot(String access) => events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '${++sequence}',
          'metadata': {'instanceId': 'identity-test', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'identity-test',
              'callerAccess': access,
              'capabilities': [
                {
                  'capability': 'CAPABILITY_IDENTITY_RECOVERY',
                  'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                },
              ],
            },
            'status': {
              'activeProfileId': 'profile-a',
              'metadata': {'instanceId': 'identity-test', 'revision': '1'},
            },
          },
        }),
      );
      final load = find.byKey(const Key('load-client-identity'));
      final confirm = find.byKey(const Key('compare-client-identity'));
      final trust = find.byKey(const Key('trust-client-identity'));
      snapshot('ACCESS_OWNER');
      await tester.pump();
      await tester.tap(load);
      await tester.pump();
      expect(find.text('Trusted key: old-key'), findsOneWidget);
      expect(tester.widget<TextButton>(trust).onPressed, isNull);
      expect(sent, isEmpty);
      snapshot('ACCESS_ADMINISTRATOR');
      await tester.pump();
      expect(find.text('Trusted key: old-key'), findsNothing);
      await tester.tap(load);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      announcement = 'announcement-b';
      await tester.tap(trust);
      await tester.pump();
      expect(sent, isEmpty);
      expect(find.textContaining('no trust command was sent'), findsOneWidget);
      await tester.tap(load);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      await tester.tap(trust);
      await tester.pump();
      expect(sent.single.announcementId, 'announcement-b');
      expect(sent.single.controlOrigin, 'https://control.example');
      expect(sent.single.announcedKeyId, 'new-key');
      expect(sent.single.isFrozen, isTrue);
      expect(
        find.textContaining('not inferred from acceptance'),
        findsOneWidget,
      );
      await tester.tap(load);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '${++sequence}',
          'metadata': {'instanceId': 'identity-test', 'revision': '1'},
          'invalidated': {
            'domain': 'DOMAIN_SERVER_IDENTITY',
            'profileId': 'profile-a',
          },
        }),
      );
      await tester.pump();
      expect(confirm, findsNothing);
      expect(find.text('Announced key: new-key'), findsNothing);
      expect(sent.length, 1);
      for (final domain in ['DOMAIN_SERVER_IDENTITY', 'DOMAIN_PROFILES']) {
        await tester.tap(load);
        await tester.pump();
        await tester.tap(confirm);
        await tester.pump();
        final pending = Completer<api.GetServerIdentityResponse>();
        pendingRead = pending;
        await tester.tap(trust);
        // Deliver invalidation and then the read response without a frame:
        // the old form is still mounted but must not submit its confirmation.
        events.add(
          api.WatchEventsResponse()..mergeFromProto3Json({
            'sequence': '${++sequence}',
            'metadata': {'instanceId': 'identity-test', 'revision': '1'},
            'invalidated': {'domain': domain, 'profileId': 'profile-a'},
          }),
        );
        await tester.idle();
        pending.complete(response());
        await tester.idle();
        expect(sent.length, 1);
        pendingRead = null;
        await tester.pump();
        expect(confirm, findsNothing);
      }
      await tester.tap(load);
      await tester.pump();
      await tester.tap(confirm);
      await tester.pump();
      final stalePress = tester.widget<TextButton>(trust).onPressed!;
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '${++sequence}',
          'metadata': {'instanceId': 'identity-test', 'revision': '1'},
          'invalidated': {
            'domain': 'DOMAIN_SERVER_IDENTITY',
            'profileId': 'profile-a',
          },
        }),
      );
      await tester.idle();
      stalePress();
      await tester.idle();
      expect(sent.length, 1);
      await tester.pump();
      snapshot('ACCESS_OBSERVER');
      await tester.pump();
      expect(tester.widget<OutlinedButton>(load).onPressed, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await events.close();
      state.dispose();
    },
  );

  testWidgets('US-14: shared host respects system safe-area hit testing', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(top: 59, bottom: 34),
          ),
          child: ContractTestScaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: TextButton(
                key: const Key('safe-area-action'),
                onPressed: () => taps++,
                child: const Text('Action'),
              ),
            ),
          ),
        ),
      ),
    );
    final action = find.byKey(const Key('safe-area-action'));
    expect(tester.getTopLeft(action).dy, greaterThanOrEqualTo(59));
    await tester.tap(action);
    expect(taps, 1);
  });
  testWidgets(
    'US-08: failed logout never falls back to administrator local forget',
    (tester) async {
      final state = ClientStateController();
      final source = StreamController<api.WatchEventsResponse>();
      await state.attach(source.stream);
      final logout = <String>[];
      final forget = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: ClientCleanupPanel(
              state: state,
              logout: (id) async {
                logout.add(id);
                throw StateError('raw cleanup failure');
              },
              forget: (id) async {
                forget.add(id);
                return ClientOperation.fromProto(
                  api.Operation(
                    id: 'forget',
                    kind: api
                        .OperationKind
                        .OPERATION_KIND_FORGET_LOCAL_ENROLLMENT,
                    state: api.OperationState.OPERATION_STATE_PENDING,
                  ),
                );
              },
            ),
          ),
        ),
      );
      final snapshot = api.WatchEventsResponse()
        ..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'cleanup-test', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'cleanup-test',
              'callerAccess': 'ACCESS_OWNER',
              'capabilities': [
                for (final cap in ['LOGOUT', 'LOCAL_FORGET'])
                  {
                    'capability': 'CAPABILITY_$cap',
                    'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                  },
              ],
            },
            'status': {
              'activeProfileId': 'profile-a',
              'metadata': {'instanceId': 'cleanup-test', 'revision': '1'},
            },
          },
        });
      source.add(snapshot);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('client-local-forget')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('client-logout')));
      await tester.pump();
      expect(logout, isEmpty);
      await tester.tap(find.byKey(const Key('cancel-client-cleanup')));
      await tester.pump();
      expect(logout, isEmpty);
      await tester.tap(find.byKey(const Key('client-logout')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirm-client-cleanup')));
      await tester.pump();
      expect(logout, ['profile-a']);
      expect(forget, isEmpty);
      expect(find.textContaining('raw cleanup failure'), findsNothing);
      snapshot.sequence += 1;
      snapshot.snapshot.runtime.callerAccess = api.Access.ACCESS_ADMINISTRATOR;
      source.add(snapshot);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('client-local-forget')));
      await tester.pump();
      expect(
        find.textContaining('without confirmed remote cleanup'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('confirm-client-cleanup')));
      await tester.pump();
      expect(forget, ['profile-a']);
      await tester.tap(find.byKey(const Key('client-local-forget')));
      await tester.pump();
      snapshot.sequence += 1;
      snapshot.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      snapshot.snapshot.status.clearActiveProfileId();
      source.add(snapshot);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm-client-cleanup')), findsNothing);
      expect(forget, ['profile-a']);
      await source.close();
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'US-02: enrollment requires capability and clears token before sending',
    (tester) async {
      final state = ClientStateController();
      final source = StreamController<api.WatchEventsResponse>();
      await state.attach(source.stream);
      final calls = <(String, api.EnrollmentMode, String, String?)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: ClientEnrollmentPanel(
              state: state,
              enroll: (id, mode, hostname, token) async {
                calls.add((id, mode, hostname, token));
                throw StateError('must-not-display-token: $token');
              },
            ),
          ),
        ),
      );
      final snapshot = api.WatchEventsResponse()
        ..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'enrollment-test', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'enrollment-test',
              'callerAccess': 'ACCESS_OWNER',
            },
            'status': {
              'activeProfileId': 'profile-a',
              'metadata': {'instanceId': 'enrollment-test', 'revision': '1'},
            },
          },
        });
      source.add(snapshot);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('enroll-hostname')))
            .enabled,
        isFalse,
      );
      snapshot.sequence += 1;
      snapshot.snapshot.runtime.capabilities.add(
        api.CapabilityStatus()..mergeFromProto3Json({
          'capability': 'CAPABILITY_ENROLLMENT',
          'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
        }),
      );
      source.add(snapshot);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('enroll-hostname')),
        'device-a',
      );
      await tester.pump();
      expect(
        state.snapshot!.supports(api.Capability.CAPABILITY_ENROLLMENT),
        isTrue,
      );
      expect(state.snapshot!.status.activeProfileId, 'profile-a');
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('enroll-submit')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('enroll-submit')));
      await tester.pump();
      expect(calls.single.$4, isNull);
      expect(calls.single.$1, 'profile-a');
      await tester.tap(find.byKey(const Key('enroll-use-token')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('enroll-token')),
        'synthetic-test-token',
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('enroll-token')))
            .obscureText,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('enroll-submit')));
      await tester.pump();
      expect(calls.last.$4, 'synthetic-test-token');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('enroll-token')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.textContaining('must-not-display-token'), findsNothing);
      snapshot.sequence += 1;
      snapshot.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      snapshot.snapshot.status.clearActiveProfileId();
      source.add(snapshot);
      await tester.pump();
      expect(find.byKey(const Key('enroll-token')), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('enroll-submit')))
            .onPressed,
        isNull,
      );
      await source.close();
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'US-02/03: browser action is refreshed, explicit and never completes operation',
    (tester) async {
      final state = ClientStateController();
      final source = StreamController<api.WatchEventsResponse>();
      await state.attach(source.stream);
      var url = 'https://example.test/old';
      var expired = false;
      var lookups = 0;
      final launched = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: ClientRecoveryPanel(
              state: state,
              recover: () async {
                lookups++;
                return [
                  ClientOperation.fromProto(
                    api.Operation()..mergeFromProto3Json({
                      'id': 'browser',
                      'requestId': 'browser-request',
                      'kind': 'OPERATION_KIND_ENROLL',
                      'state': 'OPERATION_STATE_WAITING_FOR_USER',
                      'userAction': {
                        'kind': 'KIND_OPEN_BROWSER',
                        'browserUrl': url,
                        if (expired) 'expiresAt': '2000-01-01T00:00:00Z',
                      },
                    }),
                  ),
                ];
              },
              acknowledge: (_) async =>
                  fail('Browser launch must not acknowledge'),
              openBrowser: (uri) async {
                launched.add(uri);
                return true;
              },
            ),
          ),
        ),
      );
      source.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'browser-test', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'browser-test',
              'callerAccess': 'ACCESS_OWNER',
            },
            'status': {
              'metadata': {'instanceId': 'browser-test', 'revision': '1'},
            },
          },
        }),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('client-recover')));
      await tester.pump();
      expect(launched, isEmpty);
      url = 'https://example.test/new';
      await tester.tap(find.byKey(const Key('browser-browser-request')));
      await tester.pump();
      expect(lookups, 2);
      expect(launched, [Uri.parse(url)]);
      expect(
        find.text(
          'Browser opened. The operation is still pending; recover its result.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ack-browser-request')), findsNothing);
      for (final rejected in [
        'file:///tmp/token',
        'https://user@example.test/token',
      ]) {
        url = rejected;
        await tester.tap(find.byKey(const Key('browser-browser-request')));
        await tester.pump();
        expect(launched, hasLength(1));
        expect(find.textContaining(rejected), findsNothing);
      }
      url = 'https://example.test/expired';
      expired = true;
      await tester.tap(find.byKey(const Key('browser-browser-request')));
      await tester.pump();
      expect(launched, hasLength(1));
      await source.close();
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'US-03/08: typed cleanup and failure keep remote and local outcomes distinct',
    (tester) async {
      for (final outcome in [
        'REMOTE_CONFIRMED',
        'REMOTE_UNCONFIRMED',
        'NOT_REGISTERED',
      ]) {
        final operation = ClientOperation.fromProto(
          api.Operation()..mergeFromProto3Json({
            'id': 'cleanup',
            'kind': 'OPERATION_KIND_FORGET_LOCAL_ENROLLMENT',
            'state': 'OPERATION_STATE_SUCCEEDED',
            'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
            'cleanup': {
              'outcome': 'CLEANUP_OUTCOME_$outcome',
              'localRegistrationRemoved': true,
              'controlRequestId': 'cleanup-correlation',
            },
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ContractTestScaffold(
              body: ClientOperationDetails(operation: operation),
            ),
          ),
        );
        expect(find.text('Local registration removed.'), findsOneWidget);
        expect(
          find.text('Control request: cleanup-correlation'),
          findsOneWidget,
        );
        expect(
          find.text('Remote cleanup confirmed.'),
          outcome == 'REMOTE_CONFIRMED' ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Remote cleanup NOT confirmed.'),
          outcome == 'REMOTE_UNCONFIRMED' ? findsOneWidget : findsNothing,
        );
      }
      final failure = ClientOperation.fromProto(
        api.Operation()..mergeFromProto3Json({
          'id': 'failed',
          'kind': 'OPERATION_KIND_LOGOUT',
          'state': 'OPERATION_STATE_FAILED',
          'failure': {
            'code': 'ERROR_CODE_REMOTE_CLEANUP_REQUIRED',
            'reasonKey': 'do-not-render-raw-reason',
            'controlRequestId': 'failure-correlation',
          },
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: ClientOperationDetails(operation: failure),
          ),
        ),
      );
      expect(
        find.text('Failure: ERROR_CODE_REMOTE_CLEANUP_REQUIRED'),
        findsOneWidget,
      );
      expect(find.text('Control request: failure-correlation'), findsOneWidget);
      expect(find.text('do-not-render-raw-reason'), findsNothing);
      expect(find.text('Remote cleanup confirmed.'), findsNothing);
      final waiting = ClientOperation.fromProto(
        api.Operation()..mergeFromProto3Json({
          'id': 'waiting',
          'kind': 'OPERATION_KIND_ENROLL',
          'state': 'OPERATION_STATE_WAITING_FOR_USER',
          'userAction': {
            'kind': 'KIND_OPEN_BROWSER',
            'browserUrl': 'https://example.test/sensitive-token',
          },
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: ClientOperationDetails(operation: waiting),
          ),
        ),
      );
      expect(find.text('Required action: KIND_OPEN_BROWSER'), findsOneWidget);
      expect(find.textContaining('sensitive-token'), findsNothing);
    },
  );
  testWidgets(
    'US-03: recovery acknowledges only terminal results and clears caller context',
    (tester) async {
      final state = ClientStateController();
      final source = StreamController<api.WatchEventsResponse>();
      await state.attach(source.stream);
      final pending = ClientOperation.fromProto(
        api.Operation(
          id: 'pending',
          requestId: 'request-pending',
          kind: api.OperationKind.OPERATION_KIND_CONNECT,
          state: api.OperationState.OPERATION_STATE_PENDING,
        ),
      );
      final terminal = ClientOperation.fromProto(
        api.Operation()..mergeFromProto3Json({
          'id': 'done',
          'requestId': 'request-done',
          'kind': 'OPERATION_KIND_DISCONNECT',
          'state': 'OPERATION_STATE_SUCCEEDED',
          'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
          'change': {'changed': true},
        }),
      );
      var lookups = 0;
      Completer<List<ClientOperation>>? delayedLookup;
      final acknowledgements = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: ClientRecoveryPanel(
              state: state,
              recover: () async {
                lookups++;
                if (delayedLookup != null) return delayedLookup.future;
                return [pending, terminal];
              },
              acknowledge: (op) async {
                acknowledgements.add(op.value.requestId);
              },
            ),
          ),
        ),
      );
      final snapshot = api.WatchEventsResponse()
        ..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'recovery-test', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'recovery-test',
              'callerAccess': 'ACCESS_OWNER',
            },
            'status': {
              'metadata': {'instanceId': 'recovery-test', 'revision': '1'},
            },
          },
        });
      source.add(snapshot);
      await tester.pump();
      await tester.tap(find.byKey(const Key('client-recover')));
      await tester.pump();
      expect(lookups, 1);
      expect(find.text('Still pending'), findsOneWidget);
      expect(find.byKey(const Key('ack-request-pending')), findsNothing);
      await tester.tap(find.byKey(const Key('ack-request-done')));
      await tester.pump();
      expect(acknowledgements, ['request-done']);
      expect(find.byKey(const Key('ack-request-done')), findsNothing);
      delayedLookup = Completer<List<ClientOperation>>();
      await tester.tap(find.byKey(const Key('client-recover')));
      await tester.pump();
      expect(lookups, 2);
      snapshot.sequence += 1;
      snapshot.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      source.add(snapshot);
      await tester.pump();
      delayedLookup.complete([pending, terminal]);
      await tester.pump();
      expect(find.byKey(const Key('ack-request-done')), findsNothing);
      expect(acknowledgements, ['request-done']);
      expect(find.text('Still pending'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('client-recover')))
            .onPressed,
        isNull,
      );
      await source.close();
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'US-01/03: typed snapshot reaches widgets and stream loss clears it',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final state = ClientStateController();
        final source = StreamController<api.WatchEventsResponse>();
        final connectResult = Completer<ClientOperation>();
        var connectCalls = 0;
        var disconnectCalls = 0;
        var renewalCalls = 0;
        await state.attach(source.stream);
        await tester.pumpWidget(
          MaterialApp(
            home: ContractTestScaffold(
              body: ClientConnectionPanel(
                state: state,
                renewSession: () async {
                  renewalCalls++;
                  return ClientOperation.fromProto(
                    api.Operation(
                      id: 'renew-operation',
                      kind: api.OperationKind.OPERATION_KIND_RENEW_SESSION,
                      state: api.OperationState.OPERATION_STATE_PENDING,
                    ),
                  );
                },
                connect: () {
                  connectCalls++;
                  return connectResult.future;
                },
                disconnect: () async {
                  disconnectCalls++;
                  return ClientOperation.fromProto(
                    api.Operation(
                      id: 'disconnect-op',
                      kind: api.OperationKind.OPERATION_KIND_DISCONNECT,
                      state: api.OperationState.OPERATION_STATE_PENDING,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        expect(find.text('Waiting for runtime snapshot…'), findsOneWidget);
        final snapshot = api.WatchEventsResponse()
          ..mergeFromProto3Json({
            'sequence': '1',
            'metadata': {'instanceId': 'native-test', 'revision': '1'},
            'snapshot': {
              'runtime': {
                'protocol': api.ClientContract.protocol,
                'contractSha256': api.ClientContract.sha256,
                'instanceId': 'native-test',
                'callerAccess': 'ACCESS_OWNER',
                'capabilities': [
                  {
                    'capability': 'CAPABILITY_CONNECTION',
                    'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                  },
                ],
              },
              'status': {
                'metadata': {'instanceId': 'native-test', 'revision': '1'},
                'activeProfileId': 'synthetic-profile',
                'connectionPhase': 'CONNECTION_PHASE_DISCONNECTED',
              },
            },
          });
        source.add(snapshot);
        await tester.pump();
        expect(find.text('Profile: synthetic-profile'), findsOneWidget);
        expect(find.text('Session expiry: Unknown'), findsOneWidget);
        expect(find.text('Credential expiry: Unknown'), findsOneWidget);
        expect(find.text('Account: Unknown'), findsOneWidget);
        expect(find.text('Network ID: Unknown'), findsOneWidget);
        expect(find.text('Device: Unknown'), findsOneWidget);
        snapshot.sequence += 1;
        snapshot.snapshot.status
          ..accountId = 'account-a'
          ..hostname = 'device-a'
          ..nodeId = 'node-a'
          ..network = api.Network(id: 'network-a', name: 'Network A');
        source.add(snapshot);
        await tester.pump();
        expect(find.text('Account: account-a'), findsOneWidget);
        expect(find.text('Network: Network A'), findsOneWidget);
        expect(find.text('Network ID: network-a'), findsOneWidget);
        expect(find.text('Device: device-a'), findsOneWidget);
        expect(find.text('Device ID: node-a'), findsOneWidget);
        snapshot.sequence += 1;
        snapshot.snapshot.status.network = api.Network(
          id: 'network-b',
          name: 'Network B',
        );
        source.add(snapshot);
        await tester.pump();
        expect(find.text('Network: Network A'), findsNothing);
        expect(find.text('Network ID: network-a'), findsNothing);
        expect(find.text('Network: Network B'), findsOneWidget);
        expect(find.text('Network ID: network-b'), findsOneWidget);
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('client-renew-session')),
              )
              .onPressed,
          isNull,
        );
        // US-09: the two clocks are independent and never synthesize connection
        // state. This same widget suite runs in Android/iOS native test hosts.
        snapshot.sequence += 1;
        snapshot.snapshot.status.ensureSession().mergeFromProto3Json({
          'expiresAt': '2030-01-01T00:00:00Z',
          'renewal': {'availability': 'AVAILABILITY_AVAILABLE'},
        });
        snapshot.snapshot.runtime.capabilities.add(
          api.CapabilityStatus()..mergeFromProto3Json({
            'capability': 'CAPABILITY_SESSION_RENEWAL',
            'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
          }),
        );
        snapshot.snapshot.status.ensureCredential().mergeFromProto3Json({
          'expiresAt': '2031-02-03T04:05:06Z',
        });
        source.add(snapshot);
        await tester.pump();
        await tester.tap(find.byKey(const Key('client-renew-session')));
        await tester.pump();
        expect(renewalCalls, 1);
        snapshot.sequence += 1;
        snapshot.snapshot.status.session.state =
            api.SessionState.SESSION_STATE_RENEWING;
        source.add(snapshot);
        await tester.pump();
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('client-renew-session')),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.text('Session expiry: 2030-01-01T00:00:00.000Z'),
          findsOneWidget,
        );
        expect(
          find.text('Credential expiry: 2031-02-03T04:05:06.000Z'),
          findsOneWidget,
        );
        snapshot.sequence += 1;
        snapshot.snapshot.status.session.clearExpiresAt();
        source.add(snapshot);
        await tester.pump();
        expect(find.text('Session expiry: Unknown'), findsOneWidget);
        expect(
          find.text('Credential expiry: 2031-02-03T04:05:06.000Z'),
          findsOneWidget,
        );
        expect(
          state.snapshot!.status.connectionPhase,
          api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED,
        );
        await tester.tap(find.byKey(const Key('client-connect')));
        await tester.pump();
        expect(connectCalls, 1);
        // Pending Connect must not prevent an explicit Disconnect.
        await tester.tap(find.byKey(const Key('client-disconnect')));
        await tester.pump();
        expect(disconnectCalls, 1);
        connectResult.complete(
          ClientOperation.fromProto(
            api.Operation(
              id: 'connect-op',
              kind: api.OperationKind.OPERATION_KIND_CONNECT,
              state: api.OperationState.OPERATION_STATE_PENDING,
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Disconnected'), findsOneWidget);
        expect(find.text('Connected'), findsNothing);
        final announcement = tester.getSemantics(
          find.byKey(const Key('client-command-announcement')),
        );
        expect(announcement.flagsCollection.isLiveRegion, isTrue);
        expect(
          announcement.label,
          'Command accepted. Waiting for the runtime result.',
        );
        snapshot.sequence += 1;
        snapshot.metadata.revision += 1;
        snapshot.snapshot.status.metadata.revision += 1;
        snapshot.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
        snapshot.snapshot.status.clearActiveProfileId();
        snapshot.snapshot.status.clearAccountId();
        snapshot.snapshot.status.clearHostname();
        snapshot.snapshot.status.clearNodeId();
        snapshot.snapshot.status.clearNetwork();
        snapshot.snapshot.status.clearSession();
        snapshot.snapshot.status.clearCredential();
        source.add(snapshot);
        await tester.pump();
        expect(find.text('Profile: synthetic-profile'), findsNothing);
        expect(find.byKey(const Key('client-session-expiry')), findsNothing);
        expect(find.byKey(const Key('client-credential-expiry')), findsNothing);
        expect(find.byKey(const Key('client-context-account')), findsNothing);
        expect(find.byKey(const Key('client-context-network')), findsNothing);
        expect(find.byKey(const Key('client-context-device')), findsNothing);
        expect(
          find.byKey(const Key('client-command-announcement')),
          findsNothing,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('client-renew-session')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('client-connect')))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('client-disconnect')),
              )
              .onPressed,
          isNull,
        );
        expect(
          find.text('Command accepted. Waiting for the runtime result.'),
          findsNothing,
        );
        await source.close();
        await tester.pump();
        expect(find.text('Profile: synthetic-profile'), findsNothing);
        expect(find.text('Runtime unavailable'), findsOneWidget);
        expect(state.link, ClientLinkState.unavailable);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      } finally {
        semantics.dispose();
      }
    },
  );
}
