@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_support_panel.dart';
import 'package:endlessnet/client_update_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

void main() {
  for (final support in [true, false]) {
    for (final fail in [true, false]) {
      testWidgets(
        'information request survives replacement support=$support oldError=$fail',
        (tester) async {
          final states = [ClientStateController(), ClientStateController()];
          final events = [
            StreamController<api.WatchEventsResponse>(),
            StreamController<api.WatchEventsResponse>(),
          ];
          for (var i = 0; i < 2; i++) {
            await states[i].attach(events[i].stream);
            events[i].add(fixtures.snapshot(1));
          }
          await tester.pump();
          expect(states[0].cacheEpoch, states[1].cacheEpoch);
          final old = Completer<Object>();
          final fresh = Completer<Object>();
          var calls = 0;
          Future<Object> load() => ++calls == 1 ? old.future : fresh.future;
          final ui = api.BuildIdentity(version: 'ui-dev');
          Future<void> render(int index) => tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: support
                      ? ClientSupportPanel(
                          state: states[index],
                          load: () async => await load() as api.SupportInfo,
                          openBrowser: (_, _) async =>
                              throw StateError('No browser action requested'),
                        )
                      : ClientUpdatePanel(
                          state: states[index],
                          uiBuild: ui,
                          load: (_) async => await load() as api.UpdateInfo,
                        ),
                ),
              ),
            ),
          );
          final button = find.byKey(
            Key(support ? 'client-load-support' : 'client-check-updates'),
          );
          await render(0);
          await tester.tap(button);
          await tester.pump();
          await render(1);
          await render(0);
          expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
          await tester.tap(button);
          await tester.pump();
          expect(calls, 2);
          final Object info = support
              ? api.SupportInfo(
                  runtime: api.BuildIdentity(),
                  productName: 'EndlessNet',
                )
              : (api.UpdateInfo()..mergeFromProto3Json({
                  'metadata': {'instanceId': 'runtime-a', 'revision': '1'},
                  'reportedUi': ui.toProto3Json(),
                  'state': 'UPDATE_STATE_SOURCE_UNAVAILABLE',
                }));
          if (fail) {
            old.completeError(StateError('private old error'));
          } else {
            old.complete(info);
          }
          await tester.pumpAndSettle();
          expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
          expect(find.textContaining('could not be confirmed'), findsNothing);
          final loaded = find.text(
            support
                ? 'Product: EndlessNet'
                : 'Update source: Source unavailable',
          );
          expect(loaded, findsNothing);
          fresh.complete(info);
          await tester.pumpAndSettle();
          expect(loaded, findsOneWidget);
          expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            for (var i = 0; i < 2; i++) {
              await states[i].detach();
              await events[i].close();
              states[i].dispose();
            }
          });
        },
      );
    }
  }
}
