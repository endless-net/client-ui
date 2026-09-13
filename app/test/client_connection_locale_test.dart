import 'dart:async';
import 'dart:convert';
import 'package:endlessnet/client_connection_panel.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

api.WatchEventsResponse _snapshot(int seq) =>
    api.WatchEventsResponse()..mergeFromProto3Json({
      'sequence': '$seq',
      'metadata': {'instanceId': 'runtime-a', 'revision': '$seq'},
      'snapshot': {
        'runtime': {
          'protocol': api.ClientContract.protocol,
          'contractSha256': api.ClientContract.sha256,
          'instanceId': 'runtime-a',
          'callerAccess': 'ACCESS_OWNER',
          'capabilities': [
            {
              'capability': 'CAPABILITY_CONNECTION',
              'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
            },
          ],
        },
        'status': {
          'metadata': {'instanceId': 'runtime-a', 'revision': '$seq'},
          'activeProfileId': 'profile-a',
          'connectionPhase': 'CONNECTION_PHASE_DISCONNECTED',
        },
      },
    });

void main() {
  _projectionTests();
  final cases =
      jsonDecode(
            r'''[{"id":"completed","en":"Command completed. Runtime status is shown above.","ru":"Команда завершена. Состояние службы показано выше."},{"id":"failed","en":"Command did not complete successfully. Check runtime status.","ru":"Команда не завершилась успешно. Проверьте состояние службы."},{"id":"accepted","en":"Command accepted. Waiting for the runtime result.","ru":"Команда принята. Ожидается результат службы."},{"id":"unknown","en":"Command result is unknown. Recover the original operation before retrying.","ru":"Результат команды неизвестен. Восстановите исходную операцию перед повтором."}]''',
          )
          as List<dynamic>;
  for (final initialLocale in ClientLocale.values) {
    for (final data in cases) {
      testWidgets(
        'US-03 connection notice ${data['id']} in ${initialLocale.name}',
        (tester) async {
          final state = ClientStateController();
          final source = StreamController<api.WatchEventsResponse>();
          await state.attach(source.stream);
          final result = Completer<ClientOperation>();
          var calls = 0;
          Future<ClientOperation> submit() {
            calls++;
            return result.future;
          }

          Future<void> render(ClientLocale locale) => tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ClientConnectionPanel(
                    state: state,
                    locale: locale,
                    connect: submit,
                    disconnect: submit,
                    renewSession: submit,
                  ),
                ),
              ),
            ),
          );
          await render(initialLocale);
          source.add(_snapshot(1));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byKey(const Key('client-connect')));
          await tester.tap(find.byKey(const Key('client-connect')));
          await tester.pump();
          expect(calls, 1);
          expect(
            find.text(
              initialLocale == ClientLocale.en ? 'Submitting…' : 'Отправка…',
            ),
            findsOneWidget,
          );
          if (data['id'] == 'unknown') {
            result.completeError(StateError('never-display-private-url'));
          } else {
            result.complete(
              ClientOperation.fromProto(
                api.Operation()..mergeFromProto3Json({
                  'id': 'op-a',
                  'requestId': 'request-a',
                  'kind': 'OPERATION_KIND_CONNECT',
                  'state': data['id'] == 'completed'
                      ? 'OPERATION_STATE_SUCCEEDED'
                      : data['id'] == 'failed'
                      ? 'OPERATION_STATE_FAILED'
                      : 'OPERATION_STATE_PENDING',
                  if (data['id'] == 'completed') ...{
                    'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
                    'change': {'changed': true},
                  },
                  if (data['id'] == 'failed')
                    'failure': {'code': 'ERROR_CODE_POLICY_BLOCKED'},
                }),
              ),
            );
          }
          await tester.pumpAndSettle();
          for (final locale in [
            initialLocale,
            initialLocale == ClientLocale.en
                ? ClientLocale.ru
                : ClientLocale.en,
          ]) {
            await render(locale);
            await tester.pumpAndSettle();
            final expected = locale == ClientLocale.en
                ? [
                    'Disconnected',
                    'Profile: profile-a',
                    'Account: Unknown',
                    'Network: Unknown',
                    'Network ID: Unknown',
                    'Device: Unknown',
                    'Device ID: Unknown',
                    'Session state: Unknown',
                    'Session expiry: Unknown',
                    'Session warning: Unknown',
                    'Session renewal: Unavailable on this runtime',
                    'Credential state: Unknown',
                    'Credential expiry: Unknown',
                    'Credential warning: Unknown',
                    'Connect',
                    'Disconnect',
                    'Renew session',
                    data['en'],
                  ]
                : [
                    'Отключено',
                    'Профиль: profile-a',
                    'Учётная запись: Неизвестно',
                    'Сеть: Неизвестно',
                    'Идентификатор сети: Неизвестно',
                    'Устройство: Неизвестно',
                    'Идентификатор устройства: Неизвестно',
                    'Состояние сессии: Неизвестно',
                    'Срок сессии: Неизвестно',
                    'Предупреждение о сессии: Неизвестно',
                    'Продление сессии: Недоступно в этой службе',
                    'Состояние учётных данных: Неизвестно',
                    'Срок учётных данных: Неизвестно',
                    'Предупреждение об учётных данных: Неизвестно',
                    'Подключить',
                    'Отключить',
                    'Продлить сессию',
                    data['ru'],
                  ];
            final actual = tester
                .widgetList<Text>(
                  find.descendant(
                    of: find.byType(ClientConnectionPanel),
                    matching: find.byType(Text),
                  ),
                )
                .map((text) => text.data);
            expect(actual, unorderedEquals(expected));
            expect(
              tester
                  .widget<Semantics>(
                    find.byKey(const Key('client-command-announcement')),
                  )
                  .properties
                  .liveRegion,
              isTrue,
            );
            expect(
              state.snapshot!.status.connectionPhase,
              api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED,
            );
            expect(calls, 1);
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await state.detach();
            await source.close();
            state.dispose();
          });
        },
      );
    }
  }
}

void _projectionTests() {
  final cases =
      jsonDecode(
            r'''[{"field":"serviceState","value":"SERVICE_STATE_NEEDS_ENROLLMENT","key":"client-runtime-state","en":"Device enrollment required","ru":"Требуется регистрация устройства"},{"field":"serviceState","value":"SERVICE_STATE_NEEDS_APPROVAL","key":"client-runtime-state","en":"Waiting for approval","ru":"Ожидание одобрения"},{"field":"serviceState","value":"SERVICE_STATE_NEEDS_LOGIN","key":"client-runtime-state","en":"Login required","ru":"Требуется вход"},{"field":"serviceState","value":"SERVICE_STATE_SERVER_IDENTITY_CHANGED","key":"client-runtime-state","en":"Server identity changed","ru":"Идентичность сервера изменилась"},{"field":"serviceState","value":"SERVICE_STATE_RECOVERING","key":"client-runtime-state","en":"Recovering","ru":"Восстановление"},{"field":"serviceState","value":"SERVICE_STATE_RECOVERY_BLOCKED","key":"client-runtime-state","en":"Recovery blocked","ru":"Восстановление заблокировано"},{"field":"serviceState","value":"SERVICE_STATE_POLICY_BLOCKED","key":"client-runtime-state","en":"Blocked by policy","ru":"Заблокировано политикой"},{"field":"serviceState","value":"SERVICE_STATE_ERROR","key":"client-runtime-state","en":"Runtime error","ru":"Ошибка службы"},{"field":"serviceState","value":"SERVICE_STATE_DEGRADED","key":"client-runtime-state","en":"Degraded","ru":"Работа с ограничениями"},{"field":"connectionPhase","value":"CONNECTION_PHASE_CONNECTING","key":"client-runtime-state","en":"Connecting","ru":"Подключение"},{"field":"connectionPhase","value":"CONNECTION_PHASE_DISCONNECTING","key":"client-runtime-state","en":"Disconnecting","ru":"Отключение"},{"field":"connectionPhase","value":"CONNECTION_PHASE_CONNECTED","key":"client-runtime-state","en":"Connected","ru":"Подключено"},{"field":"connectionPhase","value":"CONNECTION_PHASE_DISCONNECTED","key":"client-runtime-state","en":"Disconnected","ru":"Отключено"},{"field":"session","value":"SESSION_STATE_NOT_AUTHENTICATED","key":"client-session-state","en":"Session state: Not authenticated","ru":"Состояние сессии: Не выполнен вход"},{"field":"session","value":"SESSION_STATE_ACTIVE","key":"client-session-state","en":"Session state: Active","ru":"Состояние сессии: Активна"},{"field":"session","value":"SESSION_STATE_EXPIRING","key":"client-session-state","en":"Session state: Expiring","ru":"Состояние сессии: Истекает"},{"field":"session","value":"SESSION_STATE_EXPIRED","key":"client-session-state","en":"Session state: Expired","ru":"Состояние сессии: Срок истёк"},{"field":"session","value":"SESSION_STATE_RENEWING","key":"client-session-state","en":"Session state: Renewing","ru":"Состояние сессии: Продлевается"},{"field":"credential","value":"CREDENTIAL_STATE_ABSENT","key":"client-credential-state","en":"Credential state: Absent","ru":"Состояние учётных данных: Отсутствуют"},{"field":"credential","value":"CREDENTIAL_STATE_VALID","key":"client-credential-state","en":"Credential state: Valid","ru":"Состояние учётных данных: Действительны"},{"field":"credential","value":"CREDENTIAL_STATE_EXPIRING","key":"client-credential-state","en":"Credential state: Expiring","ru":"Состояние учётных данных: Истекает"},{"field":"credential","value":"CREDENTIAL_STATE_EXPIRED","key":"client-credential-state","en":"Credential state: Expired","ru":"Состояние учётных данных: Срок истёк"},{"field":"credential","value":"CREDENTIAL_STATE_RENEWING","key":"client-credential-state","en":"Credential state: Renewing","ru":"Состояние учётных данных: Продлевается"},{"field":"credential","value":"CREDENTIAL_STATE_BLOCKED","key":"client-credential-state","en":"Credential state: Blocked","ru":"Состояние учётных данных: Заблокированы"},{"field":"renewal","value":"AVAILABILITY_AVAILABLE","key":"client-session-renewal-status","en":"Session renewal: Available — choose Renew session","ru":"Продление сессии: Доступно — выберите «Продлить сессию»"},{"field":"renewal","value":"AVAILABILITY_UNSUPPORTED","key":"client-session-renewal-status","en":"Session renewal: Not supported","ru":"Продление сессии: Не поддерживается"},{"field":"renewal","value":"AVAILABILITY_POLICY_BLOCKED","key":"client-session-renewal-status","en":"Session renewal: Blocked by policy","ru":"Продление сессии: Заблокировано политикой"},{"field":"renewal","value":"AVAILABILITY_PERMISSION_REQUIRED","key":"client-session-renewal-status","en":"Session renewal: Permission required","ru":"Продление сессии: Требуется разрешение"},{"field":"renewal","value":"AVAILABILITY_TEMPORARILY_UNAVAILABLE","key":"client-session-renewal-status","en":"Session renewal: Temporarily unavailable","ru":"Продление сессии: Временно недоступно"}]''',
          )
          as List<dynamic>;
  for (final locale in ClientLocale.values) {
    testWidgets('US-03 typed connection projections in ${locale.name}', (
      tester,
    ) async {
      final state = ClientStateController();
      final source = StreamController<api.WatchEventsResponse>();
      await state.attach(source.stream);
      Future<ClientOperation> unexpected() async =>
          throw StateError('Projection cannot submit');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ClientConnectionPanel(
                state: state,
                locale: locale,
                connect: unexpected,
                disconnect: unexpected,
                renewSession: unexpected,
              ),
            ),
          ),
        ),
      );
      var seq = 0;
      for (final data in cases) {
        final event = _snapshot(++seq);
        event.snapshot.runtime.mergeFromProto3Json({
          'capabilities': [
            {
              'capability': 'CAPABILITY_SESSION_RENEWAL',
              'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
            },
          ],
        });
        final field = data['field'] as String;
        final value = data['value'];
        event.snapshot.status.mergeFromProto3Json({
          if (field == 'session' || field == 'credential')
            field: {'state': value}
          else if (field == 'renewal')
            'session': {
              'state': 'SESSION_STATE_ACTIVE',
              'renewal': {'availability': value},
            }
          else
            field: value,
        });
        source.add(event);
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(find.byKey(Key(data['key'] as String))).data,
          data[locale.name],
        );
        expect(tester.takeException(), isNull);
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
