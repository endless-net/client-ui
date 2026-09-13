import 'dart:async';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_runtime_operations_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

api.WatchEventsResponse snapshot(
  int sequence, {
  bool observer = false,
  bool empty = false,
}) => api.WatchEventsResponse()
  ..mergeFromProto3Json({
    'sequence': '$sequence',
    'metadata': {'instanceId': 'runtime-a', 'revision': '$sequence'},
    'snapshot': {
      'runtime': {
        'protocol': api.ClientContract.protocol,
        'contractSha256': api.ClientContract.sha256,
        'instanceId': 'runtime-a',
        'callerAccess': observer ? 'ACCESS_OBSERVER' : 'ACCESS_OWNER',
      },
      'status': {
        'metadata': {'instanceId': 'runtime-a', 'revision': '$sequence'},
        'connectionPhase': 'CONNECTION_PHASE_CONNECTING',
        'currentOperations': [
          if (!observer && !empty)
            {
              'id': 'op-a',
              'profileId': 'inactive-profile',
              'kind': 'OPERATION_KIND_CONNECT',
              'state': 'OPERATION_STATE_RUNNING',
            },
        ],
      },
    },
  });

void main() {
  for (final locale in ClientLocale.values) {
    testWidgets(
      'US-03 stream operations render without local journal in ${locale.name}',
      (tester) async {
        final state = ClientStateController();
        final source = StreamController<api.WatchEventsResponse>();
        await state.attach(source.stream);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ClientRuntimeOperationsPanel(
                  state: state,
                  locale: locale,
                ),
              ),
            ),
          ),
        );
        expect(find.byKey(const Key('runtime-operation-op-a')), findsNothing);
        source.add(snapshot(1));
        await tester.pumpAndSettle();
        expect(
          state.snapshot!.status.connectionPhase,
          api.ConnectionPhase.CONNECTION_PHASE_CONNECTING,
        );
        expect(find.byKey(const Key('runtime-operation-op-a')), findsOneWidget);
        expect(
          find.text(
            locale.text(
              en: 'Profile: inactive-profile',
              ru: 'Профиль: inactive-profile',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.text(locale.text(en: 'In progress', ru: 'Выполняется')),
          findsOneWidget,
        );
        // No local journal/recover callback is provided to this read-only surface.
        expect(find.byType(TextButton), findsNothing);
        source.add(
          api.WatchEventsResponse()..mergeFromProto3Json({
            'sequence': '2',
            'metadata': {'instanceId': 'runtime-a', 'revision': '2'},
            'operationChanged': {
              'id': 'op-a',
              'profileId': 'inactive-profile',
              'kind': 'OPERATION_KIND_CONNECT',
              'state': 'OPERATION_STATE_SUCCEEDED',
              'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
              'change': {'changed': true},
            },
          }),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(locale.text(en: 'Completed', ru: 'Завершено')),
          findsOneWidget,
        );
        expect(
          find.text(locale.text(en: 'In progress', ru: 'Выполняется')),
          findsNothing,
        );
        // A terminal operation is not evidence of Connected.
        expect(
          state.snapshot!.status.connectionPhase,
          api.ConnectionPhase.CONNECTION_PHASE_CONNECTING,
        );
        source.add(snapshot(3, observer: true));
        await tester.pumpAndSettle();
        expect(
          state.snapshot!.runtime.callerAccess,
          api.Access.ACCESS_OBSERVER,
        );
        expect(find.byKey(const Key('runtime-operation-op-a')), findsNothing);
        expect(find.textContaining('inactive-profile'), findsNothing);
        source.add(snapshot(4, empty: true));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('runtime-operation-op-a')), findsNothing);
        source.add(snapshot(5));
        await tester.pumpAndSettle();
        expect(state.link, ClientLinkState.ready);
        expect(state.snapshot!.runtime.callerAccess, api.Access.ACCESS_OWNER);
        expect(state.operations.keys, contains('op-a'));
        expect(find.byKey(const Key('runtime-operation-op-a')), findsOneWidget);
        await tester.runAsync(state.detach);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('runtime-operation-op-a')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await source.close();
          state.dispose();
        });
        expect(tester.takeException(), isNull);
      },
    );
  }
}
