import 'dart:async';

import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reused by the native integration-test host; no desktop channel is imported.
void main() {
  testWidgets(
    'US-01/03: typed snapshot reaches widgets and stream loss clears it',
    (tester) async {
      final state = ClientStateController();
      final source = StreamController<api.WatchEventsResponse>();
      await state.attach(source.stream);
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: state,
            builder: (context, _) => Scaffold(
              body: Text(
                state.snapshot == null
                    ? 'No current runtime state'
                    : state.snapshot!.status.activeProfileId,
              ),
            ),
          ),
        ),
      );
      expect(find.text('No current runtime state'), findsOneWidget);
      final snapshot = api.WatchEventsResponse()
        ..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'native-test', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'native-test',
              'callerAccess': 'ACCESS_OWNER',
            },
            'status': {
              'metadata': {'instanceId': 'native-test', 'revision': '1'},
              'activeProfileId': 'synthetic-profile',
              'connectionPhase': 'CONNECTION_PHASE_CONNECTING',
            },
          },
        });
      source.add(snapshot);
      await tester.pump();
      expect(find.text('synthetic-profile'), findsOneWidget);
      expect(
        state.snapshot!.status.connectionPhase,
        api.ConnectionPhase.CONNECTION_PHASE_CONNECTING,
      );
      await source.close();
      await tester.pump();
      expect(find.text('synthetic-profile'), findsNothing);
      expect(find.text('No current runtime state'), findsOneWidget);
      expect(state.link, ClientLinkState.unavailable);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
