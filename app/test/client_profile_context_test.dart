@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_profile_labels.dart';
import 'package:endlessnet/client_profiles.dart';
import 'package:endlessnet/client_profiles_panel.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

Future<ClientProfileCatalog> catalog(bool absent, bool blocked) =>
    readClientProfiles(
      (_) async => api.ListProfilesResponse()
        ..mergeFromProto3Json({
          'activeProfileId': 'a',
          'page': {
            'metadata': {'instanceId': 'runtime-a', 'revision': '1'},
          },
          'profiles': [
            for (final id in ['a', 'b'])
              {
                'id': id,
                'displayName': 'Office',
                'active': id == 'a',
                'state': id == 'a'
                    ? 'PROFILE_STATE_REGISTERED'
                    : 'PROFILE_STATE_NEEDS_LOGIN',
                if (!absent) ...{
                  'accountId': 'account-$id',
                  'identityDisplayName': 'Identity $id',
                  'controlOrigin': 'https://control-$id.example.test',
                  'selectedNetworkId': 'network-$id',
                },
                'selection': {
                  'availability': blocked
                      ? 'AVAILABILITY_POLICY_BLOCKED'
                      : 'AVAILABILITY_AVAILABLE',
                  'actionOwner': blocked
                      ? 'ACTION_OWNER_ACCESS_ADMINISTRATOR'
                      : 'ACTION_OWNER_USER',
                },
              },
          ],
        }),
      instanceId: 'runtime-a',
    );

void main() {
  test('all profile states have explicit RU/EN labels', () {
    expect(
      api.ProfileState.values.map(
        (s) => clientProfileStateLabel(s, ClientLocale.en),
      ),
      [
        'Not specified',
        'Empty',
        'Registered',
        'Sign-in required',
        'Approval required',
        'Blocked',
      ],
    );
    expect(
      api.ProfileState.values.map(
        (s) => clientProfileStateLabel(s, ClientLocale.ru),
      ),
      [
        'Не указано',
        'Пустой',
        'Зарегистрирован',
        'Требуется вход',
        'Требуется одобрение',
        'Заблокирован',
      ],
    );
  });
  for (final locale in ClientLocale.values) {
    for (final (absent, blocked) in [
      (false, false),
      (true, false),
      (false, true),
    ]) {
      testWidgets(
        'UBR-23 profile context absent=$absent blocked=$blocked in $locale',
        (tester) async {
          tester.view.physicalSize = const Size(360, 640);
          final semantics = tester.ensureSemantics();

          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final state = ClientStateController();
          final events = StreamController<api.WatchEventsResponse>();
          await state.attach(events.stream);
          events.add(fixtures.snapshot(1));
          await tester.pump();
          var selections = 0;
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ClientProfilesPanel(
                    state: state,
                    locale: locale,
                    load: () => catalog(absent, blocked),
                    select: (id) async {
                      expect(id, 'b');
                      selections++;
                      return ClientOperation.fromProto(
                        api.Operation()..mergeFromProto3Json({
                          'id': 'operation',
                          'kind': 'OPERATION_KIND_SELECT_PROFILE',
                          'state': 'OPERATION_STATE_PENDING',
                        }),
                      );
                    },
                    rename: (_, _) async =>
                        throw StateError('Unexpected rename'),
                    remove: (_) async => throw StateError('Unexpected removal'),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('client-load-profiles')));
          await tester.pumpAndSettle();
          final ru = locale == ClientLocale.ru;
          for (final id in ['a', 'b']) {
            final tile = find.ancestor(
              of: find.text(id),
              matching: find.byType(ListTile),
            );
            expect(tile, findsOneWidget);
            final fields = <String, String>{
              ru ? 'Идентичность аккаунта' : 'Account identity': 'Identity $id',
              ru ? 'ID аккаунта' : 'Account ID': 'account-$id',
              ru ? 'Адрес сервера управления' : 'Control origin':
                  'https://control-$id.example.test',
              ru ? 'ID выбранной сети' : 'Selected network ID': 'network-$id',
            };
            for (final entry in fields.entries) {
              final value = absent
                  ? (ru ? 'Нет данных' : 'Not reported')
                  : entry.value;
              expect(
                find.descendant(
                  of: tile,
                  matching: find.text('${entry.key}: $value'),
                ),
                findsOneWidget,
              );
            }
          }
          expect(
            find.text(
              ru
                  ? 'Состояние профиля: Требуется вход'
                  : 'Profile state: Sign-in required',
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              blocked
                  ? (ru
                        ? 'Выбор: Заблокировано политикой'
                        : 'Selection: Blocked by policy')
                  : (ru ? 'Выбор: Доступно' : 'Selection: Available'),
            ),
            findsOneWidget,
          );
          expect(
            find.text(
              blocked
                  ? (ru
                        ? 'Ответственный за действие: Администратор доступа'
                        : 'Action owner: Access administrator')
                  : (ru
                        ? 'Ответственный за действие: Вы'
                        : 'Action owner: You'),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          final select = find.byKey(const ValueKey('select-profile-b'));
          await tester.ensureVisible(select);
          await tester.pumpAndSettle();
          expect(
            tester.getSemantics(select).label,
            ru ? 'Выбрать профиль Office, ID b' : 'Select profile Office, ID b',
          );
          for (final id in ['a', 'b']) {
            for (final action in ['rename', 'remove']) {
              final button = find.byKey(ValueKey('$action-profile-$id'));
              await tester.ensureVisible(button);
              await tester.pumpAndSettle();
              final verb = action == 'rename'
                  ? (ru ? 'Переименовать профиль' : 'Rename profile')
                  : (ru ? 'Удалить профиль' : 'Remove profile');
              expect(tester.getSemantics(button).label, '$verb Office, ID $id');
            }
          }
          await tester.ensureVisible(select);
          await tester.pumpAndSettle();
          if (blocked) {
            expect(tester.widget<TextButton>(select).onPressed, isNull);
          } else {
            await tester.tap(select);
          }
          await tester.pumpAndSettle();
          expect(selections, blocked ? 0 : 1);
          expect(tester.takeException(), isNull);
          events.add(
            fixtures.snapshot(2)
              ..snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER,
          );
          await tester.pumpAndSettle();
          expect(find.text('Office'), findsNothing);
          expect(find.textContaining('control-a.example.test'), findsNothing);
          expect(find.byKey(const ValueKey('select-profile-b')), findsNothing);
          semantics.dispose();
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() async {
            await state.detach();
            await events.close();
            state.dispose();
          });
        },
      );
    }
  }
}
