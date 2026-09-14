@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_resources.dart';
import 'package:endlessnet/client_resources_panel.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

void main() {
  for (final locale in ClientLocale.values) {
    testWidgets(
      'UF-19 same-name resources retain network and overlap identity in $locale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = ClientStateController();
        final stream = StreamController<api.WatchEventsResponse>();
        await state.attach(stream.stream);
        final snapshot = fixtures.snapshot(1);
        snapshot.snapshot.runtime.mergeFromProto3Json({
          'capabilities': [
            {
              'capability': 'CAPABILITY_RESOURCES',
              'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
            },
          ],
        });
        stream.add(snapshot);
        await tester.pump();
        var commands = 0;
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
                child: ClientResourcesPanel(
                  state: state,
                  locale: locale,
                  load: (search, kinds) => readClientResources(
                    (_) async => api.ListResourcesResponse()
                      ..mergeFromProto3Json({
                        'page': {
                          'metadata': {
                            'instanceId': 'runtime-a',
                            'revision': '1',
                          },
                        },
                        'resources': [
                          for (final id in ['a', 'b'])
                            {
                              'id': id,
                              'networkId': 'network-$id',
                              'displayName': 'Office',
                              'kind': 'RESOURCE_KIND_SUBNET',
                              'subnet': {'cidr': '10.0.0.0/24'},
                              'availability': {
                                'availability': 'AVAILABILITY_AVAILABLE',
                              },
                              'enabled': {
                                'effective': false,
                                'control': {
                                  'mutation': {
                                    'availability': 'AVAILABILITY_AVAILABLE',
                                  },
                                },
                              },
                              'overlappingResourceIds': [id == 'a' ? 'b' : 'a'],
                              'overlapReasonKey': 'overlap.route',
                            },
                        ],
                      }),
                    instanceId: 'runtime-a',
                    profileId: 'profile-a',
                    search: search,
                    kinds: kinds,
                    checkContext: () {},
                  ),
                  setEnabled: (profile, id, enabled, check) async {
                    check();
                    expect((profile, id, enabled), ('profile-a', 'b', true));
                    commands++;
                    return ClientOperation.fromProto(
                      api.Operation()..mergeFromProto3Json({
                        'id': 'op',
                        'kind': 'OPERATION_KIND_SET_RESOURCE_ENABLED',
                        'state': 'OPERATION_STATE_PENDING',
                      }),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const Key('client-load-resources')),
        );
        await tester.tap(find.byKey(const Key('client-load-resources')));
        await tester.pumpAndSettle();
        final ru = locale == ClientLocale.ru;
        for (final id in ['a', 'b']) {
          expect(
            find.text('${ru ? 'ID ресурса' : 'Resource ID'}: $id'),
            findsOneWidget,
          );
          expect(
            find.text('${ru ? 'ID сети' : 'Network ID'}: network-$id'),
            findsOneWidget,
          );
          expect(
            find.text('${ru ? 'Пересечение' : 'Overlap'}: $id; overlap.route'),
            findsOneWidget,
          );
        }
        expect(find.text('Office'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        final enable = find.byKey(const ValueKey('resource-b-true'));
        await tester.ensureVisible(enable);
        await tester.pumpAndSettle();
        await tester.tap(enable);
        await tester.pumpAndSettle();
        expect(commands, 1);
        expect(find.text('Office'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await state.detach();
          await stream.close();
          state.dispose();
        });
      },
    );
  }
}
