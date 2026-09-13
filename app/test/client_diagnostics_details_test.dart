@Tags(['short'])
library;

import 'package:endlessnet/client_diagnostics_details.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in ClientLocale.values) {
    for (final empty in [false, true]) {
      testWidgets('diagnostic inspection $locale empty=$empty', (tester) async {
        final diagnostics = api.Diagnostics()
          ..mergeFromProto3Json({
            'status': {
              'pendingAction': {'browserUrl': 'https://private.example/action'},
            },
            if (!empty) ...{
              'interfaces': [
                {
                  'name': 'tun0',
                  'index': 7,
                  'mtu': 1280,
                  'addresses': ['100.64.0.1', 'fd00::1'],
                  'prefixes': ['100.64.0.0/24'],
                  'flags': ['up'],
                },
              ],
              'routes': [
                {
                  'target': '10.0.0.0/8',
                  'interfaceName': 'tun0',
                  'usesInterface': false,
                  'peerId': 'peer-a',
                  'failure': {'code': 'ERROR_CODE_UNSUPPORTED'},
                },
              ],
              'routeConflicts': [
                {
                  'overlayCidr': '10.0.0.0/8',
                  'localPrefix': '10.1.0.0/16',
                  'interfaceName': 'eth0',
                  'reasonKey': 'route.overlap',
                },
              ],
              'failures': [
                {
                  'code': 'ERROR_CODE_UNSUPPORTED',
                  'retryable': true,
                  'reasonKey': 'private failure context',
                },
              ],
            },
          })
          ..freeze();
        final ru = locale == ClientLocale.ru;
        final headers = ru
            ? [
                'Подробности интерфейсов',
                'Подробности маршрутов',
                'Подробности конфликтов',
                'Подробности ошибок',
              ]
            : [
                'Interface details',
                'Route details',
                'Conflict details',
                'Failure details',
              ];
        Future<void> render(ClientLocale language) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ClientDiagnosticsDetails(
                    diagnostics: diagnostics,
                    locale: language,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await render(locale);
        expect(tester.widgetList<Text>(find.byType(Text)).map((t) => t.data), [
          ru ? 'Подробности туннеля: 0' : 'Tunnel details: 0',
          ru ? 'Подробности DNS: 0' : 'DNS details: 0',
          ...headers.map((h) => '$h: ${empty ? 0 : 1}'),
        ]);
        for (final key in [
          'diagnostic-interfaces',
          'diagnostic-routes',
          'diagnostic-conflicts',
          'diagnostic-failures',
        ]) {
          final finder = find.byKey(Key(key));
          await tester.ensureVisible(finder);
          await tester.tap(
            find.descendant(of: finder, matching: find.byType(ListTile)).first,
          );
          await tester.pumpAndSettle();
        }
        final actual = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .toSet();
        final expected = <String>{
          ru ? 'Подробности туннеля: 0' : 'Tunnel details: 0',
          ru ? 'Подробности DNS: 0' : 'DNS details: 0',
          for (final h in headers) '$h: ${empty ? 0 : 1}',
        };
        expected.addAll(
          empty
              ? {
                  ru
                      ? 'В этом снимке нет записей.'
                      : 'No entries in this snapshot.',
                }
              : (ru
                    ? {
                        'Имя: tun0',
                        'Индекс: 7; MTU: 1280',
                        'Адреса: 100.64.0.1, fd00::1',
                        'Префиксы: 100.64.0.0/24',
                        'Флаги: up',
                        'Ошибка: Не сообщена',
                        'Назначение: 10.0.0.0/8',
                        'Интерфейс: tun0',
                        'Использует интерфейс: Нет',
                        'Устройство: peer-a',
                        'Ошибка: Не поддерживается',
                        'CIDR оверлея: 10.0.0.0/8',
                        'Локальный префикс: 10.1.0.0/16',
                        'Интерфейс: eth0',
                        'Код причины: route.overlap',
                        'Не поддерживается',
                        'Возможен повтор: Да',
                      }
                    : {
                        'Name: tun0',
                        'Index: 7; MTU: 1280',
                        'Addresses: 100.64.0.1, fd00::1',
                        'Prefixes: 100.64.0.0/24',
                        'Flags: up',
                        'Failure: Not reported',
                        'Target: 10.0.0.0/8',
                        'Interface: tun0',
                        'Uses interface: No',
                        'Peer: peer-a',
                        'Failure: Not supported',
                        'Overlay CIDR: 10.0.0.0/8',
                        'Local prefix: 10.1.0.0/16',
                        'Interface: eth0',
                        'Reason code: route.overlap',
                        'Not supported',
                        'Retryable: Yes',
                      }),
        );
        expect(actual, expected);
        expect(find.textContaining('private'), findsNothing);
        await render(
          locale == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
        );
        expect(
          find.textContaining(
            ru ? 'Interface details' : 'Подробности интерфейсов',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('private'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
