import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

import 'support/scenario_host.dart';

Map<String, Object> recoveredOperation(Map<String, Object> accepted) => {
  ...accepted,
  'state': 'OPERATION_STATE_SUCCEEDED',
  'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
  if (accepted['kind'] == 'OPERATION_KIND_ENROLL')
    'enrollment': {'profileId': 'profile-a', 'nodeId': 'node-a'}
  else if (accepted['kind'] == 'OPERATION_KIND_SELECT_EXIT_NODE')
    'selection': {'selectedId': 'exit-a'}
  else if (accepted['kind'] == 'OPERATION_KIND_CLEAR_EXIT_NODE')
    'selection': <String, Object>{}
  else if (accepted['kind'] == 'OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE')
    'bundle': {
      'bundleId': 'bundle-a',
      'sizeBytes': '3',
      'expiresAt': '2099-01-01T00:00:00Z',
      'sha256':
          '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
    }
  else
    'change': {'changed': true},
};

Map<String, Object> resourceConflictOperation(Map<String, Object> accepted) => {
  ...accepted,
  'state': 'OPERATION_STATE_FAILED',
  'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
  'failure': {
    'code': 'ERROR_CODE_RESOURCE_CONFLICT',
    'reasonKey': 'resource.overlap',
    'controlRequestId': 'control-resource-a',
  },
};

Map<String, Object> exitFailureOperation(Map<String, Object> accepted) => {
  ...accepted,
  'state': 'OPERATION_STATE_FAILED',
  'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
  'failure': {
    'code': 'ERROR_CODE_UNSUPPORTED',
    'reasonKey': 'exit.family_unavailable',
    'controlRequestId': 'control-exit-a',
  },
};

void main() {
  final executable = Platform.environment['ENDLESSNET_TESTSERVER'];
  test('US-05: exit failure fixture is not selection success', () {
    final result = ClientOperation.fromProto(
      api.Operation()..mergeFromProto3Json(
        exitFailureOperation({
          'id': 'operation-a',
          'requestId': 'c06bd29f-7c77-4b27-943a-620081f313df',
          'kind': 'OPERATION_KIND_SELECT_EXIT_NODE',
        }),
      ),
    );
    expect(result.terminal, isTrue);
    expect(result.succeeded, isFalse);
    expect(result.value.failure.code, api.ErrorCode.ERROR_CODE_UNSUPPORTED);
    expect(result.value.failure.controlRequestId, 'control-exit-a');
    expect(result.value.hasSelection(), isFalse);
  });
  test(
    'US-11: resource conflict fixture preserves typed failure and correlation',
    () {
      final result = ClientOperation.fromProto(
        api.Operation()..mergeFromProto3Json(
          resourceConflictOperation({
            'id': 'resource-op',
            'requestId': 'c06bd29f-7c77-4b27-943a-620081f313df',
            'kind': 'OPERATION_KIND_SET_RESOURCE_ENABLED',
          }),
        ),
      );
      expect(result.terminal, isTrue);
      expect(result.succeeded, isFalse);
      expect(
        result.value.failure.code,
        api.ErrorCode.ERROR_CODE_RESOURCE_CONFLICT,
      );
      expect(result.value.failure.controlRequestId, 'control-resource-a');
    },
  );
  test('Synthetic host diagnostics retain only exact lifecycle errors', () {
    expect(
      scenarioLifecycleDiagnostic('script has in-flight calls'),
      'script has in-flight calls',
    );
    expect(
      scenarioLifecycleDiagnostic('testserver transport failed'),
      'testserver transport failed',
    );
    for (final line in [
      'Authorization: synthetic-value',
      'request mismatch: payload',
      'script has in-flight calls: extra payload',
      ' response body ',
      '',
    ]) {
      expect(scenarioLifecycleDiagnostic(line), isNull);
    }
  });
  test('US-03: process recovery fixture satisfies operation contract', () {
    for (final kind in [
      'CONNECT',
      'ENROLL',
      'TRUST_SERVER_IDENTITY',
      'CREATE_DIAGNOSTICS_BUNDLE',
      'SET_PREFERENCES',
      'RESET_PREFERENCES',
      'SET_RESOURCE_ENABLED',
      'SELECT_EXIT_NODE',
      'CLEAR_EXIT_NODE',
    ]) {
      final operation = ClientOperation.fromProto(
        api.Operation()..mergeFromProto3Json(
          recoveredOperation({
            'id': 'operation-a',
            'requestId': 'c06bd29f-7c77-4b27-943a-620081f313df',
            'kind': 'OPERATION_KIND_$kind',
            'state': 'OPERATION_STATE_PENDING',
          }),
        ),
      );
      expect(operation.succeeded, isTrue);
      expect(
        operation.value.continuity,
        api.ConnectionContinuity.CONNECTION_CONTINUITY_UNKNOWN,
      );
      expect(operation.value.whichOutcome(), switch (kind) {
        'ENROLL' => api.Operation_Outcome.enrollment,
        'CREATE_DIAGNOSTICS_BUNDLE' => api.Operation_Outcome.bundle,
        'SELECT_EXIT_NODE' ||
        'CLEAR_EXIT_NODE' => api.Operation_Outcome.selection,
        _ => api.Operation_Outcome.change,
      });
    }
  });
  for (final authentication in [
    'connect',
    'browser',
    'token',
    'trust',
    'bundle',
    'set-preferences',
    'reset-preferences',
    'enable-resource',
    'disable-resource',
    'conflict-resource',
    'select-exit',
    'clear-exit',
    'failed-exit',
  ]) {
    test(
      'US-01/02/03/05/06/07/10/11: $authentication session submits and recovers while WatchEvents stays open',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'en-session-rpc-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final intent = PendingClientIntent(
          'c06bd29f-7c77-4b27-943a-620081f313df',
          switch (authentication) {
            'select-exit' ||
            'failed-exit' => api.OperationKind.OPERATION_KIND_SELECT_EXIT_NODE,
            'clear-exit' => api.OperationKind.OPERATION_KIND_CLEAR_EXIT_NODE,
            'enable-resource' || 'disable-resource' || 'conflict-resource' =>
              api.OperationKind.OPERATION_KIND_SET_RESOURCE_ENABLED,
            'connect' => api.OperationKind.OPERATION_KIND_CONNECT,
            'trust' => api.OperationKind.OPERATION_KIND_TRUST_SERVER_IDENTITY,
            'bundle' =>
              api.OperationKind.OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE,
            'set-preferences' =>
              api.OperationKind.OPERATION_KIND_SET_PREFERENCES,
            'reset-preferences' =>
              api.OperationKind.OPERATION_KIND_RESET_PREFERENCES,
            _ => api.OperationKind.OPERATION_KIND_ENROLL,
          },
        );
        // Only UUID generation is deterministic. Preparation, persistence and
        // submission ordering are production code, not a pre-seeded outbox.
        final journal = ClientIntentJournal(
          directory,
          requestIdFactory: () => intent.requestId,
        );
        final runtime = {
          'protocol': api.ClientContract.protocol,
          'contractSha256': api.ClientContract.sha256,
          'instanceId': 'runtime-a',
          'callerAccess': authentication == 'trust'
              ? 'ACCESS_ADMINISTRATOR'
              : 'ACCESS_OWNER',
        };
        final accepted = {
          'id': 'operation-a',
          'requestId': intent.requestId,
          'kind': intent.kind.name,
          'state': 'OPERATION_STATE_PENDING',
        };
        final terminal = switch (authentication) {
          'conflict-resource' => resourceConflictOperation(accepted),
          'failed-exit' => exitFailureOperation(accepted),
          _ => recoveredOperation(accepted),
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
                    'activeProfileId': 'profile-a',
                    'serviceState': 'SERVICE_STATE_DISCONNECTED',
                    'connectionPhase': 'CONNECTION_PHASE_DISCONNECTED',
                  },
                },
              },
            ],
          },
          if (authentication.endsWith('-resource'))
            {
              'method': 'ListResources',
              'request': {
                'profile': {'profileId': 'profile-a'},
                'page': {'pageSize': 100},
                'search': 'synthetic',
                'kinds': ['RESOURCE_KIND_HOST'],
              },
              'responses': [
                {
                  'page': {
                    'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
                  },
                  'resources': [
                    {
                      'id': 'resource-a',
                      'displayName': 'Synthetic host',
                      'networkId': 'network-a',
                      'kind': 'RESOURCE_KIND_HOST',
                      'host': {'hostname': 'synthetic.example'},
                      'enabled': {
                        'requested': authentication == 'disable-resource',
                        'effective': authentication == 'disable-resource',
                      },
                      'overlappingResourceIds': ['visible-outside-query'],
                    },
                  ],
                },
              ],
            },
          if (authentication.endsWith('-exit')) ...[
            {
              'method': 'ListExitNodes',
              'request': {
                'profile': {'profileId': 'profile-a'},
                'page': {'pageSize': 100},
              },
              'responses': [
                {
                  'page': {
                    'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
                  },
                  'exitNodes': [
                    {
                      'id': 'exit-a',
                      'displayName': 'Synthetic exit',
                      'peerId': 'peer-a',
                      'allowedFamilyModes': ['EXIT_FAMILY_MODE_DUAL_STACK'],
                      'allowedLanAccess': ['LAN_ACCESS_BLOCK'],
                    },
                  ],
                },
              ],
            },
            {
              'method': 'GetExitNode',
              'request': {
                'profile': {'profileId': 'profile-a'},
              },
              'responses': [
                {
                  'status': {
                    'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
                    'profileId': 'profile-a',
                    'requestedExitNodeId': 'exit-a',
                    'requestedFamilyMode': 'EXIT_FAMILY_MODE_DUAL_STACK',
                    'applyState': 'APPLY_STATE_FAILED',
                    'failure': {'code': 'ERROR_CODE_UNSUPPORTED'},
                    'ipv4': {
                      'requestedExitNodeId': 'exit-a',
                      'effectiveExitNodeId': 'exit-a',
                      'applyState': 'APPLY_STATE_APPLIED',
                      'failClosed': true,
                    },
                    'ipv6': {
                      'requestedExitNodeId': 'exit-a',
                      'applyState': 'APPLY_STATE_FAILED',
                      'failure': {'code': 'ERROR_CODE_UNSUPPORTED'},
                    },
                  },
                },
              ],
            },
          ],
          if (authentication.endsWith('-preferences')) ...[
            {
              'method': 'GetPreferences',
              'request': {
                'profile': {'profileId': 'profile-a'},
              },
              'responses': [
                {
                  'preferences': {
                    'profileId': 'profile-a',
                    'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
                    'allowInbound': {'effective': true, 'requested': false},
                    'acceptDns': {'effective': true},
                  },
                },
              ],
            },
            {
              'method': 'ListManagedSettings',
              'request': {
                'profile': {'profileId': 'profile-a'},
              },
              'responses': [
                {
                  'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
                  'settings': [
                    {
                      'key': 'PREFERENCE_KEY_ALLOW_INBOUND',
                      'booleanValue': true,
                      'control': {
                        'source': 'SETTING_SOURCE_USER',
                        'mutation': {'availability': 'AVAILABILITY_AVAILABLE'},
                      },
                    },
                  ],
                },
              ],
            },
          ],
          if (authentication == 'trust')
            {
              'method': 'GetServerIdentity',
              'request': {
                'profile': {'profileId': 'profile-a'},
              },
              'responses': [
                {
                  'identity': {
                    'profileId': 'profile-a',
                    'controlOrigin': 'https://control.example',
                    'trustedKeyId': 'old-key',
                    'announcedKeyId': 'new-key',
                    'announcementId': 'announcement-a',
                    'changed': true,
                  },
                  'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
                },
              ],
            },
          {
            'method': switch (authentication) {
              'select-exit' || 'failed-exit' => 'SelectExitNode',
              'clear-exit' => 'ClearExitNode',
              'enable-resource' ||
              'disable-resource' ||
              'conflict-resource' => 'SetResourceEnabled',
              'connect' => 'Connect',
              'trust' => 'TrustServerIdentity',
              'bundle' => 'CreateDiagnosticsBundle',
              'set-preferences' => 'SetPreferences',
              'reset-preferences' => 'ResetPreferences',
              _ => 'Enroll',
            },
            'request': {
              'mutation': {
                'requestId': intent.requestId,
                'expectedInstanceId': 'runtime-a',
                'expectedRevision': '7',
              },
              'profile': {'profileId': 'profile-a'},
              if (authentication == 'select-exit' ||
                  authentication == 'failed-exit') ...{
                'exitNodeId': 'exit-a',
                'familyMode': 'EXIT_FAMILY_MODE_DUAL_STACK',
                'lanAccess': 'LAN_ACCESS_BLOCK',
              },
              if (authentication.endsWith('-resource')) ...{
                'resourceId': 'resource-a',
                'enabled': authentication != 'disable-resource',
              },
              if (authentication == 'set-preferences')
                'patch': {
                  'allowInbound': false,
                  'acceptDns': false,
                  'acceptRoutes': false,
                  'runtimeStart': 'LIFECYCLE_BEHAVIOR_KEEP_INTENT',
                  'uiQuit': 'LIFECYCLE_BEHAVIOR_DISCONNECT',
                  'userLogoff': 'LIFECYCLE_BEHAVIOR_DISCONNECT',
                  'suspend': 'LIFECYCLE_BEHAVIOR_DISCONNECT',
                  'resume': 'LIFECYCLE_BEHAVIOR_CONNECT',
                },
              if (authentication == 'reset-preferences')
                'keys': [
                  'PREFERENCE_KEY_ALLOW_INBOUND',
                  'PREFERENCE_KEY_UI_QUIT',
                ],
              if (authentication == 'trust') ...{
                'confirmedControlOrigin': 'https://control.example',
                'confirmedKeyId': 'new-key',
                'confirmedAnnouncementId': 'announcement-a',
              },
              if (authentication == 'browser' || authentication == 'token') ...{
                'mode': 'ENROLLMENT_MODE_WORKSTATION',
                'hostname': 'device-a',
                if (authentication == 'browser') 'browserLogin': true,
                if (authentication == 'token')
                  'enrollmentToken': 'synthetic-contract-token',
              },
            },
            'responses': [
              {'operation': accepted},
            ],
          },
          {
            'method': 'GetOperation',
            'request': {'requestId': intent.requestId},
            'responses': [
              {'operation': terminal},
            ],
          },
          if (authentication == 'bundle') ...[
            {
              'method': 'GetOperation',
              'request': {'requestId': intent.requestId},
              'responses': [
                {'operation': recoveredOperation(accepted)},
              ],
            },
            {
              'method': 'ReadDiagnosticsBundle',
              'request': {'bundleId': 'bundle-a', 'maxBytes': 65536},
              'responses': [
                {'data': 'AQI=', 'nextOffset': '2'},
              ],
            },
            {
              'method': 'ReadDiagnosticsBundle',
              'request': {
                'bundleId': 'bundle-a',
                'offset': '2',
                'maxBytes': 65536,
              },
              'responses': [
                {'data': 'Aw==', 'nextOffset': '3', 'eof': true},
              ],
            },
          ],
        ], administrator: authentication == 'trust');
        final session = ClientSession(
          journal: journal,
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
          final identity = authentication == 'trust'
              ? (await session.getServerIdentity()).identity
              : null;
          final preferences = authentication.endsWith('-preferences')
              ? await session.getPreferences()
              : null;
          final exits = authentication.endsWith('-exit')
              ? await session.getExitNodes()
              : null;
          final resources = authentication.endsWith('-resource')
              ? await session.listResources(
                  search: 'synthetic',
                  kinds: [api.ResourceKind.RESOURCE_KIND_HOST],
                )
              : null;
          if (resources != null) {
            expect(resources.resources.single.id, 'resource-a');
            expect(resources.resources.single.overlappingResourceIds, [
              'visible-outside-query',
            ]);
          }
          if (preferences != null) {
            expect(preferences.preferences.allowInbound.hasRequested(), isTrue);
            expect(preferences.preferences.allowInbound.requested, isFalse);
            expect(preferences.preferences.acceptDns.hasRequested(), isFalse);
            expect(preferences.managed.single.hasBooleanValue(), isTrue);
          }
          final result = await session.submit(intent.kind, (commands, context) {
            if (exits != null) {
              if (authentication == 'clear-exit') {
                return commands.clearExitNode(
                  api.ClearExitNodeRequest(
                    mutation: context,
                    profile: api.ProfileRef(profileId: exits.status.profileId),
                  ),
                );
              }
              return commands.selectExitNode(
                api.SelectExitNodeRequest(
                  mutation: context,
                  profile: api.ProfileRef(profileId: exits.status.profileId),
                  exitNodeId: exits.nodes.single.id,
                  familyMode: api.ExitFamilyMode.EXIT_FAMILY_MODE_DUAL_STACK,
                  lanAccess: api.LanAccess.LAN_ACCESS_BLOCK,
                ),
              );
            }
            if (resources != null) {
              return commands.setResourceEnabled(
                api.SetResourceEnabledRequest(
                  mutation: context,
                  profile: api.ProfileRef(profileId: resources.profileId),
                  resourceId: resources.resources.single.id,
                  enabled: authentication != 'disable-resource',
                ),
              );
            }
            if (authentication == 'set-preferences') {
              return commands.setPreferences(
                api.SetPreferencesRequest(
                  mutation: context,
                  profile: api.ProfileRef(profileId: 'profile-a'),
                  patch: api.PreferencesPatch(
                    allowInbound: false,
                    acceptDns: false,
                    acceptRoutes: false,
                    runtimeStart:
                        api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_KEEP_INTENT,
                    uiQuit: api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_DISCONNECT,
                    userLogoff:
                        api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_DISCONNECT,
                    suspend:
                        api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_DISCONNECT,
                    resume: api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_CONNECT,
                  ),
                ),
              );
            }
            if (authentication == 'reset-preferences') {
              return commands.resetPreferences(
                api.ResetPreferencesRequest(
                  mutation: context,
                  profile: api.ProfileRef(profileId: 'profile-a'),
                  keys: [
                    api.PreferenceKey.PREFERENCE_KEY_ALLOW_INBOUND,
                    api.PreferenceKey.PREFERENCE_KEY_UI_QUIT,
                  ],
                ),
              );
            }
            if (authentication == 'bundle') {
              return commands.createDiagnosticsBundle(
                api.CreateDiagnosticsBundleRequest(
                  mutation: context,
                  profile: api.ProfileRef(profileId: 'profile-a'),
                ),
              );
            }
            if (identity != null) {
              return commands.trustServerIdentity(
                api.TrustServerIdentityRequest(
                  mutation: context,
                  profile: api.ProfileRef(profileId: identity.profileId),
                  confirmedControlOrigin: identity.controlOrigin,
                  confirmedKeyId: identity.announcedKeyId,
                  confirmedAnnouncementId: identity.announcementId,
                ),
              );
            }
            if (authentication == 'browser' || authentication == 'token') {
              final request = api.EnrollRequest(
                mutation: context,
                profile: api.ProfileRef(profileId: 'profile-a'),
                mode: api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION,
                hostname: 'device-a',
              );
              if (authentication == 'browser') {
                request.browserLogin = true;
              } else {
                request.enrollmentToken = 'synthetic-contract-token';
              }
              return commands.enroll(request);
            }
            return commands.connect(
              api.ConnectRequest(
                mutation: context,
                profile: api.ProfileRef(
                  profileId: session.state.snapshot!.status.activeProfileId,
                ),
              ),
            );
          });
          expect(result.terminal, isFalse);
          final record = File.fromUri(
            directory.uri.resolve('${intent.requestId}.json'),
          );
          expect(jsonDecode(await record.readAsString()), {
            'request_id': intent.requestId,
            'kind': intent.kind.value,
          });
          expect(session.state.link, ClientLinkState.ready);
          // RPC acceptance must not synthesize connected state in the UI.
          expect(
            session.state.snapshot!.status.connectionPhase,
            api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED,
          );
          final recovered = await session.recoverPending();
          expect(
            recovered.single.succeeded,
            authentication != 'conflict-resource' &&
                authentication != 'failed-exit',
          );
          if (exits != null) {
            // Operation recovery cannot replace the last per-family projection.
            expect(exits.status.applyState, api.ApplyState.APPLY_STATE_FAILED);
            expect(exits.status.hasEffectiveExitNodeId(), isFalse);
            expect(exits.status.ipv4.effectiveExitNodeId, 'exit-a');
            expect(exits.status.ipv6.hasEffectiveExitNodeId(), isFalse);
            expect(exits.status.failClosed, isFalse);
            expect(
              (await journal.pending()).single.requestId,
              intent.requestId,
            );
            if (authentication == 'failed-exit') {
              expect(
                recovered.single.value.failure.code,
                api.ErrorCode.ERROR_CODE_UNSUPPORTED,
              );
              expect(
                recovered.single.value.failure.controlRequestId,
                'control-exit-a',
              );
              expect(recovered.single.value.hasSelection(), isFalse);
            } else {
              expect(recovered.single.value.hasSelection(), isTrue);
              expect(
                recovered.single.value.selection.selectedId,
                authentication == 'clear-exit' ? '' : 'exit-a',
              );
            }
          }
          if (authentication == 'conflict-resource') {
            expect(
              recovered.single.value.state,
              api.OperationState.OPERATION_STATE_FAILED,
            );
            expect(
              recovered.single.value.failure.code,
              api.ErrorCode.ERROR_CODE_RESOURCE_CONFLICT,
            );
            expect(recovered.single.value.requestId, intent.requestId);
            expect(
              recovered.single.value.failure.controlRequestId,
              'control-resource-a',
            );
          }
          if (resources != null) {
            expect(
              resources.resources.single.enabled.effective,
              authentication == 'disable-resource',
            );
            expect(
              (await journal.pending()).single.requestId,
              intent.requestId,
            );
          }
          expect(recovered.single.value.id, result.value.id);
          if (preferences != null) {
            // A scripted success is not a fresh effective-settings projection.
            expect(preferences.preferences.allowInbound.effective, isTrue);
            expect(preferences.preferences.allowInbound.requested, isFalse);
            expect(
              (await journal.pending()).single.requestId,
              intent.requestId,
            );
          }
          if (authentication == 'bundle') {
            expect(await session.readDiagnosticsBundle(intent.requestId), [
              1,
              2,
              3,
            ]);
            expect(
              (await journal.pending()).single.requestId,
              intent.requestId,
            );
          }
          await journal.acknowledge(recovered.single);
          expect(await journal.pending(), isEmpty);
          await session.close();
          await host.verify();
        } finally {
          await session.close();
          await host.close();
        }
      },
      skip: executable == null
          ? 'Requires pinned held-open producer fixture in CI'
          : false,
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
