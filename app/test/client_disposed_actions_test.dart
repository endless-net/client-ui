import 'dart:async';
import 'package:endlessnet/client_diagnostics_panel.dart';
import 'package:endlessnet/client_exit_panel.dart';
import 'package:endlessnet/client_networks_panel.dart';
import 'package:endlessnet/client_peers_panel.dart';
import 'package:endlessnet/client_preferences_panel.dart';
import 'package:endlessnet/client_profiles_panel.dart';
import 'package:endlessnet/client_recovery_panel.dart';
import 'package:endlessnet/client_resources_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/contract_test_scaffold.dart';

Widget panel(
  String action,
  ClientStateController state,
  Never Function() invoked,
) => switch (action) {
  'load-client-diagnostics' || 'load-client-logs' => ClientDiagnosticsPanel(
    state: state,
    load: () async => invoked(),
    loadLogs: () async => invoked(),
    createBundle: (_) async => invoked(),
  ),
  'client-load-peers' => ClientPeersPanel(
    state: state,
    load: (_) async => invoked(),
  ),
  'client-load-networks' => ClientNetworksPanel(
    state: state,
    load: () async => invoked(),
    select: (_, _) async => invoked(),
  ),
  'client-load-profiles' => ClientProfilesPanel(
    state: state,
    load: () async => invoked(),
    select: (_) async => invoked(),
    rename: (_, _) async => invoked(),
    remove: (_) async => invoked(),
  ),
  'client-load-preferences' => ClientPreferencesPanel(
    state: state,
    load: () async => invoked(),
    apply: (_, _, _) async => invoked(),
    reset: (_, _, _) async => invoked(),
  ),
  'client-load-resources' => ClientResourcesPanel(
    state: state,
    load: (_, _) async => invoked(),
    setEnabled: (_, _, _, _) async => invoked(),
  ),
  'client-load-exits' => ClientExitPanel(
    state: state,
    load: () async => invoked(),
    select: (_, _, _, _, _) async => invoked(),
    clear: (_, _) async => invoked(),
  ),
  'client-recover' => ClientRecoveryPanel(
    state: state,
    recover: () async => invoked(),
    acknowledge: (_) async => invoked(),
  ),
  _ => throw StateError('Unknown test action'),
};

void main() {
  for (final action in [
    'load-client-diagnostics',
    'load-client-logs',
    'client-load-peers',
    'client-load-networks',
    'client-load-profiles',
    'client-load-preferences',
    'client-load-resources',
    'client-load-exits',
    'client-recover',
  ]) {
    testWidgets('Disposed panel does not execute queued $action', (
      tester,
    ) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      addTearDown(() async {
        await state.detach();
        await events.close();
        state.dispose();
      });
      var calls = 0;
      Never invoked() {
        calls++;
        throw StateError('Disposed action reached a provider');
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ContractTestScaffold(
            body: SingleChildScrollView(child: panel(action, state, invoked)),
          ),
        ),
      );
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'runtime-a',
              'callerAccess': 'ACCESS_OWNER',
              'capabilities': [
                for (final capability in api.Capability.values.where(
                  (value) => value.value != 0,
                ))
                  {
                    'capability': capability.name,
                    'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                  },
              ],
            },
            'status': {
              'activeProfileId': 'profile-a',
              'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
            },
          },
        }),
      );
      await tester.pump();
      final callback = tester
          .widget<ButtonStyleButton>(find.byKey(Key(action)))
          .onPressed;
      expect(callback, isNotNull);
      expect(calls, 0);
      await tester.pumpWidget(const SizedBox());
      callback!();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(calls, 0);
    });
  }
}
