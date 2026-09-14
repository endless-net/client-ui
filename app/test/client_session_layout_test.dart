@Tags(['short'])
library;

import 'dart:async';
import 'dart:io';

import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_session_panel.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in ClientLocale.values) {
    testWidgets('US-09/14 active session headings and large text in $locale', (
      tester,
    ) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('ui-layout-'),
      ))!;
      final events = StreamController<api.WatchEventsResponse>();
      var opens = 0;
      final session = ClientSession(
        journal: ClientIntentJournal(directory),
        open: () async {
          opens++;
          throw StateError('Layout must not open a native connection');
        },
      );
      addTearDown(() async {
        await session.close();
        await events.close();
        await directory.delete(recursive: true);
      });
      await session.state.attach(events.stream);
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'layout', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'layout',
              'callerAccess': 'ACCESS_OWNER',
            },
            'status': {
              'metadata': {'instanceId': 'layout', 'revision': '1'},
              'activeProfileId': 'profile-a',
              'accountId': 'account-a',
              'nodeId': 'node-a',
              'hostname': 'layout-device',
              'network': {'id': 'network-a', 'name': 'Layout network'},
              'connectionPhase': 'CONNECTION_PHASE_DISCONNECTED',
              'session': {'state': 'SESSION_STATE_EXPIRING'},
              'credential': {'state': 'CREDENTIAL_STATE_VALID'},
            },
          },
        }),
      );
      await tester.pump();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              // Preserve the device's real insets. Only text scaling and the panel's
              // available bounds are constrained; no native hit testing is bypassed.
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 360,
                    height: 640,
                    child: ClientSessionPanel(
                      session: session,
                      locale: locale,
                      uiBuild: api.BuildIdentity(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final semantics = tester.ensureSemantics();
      final headings = locale == ClientLocale.en
          ? [
              'Help and support',
              'Updates',
              'Internet exit',
              'Resources',
              'Runtime preferences',
              'Diagnostics',
              'Server identity',
              'Networks',
              'Peers',
              'Enrollment cleanup',
              'Enroll the selected profile',
              'New profile',
              'Connection and session',
              'Saved intentions',
              'Profiles',
            ]
          : [
              'Справка и поддержка',
              'Обновления',
              'Выход в интернет',
              'Ресурсы',
              'Настройки службы',
              'Диагностика',
              'Идентичность сервера',
              'Сети',
              'Устройства',
              'Удаление регистрации',
              'Зарегистрировать выбранный профиль',
              'Новый профиль',
              'Подключение и сессия',
              'Сохранённые намерения',
              'Профили',
            ];
      for (final heading in headings) {
        final target = find.text(heading);
        expect(target, findsOneWidget);
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(target).flagsCollection.isHeader,
          isTrue,
          reason: heading,
        );
        expect(target.hitTestable(), findsOneWidget, reason: heading);
        expect(tester.takeException(), isNull, reason: heading);
      }
      semantics.dispose();
      for (final key in [
        'client-session-state',
        'client-session-warning',
        'client-credential-state',
        'client-credential-warning',
        'client-renew-session',
        'client-load-profiles',
      ]) {
        final target = find.byKey(Key(key));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget, reason: key);
        expect(tester.takeException(), isNull, reason: key);
      }
      expect(opens, 0);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
