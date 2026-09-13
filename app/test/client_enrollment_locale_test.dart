@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_enrollment_panel.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

api.WatchEventsResponse snapshot() {
  final value = fixtures.snapshot(1);
  value.snapshot.runtime.mergeFromProto3Json({
    'capabilities': [
      {
        'capability': 'CAPABILITY_ENROLLMENT',
        'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
      },
    ],
  });
  return value;
}

ClientOperation operation(bool terminal) => ClientOperation.fromProto(
  api.Operation()..mergeFromProto3Json({
    'id': 'op',
    'kind': 'OPERATION_KIND_ENROLL',
    'state': terminal ? 'OPERATION_STATE_FAILED' : 'OPERATION_STATE_PENDING',
    if (terminal) 'failure': {'code': 'ERROR_CODE_STALE_STATE'},
  }),
);

void main() {
  test('every enrollment mode has exact RU/EN labels', () {
    expect(
      api.EnrollmentMode.values.map(
        (m) => enrollmentModeLabel(m, ClientLocale.en),
      ),
      [
        'Not specified',
        'Workstation',
        'Server',
        'Subnet router',
        'Interactive',
      ],
    );
    expect(
      api.EnrollmentMode.values.map(
        (m) => enrollmentModeLabel(m, ClientLocale.ru),
      ),
      [
        'Не указан',
        'Рабочая станция',
        'Сервер',
        'Маршрутизатор подсети',
        'Интерактивный',
      ],
    );
  });
  for (final locale in ClientLocale.values) {
    for (final tokenLogin in [false, true]) {
      for (final outcome in ['accepted', 'result', 'unknown']) {
        testWidgets('enrollment $tokenLogin/$outcome in $locale', (
          tester,
        ) async {
          final state = ClientStateController();
          final stream = StreamController<api.WatchEventsResponse>();
          await state.attach(stream.stream);
          stream.add(snapshot());
          var calls = 0;
          Future<void> render(ClientLocale language) async {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: ClientEnrollmentPanel(
                    state: state,
                    locale: language,
                    enroll: (profile, mode, hostname, token) async {
                      calls++;
                      expect(profile, 'profile-a');
                      expect(hostname, 'device');
                      expect(
                        mode,
                        api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION,
                      );
                      expect(token, tokenLogin ? 'secret-fixture' : null);
                      if (outcome == 'unknown') {
                        throw StateError('secret-fixture');
                      }
                      return operation(outcome == 'result');
                    },
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
          }

          await render(locale);
          await tester.enterText(
            find.byKey(const Key('enroll-hostname')),
            'device',
          );
          await tester.pumpAndSettle();
          if (tokenLogin) {
            await tester.tap(find.byKey(const Key('enroll-use-token')));
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byKey(const Key('enroll-token')),
              'secret-fixture',
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byKey(const Key('enroll-submit')));
          await tester.pumpAndSettle();
          for (final language in [
            locale,
            locale == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
          ]) {
            await render(language);
            final ru = language == ClientLocale.ru;
            final notice = switch (outcome) {
              'accepted' =>
                ru
                    ? 'Регистрация принята. Восстановите операцию, чтобы узнать необходимые действия и результат.'
                    : 'Enrollment accepted. Recover the operation for required actions and its result.',
              'result' =>
                ru
                    ? 'Получен результат регистрации. Обновите состояние клиента.'
                    : 'Enrollment result received. Refresh runtime status.',
              _ =>
                ru
                    ? 'Не удалось подтвердить регистрацию. Восстановите исходное намерение перед повторной попыткой.'
                    : 'Enrollment could not be confirmed. Recover the intention before retrying.',
            };
            final allowed = {
              ru
                  ? 'Зарегистрировать выбранный профиль'
                  : 'Enroll the selected profile',
              ru ? 'Имя устройства' : 'Device hostname',
              ru
                  ? 'Использовать токен регистрации вместо входа через браузер'
                  : 'Use enrollment token instead of browser login',
              if (tokenLogin) ru ? 'Токен регистрации' : 'Enrollment token',
              ru ? 'Зарегистрировать профиль' : 'Enroll profile',
              notice,
              ...api.EnrollmentMode.values.map(
                (mode) => enrollmentModeLabel(mode, language),
              ),
            };
            final texts = tester
                .widgetList<Text>(find.byType(Text))
                .map((w) => w.data)
                .whereType<String>()
                .toList();
            expect(
              texts.every(allowed.contains),
              isTrue,
              reason: texts.join('\n'),
            );
            expect(find.text(notice), findsOneWidget);
            expect(calls, 1);
            if (tokenLogin) {
              final field = tester.widget<TextField>(
                find.byKey(const Key('enroll-token')),
              );
              expect(field.controller!.text, isEmpty);
              expect(field.obscureText, isTrue);
            }
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
  for (final change in ['hostname', 'token', 'mode', 'login method']) {
    testWidgets('queued enrollment rejects changed $change', (tester) async {
      final state = ClientStateController();
      final stream = StreamController<api.WatchEventsResponse>();
      await state.attach(stream.stream);
      stream.add(snapshot());
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientEnrollmentPanel(
              state: state,
              enroll: (_, _, _, _) async {
                calls++;
                return operation(false);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('enroll-hostname')),
        'device',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('enroll-use-token')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('enroll-token')),
        'secret-fixture',
      );
      await tester.pumpAndSettle();
      final stale = tester
          .widget<OutlinedButton>(find.byKey(const Key('enroll-submit')))
          .onPressed!;
      if (change == 'hostname' || change == 'token') {
        await tester.enterText(
          find.byKey(Key('enroll-$change')),
          'replacement',
        );
      } else if (change == 'mode') {
        tester
            .widget<DropdownButton<api.EnrollmentMode>>(
              find.byKey(const Key('enroll-mode')),
            )
            .onChanged!(api.EnrollmentMode.ENROLLMENT_MODE_SERVER);
      } else {
        await tester.tap(find.byKey(const Key('enroll-use-token')));
      }
      await tester.pumpAndSettle();
      stale();
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.byKey(const Key('enroll-submit')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await state.detach();
        await stream.close();
        state.dispose();
      });
    });
  }
}
