@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_autostart_panel.dart';
import 'package:endlessnet/client_autostart_setting.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in ClientLocale.values) {
    for (final failure in [false, true]) {
      testWidgets('autostart explicit write locale=$locale failure=$failure', (
        tester,
      ) async {
        var reads = 0;
        final writes = <bool>[];
        final pending = Completer<ClientAutostartSetting>();
        Future<ClientAutostartSetting> read() async {
          reads++;
          return ClientAutostartSetting.notConfigured;
        }

        Future<ClientAutostartSetting> write(bool value) {
          writes.add(value);
          return pending.future;
        }

        Future<void> show(ClientLocale selected, {bool enabled = true}) =>
            tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: ClientAutostartPanel(
                      read: read,
                      write: write,
                      locale: selected,
                      enabled: enabled,
                    ),
                  ),
                ),
              ),
            );
        await show(locale);
        await tester.pumpAndSettle();
        expect(reads, 1);
        expect(writes, isEmpty);
        expect(
          find.text(
            locale == ClientLocale.en
                ? 'No user autostart entry. System-wide policy is not evaluated.'
                : 'Пользовательская запись отсутствует. Системная политика не проверялась.',
          ),
          findsOneWidget,
        );
        final button = find.byKey(const Key('ui-autostart-enable'));
        final old = tester.widget<TextButton>(button).onPressed!;
        await tester.tap(button);
        await tester.pump();
        old();
        expect(writes, [true]);
        expect(tester.widget<TextButton>(button).onPressed, isNull);
        if (failure) {
          pending.completeError(StateError('private path'));
        } else {
          pending.complete(ClientAutostartSetting.enabled);
        }
        await tester.pumpAndSettle();
        for (final selected in ClientLocale.values) {
          await show(selected);
          await tester.pumpAndSettle();
          expect(
            find.text(
              failure
                  ? selected == ClientLocale.en
                        ? 'Autostart could not be read or changed. An unrecognized entry is never overwritten.'
                        : 'Не удалось прочитать или изменить автозапуск. Неизвестная запись не перезаписывается.'
                  : selected == ClientLocale.en
                  ? 'User autostart entry enabled.'
                  : 'Автозапуск пользователя включён.',
            ),
            findsOneWidget,
          );
        }
        expect(reads, 1);
        expect(writes, [true]);
        expect(find.textContaining('private path'), findsNothing);
        await show(locale, enabled: false);
        old();
        expect(writes, [true]);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'unknown entry read failure disables writes until explicit refresh',
    (tester) async {
      var reads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ClientAutostartPanel(
                locale: ClientLocale.en,
                read: () async {
                  if (++reads == 1) throw const FormatException('foreign');
                  return ClientAutostartSetting.disabled;
                },
                write: (_) async => throw StateError('Must not write'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('ui-autostart-enable')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('ui-autostart-read')));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('User autostart entry disabled.'), findsOneWidget);
    },
  );
}
