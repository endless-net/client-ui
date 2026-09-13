import 'package:endlessnet/client_profiles.dart';
import 'package:endlessnet/client_networks.dart';
import 'package:endlessnet/client_resources.dart';
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

void main() {
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
            body: ClientNetworksPanel(
              state: state,
              load: () => readClientNetworks(
                (_) async => api.ListNetworksResponse()
                  ..mergeFromProto3Json({
                    'networks': [
                      {'id': 'network-a', 'name': 'A'},
                      {
                        'id': 'network-b',
                        'name': 'B',
                        'selection': {'availability': 'AVAILABILITY_AVAILABLE'},
                      },
                      {'id': 'network-c', 'name': 'C'},
                    ],
                    'selectedNetworkId': 'network-a',
                    'page': {
                      'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
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
      await tester.tap(find.byKey(const Key('select-network-network-b')));
      await tester.pump();
      expect(calls, [('profile-a', 'network-b')]);
      expect(state.snapshot!.status.network.id, 'network-a');
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
      await tester.pump();
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
            body: ClientProfilesPanel(
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
      await tester.tap(find.byKey(const Key('client-load-profiles')));
      await tester.pump();
      expect(find.text('Profile b'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('remove-profile-a')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('remove-profile-b')));
      await tester.pump();
      expect(removed, isEmpty);
      await tester.tap(find.byKey(const Key('cancel-profile-removal')));
      await tester.pump();
      expect(removed, isEmpty);
      await tester.tap(find.byKey(const Key('remove-profile-b')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirm-profile-removal')));
      await tester.pump();
      expect(removed, ['b']);
      expect(find.text('Profile b'), findsNothing);
      expect(state.snapshot!.status.activeProfileId, 'a');
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
      await tester.tap(renameButton);
      await tester.pump();
      expect(renamed, [('b', 'Новое имя')]);
      expect(find.text('Новое имя'), findsNothing);
      expect(find.text('Profile b'), findsNothing);
      await tester.tap(find.byKey(const Key('client-load-profiles')));
      await tester.pump();
      for (var repeat = 0; repeat < 2; repeat++) {
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
        await tester.tap(find.byKey(const Key('client-load-profiles')));
        await tester.pump();
        expect(find.text('Profile b'), findsOneWidget);
      }
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
