@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_create_profile_panel.dart';
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
        },
      },
    });

ClientOperation operation({bool terminal = false}) => ClientOperation.fromProto(
  api.Operation()..mergeFromProto3Json({
    'id': 'operation',
    'requestId': 'request',
    'kind': 'OPERATION_KIND_CREATE_PROFILE',
    'state': terminal ? 'OPERATION_STATE_FAILED' : 'OPERATION_STATE_PENDING',
    if (terminal) 'failure': {'code': 'ERROR_CODE_STALE_STATE'},
  }),
);

void main() {
  for (final scenario in [
    'name',
    'origin',
    'snapshot',
    'controller',
    'late response',
    'late failure',
  ]) {
    testWidgets('create profile rejects stale $scenario', (tester) async {
      final states = [ClientStateController(), ClientStateController()];
      final streams = [
        StreamController<api.WatchEventsResponse>(),
        StreamController<api.WatchEventsResponse>(),
      ];
      for (var i = 0; i < states.length; i++) {
        await states[i].attach(streams[i].stream);
        streams[i].add(snapshot(1));
      }
      final pending = Completer<ClientOperation>();
      final calls = <String>[];
      Future<void> render(ClientStateController state) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ClientCreateProfilePanel(
                state: state,
                create: (name, origin) {
                  calls.add('$name|$origin');
                  return pending.future;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await render(states.first);
      await tester.enterText(
        find.byKey(const Key('create-profile-name')),
        'Original',
      );
      await tester.enterText(
        find.byKey(const Key('create-profile-origin')),
        'https://control.example',
      );
      await tester.pumpAndSettle();
      final callback = tester
          .widget<OutlinedButton>(
            find.byKey(const Key('create-profile-submit')),
          )
          .onPressed!;
      if (scenario.startsWith('late')) {
        callback();
        await tester.pump();
        streams.first.add(snapshot(2));
        await tester.pumpAndSettle();
        if (scenario == 'late failure') {
          pending.completeError(StateError('private failure'));
        } else {
          pending.complete(operation());
        }
        await tester.pumpAndSettle();
        expect(calls, ['Original|https://control.example']);
        expect(find.textContaining('Creation accepted'), findsNothing);
        expect(find.textContaining('could not be confirmed'), findsNothing);
      } else {
        if (scenario == 'name' || scenario == 'origin') {
          await tester.enterText(
            find.byKey(Key('create-profile-$scenario')),
            scenario == 'name' ? 'Replacement' : 'https://new.example',
          );
        } else if (scenario == 'controller') {
          await render(states.last);
        } else {
          streams.first.add(snapshot(2));
        }
        await tester.pumpAndSettle();
        callback();
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
      }
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
    for (final result in ['accepted', 'terminal', 'unknown']) {
      testWidgets('create profile $result notices in $initial', (tester) async {
        final state = ClientStateController();
        final stream = StreamController<api.WatchEventsResponse>();
        await state.attach(stream.stream);
        stream.add(snapshot(1));
        var calls = 0;
        Future<void> render(ClientLocale locale) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ClientCreateProfilePanel(
                  state: state,
                  locale: locale,
                  create: (name, origin) async {
                    calls++;
                    expect(name, 'Мой профиль');
                    expect(origin, 'https://control.example');
                    if (result == 'unknown') {
                      throw StateError('private error');
                    }
                    return operation(terminal: result == 'terminal');
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await render(initial);
        await tester.enterText(
          find.byKey(const Key('create-profile-name')),
          'Мой профиль',
        );
        await tester.enterText(
          find.byKey(const Key('create-profile-origin')),
          'https://control.example',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('create-profile-submit')));
        await tester.pumpAndSettle();
        for (final locale in [
          initial,
          initial == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
        ]) {
          await render(locale);
          final ru = locale == ClientLocale.ru;
          final notice = switch (result) {
            'accepted' =>
              ru
                  ? 'Создание профиля принято. Восстановите операцию, чтобы узнать результат.'
                  : 'Creation accepted. Recover the operation to see its result.',
            'terminal' =>
              ru
                  ? 'Получен результат создания профиля. Обновите профили и состояние клиента.'
                  : 'Creation result received. Refresh profiles and runtime status.',
            _ =>
              ru
                  ? 'Не удалось подтвердить создание профиля. Восстановите незавершённую операцию перед повторной попыткой.'
                  : 'Profile creation could not be confirmed. Recover any pending operation before retrying.',
          };
          expect(
            tester
                .widgetList<Text>(find.byType(Text))
                .map((w) => w.data)
                .whereType<String>()
                .toList(),
            [
              ru
                  ? 'Создайте профиль. Служба проверяет права владельца; при первой настройке вы можете стать владельцем.'
                  : 'Create a profile. The service checks ownership; a fresh installation may assign you as owner.',
              ru ? 'Имя профиля' : 'Profile name',
              ru ? 'HTTPS-адрес сервера управления' : 'Control HTTPS origin',
              ru ? 'Создать профиль' : 'Create profile',
              notice,
            ],
          );
          expect(calls, 1);
          expect(
            tester
                .widgetList<Semantics>(find.byType(Semantics))
                .any((w) => w.properties.liveRegion == true),
            isTrue,
          );
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
