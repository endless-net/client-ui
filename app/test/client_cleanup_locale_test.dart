@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_cleanup_panel.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

api.WatchEventsResponse snapshot(int sequence) {
  final value = fixtures.snapshot(sequence);
  value.snapshot.runtime.callerAccess = api.Access.ACCESS_ADMINISTRATOR;
  value.snapshot.runtime.mergeFromProto3Json({
    'capabilities': [
      for (final kind in ['CAPABILITY_LOGOUT', 'CAPABILITY_LOCAL_FORGET'])
        {
          'capability': kind,
          'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
        },
    ],
  });
  return value;
}

ClientOperation result(bool forget, bool terminal) => ClientOperation.fromProto(
  api.Operation()..mergeFromProto3Json({
    'id': 'op',
    'kind': forget
        ? 'OPERATION_KIND_FORGET_LOCAL_ENROLLMENT'
        : 'OPERATION_KIND_LOGOUT',
    'state': terminal ? 'OPERATION_STATE_FAILED' : 'OPERATION_STATE_PENDING',
    if (terminal) 'failure': {'code': 'ERROR_CODE_STALE_STATE'},
  }),
);

void main() {
  for (final locale in ClientLocale.values) {
    for (final forget in [false, true]) {
      for (final outcome in ['accepted', 'result', 'unknown']) {
        testWidgets('cleanup $forget/$outcome in $locale', (tester) async {
          final state = ClientStateController();
          final stream = StreamController<api.WatchEventsResponse>();
          await state.attach(stream.stream);
          stream.add(snapshot(1));
          final calls = <bool>[];
          Future<ClientOperation> submit(bool local, String profile) async {
            expect(profile, 'profile-a');
            calls.add(local);
            if (outcome == 'unknown') {
              throw StateError('private details');
            }
            return result(local, outcome == 'result');
          }

          Future<void> render(ClientLocale language) async {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: ClientCleanupPanel(
                    state: state,
                    locale: language,
                    logout: (id) => submit(false, id),
                    forget: (id) => submit(true, id),
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
          await render(locale);
          await tester.tap(
            find.byKey(Key(forget ? 'client-local-forget' : 'client-logout')),
          );
          await tester.pumpAndSettle();
          for (final language in [
            locale,
            locale == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
          ]) {
            await render(language);
            final ru = language == ClientLocale.ru;
            expect(texts(), [
              ru ? 'Выйти' : 'Log out',
              ru ? 'Удалить локальную регистрацию' : 'Forget local enrollment',
              forget
                  ? (ru
                        ? 'Удалить локальную регистрацию без подтверждённой очистки на сервере? Регистрация на сервере может сохраниться. Владелец установки не изменится.'
                        : 'Remove local registration without confirmed remote cleanup? Remote registration may remain. Installation ownership is retained.')
                  : (ru
                        ? 'Выйти из выбранного профиля? Очистка на сервере должна быть подтверждена до удаления локальной регистрации.'
                        : 'Log out the selected profile? Remote cleanup must be confirmed before local registration is removed.'),
              ru ? 'Отмена' : 'Cancel',
              ru ? 'Подтвердить' : 'Confirm',
            ]);
            expect(calls, isEmpty);
          }
          await tester.tap(find.byKey(const Key('confirm-client-cleanup')));
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
                    ? 'Очистка принята. Восстановите операцию; удаление ещё не подтверждено.'
                    : 'Cleanup accepted. Recover the operation; removal is not yet confirmed.',
              'result' =>
                ru
                    ? 'Получен результат очистки. Восстановите его, чтобы проверить результат на сервере и локально.'
                    : 'Cleanup result received. Recover it to inspect remote and local outcomes.',
              _ =>
                ru
                    ? 'Не удалось подтвердить очистку. Восстановите исходное намерение. Другая команда очистки не отправлялась.'
                    : 'Cleanup could not be confirmed. Recover the intention. No other cleanup command was sent.',
            };
            expect(texts(), [
              ru ? 'Выйти' : 'Log out',
              ru ? 'Удалить локальную регистрацию' : 'Forget local enrollment',
              notice,
            ]);
            expect(calls, [forget]);
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
  for (final change in ['retarget', 'reconfirm', 'snapshot', 'controller']) {
    testWidgets('cleanup consent cannot cross $change', (tester) async {
      final states = [ClientStateController(), ClientStateController()];
      final streams = [
        StreamController<api.WatchEventsResponse>(),
        StreamController<api.WatchEventsResponse>(),
      ];
      for (var i = 0; i < states.length; i++) {
        await states[i].attach(streams[i].stream);
        streams[i].add(snapshot(1));
      }
      final calls = <bool>[];
      Future<void> render(ClientStateController state) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ClientCleanupPanel(
                state: state,
                logout: (_) async {
                  calls.add(false);
                  return result(false, false);
                },
                forget: (_) async {
                  calls.add(true);
                  return result(true, false);
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> tap(String key) async {
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
      }

      await render(states.first);
      await tap('client-logout');
      final stale = tester
          .widget<TextButton>(find.byKey(const Key('confirm-client-cleanup')))
          .onPressed!;
      final staleCancel = tester
          .widget<TextButton>(find.byKey(const Key('cancel-client-cleanup')))
          .onPressed!;
      if (change == 'controller') {
        await render(states.last);
      } else if (change == 'snapshot') {
        streams.first.add(snapshot(2));
        await tester.pumpAndSettle();
      } else {
        await tap('cancel-client-cleanup');
      }
      await tap(change == 'retarget' ? 'client-local-forget' : 'client-logout');
      stale();
      staleCancel();
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.byKey(const Key('confirm-client-cleanup')), findsOneWidget);
      await tap('confirm-client-cleanup');
      expect(calls, [change == 'retarget']);
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
}
