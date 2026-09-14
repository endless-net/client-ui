@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_networks.dart';
import 'package:endlessnet/client_networks_panel.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

api.WatchEventsResponse snapshot(int sequence) =>
    api.WatchEventsResponse()..mergeFromProto3Json({
      'sequence': '$sequence',
      'metadata': {'instanceId': 'runtime-a', 'revision': '$sequence'},
      'snapshot': {
        'runtime': {
          'protocol': api.ClientContract.protocol,
          'contractSha256': api.ClientContract.sha256,
          'instanceId': 'runtime-a',
          'callerAccess': 'ACCESS_OWNER',
        },
        'status': {
          'metadata': {'instanceId': 'runtime-a', 'revision': '$sequence'},
          'activeProfileId': 'profile-a',
        },
      },
    });

Future<ClientNetworkCatalog> catalog({bool empty = false}) =>
    readClientNetworks(
      (_) async => api.ListNetworksResponse()
        ..mergeFromProto3Json({
          'selectedNetworkId': empty ? '' : 'a',
          'networks': [
            for (final id in empty ? <String>[] : ['a', 'b'])
              {
                'id': id,
                'name': 'Network $id',
                'selection': {'availability': 'AVAILABILITY_AVAILABLE'},
              },
          ],
          'page': {
            'metadata': {'instanceId': 'runtime-a', 'revision': '1'},
          },
        }),
      instanceId: 'runtime-a',
      profileId: 'profile-a',
    );

ClientOperation operation(bool terminal) => ClientOperation.fromProto(
  api.Operation()..mergeFromProto3Json({
    'id': 'operation',
    'requestId': 'request',
    'kind': 'OPERATION_KIND_SELECT_NETWORK',
    'state': terminal ? 'OPERATION_STATE_FAILED' : 'OPERATION_STATE_PENDING',
    if (terminal) 'failure': {'code': 'ERROR_CODE_STALE_STATE'},
  }),
);

void main() {
  for (final scenario in ['snapshot', 'controller', 'reload', 'late lookup']) {
    testWidgets('network action context: $scenario', (tester) async {
      final states = [ClientStateController(), ClientStateController()];
      final streams = [
        StreamController<api.WatchEventsResponse>(),
        StreamController<api.WatchEventsResponse>(),
      ];
      for (var i = 0; i < states.length; i++) {
        await states[i].attach(streams[i].stream);
        streams[i].add(snapshot(1));
      }
      final pending = Completer<ClientNetworkCatalog>();
      var calls = 0;
      var loads = 0;
      Future<void> render(ClientStateController state) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ClientNetworksPanel(
                state: state,
                load: () {
                  loads++;
                  return scenario == 'late lookup' && loads == 1
                      ? pending.future
                      : catalog();
                },
                select: (profile, network) async {
                  calls++;
                  return operation(false);
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await render(states.first);
      await tester.tap(find.byKey(const Key('client-load-networks')));
      await tester.pumpAndSettle();
      if (scenario == 'late lookup') {
        await render(states.last);
        pending.complete(await catalog());
        await tester.pumpAndSettle();
        expect(find.text('Network b'), findsNothing);
      } else {
        final callback = tester
            .widget<TextButton>(find.byKey(const ValueKey('select-network-b')))
            .onPressed!;
        if (scenario == 'controller') {
          await render(states.last);
        } else if (scenario == 'snapshot') {
          streams.first.add(snapshot(2));
          await tester.pumpAndSettle();
        } else {
          await tester.tap(find.byKey(const Key('client-load-networks')));
          await tester.pumpAndSettle();
        }
        callback();
        await tester.pumpAndSettle();
        expect(calls, 0);
      }
      // A fresh lookup still allows the same selection after invalidation.
      await tester.tap(find.byKey(const Key('client-load-networks')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-network-b')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        for (var i = 0; i < states.length; i++) {
          await states[i].detach();
          await streams[i].close();
          states[i].dispose();
        }
      });
    });
  }
  for (final initial in ClientLocale.values) {
    for (final result in ['accepted', 'terminal', 'unknown', 'empty']) {
      testWidgets('network $result text in $initial', (tester) async {
        final state = ClientStateController();
        final stream = StreamController<api.WatchEventsResponse>();
        await state.attach(stream.stream);
        stream.add(snapshot(1));
        var calls = 0;
        var loads = 0;
        Future<void> render(ClientLocale locale) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ClientNetworksPanel(
                  state: state,
                  locale: locale,
                  load: () {
                    loads++;
                    return catalog(empty: result == 'empty');
                  },
                  select: (profile, network) async {
                    expect(profile, 'profile-a');
                    expect(network, 'b');
                    calls++;
                    if (result == 'unknown') {
                      throw StateError('private details');
                    }
                    return operation(result == 'terminal');
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        List<String> texts() => tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .whereType<String>()
            .toList();
        await render(initial);
        await tester.tap(find.byKey(const Key('client-load-networks')));
        await tester.pumpAndSettle();
        final ru = initial == ClientLocale.ru;
        expect(texts(), [
          ru ? 'Обновить сети' : 'Refresh networks',
          if (result == 'empty')
            ru ? 'Нет сетей' : 'No networks'
          else ...[
            'Network a',
            'a',
            ru ? 'ID аккаунта: Нет данных' : 'Account ID: Not reported',
            ru ? 'Диапазон IPv4: Нет данных' : 'IPv4 range: Not reported',
            ru ? 'Диапазон IPv6: Нет данных' : 'IPv6 range: Not reported',
            ru ? 'Выбрана' : 'Selected',
            'Network b',
            'b',
            ru ? 'ID аккаунта: Нет данных' : 'Account ID: Not reported',
            ru ? 'Диапазон IPv4: Нет данных' : 'IPv4 range: Not reported',
            ru ? 'Диапазон IPv6: Нет данных' : 'IPv6 range: Not reported',
            ru ? 'Выбор: Доступно' : 'Selection: Available',
            ru
                ? 'Ответственный за действие: Неизвестно'
                : 'Action owner: Unknown',
            ru ? 'Выбрать' : 'Select',
          ],
        ]);
        if (result != 'empty') {
          await tester.tap(find.byKey(const ValueKey('select-network-b')));
          await tester.pumpAndSettle();
        }
        for (final locale in [
          initial,
          initial == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
        ]) {
          await render(locale);
          final ru = locale == ClientLocale.ru;
          final notice = switch (result) {
            'empty' => ru ? 'Нет сетей' : 'No networks',
            'accepted' =>
              ru
                  ? 'Выбор сети принят. Восстановите операцию, чтобы узнать результат.'
                  : 'Network selection accepted. Recover the operation for its result.',
            'terminal' =>
              ru
                  ? 'Получен результат выбора сети. Обновите состояние клиента.'
                  : 'Network selection result received. Refresh runtime status.',
            _ =>
              ru
                  ? 'Не удалось подтвердить запрос сети. Восстановите незавершённый выбор сети перед повторной попыткой.'
                  : 'Network request could not be confirmed. Recover any pending selection before retrying.',
          };
          expect(texts(), [ru ? 'Обновить сети' : 'Refresh networks', notice]);
          expect(calls, result == 'empty' ? 0 : 1);
          expect(loads, 1);
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
