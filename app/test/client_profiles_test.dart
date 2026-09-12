import 'package:endlessnet/client_profiles.dart';
import 'dart:async';
import 'package:endlessnet/client_profiles_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:flutter/material.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

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

void main() {
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
          home: Scaffold(
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
