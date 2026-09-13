@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_autostart_panel.dart';
import 'package:endlessnet/client_autostart_setting.dart';
import 'package:endlessnet/client_native_autostart.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const settingsKey = Key('ui-autostart-settings');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('endlessnet/ui-autostart');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'settings channel has no arguments and only true confirms dispatch',
    () async {
      for (final response in [true, false, null]) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'openSettings');
          expect(call.arguments, isNull);
          return response;
        });
        expect(await openNativeClientAutostartSettings(), response == true);
      }
      messenger.setMockMethodCallHandler(channel, null);
      await expectLater(
        openNativeClientAutostartSettings(),
        throwsA(isA<MissingPluginException>()),
      );
    },
  );
  for (final locale in ClientLocale.values) {
    for (final success in [true, false]) {
      testWidgets(
        'Login Items $locale success=$success never approves registration',
        (tester) async {
          var opens = 0;
          var reads = 0;
          var writes = 0;
          var setting = ClientAutostartSetting.requiresApproval;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ClientAutostartPanel(
                  locale: locale,
                  read: () async {
                    reads++;
                    return setting;
                  },
                  write: (_) async {
                    writes++;
                    return setting;
                  },
                  openSettings: () async {
                    opens++;
                    return success;
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(opens, 0);
          await tester.tap(find.byKey(settingsKey));
          await tester.pumpAndSettle();
          expect(opens, 1);
          expect(reads, 1);
          expect(writes, 0);
          expect(
            find.textContaining(
              locale == ClientLocale.en
                  ? 'Autostart requires your approval'
                  : 'Для автозапуска требуется ваше одобрение',
            ),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              locale == ClientLocale.en
                  ? 'Could not request Login Items settings'
                  : 'Не удалось запросить открытие настроек объектов входа',
            ),
            success ? findsNothing : findsOneWidget,
          );
          setting = ClientAutostartSetting.enabled;
          await tester.tap(find.byKey(const Key('ui-autostart-read')));
          await tester.pumpAndSettle();
          expect(reads, 2);
          expect(find.byKey(settingsKey), findsNothing);
          expect(
            find.text(
              locale == ClientLocale.en
                  ? 'User autostart entry enabled.'
                  : 'Автозапуск пользователя включён.',
            ),
            findsOneWidget,
          );
        },
      );
    }
  }
  testWidgets('settings busy/disabled guards and sanitized exception', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<bool>();
    Future<bool> open() {
      calls++;
      return pending.future;
    }

    Widget panel(bool enabled) => MaterialApp(
      home: Scaffold(
        body: ClientAutostartPanel(
          read: () async => ClientAutostartSetting.requiresApproval,
          write: (_) async => ClientAutostartSetting.requiresApproval,
          locale: ClientLocale.en,
          enabled: enabled,
          openSettings: open,
        ),
      ),
    );
    await tester.pumpWidget(panel(true));
    await tester.pumpAndSettle();
    final queued = tester
        .widget<TextButton>(find.byKey(settingsKey))
        .onPressed!;
    await tester.pumpWidget(panel(false));
    queued();
    expect(calls, 0);
    await tester.pumpWidget(panel(true));
    queued();
    queued();
    expect(calls, 1);
    pending.completeError(StateError('private native details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('private native details'), findsNothing);
    expect(
      find.textContaining('Could not request Login Items settings'),
      findsOneWidget,
    );
  });
  testWidgets('unsupported host has no settings action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientAutostartPanel(
            read: () async => ClientAutostartSetting.unsupported,
            write: (_) async => throw StateError('Unexpected write'),
            openSettings: () async => throw StateError('Unexpected open'),
            locale: ClientLocale.en,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(settingsKey), findsNothing);
  });
  testWidgets(
    'disposed panel ignores settings completion and queued activation',
    (tester) async {
      final pending = Completer<bool>();
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientAutostartPanel(
              read: () async => ClientAutostartSetting.requiresApproval,
              write: (_) async => throw StateError('Unexpected write'),
              openSettings: () {
                opens++;
                return pending.future;
              },
              locale: ClientLocale.en,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final queued = tester
          .widget<TextButton>(find.byKey(settingsKey))
          .onPressed!;
      queued();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete(true);
      queued();
      await tester.pumpAndSettle();
      expect(opens, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
