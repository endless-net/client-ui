@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_support_panel.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

void main() {
  for (final initial in ClientLocale.values) {
    for (final scenario in [
      'offline',
      'loaded',
      'error',
      'documentation',
      'support',
      'privacy',
      'license',
    ]) {
      testWidgets('support $scenario in $initial', (tester) async {
        final state = ClientStateController();
        final stream = StreamController<api.WatchEventsResponse>();
        await state.attach(stream.stream);
        if (scenario != 'offline') stream.add(fixtures.snapshot(1));
        var loads = 0;
        final opened = <Uri>[];
        Future<void> render(ClientLocale locale) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ClientSupportPanel(
                    state: state,
                    locale: locale,
                    load: () async {
                      loads++;
                      if (scenario == 'error') {
                        throw StateError('private details');
                      }
                      return api.SupportInfo(
                        runtime: api.BuildIdentity(),
                        productName: 'EndlessNet',
                        documentationUrl: 'https://help.example/documentation',
                        supportUrl: 'https://help.example/support',
                        privacyUrl: 'https://help.example/privacy',
                        licenseUrl: 'https://help.example/license',
                        offlineHelpKey: 'unknown-topic',
                      );
                    },
                    openBrowser: (uri, check) async {
                      check();
                      opened.add(uri);
                      return true;
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Future<void> tap(String key) async {
          final target = find.byKey(Key(key));
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pumpAndSettle();
        }

        await render(initial);
        await tap('client-offline-help');
        if (scenario != 'offline') await tap('client-load-support');
        if (!['offline', 'loaded', 'error'].contains(scenario)) {
          await tap('client-support-$scenario');
        }
        final loadsBefore = loads;
        final openedBefore = opened.length;
        for (final locale in [
          initial,
          initial == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
        ]) {
          await render(locale);
          final ru = locale == ClientLocale.ru;
          expect(
            tester
                .widgetList<Text>(find.byType(Text))
                .map((w) => w.data)
                .whereType<String>()
                .toList(),
            [
              ru ? 'Справка без интернета' : 'Offline help',
              ru
                  ? 'Встроенная справка: переподключитесь к службе, если её состояние недоступно. Принятие операции не означает завершения: восстановите незавершённые операции перед повтором. Выход и удаление локальной регистрации — разные действия. Никому не передавайте токены регистрации и закрытые ключи. Для обращения в поддержку явно экспортируйте диагностику; проверьте файл перед отправкой.'
                  : 'Built-in help: Reconnect runtime if its status is unavailable. An accepted operation is not a completed result: recover pending operations before retrying. Logout and Forget local enrollment are different actions. Never share enrollment tokens or private keys. Use explicit diagnostics export when requesting support; inspect the file before sharing.',
              ...(ru
                  ? [
                      'Служба и разрешения',
                      'Регистрация и вход',
                      'Подключение и сети',
                      'Неизвестный результат операции',
                      'Изменение идентичности сервера',
                      'Выходной узел и локальная сеть',
                      'Ресурсы и конфликты маршрутов',
                      'Настройки и политика',
                      'Выход и локальное удаление',
                      'Диагностика и конфиденциальность',
                      'Обновления и совместимость',
                      'Язык и обращение в поддержку',
                    ]
                  : [
                      'Service and permissions',
                      'Enrollment and login',
                      'Connection and networks',
                      'Unknown operation result',
                      'Changed server identity',
                      'Exit node and LAN access',
                      'Resources and route conflicts',
                      'Preferences and policy',
                      'Logout and local removal',
                      'Diagnostics and privacy',
                      'Updates and compatibility',
                      'Language and contacting support',
                    ]),
              ru
                  ? 'Обновить сведения о поддержке'
                  : 'Refresh support information',
              if (scenario == 'error')
                ru
                    ? 'Не удалось подтвердить сведения о поддержке. Обновите их перед открытием ссылки.'
                    : 'Support information could not be confirmed. Refresh before opening a link.',
              if (!['offline', 'error'].contains(scenario)) ...[
                ru ? 'Продукт: EndlessNet' : 'Product: EndlessNet',
                ru
                    ? 'Запрошенная службой тема отсутствует во встроенной справке. Общая справка остаётся доступной.'
                    : 'The runtime-requested offline topic is not bundled. Built-in help remains available.',
                ru ? 'Открыть документацию' : 'Open documentation',
                ru ? 'Открыть поддержку' : 'Open support',
                ru ? 'Открыть политику конфиденциальности' : 'Open privacy',
                ru ? 'Открыть лицензию' : 'Open license',
              ],
            ],
          );
          expect(loads, loadsBefore);
          expect(opened.length, openedBefore);
        }
        if (scenario == 'offline') {
          expect(loads, 0);
          expect(opened, isEmpty);
        } else if (['loaded', 'error'].contains(scenario)) {
          expect(loads, 1);
          expect(opened, isEmpty);
        } else {
          expect(loads, 2);
          expect(opened, [Uri.parse('https://help.example/$scenario')]);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await state.detach();
          await stream.close();
          state.dispose();
        });
      });
    }
  }
}
