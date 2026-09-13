@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_exit_labels.dart';
import 'package:endlessnet/client_exit_panel.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_exit_activation_test.dart' as fixtures;

void main() {
  test('all exit family modes have RU/EN labels', () {
    expect(
      api.ExitFamilyMode.values.map(
        (v) => exitFamilyModeLabel(v, ClientLocale.en),
      ),
      ['Not specified', 'No exit', 'IPv4 only', 'IPv6 only', 'IPv4 and IPv6'],
    );
    expect(
      api.ExitFamilyMode.values.map(
        (v) => exitFamilyModeLabel(v, ClientLocale.ru),
      ),
      [
        'Не указано',
        'Без выходного узла',
        'Только IPv4',
        'Только IPv6',
        'IPv4 и IPv6',
      ],
    );
  });
  test('all LAN policies have RU/EN labels', () {
    expect(
      api.LanAccess.values.map((v) => exitLanAccessLabel(v, ClientLocale.en)),
      ['Not specified', 'Block', 'Allow'],
    );
    expect(
      api.LanAccess.values.map((v) => exitLanAccessLabel(v, ClientLocale.ru)),
      ['Не указано', 'Запретить', 'Разрешить'],
    );
  });
  test('all apply states have RU/EN labels', () {
    expect(
      api.ApplyState.values.map((v) => exitApplyStateLabel(v, ClientLocale.en)),
      ['Not specified', 'Pending', 'Applied', 'Failed'],
    );
    expect(
      api.ApplyState.values.map((v) => exitApplyStateLabel(v, ClientLocale.ru)),
      ['Не указано', 'Ожидание', 'Применено', 'Ошибка'],
    );
  });
  for (final initial in ClientLocale.values) {
    for (final scenario in [
      'catalog',
      'ipv4',
      'ipv6',
      'confirm',
      'select',
      'clear',
      'error',
    ]) {
      testWidgets('exit $scenario in $initial', (tester) async {
        final state = ClientStateController();
        final stream = StreamController<api.WatchEventsResponse>();
        await state.attach(stream.stream);
        stream.add(fixtures.snapshot(1));
        var loads = 0;
        var commands = 0;
        Future<void> render(ClientLocale locale) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ClientExitPanel(
                    state: state,
                    locale: locale,
                    load: () async {
                      loads++;
                      if (scenario == 'error') {
                        throw StateError('private failure');
                      }
                      return fixtures.catalog();
                    },
                    select: (profile, node, mode, lan, check) async {
                      check();
                      commands++;
                      expect(
                        (profile, node, mode, lan),
                        (
                          'profile-a',
                          'a',
                          api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV4_ONLY,
                          api.LanAccess.LAN_ACCESS_BLOCK,
                        ),
                      );
                      return fixtures.pending(
                        api.OperationKind.OPERATION_KIND_SELECT_EXIT_NODE,
                      );
                    },
                    clear: (profile, check) async {
                      check();
                      commands++;
                      expect(profile, 'profile-a');
                      return fixtures.pending(
                        api.OperationKind.OPERATION_KIND_CLEAR_EXIT_NODE,
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Future<void> button(String key) async {
          tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed!();
          await tester.pumpAndSettle();
        }

        Future<void> change<T>(String key, T value) async {
          tester.widget<DropdownButton<T>>(find.byKey(Key(key))).onChanged!(
            value,
          );
          await tester.pumpAndSettle();
        }

        await render(initial);
        await button('client-load-exits');
        if (['ipv4', 'ipv6', 'select'].contains(scenario)) {
          await change('client-exit-node', 'a');
          await change(
            'client-exit-mode',
            scenario == 'ipv6'
                ? api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV6_ONLY
                : api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV4_ONLY,
          );
          await change('client-exit-lan', api.LanAccess.LAN_ACCESS_BLOCK);
          if (scenario == 'select') await button('client-select-exit');
        }
        if (scenario == 'confirm' || scenario == 'clear') {
          await button('client-clear-exit');
          if (scenario == 'clear') await button('client-confirm-clear-exit');
        }
        for (final locale in [
          initial,
          initial == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
        ]) {
          await render(locale);
          final ru = locale == ClientLocale.ru;
          final texts = tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .whereType<String>()
              .toSet();
          final refresh = ru ? 'Обновить выходные узлы' : 'Refresh exit nodes';
          if (['select', 'clear', 'error'].contains(scenario)) {
            final notice = scenario == 'error'
                ? (ru
                      ? 'Запрос выходного узла не удалось подтвердить. Восстановите незавершённые операции перед повтором.'
                      : 'Exit request could not be confirmed. Recover pending operations before retrying.')
                : (ru
                      ? 'Операция выходного узла получена. Восстановите её результат и обновите состояние обоих семейств адресов.'
                      : 'Exit operation received. Recover its result and refresh both address families.');
            expect(texts, {refresh, notice});
            expect(
              tester
                  .widgetList<Semantics>(find.byType(Semantics))
                  .where((s) => s.properties.liveRegion == true),
              isNotEmpty,
            );
          } else {
            final expected = <String>{
              refresh,
              ru
                  ? 'Запрошенный режим: Без выходного узла'
                  : 'Requested exit mode: No exit',
              ru
                  ? 'Применение: Применено; ошибка: Не сообщена'
                  : 'Exit apply: Applied; failure: Not reported',
              for (final family in ['IPv4', 'IPv6']) ...[
                ru
                    ? '$family: запрошено Без выходного узла; фактически Без выходного узла'
                    : '$family: requested No exit; effective No exit',
                ru
                    ? '$family: Применено; блокировка при отказе по данным службы: Нет; ошибка: Не сообщена'
                    : '$family: Applied; reported fail-closed: No; failure: Not reported',
                ru
                    ? 'Для $family выходной узел не запрошен; текущая маршрутизация указана в фактическом состоянии.'
                    : 'No exit is requested for $family; see effective state for current routing.',
              ],
              ru
                  ? 'Локальная сеть: запрошено: Не указано; фактически: Не указано'
                  : 'LAN requested: Not specified; effective: Not specified',
              ru
                  ? 'Управление выходным узлом: Доступно; заблокировано: Нет; причина: ; исполнитель: Неизвестно'
                  : 'Exit control: Available; locked: No; reason: ; owner: Unknown',
              ru ? 'Выбрать выходной узел' : 'Select exit node',
              ru ? 'Сбросить выходной узел' : 'Clear exit node',
            };
            if (scenario == 'ipv4' || scenario == 'ipv6') {
              expected.addAll({
                ru ? 'Candidate a: Доступно' : 'Candidate a: Available',
                ru ? 'Запретить' : 'Block',
                scenario == 'ipv4'
                    ? (ru ? 'Только IPv4' : 'IPv4 only')
                    : (ru ? 'Только IPv6' : 'IPv6 only'),
                scenario == 'ipv4'
                    ? (ru
                          ? 'Этот выбор выходного узла не защитит IPv6.'
                          : 'IPv6 will not be protected by this exit selection.')
                    : (ru
                          ? 'Этот выбор выходного узла не защитит IPv4.'
                          : 'IPv4 will not be protected by this exit selection.'),
              });
            } else {
              expected.add(ru ? 'Выберите выходной узел' : 'Choose exit node');
            }
            if (scenario == 'confirm') {
              expected.addAll({
                ru
                    ? 'Сбросить выходной узел для обоих семейств адресов и восстановить обычную политику маршрутизации?'
                    : 'Clear both exit families and restore ordinary routing policy?',
                ru ? 'Отмена' : 'Cancel',
                ru ? 'Подтвердить сброс' : 'Confirm clear',
              });
            }
            expect(texts, expected);
          }
          expect(loads, 1);
          expect(commands, scenario == 'select' || scenario == 'clear' ? 1 : 0);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await state.detach();
          await stream.close();
          state.dispose();
        });
      });
    }
  }
}
