@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_exit_nodes.dart';
import 'package:endlessnet/client_exit_panel.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

api.WatchEventsResponse snapshot(int sequence) {
  final value = fixtures.snapshot(sequence);
  value.snapshot.runtime.mergeFromProto3Json({
    'capabilities': [
      {
        'capability': 'CAPABILITY_EXIT_NODE',
        'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
      },
    ],
  });
  return value;
}

Future<ClientExitNodes> catalog() => readClientExitNodes(
  instanceId: 'runtime-a',
  profileId: 'profile-a',
  checkContext: () {},
  list: (_) async => api.ListExitNodesResponse()
    ..mergeFromProto3Json({
      'page': {
        'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
      },
      'exitNodes': [
        for (final id in ['a', 'b'])
          {
            'id': id,
            'displayName': 'Candidate $id',
            'peerId': 'peer-$id',
            'selection': {'availability': 'AVAILABILITY_AVAILABLE'},
            'allowedFamilyModes': [
              'EXIT_FAMILY_MODE_IPV4_ONLY',
              'EXIT_FAMILY_MODE_IPV6_ONLY',
            ],
            'allowedLanAccess': ['LAN_ACCESS_BLOCK', 'LAN_ACCESS_ALLOW'],
          },
      ],
    }),
  get: (_) async => api.GetExitNodeResponse()
    ..mergeFromProto3Json({
      'status': {
        'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
        'profileId': 'profile-a',
        'requestedFamilyMode': 'EXIT_FAMILY_MODE_NONE',
        'applyState': 'APPLY_STATE_APPLIED',
        'ipv4': {'applyState': 'APPLY_STATE_APPLIED'},
        'ipv6': {'applyState': 'APPLY_STATE_APPLIED'},
        'control': {
          'mutation': {'availability': 'AVAILABILITY_AVAILABLE'},
        },
      },
    }),
);

ClientOperation pending(api.OperationKind kind) => ClientOperation.fromProto(
  api.Operation(
    id: 'operation',
    kind: kind,
    state: api.OperationState.OPERATION_STATE_PENDING,
  ),
);

void main() {
  for (final scenario in [
    'node',
    'mode',
    'lan',
    'reconfirm',
    'snapshot',
    'controller',
    'late lookup',
    'late failure',
  ]) {
    testWidgets('exit action context: $scenario', (tester) async {
      final states = [ClientStateController(), ClientStateController()];
      final streams = [
        StreamController<api.WatchEventsResponse>(),
        StreamController<api.WatchEventsResponse>(),
      ];
      for (var i = 0; i < states.length; i++) {
        await states[i].attach(streams[i].stream);
        streams[i].add(snapshot(1));
      }
      final delayed = Completer<ClientExitNodes>();
      var loads = 0;
      var clears = 0;
      final selections =
          <(String, String, api.ExitFamilyMode, api.LanAccess)>[];
      Future<void> render(ClientStateController state) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ClientExitPanel(
                  state: state,
                  load: () {
                    loads++;
                    return scenario.startsWith('late ') && loads == 1
                        ? delayed.future
                        : catalog();
                  },
                  select: (profile, node, mode, lan, check) async {
                    check();
                    selections.add((profile, node, mode, lan));
                    return pending(
                      api.OperationKind.OPERATION_KIND_SELECT_EXIT_NODE,
                    );
                  },
                  clear: (profile, check) async {
                    check();
                    expect(profile, 'profile-a');
                    clears++;
                    return pending(
                      api.OperationKind.OPERATION_KIND_CLEAR_EXIT_NODE,
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      VoidCallback button(String key) =>
          tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed!;
      Future<void> change<T>(String key, T value) async {
        tester.widget<DropdownButton<T>>(find.byKey(Key(key))).onChanged!(
          value,
        );
        await tester.pumpAndSettle();
      }

      Future<void> choose() async {
        await change('client-exit-node', 'a');
        await change(
          'client-exit-mode',
          api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV4_ONLY,
        );
        await change('client-exit-lan', api.LanAccess.LAN_ACCESS_BLOCK);
      }

      await render(states.first);
      button('client-load-exits')();
      await tester.pumpAndSettle();
      if (scenario.startsWith('late ')) {
        await render(states.last);
        if (scenario == 'late failure') {
          delayed.completeError(StateError('private old controller failure'));
        } else {
          delayed.complete(await catalog());
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('client-exit-node')), findsNothing);
        expect(find.textContaining('could not be confirmed'), findsNothing);
        button('client-load-exits')();
        await tester.pumpAndSettle();
        await choose();
        button('client-select-exit')();
        await tester.pumpAndSettle();
        expect(selections.length, 1);
      } else {
        await choose();
        button('client-clear-exit')();
        await tester.pumpAndSettle();
        final oldSelect = button('client-select-exit');
        final oldConfirm = button('client-confirm-clear-exit');
        final oldCancel = button('client-cancel-clear-exit');
        switch (scenario) {
          case 'node':
            await change('client-exit-node', 'b');
          case 'mode':
            await change(
              'client-exit-mode',
              api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV6_ONLY,
            );
          case 'lan':
            await change('client-exit-lan', api.LanAccess.LAN_ACCESS_ALLOW);
          case 'reconfirm':
            oldCancel();
            await tester.pumpAndSettle();
            button('client-clear-exit')();
            await tester.pumpAndSettle();
          case 'snapshot':
            streams.first.add(snapshot(2));
            await tester.idle();
          case 'controller':
            await render(states.last);
        }
        oldSelect();
        oldConfirm();
        oldCancel();
        await tester.pumpAndSettle();
        expect(selections, isEmpty);
        expect(clears, 0);
        if (scenario == 'reconfirm') {
          button('client-confirm-clear-exit')();
          await tester.pumpAndSettle();
          expect(clears, 1);
        } else {
          expect(
            find.byKey(const Key('client-confirm-clear-exit')),
            findsNothing,
          );
          if (scenario == 'snapshot' || scenario == 'controller') {
            expect(find.byKey(const Key('client-exit-node')), findsNothing);
            button('client-load-exits')();
            await tester.pumpAndSettle();
            await choose();
          } else if (scenario == 'node') {
            await change(
              'client-exit-mode',
              api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV4_ONLY,
            );
            await change('client-exit-lan', api.LanAccess.LAN_ACCESS_BLOCK);
          }
          button('client-select-exit')();
          await tester.pumpAndSettle();
          expect(selections, [
            (
              'profile-a',
              scenario == 'node' ? 'b' : 'a',
              scenario == 'mode'
                  ? api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV6_ONLY
                  : api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV4_ONLY,
              scenario == 'lan'
                  ? api.LanAccess.LAN_ACCESS_ALLOW
                  : api.LanAccess.LAN_ACCESS_BLOCK,
            ),
          ]);
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        for (var i = 0; i < states.length; i++) {
          await states[i].detach();
          await streams[i].close();
          states[i].dispose();
        }
      });
    });
  }
}
