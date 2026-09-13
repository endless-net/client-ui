import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:endlessnet/client_bundle_export.dart';

import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_mutations.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_privileged_recovery.dart';
import 'dart:convert';
import 'package:endlessnet/client_profiles.dart';
import 'package:endlessnet/client_networks.dart';
import 'package:endlessnet/client_preferences.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_session_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

class NoCallsClient implements api.ClientServiceClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected RPC');
}

class FakeConnection implements ClientConnection {
  Future<ClientPreferences> Function(String, void Function())? preferences;
  @override
  Future<ClientPreferences> getPreferences(
    String profileId,
    void Function() checkContext,
  ) => preferences!(profileId, checkContext);
  Future<ClientOperation> Function(String, api.OperationKind)? lookup;
  @override
  Future<ClientOperation> recoverOperation(String id, api.OperationKind kind) =>
      lookup!(id, kind);
  Future<api.ReadDiagnosticsBundleResponse> Function(
    api.ReadDiagnosticsBundleRequest,
  )?
  chunks;
  @override
  Future<api.ReadDiagnosticsBundleResponse> readDiagnosticsBundle(
    api.ReadDiagnosticsBundleRequest request,
  ) => chunks!(request);
  Future<api.GetDiagnosticsResponse> Function(String)? diagnostics;
  @override
  Future<api.GetDiagnosticsResponse> getDiagnostics(String profileId) =>
      diagnostics!(profileId);
  Future<api.GetServerIdentityResponse> Function(String)? identity;
  @override
  Future<api.GetServerIdentityResponse> getServerIdentity(String profileId) =>
      identity!(profileId);
  Future<ClientNetworkCatalog> Function(String profileId)? networks;
  @override
  Future<ClientNetworkCatalog> listNetworks(String profileId) =>
      networks!(profileId);
  Future<ClientProfileCatalog> Function()? profiles;
  @override
  Future<ClientProfileCatalog> listProfiles() => profiles!();
  final events = StreamController<api.WatchEventsResponse>();
  bool closed = false;
  @override
  ClientMutations mutations = ClientMutations(
    NoCallsClient(),
    instanceId: 'runtime-a',
  );
  @override
  Stream<api.WatchEventsResponse> watch() => events.stream;
  @override
  Future<void> close() async {
    closed = true;
    await events.close();
  }
}

class FailedWatchConnection extends FakeConnection {
  int closeCalls = 0;
  @override
  Stream<api.WatchEventsResponse> watch() =>
      throw const FormatException('Synthetic watch setup failure');
  @override
  Future<void> close() async {
    closeCalls++;
    closed = true;
    // No subscription was created. Do not await an unlistened controller.
    unawaited(events.close());
  }
}

api.WatchEventsResponse snapshot() =>
    api.WatchEventsResponse()..mergeFromProto3Json({
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
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
        },
      },
    });

ClientOperation accepted(api.MutationContext context) =>
    ClientOperation.fromProto(
      api.Operation(
        id: 'operation-a',
        requestId: context.requestId,
        kind: api.OperationKind.OPERATION_KIND_CONNECT,
        state: api.OperationState.OPERATION_STATE_PENDING,
      ),
    );

void main() {
  test(
    'US-07: explicit bundle export never overwrites and cleans cancelled output',
    () async {
      final destination = await Directory.systemTemp.createTemp(
        'en-export-test-',
      );
      try {
        final existing = File.fromUri(
          destination.uri.resolve('diagnostics.zip'),
        );
        await existing.writeAsString('keep');
        final input = Uint8List.fromList([1, 2, 3]);
        final first = await exportClientBundle(
          destination,
          input,
          checkContext: () {},
        );
        final second = await exportClientBundle(
          destination,
          input,
          checkContext: () {},
        );
        expect(first.path, isNot(second.path));
        expect(await first.readAsBytes(), [1, 2, 3]);
        expect(await second.readAsBytes(), [1, 2, 3]);
        expect(await existing.readAsString(), 'keep');
        final before = await destination.list().length;
        var checks = 0;
        await expectLater(
          exportClientBundle(
            destination,
            input,
            checkContext: () {
              if (++checks == 3) {
                throw StateError('Context expired after write');
              }
            },
          ),
          throwsStateError,
        );
        expect(await destination.list().length, before);
        await expectLater(
          exportClientBundle(Directory('relative'), input, checkContext: () {}),
          throwsArgumentError,
        );
      } finally {
        await destination.delete(recursive: true);
      }
    },
  );

  late Directory directory;
  late FakeConnection connection;
  late ClientSession session;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('en-session-');
    connection = FakeConnection();
    session = ClientSession(
      journal: ClientIntentJournal(directory),
      open: () async => connection,
    );
    await session.connect();
  });
  tearDown(() async {
    await session.close();
    await directory.delete(recursive: true);
  });

  test(
    'privileged recovery journals before launch and retains ambiguous outcomes',
    () async {
      connection.events.add(
        snapshot()..snapshot.status.activeProfileId = 'profile-a',
      );
      await pumpEventQueue();
      const kind = api.OperationKind.OPERATION_KIND_TRUST_SERVER_IDENTITY;
      var calls = 0;
      Future<ClientOperation> send() => session.submitPrivileged(
        kind,
        (mutation) => ClientPrivilegedRecovery.trust(
          api.TrustServerIdentityRequest(
            mutation: mutation,
            profile: api.ProfileRef(profileId: 'profile-a'),
            confirmedControlOrigin: 'https://control.test',
            confirmedKeyId: 'key',
            confirmedAnnouncementId: 'a' * 64,
          ),
        ),
        (request) async {
          calls++;
          expect(
            (await session.journal.pending()).single.requestId,
            request.mutation.requestId,
          );
          expect(
            request.arguments,
            containsAll([
              '--confirmed-announcement-id',
              'a' * 64,
              '--expected-revision',
              '7',
            ]),
          );
          return (
            0,
            jsonEncode({
              'id': 'operation',
              'requestId': request.mutation.requestId,
              'profileId': 'profile-a',
              'kind': kind.name,
              'state': 'OPERATION_STATE_PENDING',
              'metadata': {'instanceId': 'runtime-a', 'revision': '8'},
            }),
          );
        },
      );
      final accepted = await send();
      expect(accepted.terminal, false);
      await expectLater(send(), throwsStateError);
      expect(calls, 1);
      expect(await session.journal.pending(), hasLength(1));
    },
  );

  test(
    'US-10: preferences reject observer, stale and invalidated reads',
    () async {
      await expectLater(session.getPreferences(), throwsStateError);
      connection.events.add(
        snapshot()..snapshot.status.activeProfileId = 'profile-a',
      );
      await pumpEventQueue();
      final response = api.GetPreferencesResponse()
        ..mergeFromProto3Json({
          'preferences': {
            'profileId': 'profile-a',
            'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            'allowInbound': {'requested': false},
          },
        });
      final policy = api.ListManagedSettingsResponse()
        ..mergeFromProto3Json({
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
        });
      Future<ClientPreferences> read(String id, void Function() check) =>
          readClientPreferences(
            instanceId: 'runtime-a',
            profileId: id,
            get: (_) async => response,
            listManaged: (_) async => policy,
            checkContext: check,
          );
      connection.preferences = read;
      expect(
        (await session.getPreferences()).preferences.allowInbound
            .hasRequested(),
        isTrue,
      );
      final domains = [
        'DOMAIN_PREFERENCES',
        'DOMAIN_PREFERENCES',
        'DOMAIN_MANAGED_SETTINGS',
        'DOMAIN_PROFILES',
      ];
      for (var i = 0; i < domains.length; i++) {
        final pending = Completer<api.ListManagedSettingsResponse>();
        connection.preferences = (id, check) => readClientPreferences(
          instanceId: 'runtime-a',
          profileId: id,
          get: (_) async => response,
          listManaged: (_) => pending.future,
          checkContext: check,
        );
        final rejected = expectLater(
          session.getPreferences(),
          throwsStateError,
        );
        await pumpEventQueue();
        connection.events.add(
          api.WatchEventsResponse()..mergeFromProto3Json({
            'sequence': '${i + 2}',
            'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            'invalidated': {'domain': domains[i], 'profileId': 'profile-a'},
          }),
        );
        await pumpEventQueue();
        pending.complete(policy);
        await rejected;
        connection.preferences = read;
        await session.getPreferences();
      }
      response.preferences.metadata.revision -= 1;
      policy.metadata.revision -= 1;
      await expectLater(session.getPreferences(), throwsStateError);
      final observer = snapshot()..sequence += 5;
      observer.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      connection.events.add(observer);
      await pumpEventQueue();
      connection.preferences = (_, _) =>
          throw TestFailure('Observer cannot read preferences');
      await expectLater(session.getPreferences(), throwsStateError);
      expect(await session.journal.pending(), isEmpty);
    },
  );

  test(
    'US-07: bundle download rechecks operation and context without acknowledging',
    () async {
      const requestId = 'c06bd29f-7c77-4b27-943a-620081f313df';
      await expectLater(
        session.readDiagnosticsBundle(requestId),
        throwsStateError,
      );
      connection.events.add(
        snapshot()..snapshot.status.activeProfileId = 'profile-a',
      );
      await pumpEventQueue();
      var lookups = 0;
      var succeeded = true;
      connection.lookup = (id, kind) async {
        expect(id, requestId);
        expect(
          kind,
          api.OperationKind.OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE,
        );
        lookups++;
        final response = api.GetOperationResponse()
          ..mergeFromProto3Json({
            'operation': {
              'id': 'bundle-operation',
              'requestId': requestId,
              'kind': 'OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE',
              'state': succeeded
                  ? 'OPERATION_STATE_SUCCEEDED'
                  : 'OPERATION_STATE_PENDING',
              if (succeeded) ...{
                'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
                'bundle': {
                  'bundleId': 'fresh-handle',
                  'sizeBytes': '3',
                  'expiresAt': '2099-01-01T00:00:00Z',
                  'sha256':
                      '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
                },
              },
            },
          });
        return ClientMutations.validateAcceptance(response.operation, id, kind);
      };
      connection.chunks = (request) async {
        expect(request.bundleId, 'fresh-handle');
        return api.ReadDiagnosticsBundleResponse()..mergeFromProto3Json({
          'data': 'AQID',
          'nextOffset': '3',
          'eof': true,
        });
      };
      expect(await session.readDiagnosticsBundle(requestId), [1, 2, 3]);
      final destination = await Directory.systemTemp.createTemp(
        'en-session-export-',
      );
      addTearDown(() => destination.delete(recursive: true));
      final exported = await session.exportDiagnosticsBundle(
        requestId,
        destination,
      );
      expect(await exported.readAsBytes(), [1, 2, 3]);
      expect(exported.parent.parent.path, destination.path);
      final successfulRead = connection.chunks;
      connection.chunks = (_) async => api.ReadDiagnosticsBundleResponse()
        ..mergeFromProto3Json({'data': 'AQIE', 'nextOffset': '3', 'eof': true});
      await expectLater(
        session.exportDiagnosticsBundle(requestId, destination),
        throwsFormatException,
      );
      expect(await destination.list().length, 1);
      connection.chunks = successfulRead;
      succeeded = false;
      await expectLater(
        session.readDiagnosticsBundle(requestId),
        throwsStateError,
      );
      expect(lookups, 4);
      succeeded = true;
      final pending = Completer<api.ReadDiagnosticsBundleResponse>();
      connection.chunks = (_) => pending.future;
      final rejected = expectLater(
        session.exportDiagnosticsBundle(requestId, destination),
        throwsStateError,
      );
      await pumpEventQueue();
      final observer = snapshot()..sequence += 1;
      observer.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      connection.events.add(observer);
      await pumpEventQueue();
      pending.complete(
        api.ReadDiagnosticsBundleResponse()..mergeFromProto3Json({
          'data': 'AQID',
          'nextOffset': '3',
          'eof': true,
        }),
      );
      await rejected;
      await expectLater(
        session.readDiagnosticsBundle(requestId),
        throwsStateError,
      );
      expect(lookups, 5);
      expect(await destination.list().length, 1);
    },
  );

  test(
    'US-07: diagnostics preview rejects stale context and freezes its copy',
    () async {
      await expectLater(session.getDiagnostics(), throwsStateError);
      connection.events.add(
        snapshot()..snapshot.status.activeProfileId = 'profile-a',
      );
      await pumpEventQueue();
      api.GetDiagnosticsResponse response() =>
          api.GetDiagnosticsResponse()..mergeFromProto3Json({
            'diagnostics': {
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
              'osName': 'synthetic-os',
              'truncated': true,
              'status': {
                'activeProfileId': 'profile-a',
                'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
              },
            },
          });
      final original = response();
      connection.diagnostics = (id) async {
        expect(id, 'profile-a');
        return original;
      };
      final preview = await session.getDiagnostics();
      original.diagnostics.osName = 'changed';
      expect(preview.osName, 'synthetic-os');
      expect(preview.truncated, isTrue);
      expect(preview.isFrozen, isTrue);
      for (final mutate in <void Function(api.GetDiagnosticsResponse)>[
        (r) => r.clearDiagnostics(),
        (r) => r.diagnostics.clearMetadata(),
        (r) => r.diagnostics.metadata.instanceId = 'runtime-b',
        (r) => r.diagnostics.metadata.revision -= 1,
        (r) => r.diagnostics.status.metadata.revision += 1,
        (r) => r.diagnostics.status.activeProfileId = 'profile-b',
      ]) {
        final invalid = response();
        mutate(invalid);
        connection.diagnostics = (_) async => invalid;
        await expectLater(session.getDiagnostics(), throwsStateError);
      }
      for (var i = 0; i < 2; i++) {
        final pending = Completer<api.GetDiagnosticsResponse>();
        connection.diagnostics = (_) => pending.future;
        final rejected = expectLater(
          session.getDiagnostics(),
          throwsStateError,
        );
        connection.events.add(
          api.WatchEventsResponse()..mergeFromProto3Json({
            'sequence': '${i + 2}',
            'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            'invalidated': {'domain': 'DOMAIN_PEERS', 'profileId': 'profile-a'},
          }),
        );
        await pumpEventQueue();
        pending.complete(response());
        await rejected;
      }
      final observer = snapshot()..sequence += 3;
      observer.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      connection.events.add(observer);
      await pumpEventQueue();
      connection.diagnostics = (_) =>
          throw TestFailure('Observer cannot request diagnostics');
      await expectLater(session.getDiagnostics(), throwsStateError);
      expect(await session.journal.pending(), isEmpty);
    },
  );

  test(
    'US-06: identity read binds profile, metadata and immutable result',
    () async {
      await expectLater(session.getServerIdentity(), throwsStateError);
      connection.events.add(
        snapshot()..snapshot.status.activeProfileId = 'profile-a',
      );
      await pumpEventQueue();
      final response = api.GetServerIdentityResponse()
        ..mergeFromProto3Json({
          'identity': {
            'profileId': 'profile-a',
            'controlOrigin': 'https://control.example',
            'announcedKeyId': 'key-a',
            'announcementId': 'announcement-a',
          },
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
        });
      connection.identity = (id) async {
        expect(id, 'profile-a');
        return response;
      };
      final result = await session.getServerIdentity();
      response.identity.announcementId = 'announcement-b';
      expect(result.identity.announcementId, 'announcement-a');
      expect(result.isFrozen, isTrue);
      for (final change in <void Function(api.GetServerIdentityResponse)>[
        (r) => r.clearIdentity(),
        (r) => r.clearMetadata(),
        (r) => r.identity.profileId = 'profile-b',
        (r) => r.metadata.instanceId = 'runtime-b',
        (r) => r.metadata.revision -= 1,
      ]) {
        final invalid = api.GetServerIdentityResponse.fromBuffer(
          response.writeToBuffer(),
        );
        change(invalid);
        connection.identity = (_) async => invalid;
        await expectLater(session.getServerIdentity(), throwsStateError);
      }
      final observer = snapshot()..sequence += 1;
      observer.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      connection.events.add(observer);
      await pumpEventQueue();
      connection.identity = (_) =>
          throw TestFailure('Observer must not call RPC');
      await expectLater(session.getServerIdentity(), throwsStateError);
    },
  );

  test(
    'US-06: repeated identity invalidation and profile change reject late reads',
    () async {
      connection.events.add(
        snapshot()..snapshot.status.activeProfileId = 'profile-a',
      );
      await pumpEventQueue();
      final response = api.GetServerIdentityResponse()
        ..mergeFromProto3Json({
          'identity': {'profileId': 'profile-a'},
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
        });
      for (var i = 0; i < 3; i++) {
        final pending = Completer<api.GetServerIdentityResponse>();
        connection.identity = (_) => pending.future;
        final rejected = expectLater(
          session.getServerIdentity(),
          throwsStateError,
        );
        connection.events.add(
          api.WatchEventsResponse()..mergeFromProto3Json({
            'sequence': '${i + 2}',
            'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            'invalidated': {
              'domain': i == 2 ? 'DOMAIN_PROFILES' : 'DOMAIN_SERVER_IDENTITY',
              'profileId': 'profile-a',
            },
          }),
        );
        await pumpEventQueue();
        pending.complete(response);
        await rejected;
        connection.identity = (_) async => response;
        expect(
          (await session.getServerIdentity()).identity.profileId,
          'profile-a',
        );
      }
      final pending = Completer<api.GetServerIdentityResponse>();
      connection.identity = (_) => pending.future;
      final rejected = expectLater(
        session.getServerIdentity(),
        throwsStateError,
      );
      final changed = snapshot()..sequence += 4;
      changed.snapshot.status.activeProfileId = 'profile-b';
      connection.events.add(changed);
      await pumpEventQueue();
      pending.complete(response);
      await rejected;
    },
  );

  test(
    'US-04: networks bind active profile and reject repeated invalidations',
    () async {
      await expectLater(session.listNetworks(), throwsStateError);
      final initial = snapshot()..snapshot.status.activeProfileId = 'profile-a';
      connection.events.add(initial);
      await pumpEventQueue();
      final catalog = await readClientNetworks(
        (_) async => api.ListNetworksResponse()
          ..mergeFromProto3Json({
            'page': {
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            },
          }),
        instanceId: 'runtime-a',
        profileId: 'profile-a',
      );
      for (var repeat = 0; repeat < 2; repeat++) {
        final response = Completer<ClientNetworkCatalog>();
        connection.networks = (id) {
          expect(id, 'profile-a');
          return response.future;
        };
        final rejected = expectLater(session.listNetworks(), throwsStateError);
        connection.events.add(
          api.WatchEventsResponse()..mergeFromProto3Json({
            'sequence': '${repeat + 2}',
            'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            'invalidated': {
              'domain': 'DOMAIN_NETWORKS',
              'profileId': 'profile-a',
            },
          }),
        );
        await pumpEventQueue();
        response.complete(catalog);
        await rejected;
        connection.networks = (_) async => catalog;
        expect(await session.listNetworks(), same(catalog));
      }
      final response = Completer<ClientNetworkCatalog>();
      connection.networks = (_) => response.future;
      final rejected = expectLater(session.listNetworks(), throwsStateError);
      final changed = snapshot()..sequence += 3;
      changed.snapshot.status.activeProfileId = 'profile-b';
      connection.events.add(changed);
      await pumpEventQueue();
      response.complete(catalog);
      await rejected;
      connection.networks = (_) async => catalog;
      await expectLater(session.listNetworks(), throwsStateError);
    },
  );

  testWidgets(
    'US-14: composed session panel remains scrollable with large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      connection.events.add(snapshot());
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2),
              padding: EdgeInsets.only(top: 59, bottom: 34),
            ),
            child: Scaffold(body: ClientSessionPanel(session: session)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('client-load-profiles')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('client-load-profiles')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'US-03: acceptance snapshot refresh does not invalidate RPC result',
    () async {
      connection.events.add(snapshot());
      await pumpEventQueue();
      final cacheEpoch = session.state.cacheEpoch;
      final contextEpoch = session.state.contextEpoch;
      final result = await session.submit(
        api.OperationKind.OPERATION_KIND_CONNECT,
        (_, context) async {
          final refresh = snapshot()..sequence += 1;
          refresh.metadata.revision += 1;
          refresh.snapshot.status.metadata.revision += 1;
          connection.events.add(refresh);
          await pumpEventQueue();
          return accepted(context);
        },
      );
      expect(result.value.kind, api.OperationKind.OPERATION_KIND_CONNECT);
      expect(session.state.cacheEpoch, greaterThan(cacheEpoch));
      expect(session.state.contextEpoch, contextEpoch);
      expect(await session.journal.pending(), hasLength(1));
    },
  );

  test(
    'US-03: real profile change still makes in-flight result recoverable',
    () async {
      connection.events.add(snapshot());
      await pumpEventQueue();
      await expectLater(
        session.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
          _,
          context,
        ) async {
          final changed = snapshot()..sequence += 1;
          changed.metadata.revision += 1;
          changed.snapshot.status.metadata.revision += 1;
          changed.snapshot.status.activeProfileId = 'different-profile';
          connection.events.add(changed);
          await pumpEventQueue();
          return accepted(context);
        }),
        throwsStateError,
      );
      expect(await session.journal.pending(), hasLength(1));
    },
  );

  test(
    'US-08: catalog requires snapshot and rejects a late caller-context result',
    () async {
      var calls = 0;
      final result = Completer<ClientProfileCatalog>();
      connection.profiles = () {
        calls++;
        return result.future;
      };
      await expectLater(session.listProfiles(), throwsStateError);
      expect(calls, 0);
      connection.events.add(snapshot());
      await pumpEventQueue();
      final query = session.listProfiles();
      final rejection = expectLater(query, throwsStateError);
      final observer = snapshot()..sequence += 1;
      observer.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      connection.events.add(observer);
      await pumpEventQueue();
      result.complete(
        await readClientProfiles(
          (_) async => api.ListProfilesResponse()
            ..mergeFromProto3Json({
              'page': {
                'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
              },
            }),
          instanceId: 'runtime-a',
        ),
      );
      await rejection;
      expect(calls, 1);
      await expectLater(session.listProfiles(), throwsStateError);
      expect(calls, 1);
    },
  );

  test(
    'US-08: owner receives a complete current catalog, never an older revision',
    () async {
      connection.events.add(snapshot());
      await pumpEventQueue();
      var revision = '7';
      connection.profiles = () => readClientProfiles(
        (_) async => api.ListProfilesResponse()
          ..mergeFromProto3Json({
            'page': {
              'metadata': {'instanceId': 'runtime-a', 'revision': revision},
            },
          }),
        instanceId: 'runtime-a',
      );
      expect((await session.listProfiles()).profiles, isEmpty);
      revision = '6';
      await expectLater(session.listProfiles(), throwsStateError);
    },
  );

  test(
    'US-08: each profiles invalidation rejects an in-flight catalog',
    () async {
      connection.events.add(snapshot());
      await pumpEventQueue();
      final catalog = await readClientProfiles(
        (_) async => api.ListProfilesResponse()
          ..mergeFromProto3Json({
            'page': {
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            },
          }),
        instanceId: 'runtime-a',
      );
      for (var repeat = 0; repeat < 2; repeat++) {
        final result = Completer<ClientProfileCatalog>();
        connection.profiles = () => result.future;
        final rejected = expectLater(session.listProfiles(), throwsStateError);
        connection.events.add(
          api.WatchEventsResponse()..mergeFromProto3Json({
            'sequence': '${repeat + 2}',
            'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            'invalidated': {'domain': 'DOMAIN_PROFILES'},
          }),
        );
        await pumpEventQueue();
        result.complete(catalog);
        await rejected;
        connection.profiles = () async => catalog;
        expect(await session.listProfiles(), same(catalog));
      }
    },
  );

  test(
    'US-01: failed watch releases bootstrapped channel before retry',
    () async {
      await session.close();
      final failed = FailedWatchConnection();
      final replacement = FakeConnection();
      var attempts = 0;
      session = ClientSession(
        journal: ClientIntentJournal(directory),
        open: () async => attempts++ == 0 ? failed : replacement,
      );
      await expectLater(session.connect(), throwsFormatException);
      await pumpEventQueue();
      expect(failed.closeCalls, 1);
      expect(session.state.link, ClientLinkState.unavailable);
      expect(session.state.snapshot, isNull);
      await session.connect();
      replacement.events.add(snapshot());
      await pumpEventQueue();
      expect(failed.closeCalls, 1);
      expect(session.state.link, ClientLinkState.ready);
      expect(replacement.closed, isFalse);
    },
  );

  test(
    'US-01/03: bootstrap alone cannot submit; snapshot context is journaled before send',
    () async {
      await expectLater(
        session.submit(
          api.OperationKind.OPERATION_KIND_CONNECT,
          (_, context) async => accepted(context),
        ),
        throwsStateError,
      );
      expect(await session.journal.pending(), isEmpty);
      connection.events.add(snapshot());
      await pumpEventQueue();
      final result = await session.submit(
        api.OperationKind.OPERATION_KIND_CONNECT,
        (_, context) async {
          expect(context.expectedInstanceId, 'runtime-a');
          expect(context.expectedRevision.toString(), '7');
          expect(
            (await ClientIntentJournal(directory).pending()).single.requestId,
            context.requestId,
          );
          return accepted(context);
        },
      );
      expect(result.terminal, isFalse);
      expect(await session.journal.pending(), hasLength(1));
      await expectLater(
        session.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
          _,
          context,
        ) async {
          fail('Accepted work must be recovered, not submitted again');
        }),
        throwsStateError,
      );
      expect(await session.journal.pending(), hasLength(1));
    },
  );

  test(
    'US-03: transport timeout preserves request identity without resubmitting',
    () async {
      connection.events.add(snapshot());
      await pumpEventQueue();
      var calls = 0;
      await expectLater(
        session.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
          _,
          context,
        ) async {
          calls++;
          throw TimeoutException('synthetic');
        }),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 1);
      expect(await session.journal.pending(), hasLength(1));
      await expectLater(
        session.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
          _,
          context,
        ) async {
          calls++;
          return accepted(context);
        }),
        throwsStateError,
      );
      expect(calls, 1);
    },
  );

  test(
    'US-03: overlapping submissions do not allocate a second intention',
    () async {
      connection.events.add(snapshot());
      await pumpEventQueue();
      final release = Completer<void>();
      final first = session.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
        _,
        context,
      ) async {
        await release.future;
        return accepted(context);
      });
      await expectLater(
        session.submit(
          api.OperationKind.OPERATION_KIND_CONNECT,
          (_, context) async => accepted(context),
        ),
        throwsStateError,
      );
      release.complete();
      await first;
      expect(await session.journal.pending(), hasLength(1));
    },
  );

  test(
    'US-03: late acceptance after stream loss is not shown in the current context',
    () async {
      connection.events.add(snapshot());
      await pumpEventQueue();
      await expectLater(
        session.submit(api.OperationKind.OPERATION_KIND_CONNECT, (
          _,
          context,
        ) async {
          await connection.events.close();
          await pumpEventQueue();
          return accepted(context);
        }),
        throwsStateError,
      );
      expect(session.state.link, ClientLinkState.unavailable);
      expect(await session.journal.pending(), hasLength(1));
    },
  );
}
