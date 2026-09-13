@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_profiles.dart';
import 'package:endlessnet/client_profiles_panel.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

api.WatchEventsResponse _snapshot(int sequence) =>
    api.WatchEventsResponse()..mergeFromProto3Json({
      'sequence': '$sequence',
      'metadata': {'instanceId': 'runtime-a', 'revision': '$sequence'},
      'snapshot': {
        'runtime': {
          'protocol': api.ClientContract.protocol,
          'contractSha256': api.ClientContract.sha256,
          'instanceId': 'runtime-a',
          'callerAccess': 'ACCESS_OWNER',
        },
        'status': {
          'metadata': {'instanceId': 'runtime-a', 'revision': '$sequence'},
        },
      },
    });

Future<ClientProfileCatalog> _catalog() => readClientProfiles(
  (_) async => api.ListProfilesResponse()
    ..mergeFromProto3Json({
      'profiles': [
        for (final id in ['a', 'b'])
          {
            'id': id,
            'displayName': 'Profile $id',
            'state': 'PROFILE_STATE_EMPTY',
            'selection': {'availability': 'AVAILABILITY_AVAILABLE'},
          },
      ],
      'page': {
        'metadata': {'instanceId': 'runtime-a', 'revision': '1'},
      },
    }),
  instanceId: 'runtime-a',
);

void main() {
  testWidgets(
    'US-08 old profile lookup cannot populate replacement controller',
    (tester) async {
      final states = [ClientStateController(), ClientStateController()];
      final sources = [
        StreamController<api.WatchEventsResponse>(),
        StreamController<api.WatchEventsResponse>(),
      ];
      for (var i = 0; i < states.length; i++) {
        await states[i].attach(sources[i].stream);
        sources[i].add(_snapshot(1));
      }
      final pending = Completer<ClientProfileCatalog>();
      var loads = 0;
      Future<ClientOperation> unexpected(String _) async =>
          throw StateError('No mutation expected');
      Future<void> render(ClientStateController state) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ClientProfilesPanel(
                state: state,
                load: () => ++loads == 1 ? pending.future : _catalog(),
                select: unexpected,
                remove: unexpected,
                rename: (id, _) => unexpected(id),
              ),
            ),
          ),
        ),
      );
      await render(states.first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('client-load-profiles')));
      await tester.pump();
      await render(states.last);
      pending.complete(await _catalog());
      await tester.pumpAndSettle();
      expect(find.text('Profile a'), findsNothing);
      expect(loads, 1);
      await tester.tap(find.byKey(const Key('client-load-profiles')));
      await tester.pumpAndSettle();
      expect(find.text('Profile a'), findsOneWidget);
      expect(loads, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        for (var i = 0; i < states.length; i++) {
          await states[i].detach();
          await sources[i].close();
          states[i].dispose();
        }
      });
    },
  );
  for (final scenario in [
    'reload',
    'snapshot',
    'rename',
    'retarget removal',
    'reconfirm removal',
    'removal snapshot',
  ]) {
    testWidgets('US-08 profile queued activation: $scenario', (tester) async {
      final state = ClientStateController();
      final source = StreamController<api.WatchEventsResponse>();
      await state.attach(source.stream);
      final calls = <String>[];
      Future<ClientOperation> submit(String action) async {
        calls.add(action);
        return ClientOperation.fromProto(
          api.Operation(
            id: 'operation',
            requestId: 'request',
            kind: api.OperationKind.OPERATION_KIND_SELECT_PROFILE,
            state: api.OperationState.OPERATION_STATE_PENDING,
          ),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ClientProfilesPanel(
                state: state,
                load: _catalog,
                select: (id) => submit('select:$id'),
                rename: (id, name) => submit('rename:$id:$name'),
                remove: (id) => submit('remove:$id'),
              ),
            ),
          ),
        ),
      );
      source.add(_snapshot(1));
      await tester.pumpAndSettle();
      Future<void> tap(String key) async {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
      }

      VoidCallback callback(String key) =>
          tester.widget<TextButton>(find.byKey(Key(key))).onPressed!;
      await tap('client-load-profiles');
      if (scenario == 'reload' || scenario == 'snapshot') {
        final old = callback('select-profile-a');
        if (scenario == 'reload') {
          await tap('client-load-profiles');
        } else {
          source.add(_snapshot(2));
          await tester.pumpAndSettle();
        }
        old();
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        if (scenario == 'snapshot') await tap('client-load-profiles');
        await tap('select-profile-a');
        expect(calls, ['select:a']);
      } else if (scenario == 'rename') {
        await tester.enterText(
          find.byKey(const Key('client-profile-name')),
          'Old name',
        );
        await tester.pumpAndSettle();
        final old = callback('rename-profile-a');
        await tester.enterText(
          find.byKey(const Key('client-profile-name')),
          'New name',
        );
        await tester.pumpAndSettle();
        old();
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        await tap('rename-profile-a');
        expect(calls, ['rename:a:New name']);
      } else {
        await tap('remove-profile-a');
        final oldConfirm = callback('confirm-profile-removal');
        final oldCancel = callback('cancel-profile-removal');
        if (scenario == 'removal snapshot') {
          source.add(_snapshot(2));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('confirm-profile-removal')),
            findsNothing,
          );
          await tap('client-load-profiles');
        } else {
          await tap('cancel-profile-removal');
        }
        final next = scenario == 'retarget removal' ? 'b' : 'a';
        await tap('remove-profile-$next');
        oldConfirm();
        oldCancel();
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        expect(
          find.byKey(const Key('confirm-profile-removal')),
          findsOneWidget,
        );
        await tap('confirm-profile-removal');
        expect(calls, ['remove:$next']);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await state.detach();
        await source.close();
        state.dispose();
      });
    });
  }
}
