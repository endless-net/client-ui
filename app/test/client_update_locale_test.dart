@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_update_labels.dart';
import 'package:endlessnet/client_update_panel.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as fixtures;

void main() {
  test('UpdateState: complete RU/EN catalog', () {
    expect(
      api.UpdateState.values.map(
        (value) => updateStateLabel(value, ClientLocale.en),
      ),
      [
        "Not specified",
        "Unknown",
        "Up to date",
        "Available",
        "External manager required",
        "Source unavailable",
        "Verification failed",
      ],
    );
    expect(
      api.UpdateState.values.map(
        (value) => updateStateLabel(value, ClientLocale.ru),
      ),
      [
        "Не указано",
        "Неизвестно",
        "Актуальная версия",
        "Доступно",
        "Требуется внешний менеджер",
        "Источник недоступен",
        "Проверка не пройдена",
      ],
    );
  });
  test('CompatibilityState: complete RU/EN catalog', () {
    expect(
      api.CompatibilityState.values.map(
        (value) => compatibilityLabel(value, ClientLocale.en),
      ),
      ["Not specified", "Compatible", "Incompatible", "Unknown"],
    );
    expect(
      api.CompatibilityState.values.map(
        (value) => compatibilityLabel(value, ClientLocale.ru),
      ),
      ["Не указано", "Совместимо", "Несовместимо", "Неизвестно"],
    );
  });
  test('UpdateClassification: complete RU/EN catalog', () {
    expect(
      api.UpdateClassification.values.map(
        (value) => updateClassificationLabel(value, ClientLocale.en),
      ),
      ["Not specified", "Ordinary", "Security", "Mandatory"],
    );
    expect(
      api.UpdateClassification.values.map(
        (value) => updateClassificationLabel(value, ClientLocale.ru),
      ),
      ["Не указано", "Обычное", "Обновление безопасности", "Обязательное"],
    );
  });
  test('DistributionChannel: complete RU/EN catalog', () {
    expect(
      api.DistributionChannel.values.map(
        (value) => distributionLabel(value, ClientLocale.en),
      ),
      [
        "Not specified",
        "Vendor package",
        "Package manager",
        "App store",
        "Enterprise",
      ],
    );
    expect(
      api.DistributionChannel.values.map(
        (value) => distributionLabel(value, ClientLocale.ru),
      ),
      [
        "Не указано",
        "Пакет поставщика",
        "Пакетный менеджер",
        "Магазин приложений",
        "Корпоративный канал",
      ],
    );
  });
  test('Platform: complete RU/EN catalog', () {
    expect(
      api.Platform.values.map(
        (value) => buildPlatformLabel(value, ClientLocale.en),
      ),
      ["Not specified", "Windows", "macOS", "Linux", "Android", "iOS"],
    );
    expect(
      api.Platform.values.map(
        (value) => buildPlatformLabel(value, ClientLocale.ru),
      ),
      ["Не указано", "Windows", "macOS", "Linux", "Android", "iOS"],
    );
  });
  test('Availability: complete RU/EN catalog', () {
    expect(
      api.Availability.values.map(
        (value) => updateAvailabilityLabel(value, ClientLocale.en),
      ),
      [
        "Not specified",
        "Available",
        "Unsupported",
        "Blocked by policy",
        "Permission required",
        "Temporarily unavailable",
      ],
    );
    expect(
      api.Availability.values.map(
        (value) => updateAvailabilityLabel(value, ClientLocale.ru),
      ),
      [
        "Не указано",
        "Доступно",
        "Не поддерживается",
        "Заблокировано политикой",
        "Требуется разрешение",
        "Временно недоступно",
      ],
    );
  });
  for (final initial in ClientLocale.values) {
    for (final fail in [false, true]) {
      testWidgets('update information fail=$fail in $initial', (tester) async {
        final state = ClientStateController();
        final stream = StreamController<api.WatchEventsResponse>();
        await state.attach(stream.stream);
        stream.add(fixtures.snapshot(1));
        var loads = 0;
        final ui = api.BuildIdentity(
          version: 'ui-dev',
          platform: api.Platform.PLATFORM_LINUX,
          architecture: 'amd64',
        );
        Future<void> render(ClientLocale locale) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: ClientUpdatePanel(
                  state: state,
                  uiBuild: ui,
                  locale: locale,
                  load: (build) async {
                    loads++;
                    expect(build, ui);
                    if (fail) {
                      throw StateError('private details');
                    }
                    return api.UpdateInfo()..mergeFromProto3Json({
                      'metadata': {'instanceId': 'runtime-a', 'revision': '1'},
                      'reportedUi': ui.toProto3Json(),
                      'state': 'UPDATE_STATE_SOURCE_UNAVAILABLE',
                      'installedPair': {
                        'state': 'COMPATIBILITY_STATE_INCOMPATIBLE',
                        'reasonKey': 'pair.mismatch',
                      },
                      'discovery': {
                        'availability': 'AVAILABILITY_TEMPORARILY_UNAVAILABLE',
                        'reasonKey': 'source.offline',
                        'actionOwner': 'ACTION_OWNER_SUPPORT',
                      },
                    });
                  },
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await render(initial);
        await tester.tap(find.byKey(const Key('client-check-updates')));
        await tester.pumpAndSettle();
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
              ru
                  ? 'Сборка интерфейса: ui-dev; коммит Неизвестно; собрано Неизвестно; Linux/amd64'
                  : 'UI build: ui-dev; commit Unknown; built Unknown; Linux/amd64',
              ru
                  ? 'Сборка службы: Неизвестно; коммит Неизвестно; собрано Неизвестно; Не указано/'
                  : 'Runtime build: Unknown; commit Unknown; built Unknown; Not specified/',
              ru ? 'Проверить обновления' : 'Check updates',
              if (fail)
                ru
                    ? 'Не удалось подтвердить сведения об обновлении.'
                    : 'Update information could not be confirmed.'
              else ...[
                ru
                    ? 'Источник обновлений: Источник недоступен'
                    : 'Update source: Source unavailable',
                ru
                    ? 'Установленная пара: Несовместимо; pair.mismatch'
                    : 'Installed pair: Incompatible; pair.mismatch',
                ru
                    ? 'Поиск обновлений: Временно недоступно; source.offline; Поддержка'
                    : 'Discovery: Temporarily unavailable; source.offline; Support',
              ],
            ],
          );
          expect(loads, 1);
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
