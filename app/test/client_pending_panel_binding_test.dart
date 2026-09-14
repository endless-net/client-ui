@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_diagnostics_panel.dart';
import 'package:endlessnet/client_exit_panel.dart';
import 'package:endlessnet/client_preferences_panel.dart';
import 'package:endlessnet/client_resources_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

void main() {
  for (final panel in [
    'diagnostics',
    'logs',
    'exit',
    'preferences',
    'resources',
  ]) {
    for (final replace in [true, false]) {
      testWidgets('$panel releases invalidated request replacement=$replace', (
        tester,
      ) async {
        final states = [ClientStateController(), ClientStateController()];
        final streams = [
          StreamController<api.WatchEventsResponse>(),
          StreamController<api.WatchEventsResponse>(),
        ];
        api.WatchEventsResponse snapshot(int sequence) {
          final event = fixtures.snapshot(sequence);
          event.snapshot.runtime.capabilities.addAll([
            for (final capability in [
              api.Capability.CAPABILITY_DIAGNOSTICS,
              api.Capability.CAPABILITY_EXIT_NODE,
              api.Capability.CAPABILITY_PREFERENCES,
              api.Capability.CAPABILITY_MANAGED_SETTINGS,
              api.Capability.CAPABILITY_RESOURCES,
            ])
              api.CapabilityStatus(
                capability: capability,
                restriction: api.Restriction(
                  availability: api.Availability.AVAILABILITY_AVAILABLE,
                ),
              ),
          ]);
          return event;
        }

        for (var i = 0; i < 2; i++) {
          await states[i].attach(streams[i].stream);
          streams[i].add(snapshot(1));
        }
        await tester.pump();
        final old = Completer<Never>();
        final fresh = Completer<Never>();
        var reads = 0;
        Future<Never> load() => ++reads == 1 ? old.future : fresh.future;
        Future<void> render(int index) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: switch (panel) {
                  'diagnostics' || 'logs' => ClientDiagnosticsPanel(
                    state: states[index],
                    load: load,
                    loadLogs: load,
                    createBundle: (_) async =>
                        throw StateError('No bundle requested'),
                  ),
                  'exit' => ClientExitPanel(
                    state: states[index],
                    load: load,
                    select: (_, _, _, _, _) async =>
                        throw StateError('No select requested'),
                    clear: (_, _) async =>
                        throw StateError('No clear requested'),
                  ),
                  'preferences' => ClientPreferencesPanel(
                    state: states[index],
                    load: load,
                    apply: (_, _, _) async =>
                        throw StateError('No apply requested'),
                    reset: (_, _, _) async =>
                        throw StateError('No reset requested'),
                  ),
                  _ => ClientResourcesPanel(
                    state: states[index],
                    load: (_, _) => load(),
                    setEnabled: (_, _, _, _) async =>
                        throw StateError('No resource mutation requested'),
                  ),
                },
              ),
            ),
          ),
        );
        final button = find.byKey(
          Key(switch (panel) {
            'diagnostics' => 'load-client-diagnostics',
            'logs' => 'load-client-logs',
            'exit' => 'client-load-exits',
            'preferences' => 'client-load-preferences',
            _ => 'client-load-resources',
          }),
        );
        await render(0);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        if (replace) {
          await render(1);
          await render(0);
        } else {
          streams[0].add(snapshot(2));
          await tester.pump();
        }
        expect(tester.widget<ButtonStyleButton>(button).onPressed, isNotNull);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        expect(reads, 2);
        old.completeError(StateError('private stale failure'));
        await tester.pumpAndSettle();
        expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
        expect(find.textContaining('could not'), findsNothing);
        fresh.completeError(StateError('private fresh failure'));
        await tester.pumpAndSettle();
        expect(tester.widget<ButtonStyleButton>(button).onPressed, isNotNull);
        expect(find.textContaining('could not'), findsOneWidget);
        expect(find.textContaining('private'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          for (var i = 0; i < 2; i++) {
            await states[i].detach();
            await streams[i].close();
            states[i].dispose();
          }
        });
      });
    }
  }
}
