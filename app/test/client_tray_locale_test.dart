@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet/client_tray.dart';
import 'package:endlessnet/client_tray_labels.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';
import 'client_tray_test.dart' as fixtures;

void main() {
  test('tray service catalog covers all 12 values in RU/EN', () {
    expect(
      api.ServiceState.values.map(
        (v) => clientTrayServiceLabel(v, ClientLocale.en),
      ),
      [
        'Unknown',
        'Connected',
        'Disconnected',
        'Degraded',
        'Runtime error',
        'Device enrollment required',
        'Waiting for approval',
        'Server identity changed',
        'Recovering',
        'Recovery blocked',
        'Blocked by policy',
        'Login required',
      ],
    );
    expect(
      api.ServiceState.values.map(
        (v) => clientTrayServiceLabel(v, ClientLocale.ru),
      ),
      [
        'Неизвестно',
        'Подключено',
        'Отключено',
        'Работа с ограничениями',
        'Ошибка службы',
        'Требуется регистрация устройства',
        'Ожидание одобрения',
        'Идентичность сервера изменилась',
        'Восстановление',
        'Восстановление заблокировано',
        'Заблокировано политикой',
        'Требуется вход',
      ],
    );
  });
  test('tray local link catalog covers all four values in RU/EN', () {
    expect(
      ClientLinkState.values.map((v) => clientLinkLabel(v, ClientLocale.en)),
      ['Disconnected', 'Waiting for snapshot', 'Ready', 'Unavailable'],
    );
    expect(
      ClientLinkState.values.map((v) => clientLinkLabel(v, ClientLocale.ru)),
      ['Отключена', 'Ожидание состояния', 'Готова', 'Недоступна'],
    );
  });
  for (final initial in ClientLocale.values) {
    for (final outcome in ['pending', 'succeeded', 'failed', 'unknown']) {
      test('tray $outcome in $initial, no locale replay', () async {
        final state = ClientStateController();
        final stream = StreamController<api.WatchEventsResponse>();
        final completion = Completer<ClientOperation>();
        var commands = 0;
        final tray = ClientTray(
          state: state,
          locale: initial,
          connect: () {
            commands++;
            return completion.future;
          },
          disconnect: () {
            commands++;
            return completion.future;
          },
        );
        await state.attach(stream.stream);
        expect(
          tray.status,
          initial == ClientLocale.ru
              ? 'Ожидание состояния'
              : 'Waiting for snapshot',
        );
        stream.add(fixtures.snapshot(1));
        await pumpEventQueue();
        String? key(String prefix) => tray.menu.items!
            .singleWhere((i) => i.key?.startsWith('$prefix:') == true)
            .key;
        final oldConnect = key('connect');
        final oldDisconnect = key('disconnect');
        final other = initial == ClientLocale.en
            ? ClientLocale.ru
            : ClientLocale.en;
        tray.locale = other;
        await tray.activate(oldConnect);
        await tray.activate(oldDisconnect);
        expect(commands, 0);
        final current = key('connect');
        tray.locale = other;
        expect(
          key('connect'),
          current,
        ); // Selecting the current language is inert.
        final work = tray.activate(current);
        expect(commands, 1);
        tray.locale = initial; // Change language while the result is in flight.
        if (outcome == 'unknown') {
          completion.completeError(StateError('private diagnostic'));
        } else {
          completion.complete(
            ClientOperation.fromProto(
              api.Operation()..mergeFromProto3Json({
                'id': 'operation',
                'kind': 'OPERATION_KIND_CONNECT',
                'state': 'OPERATION_STATE_${outcome.toUpperCase()}',
                if (outcome == 'succeeded') ...{
                  'continuity': 'CONNECTION_CONTINUITY_PRESERVED',
                  'change': {},
                },
                if (outcome == 'failed')
                  'failure': {'code': 'ERROR_CODE_STALE_STATE'},
              }),
            ),
          );
        }
        await work;
        for (final locale in [initial, other]) {
          tray.locale = locale;
          final ru = locale == ClientLocale.ru;
          expect(
            tray.menu.items!.map((i) => i.label),
            ru
                ? [
                    'Открыть EndlessNet',
                    'Служба: Отключено',
                    'Подключить',
                    'Отключить',
                    'Выход',
                  ]
                : [
                    'Open EndlessNet',
                    'Runtime: Disconnected',
                    'Connect',
                    'Disconnect',
                    'Quit',
                  ],
          );
          expect(tray.status, ru ? 'Отключено' : 'Disconnected');
          expect(tray.notice, switch (outcome) {
            'pending' =>
              ru
                  ? 'Команда принята. Завершение ещё не подтверждено.'
                  : 'Command accepted. Completion is not yet confirmed.',
            'succeeded' =>
              ru
                  ? 'Команда выполнена. Проверьте состояние службы.'
                  : 'Command completed. Check runtime status.',
            'failed' =>
              ru
                  ? 'Команда завершилась ошибкой. Проверьте результат операции.'
                  : 'Command failed. Check the operation result.',
            _ =>
              ru
                  ? 'Результат команды неизвестен. Восстановите исходное намерение перед повтором.'
                  : 'Command result is unknown. Recover the original intention before retrying.',
          });
          expect(commands, 1);
        }
        tray.dispose();
        await state.detach();
        await stream.close();
        state.dispose();
      });
    }
  }
}
