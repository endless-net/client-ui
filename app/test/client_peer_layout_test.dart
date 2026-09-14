@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_peers.dart';
import 'package:endlessnet/client_peers_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

void main() {
  for (final locale in ClientLocale.values) {
    testWidgets('US-14 peers keyboard and full text at 200% in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      events.add(fixtures.snapshot(1));
      await tester.pump();
      var reads = 0;
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
              child: ClientPeersPanel(
                state: state,
                locale: locale,
                load: (search) {
                  reads++;
                  return readClientPeers(
                    (request) async {
                      expect(request.search, 'office');
                      return api.ListPeersResponse()..mergeFromProto3Json({
                        'page': {
                          'metadata': {
                            'instanceId': 'runtime-a',
                            'revision': '1',
                          },
                        },
                        'peers': [
                          for (final id in ['a', 'b'])
                            {
                              'id': id,
                              'hostname':
                                  'Regional office shared workstation with a long name',
                              'selectedPath': 'PATH_KIND_RELAY',
                              'candidates': [
                                {
                                  'kind': 'PATH_KIND_DIRECT',
                                  'health': 'PATH_HEALTH_UNREACHABLE',
                                  'endpoint':
                                      '192.0.2.${id == 'a' ? 1 : 2}:1234',
                                  'reasonKey': 'path.timeout',
                                },
                              ],
                            },
                        ],
                      });
                    },
                    instanceId: 'runtime-a',
                    profileId: 'profile-a',
                    search: search,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.enterText(
        find.byKey(const Key('client-peer-search')),
        'office',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(reads, 1);
      for (final id in ['a', 'b']) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final candidate = find.textContaining(
          '192.0.2.${id == 'a' ? 1 : 2}:1234',
        );
        expect(candidate, findsOneWidget);
        await tester.ensureVisible(candidate);
        await tester.pumpAndSettle();
        expect(candidate.hitTestable(), findsOneWidget);
        // Detect clipping even when layout emits no overflow exception.
        final tile = find.byKey(ValueKey('client-peer-$id'));
        for (final element
            in find
                .descendant(of: tile, matching: find.byType(Text))
                .evaluate()) {
          final paragraph = element.findRenderObject()! as RenderParagraph;
          final painter = TextPainter(
            text: paragraph.text,
            textDirection: paragraph.textDirection,
            textScaler: paragraph.textScaler,
          )..layout(maxWidth: paragraph.size.width);
          expect(
            paragraph.size.height + 0.01,
            greaterThanOrEqualTo(painter.height),
          );
          painter.dispose();
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(candidate, findsNothing);
      }
      expect(reads, 1);
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
