@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_networks_panel.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_recovery_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

void main() {
  for (final locale in ClientLocale.values) {
    for (final scenario in ['network', 'ack', 'browser', 'pending']) {
      testWidgets('US-14 loaded catalog $scenario at 200% in $locale', (
        tester,
      ) async {
        final recovery = scenario != 'network';
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = ClientStateController();
        final events = StreamController<api.WatchEventsResponse>();
        await state.attach(events.stream);
        events.add(fixtures.snapshot(1));
        await tester.pump();
        var actions = 0;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: recovery
                    ? ClientRecoveryPanel(
                        state: state,
                        locale: locale,
                        recover: () async => [
                          if (scenario == 'ack')
                            fixtures.operation(true)
                          else
                            ClientOperation.fromProto(
                              api.Operation()..mergeFromProto3Json({
                                'id': 'operation',
                                'requestId': 'request',
                                'kind': 'OPERATION_KIND_ENROLL',
                                'state': scenario == 'browser'
                                    ? 'OPERATION_STATE_WAITING_FOR_USER'
                                    : 'OPERATION_STATE_PENDING',
                                if (scenario == 'browser')
                                  'userAction': {
                                    'kind': 'KIND_OPEN_BROWSER',
                                    'browserUrl': 'https://example.test/enroll',
                                  },
                              }),
                            ),
                        ],
                        acknowledge: (_) async {
                          expect(scenario, 'ack');
                          actions++;
                        },
                        openBrowser: (uri) async {
                          expect(scenario, 'browser');
                          expect(uri, Uri.parse('https://example.test/enroll'));
                          actions++;
                          return true;
                        },
                      )
                    : ClientNetworksPanel(
                        state: state,
                        locale: locale,
                        load: fixtures.catalog,
                        select: (_, network) async {
                          expect(network, 'b');
                          actions++;
                          return fixtures.operation(false);
                        },
                      ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(Key(recovery ? 'client-recover' : 'client-load-networks')),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final action = scenario == 'pending'
            ? find.text(
                locale == ClientLocale.en ? 'Still pending' : 'Ещё выполняется',
              )
            : find.byKey(
                Key(switch (scenario) {
                  'ack' => 'ack-request',
                  'browser' => 'browser-request',
                  _ => 'select-network-b',
                }),
              );
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (scenario != 'pending') await tester.tap(action);
        await tester.pumpAndSettle();
        expect(actions, scenario == 'pending' ? 0 : 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await state.detach();
          await events.close();
          state.dispose();
        });
      });
    }
  }
}
