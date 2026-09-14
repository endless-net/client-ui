@Tags(['short'])
library;

import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_offline_help.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet/client_support_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'built-in topics cover the intended twelve task groups in both languages',
    () {
      expect(clientHelpArticles.map((a) => a.id), [
        'service',
        'enrollment',
        'connection',
        'recovery',
        'trust',
        'exit',
        'resources',
        'preferences',
        'cleanup',
        'diagnostics',
        'updates',
        'help',
      ]);
      for (final article in clientHelpArticles) {
        expect(article.enTitle, isNotEmpty);
        expect(article.ruTitle, isNotEmpty);
        expect(article.en, isNotEmpty);
        expect(article.ru, isNotEmpty);
        expect(article.en, isNot(article.ru));
        expect(article.en + article.ru, isNot(contains('https://')));
      }
      final recovery = clientHelpArticles.singleWhere(
        (a) => a.id == 'recovery',
      );
      expect(recovery.en, contains('it does not resend it'));
      expect(recovery.ru, contains('а не отправляет её заново'));
      final cleanup = clientHelpArticles.singleWhere((a) => a.id == 'cleanup');
      expect(
        cleanup.en,
        contains('Local removal does not prove remote cleanup'),
      );
      expect(
        cleanup.ru,
        contains('Локальное удаление не подтверждает очистку на сервере'),
      );
      final diagnostics = clientHelpArticles.singleWhere(
        (a) => a.id == 'diagnostics',
      );
      expect(
        diagnostics.en,
        contains('Creating an archive neither exports nor uploads it'),
      );
      expect(
        diagnostics.ru,
        contains('Создание архива не экспортирует и не отправляет его'),
      );
    },
  );
  for (final initial in ClientLocale.values) {
    testWidgets('offline help keyboard disclosure semantics in $initial', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final state = ClientStateController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ClientSupportPanel(
                state: state,
                locale: initial,
                load: () async =>
                    throw StateError('Offline help must not read RPC'),
                openBrowser: (_, _) async =>
                    throw StateError('Offline help must not open browser'),
              ),
            ),
          ),
        ),
      );
      final button = find.byKey(const Key('client-offline-help'));
      void check(bool expanded) {
        expect(
          tester.getSemantics(button),
          matchesSemantics(
            label: initial == ClientLocale.ru
                ? 'Справка без интернета'
                : 'Offline help',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            isFocused: true,
            hasTapAction: true,
            hasFocusAction: true,
            hasExpandedState: true,
            isExpanded: expanded,
          ),
        );
      }

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      check(false);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      check(true);
      expect(find.byType(ClientOfflineHelp), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      check(false);
      expect(find.byType(ClientOfflineHelp), findsNothing);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    });
    testWidgets(
      'all offline topics readable at narrow scaled layout in $initial',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = ClientStateController();
        var reads = 0;
        var opens = 0;
        Future<void> render(ClientLocale locale) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(2)),
                    child: SingleChildScrollView(
                      child: ClientSupportPanel(
                        state: state,
                        locale: locale,
                        load: () async {
                          reads++;
                          throw StateError('Offline help must not read RPC');
                        },
                        openBrowser: (_, _) async {
                          opens++;
                          return false;
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await render(initial);
        expect(find.byType(ClientOfflineHelp), findsNothing);
        await tester.tap(find.byKey(const Key('client-offline-help')));
        await tester.pumpAndSettle();
        for (final article in clientHelpArticles) {
          await render(initial);
          final tile = find.byKey(Key('client-help-${article.id}'));
          await tester.ensureVisible(tile);
          await tester.tap(
            find.descendant(of: tile, matching: find.byType(ListTile)).first,
          );
          await tester.pumpAndSettle();
          for (final locale in [
            initial,
            initial == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
          ]) {
            await render(locale);
            final body = locale == ClientLocale.ru ? article.ru : article.en;
            expect(find.text(body), findsOneWidget);
            expect(
              find.text(locale == ClientLocale.ru ? article.en : article.ru),
              findsNothing,
            );
            expect(reads, 0);
            expect(opens, 0);
            expect(tester.takeException(), isNull);
          }
        }
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      },
    );
  }
}
