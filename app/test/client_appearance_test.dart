@Tags(['short'])
library;

import 'dart:io';
import 'package:endlessnet/client_desktop_app.dart';
import 'package:endlessnet/client_device_card.dart';
import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_session_panel.dart';
import 'package:flutter/material.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'client_session_test.dart' as fixtures;

void main() {
  for (final size in [
    const Size(360, 780),
    const Size(820, 1000),
    const Size(1440, 1000),
  ]) {
    testWidgets('appearance changes preserve session and adapt at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('en-appearance-'),
      ))!;
      final connection = fixtures.FakeConnection();
      var opens = 0;
      var peerReads = 0;
      connection.peers = (_) async {
        peerReads++;
        return api.ListPeersResponse()..mergeFromProto3Json({
          'page': {
            'metadata': {'instanceId': 'runtime-a', 'revision': '7'},
          },
          'snapshotState': 'AGENT_SNAPSHOT_STATE_CURRENT',
          'peers': [
            {'id': 'peer-a', 'hostname': 'Fixture peer'},
          ],
        });
      };
      final session = ClientSession(
        journal: ClientIntentJournal(directory),
        open: () async {
          opens++;
          return connection;
        },
      );
      final saved = <ThemeMode>[];
      await tester.pumpWidget(
        ClientDesktopApp(
          session: session,
          desktopIntegration: false,
          saveTheme: (mode) async => saved.add(mode),
        ),
      );
      await tester.pumpAndSettle();
      expect(peerReads, 0);
      final event = fixtures.snapshot();
      event.snapshot.status
        ..activeProfileId = 'profile-a'
        ..hostname = 'Fixture device';
      connection.events.add(event);
      await tester.pumpAndSettle();
      expect(peerReads, 1);
      expect(find.text('Fixture peer'), findsOneWidget);
      final snapshot = session.state.snapshot;
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(ClientSessionPanel))).brightness;
      expect(brightness(), Brightness.dark);
      final device = tester.getRect(find.byType(ClientDeviceCard));
      final peers = tester.getRect(
        find.byKey(const ValueKey('home-peer-summary')),
      );
      if (size.width >= 1400) {
        expect(peers.left, greaterThan(device.right));
      } else {
        expect(peers.top, greaterThanOrEqualTo(device.bottom));
      }
      await tester.tap(find.byKey(const ValueKey('page-settings')));
      await tester.pumpAndSettle();
      for (final entry in [
        (ThemeMode.light, 'Light', Brightness.light),
        (ThemeMode.dark, 'Dark', Brightness.dark),
      ]) {
        final selector = find.byType(DropdownButtonFormField<ThemeMode>);
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text(entry.$2).last);
        await tester.pumpAndSettle();
        expect(brightness(), entry.$3);
        expect(saved.last, entry.$1);
        expect(identical(session.state.snapshot, snapshot), isTrue);
        expect(opens, 1);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const ValueKey('page-connection')));
      await tester.pumpAndSettle();
      expect(peerReads, 1);
      final observer = fixtures.snapshot()..sequence += 1;
      observer.snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER;
      connection.events.add(observer);
      await tester.pumpAndSettle();
      expect(find.text('Fixture peer', skipOffstage: false), findsNothing);
      expect(find.text('Fixture device', skipOffstage: false), findsNothing);
      expect(peerReads, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await session.close();
        await directory.delete(recursive: true);
      });
    });
  }
}
