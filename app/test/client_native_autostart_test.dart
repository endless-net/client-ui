@Tags(['short'])
library;

import 'package:endlessnet/client_native_autostart.dart';
import 'package:endlessnet/client_autostart_setting.dart';
import 'package:endlessnet/client_autostart_panel.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('endlessnet/ui-autostart');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  for (final locale in ClientLocale.values) {
    testWidgets('Windows registration is opt-in and not OS permission: $locale', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.arguments == true ? 'registered' : 'notConfigured';
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ClientAutostartPanel(
                read: readNativeClientAutostart,
                write: writeNativeClientAutostart,
                locale: locale,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.method), ['read']);
      await tester.tap(find.byKey(const Key('ui-autostart-enable')));
      await tester.pumpAndSettle();
      expect(calls.last.arguments, true);
      expect(
        find.text(
          locale == ClientLocale.en
              ? 'User autostart entry registered. Windows startup permission is not checked; review it in Windows startup settings.'
              : 'Запись автозапуска пользователя создана. Разрешение Windows не проверено; проверьте его в настройках автозагрузки Windows.',
        ),
        findsOneWidget,
      );
      expect(find.text('User autostart entry enabled.'), findsNothing);
      await tester.tap(find.byKey(const Key('ui-autostart-disable')));
      await tester.pumpAndSettle();
      expect(calls.map((c) => c.arguments), [null, true, false]);
      expect(
        find.textContaining(
          locale == ClientLocale.en
              ? 'No user autostart entry.'
              : 'Пользовательская запись отсутствует.',
        ),
        findsOneWidget,
      );
    });
  }
  for (final state in [
    ClientAutostartSetting.notConfigured,
    ClientAutostartSetting.registered,
    ClientAutostartSetting.enabled,
    ClientAutostartSetting.disabled,
    ClientAutostartSetting.requiresApproval,
    ClientAutostartSetting.unsupported,
  ]) {
    test(
      'native autostart $state is authoritative for read and write',
      () async {
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return state.name;
        });
        expect(await readNativeClientAutostart(), state);
        expect(await writeNativeClientAutostart(true), state);
        expect(await writeNativeClientAutostart(false), state);
        expect(calls.map((c) => c.method), [
          'read',
          'setEnabled',
          'setEnabled',
        ]);
        expect(calls.map((c) => c.arguments), [null, true, false]);
      },
    );
  }
  test(
    'missing host is unsupported; bad response and error are not disabled',
    () async {
      expect(
        await readNativeClientAutostart(),
        ClientAutostartSetting.unsupported,
      );
      for (final response in ['unexpected', null]) {
        messenger.setMockMethodCallHandler(channel, (_) async => response);
        await expectLater(readNativeClientAutostart(), throwsFormatException);
      }
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'denied'),
      );
      await expectLater(
        writeNativeClientAutostart(true),
        throwsA(isA<PlatformException>()),
      );
    },
  );
  for (final locale in ClientLocale.values) {
    for (final state in [
      ClientAutostartSetting.requiresApproval,
      ClientAutostartSetting.unsupported,
    ]) {
      testWidgets('autostart $state has distinct UI in $locale', (
        tester,
      ) async {
        var writes = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ClientAutostartPanel(
                  read: () async => state,
                  write: (_) async {
                    writes++;
                    return state;
                  },
                  locale: locale,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            state == ClientAutostartSetting.requiresApproval
                ? locale == ClientLocale.en
                      ? 'Autostart requires your approval in system Login Items settings.'
                      : 'Для автозапуска требуется ваше одобрение в системных настройках объектов входа.'
                : locale == ClientLocale.en
                ? 'UI autostart is not supported on this operating system version.'
                : 'Эта версия операционной системы не поддерживает автозапуск интерфейса.',
          ),
          findsOneWidget,
        );
        expect(writes, 0);
        final enable = tester
            .widget<TextButton>(find.byKey(const Key('ui-autostart-enable')))
            .onPressed;
        if (state == ClientAutostartSetting.unsupported) {
          expect(enable, isNull);
          expect(
            tester
                .widget<TextButton>(
                  find.byKey(const Key('ui-autostart-disable')),
                )
                .onPressed,
            isNull,
          );
        } else {
          await tester.tap(find.byKey(const Key('ui-autostart-enable')));
          await tester.pumpAndSettle();
          expect(writes, 1);
          expect(find.text('User autostart entry enabled.'), findsNothing);
          expect(find.text('Автозапуск пользователя включён.'), findsNothing);
        }
      });
    }
  }
}
