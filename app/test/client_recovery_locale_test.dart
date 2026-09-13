import 'dart:async';
import 'dart:convert';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_recovery_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases =
      jsonDecode(
            r'''[{"id":"browserOpened","en":"Browser opened. The operation is still pending; recover its result.","ru":"Браузер открыт. Операция ещё выполняется; запросите её результат."},{"id":"browserUnavailable","en":"Browser could not be opened. The operation is retained.","ru":"Не удалось открыть браузер. Операция сохранена."},{"id":"browserFailed","en":"Browser action could not be completed. Refresh the operation; no command was replayed.","ru":"Не удалось выполнить действие в браузере. Обновите операцию; команда не отправлялась повторно."},{"id":"exported","en":"Verified bundle exported. The operation is retained.","ru":"Проверенный пакет экспортирован. Операция сохранена."},{"id":"exportCancelled","en":"Export cancelled. The operation is retained.","ru":"Экспорт отменён. Операция сохранена."},{"id":"exportFailed","en":"Export could not complete. The operation is retained.","ru":"Не удалось завершить экспорт. Операция сохранена."},{"id":"empty","en":"No pending intentions.","ru":"Нет незавершённых намерений."},{"id":"acknowledged","en":"Result acknowledged. No command was replayed.","ru":"Результат подтверждён. Команда не отправлялась повторно."},{"id":"recoveryFailed","en":"Recovery could not complete. Pending intentions are retained.","ru":"Не удалось восстановить результаты. Незавершённые намерения сохранены."},{"id":"noExport","en":null,"ru":null},{"id":"pending","en":null,"ru":null}]''',
          )
          as List<dynamic>;
  for (final initialLocale in ClientLocale.values) {
    for (final data in cases) {
      final scenario = data['id'] as String;
      testWidgets('US-03 recovery $scenario follows locale ${initialLocale.name}', (
        tester,
      ) async {
        final state = ClientStateController();
        final source = StreamController<api.WatchEventsResponse>();
        await state.attach(source.stream);
        final browser = scenario.startsWith('browser');
        final bundle = scenario.startsWith('export') || scenario == 'noExport';
        final operation = ClientOperation.fromProto(
          api.Operation()..mergeFromProto3Json({
            'id': 'operation-a',
            'requestId': 'request-a',
            'kind': bundle
                ? 'OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE'
                : 'OPERATION_KIND_CONNECT',
            'state': browser
                ? 'OPERATION_STATE_WAITING_FOR_USER'
                : scenario == 'pending'
                ? 'OPERATION_STATE_PENDING'
                : 'OPERATION_STATE_SUCCEEDED',
            if (browser)
              'userAction': {
                'kind': 'KIND_OPEN_BROWSER',
                'browserUrl':
                    'https://example.test/never-display-sensitive-action',
              },
            if (!browser && scenario != 'pending') ...{
              'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
              if (bundle)
                'bundle': {
                  'bundleId': 'never-display-handle',
                  'sizeBytes': '32',
                }
              else
                'change': {'changed': true},
            },
          }),
        );
        var lookups = 0;
        var acknowledgements = 0;
        var launches = 0;
        var exports = 0;
        Future<void> render(ClientLocale locale) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ClientRecoveryPanel(
                  key: const Key('preserved-recovery-state'),
                  state: state,
                  locale: locale,
                  recover: () async {
                    lookups++;
                    if (scenario == 'recoveryFailed') {
                      throw StateError('never-display-exception');
                    }
                    return scenario == 'empty' ? [] : [operation];
                  },
                  acknowledge: (_) async {
                    acknowledgements++;
                  },
                  openBrowser: (_) async {
                    launches++;
                    if (scenario == 'browserFailed') {
                      throw StateError('never-display-exception');
                    }
                    return scenario == 'browserOpened';
                  },
                  exportBundle: scenario == 'noExport'
                      ? null
                      : (_, check) async {
                          check();
                          exports++;
                          if (scenario == 'exportFailed') {
                            throw StateError('never-display-exception');
                          }
                          return scenario == 'exported';
                        },
                ),
              ),
            ),
          ),
        );
        await render(initialLocale);
        source.add(
          api.WatchEventsResponse()..mergeFromProto3Json({
            'sequence': '1',
            'metadata': {'instanceId': 'runtime-a', 'revision': '1'},
            'snapshot': {
              'runtime': {
                'protocol': api.ClientContract.protocol,
                'contractSha256': api.ClientContract.sha256,
                'instanceId': 'runtime-a',
                'callerAccess': 'ACCESS_OWNER',
              },
              'status': {
                'metadata': {'instanceId': 'runtime-a', 'revision': '1'},
              },
            },
          }),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('client-recover')));
        await tester.pumpAndSettle();
        String? action;
        if (browser) action = 'browser-request-a';
        if (bundle && scenario != 'noExport') action = 'export-request-a';
        if (scenario == 'acknowledged') action = 'ack-request-a';
        if (action != null) {
          await tester.tap(find.byKey(Key(action)));
          await tester.pumpAndSettle();
        }
        expect(lookups, browser || (bundle && scenario != 'noExport') ? 2 : 1);
        expect(acknowledgements, scenario == 'acknowledged' ? 1 : 0);
        expect(launches, browser ? 1 : 0);
        expect(exports, bundle && scenario != 'noExport' ? 1 : 0);
        final counts = [lookups, acknowledgements, launches, exports];
        // Rebuild the same state in both locales: no re-lookup, launch or replay.
        for (final locale in [
          initialLocale,
          initialLocale == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
        ]) {
          await render(locale);
          await tester.pumpAndSettle();
          String text(String en, String ru) =>
              locale == ClientLocale.en ? en : ru;
          final expected = <String>[
            text(
              'Recover pending operations',
              'Восстановить результаты операций',
            ),
            if (data[locale.name] != null) data[locale.name] as String,
            if (browser) ...[
              text('Connect', 'Подключение'),
              text(
                'Waiting for required action',
                'Ожидает необходимого действия',
              ),
              text(
                'Required action: Continue in your browser',
                'Необходимое действие: Продолжите в браузере',
              ),
              text('Open browser', 'Открыть браузер'),
            ],
            if (bundle) ...[
              text(
                'Create diagnostics bundle',
                'Создание диагностического пакета',
              ),
              text('Completed', 'Завершено'),
              text(
                'Connection continuity: Unknown',
                'Непрерывность соединения: Неизвестно',
              ),
              text(
                'Diagnostics bundle ready: 32 bytes.',
                'Диагностический пакет готов: 32 байт.',
              ),
              text(
                'Download requires the caller-bound bundle RPC.',
                'Загрузка требует вызова API пакета от имени исходного пользователя.',
              ),
              scenario == 'noExport'
                  ? text(
                      'Native export adapter is not available.',
                      'Системный адаптер экспорта недоступен.',
                    )
                  : text(
                      'Export verified bundle',
                      'Экспортировать проверенный пакет',
                    ),
              text('Acknowledge result', 'Подтвердить результат'),
            ],
            if (scenario == 'pending') ...[
              text('Connect', 'Подключение'),
              text('Pending', 'Ожидает выполнения'),
              text('Still pending', 'Ещё выполняется'),
            ],
          ];
          final actual = tester
              .widgetList<Text>(
                find.descendant(
                  of: find.byType(ClientRecoveryPanel),
                  matching: find.byType(Text),
                ),
              )
              .map((widget) => widget.data)
              .toList();
          expect(actual, unorderedEquals(expected));
          expect([lookups, acknowledgements, launches, exports], counts);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          await state.detach();
          await source.close();
          state.dispose();
        });
      });
    }
  }
}
