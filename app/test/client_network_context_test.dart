@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_networks.dart';
import 'package:endlessnet/client_networks_panel.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

Future<ClientNetworkCatalog> catalog(String scenario) => readClientNetworks(
  (_) async => api.ListNetworksResponse()
    ..mergeFromProto3Json({
      'selectedNetworkId': 'a',
      'page': {
        'metadata': {'instanceId': 'runtime-a', 'revision': '1'},
      },
      'networks': [
        for (final id in ['a', 'b'])
          {
            'id': id,
            'name': 'Office',
            if (scenario != 'absent') ...{
              'accountId': 'account-$id',
              'ipv4Cidr': id == 'a' ? '10.0.0.0/24' : '10.1.0.0/24',
              'ipv6Cidr': id == 'a' ? 'fd00::/64' : 'fd01::/64',
            },
            'selection': {
              'availability': scenario == 'denied'
                  ? 'AVAILABILITY_PERMISSION_REQUIRED'
                  : 'AVAILABILITY_AVAILABLE',
              'actionOwner': scenario == 'denied'
                  ? 'ACTION_OWNER_ACCESS_ADMINISTRATOR'
                  : 'ACTION_OWNER_USER',
            },
          },
      ],
    }),
  instanceId: 'runtime-a',
  profileId: 'profile-a',
);

void main() {
  for (final locale in ClientLocale.values) {
    for (final scenario in ['available', 'denied', 'absent']) {
      testWidgets('UBR-09/10 network context $scenario in $locale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = ClientStateController();
        final stream = StreamController<api.WatchEventsResponse>();
        await state.attach(stream.stream);
        stream.add(fixtures.snapshot(1));
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
                child: ClientNetworksPanel(
                  state: state,
                  locale: locale,
                  load: () => catalog(scenario),
                  select: (profile, network) async {
                    expect((profile, network), ('profile-a', 'b'));
                    selections++;
                    return fixtures.operation(false);
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('client-load-networks')));
        await tester.pumpAndSettle();
        final ru = locale == ClientLocale.ru;
        for (final id in ['a', 'b']) {
          final tile = find.ancestor(
            of: find.text(id),
            matching: find.byType(ListTile),
          );
          final fields = {
            ru ? 'ID аккаунта' : 'Account ID': 'account-$id',
            ru ? 'Диапазон IPv4' : 'IPv4 range': id == 'a'
                ? '10.0.0.0/24'
                : '10.1.0.0/24',
            ru ? 'Диапазон IPv6' : 'IPv6 range': id == 'a'
                ? 'fd00::/64'
                : 'fd01::/64',
          };
          for (final entry in fields.entries) {
            final value = scenario == 'absent'
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
        final denied = scenario == 'denied';
        expect(
          find.text(
            denied
                ? (ru
                      ? 'Выбор: Требуется разрешение'
                      : 'Selection: Permission required')
                : (ru ? 'Выбор: Доступно' : 'Selection: Available'),
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            denied
                ? (ru
                      ? 'Ответственный за действие: Администратор доступа'
                      : 'Action owner: Access administrator')
                : (ru ? 'Ответственный за действие: Вы' : 'Action owner: You'),
          ),
          findsOneWidget,
        );
        final select = find.byKey(const ValueKey('select-network-b'));
        await tester.ensureVisible(select);
        await tester.pumpAndSettle();
        if (denied) {
          expect(tester.widget<TextButton>(select).onPressed, isNull);
        } else {
          await tester.tap(select);
          await tester.pumpAndSettle();
        }
        expect(selections, denied ? 0 : 1);
        expect(tester.takeException(), isNull);
        stream.add(
          fixtures.snapshot(2)
            ..snapshot.runtime.callerAccess = api.Access.ACCESS_OBSERVER,
        );
        await tester.pumpAndSettle();
        expect(find.text('Office'), findsNothing);
        expect(find.textContaining('account-'), findsNothing);
        expect(find.byKey(const ValueKey('select-network-b')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await state.detach();
          await stream.close();
          state.dispose();
        });
      });
    }
  }
}
