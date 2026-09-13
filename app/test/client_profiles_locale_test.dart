@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_profiles.dart';
import 'package:endlessnet/client_profiles_panel.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

api.WatchEventsResponse _snapshot(int sequence) =>
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

Future<ClientProfileCatalog> _catalog({
  bool empty = false,
  bool active = false,
}) => readClientProfiles(
  (_) async => api.ListProfilesResponse()
    ..mergeFromProto3Json({
      'activeProfileId': active ? 'a' : '',
      'profiles': [
        for (final id in empty ? <String>[] : ['a', 'b'])
          {
            'id': id,
            'displayName': 'Profile $id',
            'active': active && id == 'a',
            'state': 'PROFILE_STATE_EMPTY',
            'selection': {'availability': 'AVAILABILITY_AVAILABLE'},
          },
      ],
      'page': {
        'metadata': {'instanceId': 'runtime-a', 'revision': '1'},
      },
    }),
  instanceId: 'runtime-a',
);

void main() {
  for (final locale in ClientLocale.values) {
    for (final empty in [true, false]) {
      testWidgets('profile catalog empty=$empty in $locale', (tester) async {
        final state = ClientStateController();
        final source = StreamController<api.WatchEventsResponse>();
        await state.attach(source.stream);
        source.add(_snapshot(1));
        Future<ClientOperation> unexpected(String _) async =>
            throw StateError('Unexpected mutation');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ClientProfilesPanel(
                state: state,
                locale: locale,
                load: () => _catalog(empty: empty, active: !empty),
                select: unexpected,
                remove: unexpected,
                rename: (id, _) => unexpected(id),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('client-load-profiles')));
        await tester.pumpAndSettle();
        expect(
          find.text(
            empty
                ? (locale == ClientLocale.ru ? 'Нет профилей' : 'No profiles')
                : (locale == ClientLocale.ru ? 'Активный' : 'Active'),
          ),
          findsOneWidget,
        );
        if (!empty) {
          expect(find.byKey(const ValueKey('select-profile-a')), findsNothing);
          expect(
            tester
                .widget<TextButton>(
                  find.byKey(const ValueKey('remove-profile-a')),
                )
                .onPressed,
            isNull,
          );
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
  final cases = [
    (
      'select',
      false,
      'Selection accepted. Recover the operation to see its result.',
      'Выбор профиля принят. Восстановите операцию, чтобы узнать результат.',
    ),
    (
      'select',
      true,
      'Selection result received. Refresh profiles and runtime status.',
      'Получен результат выбора профиля. Обновите профили и состояние клиента.',
    ),
    (
      'rename',
      false,
      'Rename accepted. Recover the operation to see its result.',
      'Переименование принято. Восстановите операцию, чтобы узнать результат.',
    ),
    (
      'rename',
      true,
      'Rename result received. Refresh profiles and runtime status.',
      'Получен результат переименования. Обновите профили и состояние клиента.',
    ),
    (
      'remove',
      false,
      'Removal accepted. Recover the operation to see its result.',
      'Удаление принято. Восстановите операцию, чтобы узнать результат.',
    ),
    (
      'remove',
      true,
      'Removal result received. Refresh profiles and runtime status.',
      'Получен результат удаления. Обновите профили и состояние клиента.',
    ),
    (
      'error',
      false,
      'Profiles could not be updated. Recover any pending operation before retrying.',
      'Не удалось обновить профили. Восстановите незавершённую операцию перед повторной попыткой.',
    ),
  ];
  for (final initialLocale in ClientLocale.values) {
    for (final scenario in cases) {
      testWidgets('profile notices ${scenario.$1}/${scenario.$2} in $initialLocale', (
        tester,
      ) async {
        final state = ClientStateController();
        final source = StreamController<api.WatchEventsResponse>();
        await state.attach(source.stream);
        source.add(_snapshot(1));
        var calls = 0;
        var loads = 0;
        Future<ClientOperation> submit(String id) async {
          calls++;
          expect(id, 'a');
          if (scenario.$1 == 'error') {
            throw StateError('private-backend-detail');
          }
          final kind = switch (scenario.$1) {
            'rename' => api.OperationKind.OPERATION_KIND_RENAME_PROFILE,
            'remove' => api.OperationKind.OPERATION_KIND_REMOVE_PROFILE,
            _ => api.OperationKind.OPERATION_KIND_SELECT_PROFILE,
          };
          return ClientOperation.fromProto(
            api.Operation()..mergeFromProto3Json({
              'id': 'operation',
              'requestId': 'request',
              'kind': kind.name,
              'state': scenario.$2
                  ? 'OPERATION_STATE_FAILED'
                  : 'OPERATION_STATE_PENDING',
              if (scenario.$2) 'failure': {'code': 'ERROR_CODE_STALE_STATE'},
            }),
          );
        }

        Future<void> render(ClientLocale locale) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ClientProfilesPanel(
                    state: state,
                    locale: locale,
                    load: () {
                      loads++;
                      return _catalog();
                    },
                    select: submit,
                    remove: submit,
                    rename: (id, name) {
                      expect(name, 'Новое имя');
                      return submit(id);
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Future<void> tap(String key) async {
          final target = find.byKey(ValueKey(key));
          await tester.ensureVisible(target);
          await tester.tap(target);
          await tester.pumpAndSettle();
        }

        await render(initialLocale);
        await tap('client-load-profiles');
        final russian = initialLocale == ClientLocale.ru;
        final catalogText = tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .whereType<String>()
            .toList();
        expect(catalogText, [
          russian ? 'Обновить профили' : 'Refresh profiles',
          russian
              ? 'Новое имя профиля (1–128 байт UTF-8)'
              : 'New profile name (1–128 UTF-8 bytes)',
          for (final id in ['a', 'b']) ...[
            'Profile $id',
            id,
            russian ? 'Переименовать' : 'Rename',
            russian ? 'Выбрать' : 'Select',
            russian ? 'Удалить' : 'Remove',
          ],
        ]);
        if (scenario.$1 == 'rename') {
          await tester.enterText(
            find.byKey(const Key('client-profile-name')),
            'Новое имя',
          );
          await tester.pumpAndSettle();
        }
        await tap(
          '${scenario.$1 == 'error' ? 'select' : scenario.$1}-profile-a',
        );
        if (scenario.$1 == 'remove') {
          // Locale changes do not consume or retarget the displayed confirmation.
          await render(
            initialLocale == ClientLocale.en
                ? ClientLocale.ru
                : ClientLocale.en,
          );
          expect(calls, 0);
          expect(
            find.text(
              russian
                  ? 'Remove profile a? This does not log out or clean up a remote registration.'
                  : 'Удалить профиль a? Это не выполняет выход и не удаляет регистрацию на сервере.',
            ),
            findsOneWidget,
          );
          expect(find.text(russian ? 'Cancel' : 'Отмена'), findsOneWidget);
          expect(
            find.text(russian ? 'Confirm removal' : 'Подтвердить удаление'),
            findsOneWidget,
          );
          await tap('confirm-profile-removal');
        }
        for (final locale in [
          initialLocale,
          initialLocale == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
        ]) {
          await render(locale);
          final text = tester
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .whereType<String>()
              .toList();
          expect(text, [
            locale == ClientLocale.en ? 'Refresh profiles' : 'Обновить профили',
            locale == ClientLocale.en ? scenario.$3 : scenario.$4,
          ]);
          expect(
            tester
                .widgetList<Semantics>(find.byType(Semantics))
                .any((w) => w.properties.liveRegion == true),
            isTrue,
          );
          expect(calls, 1);
          expect(loads, 1);
          expect(find.text('Active'), findsNothing);
          expect(find.text('Активный'), findsNothing);
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
