@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_identity_panel.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

void main() {
  for (final initial in ClientLocale.values) {
    for (final scenario in [
      'read error',
      'changed',
      'received',
      'unknown',
      'reconfirm',
    ]) {
      testWidgets('identity $scenario in $initial', (tester) async {
        final state = ClientStateController();
        final stream = StreamController<api.WatchEventsResponse>();
        await state.attach(stream.stream);
        final snapshot = fixtures.snapshot(1);
        snapshot.snapshot.runtime.callerAccess =
            api.Access.ACCESS_ADMINISTRATOR;
        snapshot.snapshot.runtime.mergeFromProto3Json({
          'capabilities': [
            {
              'capability': 'CAPABILITY_IDENTITY_RECOVERY',
              'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
            },
          ],
        });
        stream.add(snapshot);
        var loads = 0;
        var trusts = 0;
        Future<void> render(ClientLocale locale) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ClientIdentityPanel(
                  state: state,
                  locale: locale,
                  load: () async {
                    loads++;
                    if (scenario == 'read error') {
                      throw StateError('private details');
                    }
                    return api.GetServerIdentityResponse()
                      ..mergeFromProto3Json({
                        'metadata': {
                          'instanceId': 'runtime-a',
                          'revision': '1',
                        },
                        'identity': {
                          'profileId': 'profile-a',
                          'controlOrigin': 'https://control.example',
                          'trustedKeyId': 'old',
                          'announcedKeyId': scenario == 'changed' && loads > 1
                              ? 'replacement'
                              : 'new',
                          'announcementId': 'announcement',
                          'changed': true,
                        },
                      });
                  },
                  trust: (identity) async {
                    trusts++;
                    expect(identity.announcedKeyId, 'new');
                    if (scenario == 'unknown') {
                      throw StateError('private trust details');
                    }
                    return ClientOperation.fromProto(
                      api.Operation(
                        id: 'op',
                        kind: api
                            .OperationKind
                            .OPERATION_KIND_TRUST_SERVER_IDENTITY,
                        state: api.OperationState.OPERATION_STATE_PENDING,
                      ),
                    );
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

        List<String> texts() => tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data)
            .whereType<String>()
            .toList();
        await render(initial);
        await tap('load-client-identity');
        if (scenario != 'read error') {
          for (final locale in [
            initial,
            initial == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
          ]) {
            await render(locale);
            final ru = locale == ClientLocale.ru;
            expect(texts(), [
              ru ? 'Проверить подлинность сервера' : 'Inspect server identity',
              ru
                  ? 'Адрес сервера управления: https://control.example'
                  : 'Control origin: https://control.example',
              ru ? 'Доверенный ключ: old' : 'Trusted key: old',
              ru ? 'Объявленный ключ: new' : 'Announced key: new',
              ru ? 'Объявление: announcement' : 'Announcement: announcement',
              ru
                  ? 'Я независимо проверил адрес сервера, ключ и объявление.'
                  : 'I independently verified this origin, key and announcement.',
              ru ? 'Подтвердить доверие серверу' : 'Confirm server trust',
            ]);
            expect(loads, 1);
            expect(trusts, 0);
          }
          await tap('compare-client-identity');
          if (scenario == 'reconfirm') {
            final stale = tester
                .widget<TextButton>(
                  find.byKey(const Key('trust-client-identity')),
                )
                .onPressed!;
            await tap('compare-client-identity');
            await tap('compare-client-identity');
            stale();
            await tester.pumpAndSettle();
            expect(loads, 1);
            expect(trusts, 0);
          }
          await tap('trust-client-identity');
        }
        final expectedLoads = scenario == 'read error' ? 1 : 2;
        final expectedTrusts = ['read error', 'changed'].contains(scenario)
            ? 0
            : 1;
        for (final locale in [
          initial,
          initial == ClientLocale.en ? ClientLocale.ru : ClientLocale.en,
        ]) {
          await render(locale);
          final ru = locale == ClientLocale.ru;
          final notice = switch (scenario) {
            'read error' =>
              ru
                  ? 'Не удалось прочитать сведения о подлинности сервера.'
                  : 'Server identity could not be read.',
            'changed' =>
              ru
                  ? 'Сведения о подлинности сервера изменились. Загрузите и сравните их снова; команда доверия не отправлена.'
                  : 'Server identity changed. Reload and compare again; no trust command was sent.',
            'unknown' =>
              ru
                  ? 'Не удалось подтвердить доверие. Проверьте восстановление операции перед повторной попыткой.'
                  : 'Trust could not be confirmed. Check operation recovery before another attempt.',
            _ =>
              ru
                  ? 'Операция доверия получена. Восстановите её результат; принятие операции не означает установления доверия.'
                  : 'Trust operation received. Recover its result; trust is not inferred from acceptance.',
          };
          expect(texts(), [
            ru ? 'Проверить подлинность сервера' : 'Inspect server identity',
            notice,
          ]);
          expect(loads, expectedLoads);
          expect(trusts, expectedTrusts);
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
