@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_peer_labels.dart';
import 'package:endlessnet/client_peers.dart';
import 'package:endlessnet/client_peers_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

void main() {
  test('closed peer enums have exact RU/EN projections', () {
    expect(
      api.AgentSnapshotState.values.map(
        (v) => peerSnapshotLabel(v, ClientLocale.en),
      ),
      ['Not specified', 'Absent', 'Current', 'Previous'],
    );
    expect(
      api.AgentSnapshotState.values.map(
        (v) => peerSnapshotLabel(v, ClientLocale.ru),
      ),
      ['Не указано', 'Отсутствует', 'Текущее', 'Предыдущее'],
    );
    expect(api.PathKind.values.map((v) => peerPathLabel(v, ClientLocale.en)), [
      'Not specified',
      'Direct',
      'Relay',
    ]);
    expect(api.PathKind.values.map((v) => peerPathLabel(v, ClientLocale.ru)), [
      'Не указан',
      'Прямой',
      'Через ретранслятор',
    ]);
    expect(
      api.PathHealth.values.map((v) => peerHealthLabel(v, ClientLocale.en)),
      ['Not specified', 'Unknown', 'Checking', 'Reachable', 'Unreachable'],
    );
    expect(
      api.PathHealth.values.map((v) => peerHealthLabel(v, ClientLocale.ru)),
      ['Не указано', 'Неизвестно', 'Проверяется', 'Доступен', 'Недоступен'],
    );
  });
  for (final initial in ClientLocale.values) {
    for (final scenario in ['details', 'empty', 'error']) {
      testWidgets('peer $scenario in $initial', (tester) async {
        final state = ClientStateController();
        final stream = StreamController<api.WatchEventsResponse>();
        await state.attach(stream.stream);
        stream.add(fixtures.snapshot(1));
        var calls = 0;
        final pending = Completer<ClientPeerCatalog>();
        Future<void> render(ClientLocale locale) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ClientPeersPanel(
                    state: state,
                    locale: locale,
                    load: (_) {
                      calls++;
                      return pending.future;
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await render(initial);
        await tester.tap(find.byKey(const Key('client-load-peers')));
        await tester.pump();
        expect(
          find.text(
            initial == ClientLocale.ru
                ? 'Загрузка устройств…'
                : 'Loading peers…',
          ),
          findsOneWidget,
        );
        if (scenario == 'error') {
          pending.completeError(StateError('private details'));
        } else {
          pending.complete(
            await readClientPeers(
              (_) async => api.ListPeersResponse()
                ..mergeFromProto3Json({
                  'page': {
                    'metadata': {'instanceId': 'runtime-a', 'revision': '1'},
                  },
                  'snapshotState': 'AGENT_SNAPSHOT_STATE_PREVIOUS',
                  'mapRevision': '11',
                  'targetMapRevision': '12',
                  'peers': [
                    if (scenario == 'details')
                      {
                        'id': 'a',
                        'hostname': 'Host',
                        'selectedPath': 'PATH_KIND_RELAY',
                        'selectionReasonKey': 'path.direct_failed',
                        'candidates': [
                          {
                            'kind': 'PATH_KIND_DIRECT',
                            'health': 'PATH_HEALTH_UNREACHABLE',
                            'endpoint': '192.0.2.1:1234',
                            'consecutiveFailures': 2,
                            'reasonKey': 'path.timeout',
                          },
                        ],
                      },
                  ],
                }),
              instanceId: 'runtime-a',
              profileId: 'profile-a',
            ),
          );
        }
        await tester.pumpAndSettle();
        if (scenario == 'details') {
          await tester.tap(find.text('Host'));
          await tester.pumpAndSettle();
        }
        for (final locale in [
          initial,
          initial == ClientLocale.ru ? ClientLocale.en : ClientLocale.ru,
        ]) {
          await render(locale);
          final ru = locale == ClientLocale.ru;
          final actual = tester
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .whereType<String>()
              .toList();
          expect(actual, [
            ru ? 'Устройства' : 'Peers',
            ru ? 'Поиск устройств' : 'Search peers',
            ru ? 'Обновить устройства' : 'Refresh peers',
            if (scenario == 'error')
              ru
                  ? 'Не удалось подтвердить сведения об устройствах. Обновите список, чтобы повторить попытку.'
                  : 'Peer information could not be confirmed. Refresh to try again.'
            else ...[
              ru ? 'Состояние снимка: Предыдущее' : 'Snapshot: Previous',
              ru
                  ? 'Применённая карта: 11; целевая карта: 12'
                  : 'Applied map: 11; target map: 12',
              ru
                  ? 'Наблюдения службы; этот экран не проверяет доступность устройств.'
                  : 'Runtime observations; this screen does not probe peers.',
              if (scenario == 'empty')
                ru
                    ? 'В этом ответе нет устройств.'
                    : 'No peers in this response.'
              else ...[
                'Host',
                ru
                    ? 'ID: a\nВыбранный путь: Через ретранслятор'
                    : 'ID: a\nSelected path: Relay',
                ru ? 'Адреса оверлейной сети: ' : 'Overlay addresses: ',
                ru
                    ? 'Выбранный адрес подключения: не сообщено'
                    : 'Selected endpoint: not reported',
                ru
                    ? 'Код причины выбора: path.direct_failed'
                    : 'Selection reason: path.direct_failed',
                ru
                    ? 'Последний переход: не сообщено'
                    : 'Last transition: not reported',
                ru
                    ? 'Вариант пути: Прямой; Недоступен\nАдрес подключения: 192.0.2.1:1234; ретранслятор: \nПротокол: ; уровень: ; приоритет: 0\nRTT: не сообщено\nПроверено: не сообщено\nПоследняя доступность: не сообщено\nОшибок подряд: 2; код причины: path.timeout'
                    : 'Candidate: Direct; Unreachable\nEndpoint: 192.0.2.1:1234; relay: \nProtocol: ; tier: ; priority: 0\nRTT: not reported\nChecked: not reported\nLast reachable: not reported\nConsecutive failures: 2; reason: path.timeout',
              ],
            ],
          ]);
          expect(calls, 1);
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
