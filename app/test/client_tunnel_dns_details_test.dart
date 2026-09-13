@Tags(['short'])
library;

import 'package:endlessnet/client_diagnostics_details.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final initial in ClientLocale.values) {
    for (final scenario in ['absent', 'empty', 'values', 'missing timing']) {
      testWidgets('tunnel/DNS $scenario in $initial', (tester) async {
        final populated = scenario == 'values' || scenario == 'missing timing';
        final timing = scenario == 'values';
        final diagnostics = api.Diagnostics()
          ..mergeFromProto3Json({
            if (scenario != 'absent') ...{
              'tunnel': {
                if (populated) ...{
                  'ok': true,
                  'interfaceName': 'tun0',
                  'mtu': 1280,
                  'listenPort': 51820,
                  'failure': {
                    'code': 'ERROR_CODE_UNSUPPORTED',
                    'reasonKey': 'private reason',
                  },
                  'peers': [
                    {
                      'peerId': 'peer-a',
                      'publicKey': 'public-key-a',
                      'endpoint': '[fd00::1]:7',
                      'allowedIps': ['100.64.0.1/32', 'fd00::1/128'],
                      'receivedBytes': '9007199254740993',
                      'transmittedBytes': '0',
                      if (timing) ...{
                        'latestHandshake': '2026-09-14T00:00:00Z',
                        'persistentKeepalive': '0s',
                      },
                    },
                  ],
                },
              },
              'dns': {
                if (populated) ...{
                  'searchDomain': 'mesh.example',
                  'servers': ['100.64.0.53', 'fd00::53'],
                  if (timing) 'ttl': '12s',
                  'records': [
                    {
                      'nodeId': 'node-a',
                      'hostname': 'host-a',
                      'label': 'host',
                      'fqdn': 'host.mesh.example',
                      'addresses': ['100.64.0.1', 'fd00::1'],
                    },
                  ],
                },
              },
            },
          })
          ..freeze();
        Future<void> render(ClientLocale locale) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ClientDiagnosticsDetails(
                    diagnostics: diagnostics,
                    locale: locale,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await render(initial);
        for (final key in ['diagnostic-tunnel', 'diagnostic-dns']) {
          final section = find.byKey(Key(key));
          await tester.ensureVisible(section);
          await tester.tap(
            find.descendant(of: section, matching: find.byType(ListTile)).first,
          );
          await tester.pumpAndSettle();
        }
        for (final locale in [
          initial,
          initial == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
        ]) {
          await render(locale);
          final ru = locale == ClientLocale.ru;
          String text(String en, String ruText) => ru ? ruText : en;
          final tunnel = <String>[
            '${text('Tunnel details', 'Подробности туннеля')}: ${scenario == 'absent' ? 0 : 1}',
          ];
          final dns = <String>[
            '${text('DNS details', 'Подробности DNS')}: ${scenario == 'absent' ? 0 : 1}',
          ];
          if (scenario == 'absent') {
            tunnel.add(
              text(
                'Tunnel inspection not reported.',
                'Проверка туннеля не предоставлена.',
              ),
            );
            dns.add(
              text(
                'DNS inspection not reported.',
                'Проверка DNS не предоставлена.',
              ),
            );
          } else {
            tunnel.addAll([
              '${text('Inspection OK', 'Проверка успешна')}: ${populated ? text('Yes', 'Да') : text('No', 'Нет')}',
              '${text('Interface', 'Интерфейс')}: ${populated ? 'tun0' : ''}',
              'MTU: ${populated ? 1280 : 0}',
              '${text('Listen port', 'Порт прослушивания')}: ${populated ? 51820 : 0}',
              '${text('Failure', 'Ошибка')}: ${populated ? text('Not supported', 'Не поддерживается') : text('Not reported', 'Не сообщена')}',
              '${text('Tunnel peers', 'Устройства туннеля')}: ${populated ? 1 : 0}',
              if (populated) ...[
                '${text('Peer', 'Устройство')}: peer-a',
                '${text('Public key', 'Публичный ключ')}: public-key-a',
                '${text('Endpoint', 'Адрес подключения')}: [fd00::1]:7',
                '${text('Allowed IPs', 'Разрешённые IP')}: 100.64.0.1/32, fd00::1/128',
                '${text('Latest handshake', 'Последнее рукопожатие')}: ${timing ? '2026-09-14T00:00:00Z' : text('Not reported', 'Не сообщается')}',
                '${text('Received bytes', 'Получено байт')}: 9007199254740993',
                '${text('Transmitted bytes', 'Отправлено байт')}: 0',
                '${text('Keepalive', 'Поддержание соединения')}: ${timing ? '0s' : text('Not reported', 'Не сообщается')}',
              ],
            ]);
            dns.addAll([
              '${text('Search domain', 'Поисковый домен')}: ${populated ? 'mesh.example' : ''}',
              'TTL: ${timing ? '12s' : text('Not reported', 'Не сообщается')}',
              '${text('Servers', 'Серверы')}: ${populated ? '100.64.0.53, fd00::53' : ''}',
              '${text('Records', 'Записи')}: ${populated ? 1 : 0}',
              if (populated) ...[
                '${text('Node', 'Узел')}: node-a',
                '${text('Hostname', 'Имя хоста')}: host-a',
                '${text('Label', 'Метка')}: host',
                'FQDN: host.mesh.example',
                '${text('Addresses', 'Адреса')}: 100.64.0.1, fd00::1',
              ],
            ]);
          }
          for (final (key, expected) in [
            ('diagnostic-tunnel', tunnel),
            ('diagnostic-dns', dns),
          ]) {
            expect(
              tester
                  .widgetList<Text>(
                    find.descendant(
                      of: find.byKey(Key(key)),
                      matching: find.byType(Text),
                    ),
                  )
                  .map((t) => t.data),
              expected,
            );
          }
          expect(find.textContaining('private reason'), findsNothing);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
