@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_diagnostics_panel.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

void main() {
  test('all diagnostic connection phases have exact RU/EN labels', () {
    expect(
      api.ConnectionPhase.values.map(
        (p) => diagnosticPhaseLabel(p, ClientLocale.en),
      ),
      [
        'Not specified',
        'Disconnected',
        'Connecting',
        'Connected',
        'Disconnecting',
      ],
    );
    expect(
      api.ConnectionPhase.values.map(
        (p) => diagnosticPhaseLabel(p, ClientLocale.ru),
      ),
      ['Не указано', 'Отключено', 'Подключение', 'Подключено', 'Отключение'],
    );
  });
  final cases = [
    (
      'logs',
      'Logs could not be read. Refresh to start a new snapshot.',
      'Не удалось прочитать журнал. Обновите его, чтобы получить новый снимок.',
    ),
    (
      'preview',
      'Diagnostics could not be read.',
      'Не удалось прочитать диагностику.',
    ),
    (
      'succeeded',
      'Bundle operation succeeded. Recover its handle before verified download; nothing was exported.',
      'Операция создания архива завершилась успешно. Восстановите дескриптор для проверенной загрузки; ничего не экспортировано.',
    ),
    (
      'received',
      'Bundle operation received. Recover its result; archive readiness is not confirmed.',
      'Операция создания архива получена. Восстановите её результат; готовность архива не подтверждена.',
    ),
    (
      'unknown',
      'Bundle creation could not be confirmed. Recover the intention before another attempt.',
      'Не удалось подтвердить создание архива. Восстановите исходное намерение перед повторной попыткой.',
    ),
    ('summary', '', ''),
    ('empty logs', '', ''),
  ];
  for (final initial in ClientLocale.values) {
    for (final scenario in cases) {
      testWidgets('diagnostics ${scenario.$1} in $initial', (tester) async {
        final state = ClientStateController();
        final stream = StreamController<api.WatchEventsResponse>();
        await state.attach(stream.stream);
        final snapshot = fixtures.snapshot(1);
        snapshot.snapshot.runtime.mergeFromProto3Json({
          'capabilities': [
            {
              'capability': 'CAPABILITY_DIAGNOSTICS',
              'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
            },
          ],
        });
        stream.add(snapshot);
        var loads = 0;
        var logs = 0;
        var creates = 0;
        Future<void> render(ClientLocale locale) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ClientDiagnosticsPanel(
                    state: state,
                    locale: locale,
                    load: () async {
                      loads++;
                      if (scenario.$1 == 'preview') {
                        throw StateError('private details');
                      }
                      return api.Diagnostics()..mergeFromProto3Json({
                        'metadata': {
                          'instanceId': 'runtime-a',
                          'revision': '1',
                        },
                        'osName': 'OS',
                        'osVersion': 'test',
                        'goVersion': 'test',
                        'truncated': true,
                        'status': {
                          'connectionPhase': 'CONNECTION_PHASE_CONNECTED',
                          'pendingAction': {
                            'browserUrl': 'https://private.example/action',
                          },
                        },
                      });
                    },
                    loadLogs: () async {
                      logs++;
                      if (scenario.$1 == 'logs') {
                        throw StateError('private log detail');
                      }
                      return [];
                    },
                    createBundle: (profile) async {
                      creates++;
                      expect(profile, 'profile-a');
                      if (scenario.$1 == 'unknown') {
                        throw StateError('private archive detail');
                      }
                      return ClientOperation.fromProto(
                        api.Operation()..mergeFromProto3Json({
                          'id': 'op',
                          'kind': 'OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE',
                          'state': scenario.$1 == 'succeeded'
                              ? 'OPERATION_STATE_SUCCEEDED'
                              : 'OPERATION_STATE_PENDING',
                          if (scenario.$1 == 'succeeded') ...{
                            'continuity': 'CONNECTION_CONTINUITY_PRESERVED',
                            'bundle': {},
                          },
                        }),
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
          final finder = find.byKey(Key(key));
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        await render(initial);
        final logCase = ['logs', 'empty logs'].contains(scenario.$1);
        await tap(logCase ? 'load-client-logs' : 'load-client-diagnostics');
        final archiveCase = [
          'succeeded',
          'received',
          'unknown',
        ].contains(scenario.$1);
        if (archiveCase) {
          await tap('create-client-bundle');
          final oldConfirm = tester
              .widget<TextButton>(
                find.byKey(const Key('confirm-client-bundle')),
              )
              .onPressed!;
          await tap('cancel-client-bundle');
          await tap('create-client-bundle');
          oldConfirm();
          await tester.pumpAndSettle();
          expect(creates, 0);
          expect(
            find.text(
              initial == ClientLocale.ru
                  ? 'Создать локальный архив диагностики с удалёнными конфиденциальными данными? Это не отправляет и не экспортирует архив.'
                  : 'Create a local redacted diagnostics archive? This does not upload or export it.',
            ),
            findsOneWidget,
          );
          await tap('confirm-client-bundle');
        }
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
              ru ? 'Прочитать последние записи журнала' : 'Read recent logs',
              if (scenario.$1 == 'empty logs') ...[
                ru
                    ? 'Последние записи локального журнала — не полная история. Ничего не отправлено.'
                    : 'Recent local log window — not a complete history. Nothing uploaded.',
                ru
                    ? 'Нет последних записей журнала.'
                    : 'No recent log entries.',
              ],
              ru ? 'Просмотреть диагностику' : 'Inspect diagnostics',
              if (!logCase && scenario.$1 != 'preview') ...[
                ru
                    ? 'Сводка локальной диагностики — данные не скопированы и не отправлены.'
                    : 'Local diagnostics summary — no data copied or uploaded.',
                ru ? 'ОС: OS test' : 'OS: OS test',
                'Go: test',
                ru
                    ? 'Интерфейсы: 0; маршруты: 0; устройства: 0'
                    : 'Interfaces: 0; routes: 0; peers: 0',
                ru
                    ? 'Конфликты маршрутов: 0; ошибки: 0'
                    : 'Route conflicts: 0; failures: 0',
                ru
                    ? 'Диагностика сокращена; это не полный отчёт.'
                    : 'Diagnostics are truncated; this is not a complete report.',
                ru
                    ? 'Состояние подключения: Подключено'
                    : 'Connection phase: Connected',
                ru
                    ? 'Это сводка. Восстановите операцию создания архива для проверенной загрузки и отдельного экспорта, если он поддерживается.'
                    : 'This is a summary. Recover the archive operation for verified download and a separate export, when supported.',
                ru ? 'Создать архив диагностики' : 'Create diagnostics archive',
                ru ? 'Подробности интерфейсов: 0' : 'Interface details: 0',
                ru ? 'Подробности маршрутов: 0' : 'Route details: 0',
                ru ? 'Подробности конфликтов: 0' : 'Conflict details: 0',
                ru ? 'Подробности ошибок: 0' : 'Failure details: 0',
              ],
              if (scenario.$2.isNotEmpty) ru ? scenario.$3 : scenario.$2,
            ],
          );
          expect(loads, logCase ? 0 : 1);
          expect(logs, logCase ? 1 : 0);
          expect(creates, archiveCase ? 1 : 0);
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
