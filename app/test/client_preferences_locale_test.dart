@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_preference_labels.dart';
import 'package:endlessnet/client_preferences.dart';
import 'package:endlessnet/client_preferences_panel.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

void main() {
  test('all preference keys have exact RU/EN labels', () {
    expect(
      api.PreferenceKey.values.map(
        (v) => preferenceKeyLabel(v, ClientLocale.en),
      ),
      [
        "Not specified",
        "Allow inbound",
        "Accept DNS",
        "Accept routes",
        "Runtime start",
        "Graceful UI quit",
        "User logoff",
        "Suspend",
        "Resume",
      ],
    );
    expect(
      api.PreferenceKey.values.map(
        (v) => preferenceKeyLabel(v, ClientLocale.ru),
      ),
      [
        "Не указано",
        "Разрешить входящие подключения",
        "Принимать DNS",
        "Принимать маршруты",
        "Запуск службы",
        "Штатное закрытие интерфейса",
        "Выход пользователя из системы",
        "Приостановка",
        "Возобновление",
      ],
    );
  });
  test('optional, boolean and lifecycle preference values are localized', () {
    final values = [null, false, true, ...api.LifecycleBehavior.values];
    expect(values.map((v) => preferenceValueLabel(v, ClientLocale.en)), [
      'No override',
      'No',
      'Yes',
      'Not specified',
      'Keep intent',
      'Connect',
      'Disconnect',
      'Platform managed',
    ]);
    expect(values.map((v) => preferenceValueLabel(v, ClientLocale.ru)), [
      'Без переопределения',
      'Нет',
      'Да',
      'Не указано',
      'Сохранить намерение',
      'Подключить',
      'Отключить',
      'Управляется платформой',
    ]);
    expect(
      () => preferenceValueLabel('arbitrary', ClientLocale.en),
      throwsStateError,
    );
  });
  for (final initial in ClientLocale.values) {
    for (final scenario in ['catalog', 'locked', 'apply', 'reset', 'error']) {
      testWidgets('preferences $scenario in $initial', (tester) async {
        final state = ClientStateController();
        final stream = StreamController<api.WatchEventsResponse>();
        await state.attach(stream.stream);
        final snapshot = fixtures.snapshot(1);
        snapshot.snapshot.runtime.mergeFromProto3Json({
          'capabilities': [
            for (final cap in [
              'CAPABILITY_PREFERENCES',
              'CAPABILITY_MANAGED_SETTINGS',
            ])
              {
                'capability': cap,
                'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
              },
          ],
        });
        stream.add(snapshot);
        var loads = 0;
        var applies = 0;
        var resets = 0;
        Future<void> render(ClientLocale locale) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ClientPreferencesPanel(
                    state: state,
                    locale: locale,
                    load: () async {
                      loads++;
                      if (scenario == 'error') {
                        throw StateError('private details');
                      }
                      return readClientPreferences(
                        instanceId: 'runtime-a',
                        profileId: 'profile-a',
                        checkContext: () {},
                        get: (_) async =>
                            api.GetPreferencesResponse()..mergeFromProto3Json({
                              'preferences': {
                                'profileId': 'profile-a',
                                'metadata': {
                                  'instanceId': 'runtime-a',
                                  'revision': '1',
                                },
                                'allowInbound': {
                                  'effective': true,
                                  'requested': false,
                                  'control': {
                                    'source': 'SETTING_SOURCE_DEVICE_POLICY',
                                    'locked': scenario == 'locked',
                                    'mutation': {
                                      'availability': 'AVAILABILITY_AVAILABLE',
                                      'reasonKey': 'policy.control',
                                      'actionOwner':
                                          'ACTION_OWNER_DEVICE_ADMINISTRATOR',
                                    },
                                  },
                                },
                              },
                            }),
                        listManaged: (_) async =>
                            api.ListManagedSettingsResponse()
                              ..mergeFromProto3Json({
                                'metadata': {
                                  'instanceId': 'runtime-a',
                                  'revision': '1',
                                },
                              }),
                      );
                    },
                    apply: (profile, patch, check) async {
                      check();
                      applies++;
                      expect(profile, 'profile-a');
                      expect(patch.toProto3Json(), {'allowInbound': true});
                      return ClientOperation.fromProto(
                        api.Operation(
                          id: 'op',
                          kind:
                              api.OperationKind.OPERATION_KIND_SET_PREFERENCES,
                          state: api.OperationState.OPERATION_STATE_PENDING,
                        ),
                      );
                    },
                    reset: (profile, keys, check) async {
                      check();
                      resets++;
                      expect(profile, 'profile-a');
                      expect(keys, [
                        api.PreferenceKey.PREFERENCE_KEY_ALLOW_INBOUND,
                      ]);
                      return ClientOperation.fromProto(
                        api.Operation(
                          id: 'op',
                          kind: api
                              .OperationKind
                              .OPERATION_KIND_RESET_PREFERENCES,
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
          await tester.tap(f);
          await tester.pumpAndSettle();
        }

        final key = api.PreferenceKey.PREFERENCE_KEY_ALLOW_INBOUND.value;
        await render(initial);
        await tap('client-load-preferences');
        if (scenario == 'apply') {
          tester
              .widget<DropdownButton<Object>>(
                find.byKey(ValueKey('preference-$key')),
              )
              .onChanged!(false);
          await tester.pumpAndSettle();
          final oldApply = tester
              .widget<FilledButton>(
                find.byKey(const Key('client-apply-preferences')),
              )
              .onPressed!;
          final oldDiscard = tester
              .widget<OutlinedButton>(
                find.byKey(const Key('client-discard-preferences')),
              )
              .onPressed!;
          tester
              .widget<DropdownButton<Object>>(
                find.byKey(ValueKey('preference-$key')),
              )
              .onChanged!(true);
          await tester.pumpAndSettle();
          oldApply();
          oldDiscard();
          await tester.pumpAndSettle();
          expect(applies, 0);
          expect(
            tester
                .widget<DropdownButton<Object>>(
                  find.byKey(ValueKey('preference-$key')),
                )
                .value,
            true,
          );
          await tap('client-apply-preferences');
        }
        if (scenario == 'reset') {
          await tap('reset-preference-$key');
        }
        for (final locale in [
          initial,
          initial == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
        ]) {
          await render(locale);
          final ru = locale == ClientLocale.ru;
          final text = tester
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .whereType<String>()
              .toList();
          if (['apply', 'reset', 'error'].contains(scenario)) {
            expect(text, [
              ru ? 'Обновить настройки' : 'Refresh preferences',
              scenario == 'error'
                  ? (ru
                        ? 'Не удалось подтвердить настройки. Восстановите незавершённые операции перед повторной попыткой.'
                        : 'Preferences could not be confirmed. Recover pending operations before retrying.')
                  : (ru
                        ? 'Операция настройки получена. Восстановите её результат и обновите фактические значения.'
                        : 'Preference operation received. Recover its result and refresh effective values.'),
            ]);
          } else {
            final locked = scenario == 'locked';
            final allowed = {
              ru ? 'Обновить настройки' : 'Refresh preferences',
              ru ? 'Разрешить входящие подключения' : 'Allow inbound',
              ru
                  ? 'Фактически: Да; Запрошено: Нет'
                  : 'Effective: Yes; requested: No',
              ru
                  ? 'Источник: Политика устройства; Заблокировано: ${locked ? 'Да' : 'Нет'}; Доступность: Доступно; Код причины: policy.control; Ответственный: Администратор устройства'
                  : 'Source: Device policy; locked: ${locked ? 'Yes' : 'No'}; availability: Available; reason: policy.control; owner: Device administrator',
              ru ? 'Да' : 'Yes',
              ru ? 'Нет' : 'No',
              ru ? 'Оставить без изменений' : 'Leave unchanged',
              ru ? 'Сбросить переопределение' : 'Reset override',
              ru ? 'Отменить правки' : 'Discard draft',
              ru ? 'Применить изменения настроек' : 'Apply preference patch',
            };
            expect(
              text.every(allowed.contains),
              isTrue,
              reason: text.join('\n'),
            );
            expect(
              find.text(
                ru
                    ? 'Фактически: Да; Запрошено: Нет'
                    : 'Effective: Yes; requested: No',
              ),
              findsOneWidget,
            );
            expect(
              tester
                      .widget<DropdownButton<Object>>(
                        find.byKey(ValueKey('preference-$key')),
                      )
                      .onChanged ==
                  null,
              locked,
            );
          }
          expect(loads, 1);
          expect(applies, scenario == 'apply' ? 1 : 0);
          expect(resets, scenario == 'reset' ? 1 : 0);
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
