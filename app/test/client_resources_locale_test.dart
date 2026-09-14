@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_resource_labels.dart';
import 'package:endlessnet/client_resources_panel.dart';
import 'package:endlessnet/client_resources.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

void main() {
  test('all resource kinds have exact RU/EN labels', () {
    expect(
      api.ResourceKind.values.map((v) => resourceKindLabel(v, ClientLocale.en)),
      ['Not specified', 'Host', 'Subnet', 'Service', 'Application'],
    );
    expect(
      api.ResourceKind.values.map((v) => resourceKindLabel(v, ClientLocale.ru)),
      ['Не указан', 'Узел', 'Подсеть', 'Сервис', 'Приложение'],
    );
  });
  test('all setting sources have exact RU/EN labels', () {
    expect(
      api.SettingSource.values.map(
        (v) => settingSourceLabel(v, ClientLocale.en),
      ),
      [
        'Not specified',
        'Default',
        'User',
        'Device policy',
        'Account policy',
        'Platform',
      ],
    );
    expect(
      api.SettingSource.values.map(
        (v) => settingSourceLabel(v, ClientLocale.ru),
      ),
      [
        'Не указан',
        'По умолчанию',
        'Пользователь',
        'Политика устройства',
        'Политика учётной записи',
        'Платформа',
      ],
    );
  });
  final cases = [
    (
      'opened',
      'Resource address handed to the browser. Reachability has not been verified.',
      'Адрес ресурса передан браузеру. Доступность назначения не проверена.',
    ),
    (
      'notOpened',
      'Browser could not open the resource.',
      'Браузер не смог открыть ресурс.',
    ),
    (
      'destination',
      'Resource access or destination could not be confirmed. Refresh before opening.',
      'Не удалось подтвердить доступ к ресурсу или его адрес. Обновите сведения перед открытием.',
    ),
    (
      'received',
      'Resource operation received. Recover its result and refresh effective values.',
      'Операция с ресурсом получена. Восстановите её результат и обновите фактические значения.',
    ),
    (
      'unknown',
      'Resource request could not be confirmed. Recover pending operations before retrying.',
      'Не удалось подтвердить запрос ресурса. Восстановите незавершённые операции перед повторной попыткой.',
    ),
    ('catalog', '', ''),
    ('empty', '', ''),
  ];
  for (final initial in ClientLocale.values) {
    for (final scenario in cases) {
      testWidgets('resource ${scenario.$1} in $initial', (tester) async {
        final state = ClientStateController();
        final semantics = tester.ensureSemantics();

        final stream = StreamController<api.WatchEventsResponse>();
        await state.attach(stream.stream);
        final snapshot = fixtures.snapshot(1);
        snapshot.snapshot.runtime.mergeFromProto3Json({
          'capabilities': [
            {
              'capability': 'CAPABILITY_RESOURCES',
              'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
            },
          ],
        });
        stream.add(snapshot);
        var loads = 0;
        var opens = 0;
        var changes = 0;
        Future<void> render(ClientLocale locale) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ClientResourcesPanel(
                    state: state,
                    locale: locale,
                    load: (search, kinds) async {
                      loads++;
                      if (scenario.$1 == 'destination' && loads > 1) {
                        throw StateError('private destination');
                      }
                      return readClientResources(
                        (_) async => api.ListResourcesResponse()
                          ..mergeFromProto3Json({
                            'page': {
                              'metadata': {
                                'instanceId': 'runtime-a',
                                'revision': '1',
                              },
                            },
                            'resources': [
                              if (scenario.$1 != 'empty')
                                {
                                  'id': 'app',
                                  'networkId': 'network',
                                  'displayName': 'Example',
                                  'kind': 'RESOURCE_KIND_APPLICATION',
                                  'application': {
                                    'browserUrl':
                                        'https://application.example/',
                                    'displayAddress': 'application.example',
                                  },
                                  'availability': {
                                    'availability': 'AVAILABILITY_AVAILABLE',
                                    'reasonKey': 'access.ready',
                                    'actionOwner': 'ACTION_OWNER_USER',
                                  },
                                  'enabled': {
                                    'effective': false,
                                    'requested': true,
                                    'control': {
                                      'source': 'SETTING_SOURCE_USER',
                                      'locked': false,
                                      'mutation': {
                                        'availability':
                                            'AVAILABILITY_AVAILABLE',
                                        'actionOwner': 'ACTION_OWNER_USER',
                                      },
                                    },
                                  },
                                  'overlappingResourceIds': ['other'],
                                  'overlapReasonKey': 'overlap.route',
                                },
                            ],
                          }),
                        instanceId: 'runtime-a',
                        profileId: 'profile-a',
                        search: search,
                        kinds: kinds,
                        checkContext: () {},
                      );
                    },
                    openBrowser: (uri, check) async {
                      check();
                      expect(uri.toString(), 'https://application.example/');
                      opens++;
                      return scenario.$1 != 'notOpened';
                    },
                    setEnabled: (profile, id, enabled, check) async {
                      check();
                      expect(profile, 'profile-a');
                      expect(id, 'app');
                      expect(enabled, isFalse);
                      changes++;
                      if (scenario.$1 == 'unknown') {
                        throw StateError('private mutation');
                      }
                      return ClientOperation.fromProto(
                        api.Operation(
                          id: 'op',
                          kind: api
                              .OperationKind
                              .OPERATION_KIND_SET_RESOURCE_ENABLED,
                          state: api.OperationState.OPERATION_STATE_PENDING,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Future<void> tap(String key) async {
          final f = find.byKey(Key(key));
          await tester.ensureVisible(f);
          await tester.pumpAndSettle();
          if (key == 'open-resource-app') {
            expect(
              tester.getSemantics(f).label,
              initial == ClientLocale.ru
                  ? 'Открыть ресурс Example, ID app, в браузере'
                  : 'Open resource Example, ID app, in browser',
            );
          }
          await tester.tap(f);
          await tester.pumpAndSettle();
        }

        await render(initial);
        await tap('client-load-resources');
        if (['opened', 'notOpened', 'destination'].contains(scenario.$1)) {
          await tap('open-resource-app');
        }
        if (['received', 'unknown'].contains(scenario.$1)) {
          await tap('resource-app-false');
        }
        final expectedLoads = loads;
        final expectedOpens = opens;
        final expectedChanges = changes;
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
              ru ? 'Поиск ресурсов' : 'Search resources',
              ...(ru
                  ? ['Узел', 'Подсеть', 'Сервис', 'Приложение']
                  : ['Host', 'Subnet', 'Service', 'Application']),
              ru ? 'Поиск ресурсов' : 'Search resources',
              if (scenario.$2.isNotEmpty) ru ? scenario.$3 : scenario.$2,
              if (scenario.$1 == 'empty')
                ru ? 'Подходящих ресурсов нет' : 'No matching resources',
              if (['catalog', 'opened', 'notOpened'].contains(scenario.$1)) ...[
                'Example',
                ru ? 'ID ресурса: app' : 'Resource ID: app',
                ru ? 'ID сети: network' : 'Network ID: network',
                ru ? 'Открыть ресурс в браузере' : 'Open resource in browser',
                ru
                    ? 'Приложение: application.example'
                    : 'Application: application.example',
                ru
                    ? 'Фактически: Нет; Запрошено: Да'
                    : 'Effective: No; requested: Yes',
                ru
                    ? 'Доступность: Доступно; Код причины: access.ready; Ответственный: Вы'
                    : 'Availability: Available; reason: access.ready; owner: You',
                ru
                    ? 'Источник: Пользователь; Заблокировано: Нет'
                    : 'Source: User; locked: No',
                ru
                    ? 'Изменение: Доступно; Код причины: ; Ответственный: Вы'
                    : 'Mutation: Available; reason: ; owner: You',
                ru
                    ? 'Пересечение: other; overlap.route'
                    : 'Overlap: other; overlap.route',
                ru ? 'Включить ресурс' : 'Enable resource',
                ru ? 'Отключить ресурс' : 'Disable resource',
              ],
            ],
          );
          expect(loads, expectedLoads);
          expect(opens, expectedOpens);
          expect(changes, expectedChanges);
        }
        expect(changes, ['received', 'unknown'].contains(scenario.$1) ? 1 : 0);
        expect(opens, ['opened', 'notOpened'].contains(scenario.$1) ? 1 : 0);
        expect(
          loads,
          ['opened', 'notOpened', 'destination'].contains(scenario.$1) ? 2 : 1,
        );
        semantics.dispose();
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
