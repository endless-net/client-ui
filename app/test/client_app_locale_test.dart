@Tags(['short'])
library;

import 'dart:io';
import 'package:endlessnet/client_desktop_app.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_session.dart';
import 'package:endlessnet/client_session_panel.dart';
import 'package:endlessnet/client_intent_journal.dart';
import 'package:endlessnet/client_support_panel.dart';
import 'package:endlessnet/client_update_panel.dart';
import 'package:endlessnet/client_exit_panel.dart';
import 'package:endlessnet/client_resources_panel.dart';
import 'package:endlessnet/client_preferences_panel.dart';
import 'package:endlessnet/client_diagnostics_panel.dart';
import 'package:endlessnet/client_identity_panel.dart';
import 'package:endlessnet/client_networks_panel.dart';
import 'package:endlessnet/client_peers_panel.dart';
import 'package:endlessnet/client_cleanup_panel.dart';
import 'package:endlessnet/client_enrollment_panel.dart';
import 'package:endlessnet/client_create_profile_panel.dart';
import 'package:endlessnet/client_connection_panel.dart';
import 'package:endlessnet/client_runtime_operations_panel.dart';
import 'package:endlessnet/client_recovery_panel.dart';
import 'package:endlessnet/client_profiles_panel.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_session_test.dart' as fixtures;

void main() {
  for (final initial in ClientLocale.values) {
    for (final failure in [false, true]) {
      testWidgets('whole session locale $initial failure=$failure', (
        tester,
      ) async {
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('en-locale-'),
        ))!;
        final connection = fixtures.FakeConnection();
        var opens = 0;
        final journal = ClientIntentJournal(directory);
        final session = ClientSession(
          journal: journal,
          open: () async {
            opens++;
            if (failure) throw StateError('private endpoint');
            return connection;
          },
        );
        await tester.pumpWidget(
          ClientDesktopApp(
            session: session,
            desktopIntegration: false,
            initialLocale: initial,
            uiBuild: api.BuildIdentity(),
          ),
        );
        await tester.pumpAndSettle();
        if (!failure) {
          connection.events.add(fixtures.snapshot());
          await tester.pumpAndSettle();
          final name = find.byKey(const Key('create-profile-name'));
          await tester.ensureVisible(name);
          await tester.enterText(name, 'My profile');
          await tester.pumpAndSettle();
        }
        final controller = session.state;
        final snapshot = controller.snapshot;
        final formState = tester.state(
          find.byKey(ValueKey((controller, controller.cacheEpoch))),
        );
        for (final locale in [
          initial,
          initial == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
          initial,
        ]) {
          final selector = find.byKey(const Key('client-ui-language'));
          await tester.ensureVisible(selector);
          await tester.tap(selector);
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(locale == ClientLocale.ru ? 'Русский' : 'English').last,
          );
          await tester.pumpAndSettle();
          final localizedContext = tester.element(
            find.byType(ClientSessionPanel),
          );
          expect(Localizations.localeOf(localizedContext), Locale(locale.name));
          final material = MaterialLocalizations.of(localizedContext);
          expect(
            [
              material.copyButtonLabel,
              material.pasteButtonLabel,
              material.selectAllButtonLabel,
              material.backButtonTooltip,
              material.modalBarrierDismissLabel,
            ],
            locale == ClientLocale.ru
                ? ['Копировать', 'Вставить', 'Выбрать все', 'Назад', 'Закрыть']
                : ['Copy', 'Paste', 'Select all', 'Back', 'Dismiss'],
          );
          expect(Directionality.of(localizedContext), TextDirection.ltr);
          expect(
            CupertinoLocalizations.of(localizedContext).copyButtonLabel,
            locale == ClientLocale.ru ? 'Копировать' : 'Copy',
          );
          expect(
            tester
                .widget<ClientSessionPanel>(find.byType(ClientSessionPanel))
                .locale,
            locale,
          );
          final locales = [
            tester
                .widget<ClientSupportPanel>(find.byType(ClientSupportPanel))
                .locale,
            tester
                .widget<ClientUpdatePanel>(find.byType(ClientUpdatePanel))
                .locale,
            tester.widget<ClientExitPanel>(find.byType(ClientExitPanel)).locale,
            tester
                .widget<ClientResourcesPanel>(find.byType(ClientResourcesPanel))
                .locale,
            tester
                .widget<ClientPreferencesPanel>(
                  find.byType(ClientPreferencesPanel),
                )
                .locale,
            tester
                .widget<ClientDiagnosticsPanel>(
                  find.byType(ClientDiagnosticsPanel),
                )
                .locale,
            tester
                .widget<ClientIdentityPanel>(find.byType(ClientIdentityPanel))
                .locale,
            tester
                .widget<ClientNetworksPanel>(find.byType(ClientNetworksPanel))
                .locale,
            tester
                .widget<ClientPeersPanel>(find.byType(ClientPeersPanel))
                .locale,
            tester
                .widget<ClientCleanupPanel>(find.byType(ClientCleanupPanel))
                .locale,
            tester
                .widget<ClientEnrollmentPanel>(
                  find.byType(ClientEnrollmentPanel),
                )
                .locale,
            tester
                .widget<ClientCreateProfilePanel>(
                  find.byType(ClientCreateProfilePanel),
                )
                .locale,
            tester
                .widget<ClientConnectionPanel>(
                  find.byType(ClientConnectionPanel),
                )
                .locale,
            tester
                .widget<ClientRuntimeOperationsPanel>(
                  find.byType(ClientRuntimeOperationsPanel),
                )
                .locale,
            tester
                .widget<ClientRecoveryPanel>(find.byType(ClientRecoveryPanel))
                .locale,
            tester
                .widget<ClientProfilesPanel>(find.byType(ClientProfilesPanel))
                .locale,
          ];
          expect(locales, List.filled(16, locale));
          expect(identical(session.state, controller), isTrue);
          expect(identical(session.state.snapshot, snapshot), isTrue);
          expect(
            identical(
              tester.state(
                find.byKey(ValueKey((controller, controller.cacheEpoch))),
              ),
              formState,
            ),
            isTrue,
          );
          if (!failure) {
            expect(
              tester
                  .widget<TextField>(
                    find.byKey(const Key('create-profile-name')),
                  )
                  .controller!
                  .text,
              'My profile',
            );
          } else {
            expect(
              find.text(
                locale == ClientLocale.ru
                    ? 'Локальная служба недоступна или несовместима. Альтернативное подключение не использовалось.'
                    : 'Native runtime is unavailable or incompatible. No fallback was used.',
              ),
              findsOneWidget,
            );
          }
          expect(
            find.text(
              locale == ClientLocale.ru
                  ? 'Переподключиться к службе'
                  : 'Reconnect runtime',
            ),
            findsOneWidget,
          );
          expect(
            find.text(locale == ClientLocale.ru ? 'Выход' : 'Quit'),
            findsOneWidget,
          );
          expect(find.textContaining('private endpoint'), findsNothing);
          expect(opens, 1);
          expect(connection.closed, isFalse);
          expect((await tester.runAsync(journal.pending))!, isEmpty);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await session.close();
          if (failure) connection.events.stream.listen((_) {});
          await connection.events.close();
          await directory.delete(recursive: true);
        });
      });
    }
    testWidgets('quit dialog uses $initial without reconnecting', (
      tester,
    ) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('en-locale-quit-'),
      ))!;
      var opens = 0;
      final session = ClientSession(
        journal: ClientIntentJournal(directory),
        open: () async {
          opens++;
          throw StateError('unavailable');
        },
      );
      await tester.pumpWidget(
        ClientDesktopApp(
          session: session,
          desktopIntegration: false,
          initialLocale: initial,
        ),
      );
      await tester.pumpAndSettle();
      final ru = initial == ClientLocale.ru;
      await tester.tap(find.text(ru ? 'Выход' : 'Quit'));
      await tester.pumpAndSettle();
      final texts = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data)
          .toSet();
      expect(
        texts,
        ru
            ? {
                'Закрыть интерфейс без подтверждения уведомления службы?',
                'Агент может сохранить текущее намерение подключения. Операция не будет отправлена повторно.',
                'Остаться',
                'Закрыть интерфейс',
              }
            : {
                'Exit without confirmed runtime notification?',
                'The agent may retain its current connection intent. The operation will not be replayed.',
                'Stay',
                'Exit UI',
              },
      );
      await tester.tap(find.text(ru ? 'Остаться' : 'Stay'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(opens, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await session.close();
        await directory.delete(recursive: true);
      });
    });
  }
}
