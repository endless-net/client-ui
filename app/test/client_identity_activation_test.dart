@Tags(['short'])
library;

import 'dart:async';

import 'package:endlessnet/client_identity_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final change in ['dispose', 'reload']) {
    testWidgets('queued identity confirmation rejects $change', (tester) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientIdentityPanel(
              state: state,
              load: () async {
                loads++;
                return api.GetServerIdentityResponse()..mergeFromProto3Json({
                  'metadata': {'instanceId': 'runtime', 'revision': '1'},
                  'identity': {
                    'profileId': 'profile',
                    'controlOrigin': 'https://control.test',
                    'trustedKeyId': 'old',
                    'announcedKeyId': 'new',
                    'announcementId': 'a' * 64,
                    'changed': true,
                  },
                });
              },
              trust: (_) async =>
                  throw StateError('Stale callback must not submit'),
            ),
          ),
        ),
      );
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'runtime', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'runtime',
              'callerAccess': 'ACCESS_ADMINISTRATOR',
              'capabilities': [
                {
                  'capability': 'CAPABILITY_IDENTITY_RECOVERY',
                  'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                },
              ],
            },
            'status': {
              'activeProfileId': 'profile',
              'metadata': {'instanceId': 'runtime', 'revision': '1'},
            },
          },
        }),
      );
      await tester.pump();
      final load = tester
          .widget<OutlinedButton>(find.byKey(const Key('load-client-identity')))
          .onPressed!;
      load();
      await tester.pump();
      final checkbox = tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('compare-client-identity')),
          )
          .onChanged!;
      if (change == 'dispose') {
        await tester.pumpWidget(const SizedBox());
        load();
        checkbox(true);
        await tester.pump();
        expect(loads, 1);
        expect(tester.takeException(), isNull);
      } else {
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('load-client-identity')),
            )
            .onPressed!();
        checkbox(true); // A pending reload cannot be confirmed by an old frame.
        await tester.pump();
        checkbox(
          true,
        ); // Even byte-identical reloaded data requires new consent.
        await tester.pump();
        expect(loads, 2);
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const Key('compare-client-identity')),
              )
              .value,
          isFalse,
        );
        expect(
          tester
              .widget<TextButton>(
                find.byKey(const Key('trust-client-identity')),
              )
              .onPressed,
          isNull,
        );
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await state.detach();
        await events.close();
        state.dispose();
      });
    });
  }
}
