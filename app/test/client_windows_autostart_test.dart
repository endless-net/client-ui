@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_windows_autostart.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget panel(
  Future<bool> Function() open,
  ClientLocale locale, {
  bool enabled = true,
}) => MaterialApp(
  home: Scaffold(
    body: ClientWindowsAutostartPanel(
      openSettings: open,
      locale: locale,
      enabled: enabled,
    ),
  ),
);
const buttonKey = Key('ui-windows-autostart-settings');

void main() {
  test(
    'Windows startup target is fixed and launcher result is preserved',
    () async {
      for (final result in [true, false]) {
        var calls = 0;
        expect(
          await openWindowsClientAutostartSettings(
            launch: (uri) async {
              calls++;
              expect(uri.toString(), 'ms-settings:startupapps');
              expect(uri.query, isEmpty);
              expect(uri.fragment, isEmpty);
              return result;
            },
          ),
          result,
        );
        expect(calls, 1);
      }
    },
  );
  for (final locale in ClientLocale.values) {
    for (final success in [true, false]) {
      testWidgets(
        'Windows autostart $locale success=$success requires explicit action',
        (tester) async {
          var calls = 0;
          Future<bool> open() async {
            calls++;
            return success;
          }

          await tester.pumpWidget(panel(open, locale));
          expect(calls, 0);
          expect(
            find.textContaining(
              locale == ClientLocale.en
                  ? 'permission is not checked here'
                  : 'разрешение автозапуска здесь не проверяется',
            ),
            findsOneWidget,
          );
          await tester.tap(find.byKey(buttonKey));
          await tester.pumpAndSettle();
          expect(calls, 1);
          expect(
            find.textContaining(
              success
                  ? locale == ClientLocale.en
                        ? 'no startup change is confirmed'
                        : 'не подтверждает изменение автозапуска'
                  : locale == ClientLocale.en
                  ? 'Could not open startup settings'
                  : 'Не удалось открыть настройки автозагрузки',
            ),
            findsOneWidget,
          );
          expect(find.text('User autostart entry enabled.'), findsNothing);
          expect(find.text('Автозапуск пользователя включён.'), findsNothing);
        },
      );
    }
  }
  testWidgets(
    'queued activation obeys disabled/busy and hides adapter exception',
    (tester) async {
      var calls = 0;
      final pending = Completer<bool>();
      Future<bool> open() {
        calls++;
        return pending.future;
      }

      await tester.pumpWidget(panel(open, ClientLocale.en));
      final activate = tester
          .widget<TextButton>(find.byKey(buttonKey))
          .onPressed!;
      await tester.pumpWidget(panel(open, ClientLocale.en, enabled: false));
      activate();
      expect(calls, 0);
      await tester.pumpWidget(panel(open, ClientLocale.en));
      activate();
      activate();
      await tester.pump();
      expect(calls, 1);
      expect(
        tester.widget<TextButton>(find.byKey(buttonKey)).onPressed,
        isNull,
      );
      pending.completeError(StateError('private native path'));
      await tester.pumpAndSettle();
      expect(find.textContaining('private native path'), findsNothing);
      expect(
        find.textContaining('Could not open startup settings'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'late completion after adapter replacement is not attributed to new adapter',
    (tester) async {
      final pending = Completer<bool>();
      Future<bool> first() => pending.future;
      await tester.pumpWidget(panel(first, ClientLocale.en));
      await tester.tap(find.byKey(buttonKey));
      await tester.pumpWidget(panel(() async => false, ClientLocale.ru));
      pending.complete(true);
      await tester.pumpAndSettle();
      expect(find.textContaining('Запрошено открытие настроек'), findsNothing);
      expect(find.textContaining('Settings launch requested'), findsNothing);
    },
  );
  testWidgets('late completion after disposal is ignored', (tester) async {
    final pending = Completer<bool>();
    await tester.pumpWidget(panel(() => pending.future, ClientLocale.en));
    final activate = tester
        .widget<TextButton>(find.byKey(buttonKey))
        .onPressed!;
    activate();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(true);
    activate();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
