import 'dart:convert';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_operation_details.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases =
      jsonDecode(r'''[
  {
    "kind": "CONNECT",
    "fields": {
      "change": {
        "changed": true
      }
    },
    "en": [
      "Change reported by service."
    ],
    "ru": [
      "Служба сообщила об изменении."
    ]
  },
  {
    "kind": "DISCONNECT",
    "fields": {
      "change": {
        "changed": false
      }
    },
    "en": [
      "No change reported by service."
    ],
    "ru": [
      "Служба сообщила об отсутствии изменений."
    ]
  },
  {
    "kind": "ENROLL",
    "fields": {
      "enrollment": {
        "profileId": "p-1",
        "nodeId": "n-1"
      }
    },
    "en": [
      "Enrollment profile: p-1",
      "Enrollment node: n-1"
    ],
    "ru": [
      "Профиль регистрации: p-1",
      "Узел регистрации: n-1"
    ]
  },
  {
    "kind": "SELECT_NETWORK",
    "fields": {
      "selection": {
        "selectedId": "n-2"
      }
    },
    "en": [
      "Result ID: n-2"
    ],
    "ru": [
      "Идентификатор результата: n-2"
    ]
  },
  {
    "kind": "CLEAR_EXIT_NODE",
    "fields": {
      "selection": {}
    },
    "en": [
      "Exit-node selection cleared."
    ],
    "ru": [
      "Выбор выходного узла сброшен."
    ]
  },
  {
    "kind": "RENEW_SESSION",
    "fields": {
      "renewal": {}
    },
    "en": [
      "Session renewal result received. Refresh session status."
    ],
    "ru": [
      "Получен результат продления сессии. Обновите состояние сессии."
    ]
  },
  {
    "kind": "CREATE_DIAGNOSTICS_BUNDLE",
    "fields": {
      "bundle": {
        "bundleId": "secret-handle",
        "sizeBytes": "42"
      }
    },
    "en": [
      "Diagnostics bundle ready: 42 bytes.",
      "Download requires the caller-bound bundle RPC."
    ],
    "ru": [
      "Диагностический пакет готов: 42 байт.",
      "Загрузка требует вызова API пакета от имени исходного пользователя."
    ]
  },
  {
    "kind": "LOGOUT",
    "fields": {
      "cleanup": {
        "outcome": "CLEANUP_OUTCOME_REMOTE_CONFIRMED",
        "localRegistrationRemoved": false,
        "controlRequestId": "c-1"
      }
    },
    "en": [
      "Remote cleanup confirmed.",
      "Local registration not reported removed.",
      "Control request: c-1"
    ],
    "ru": [
      "Удалённая очистка подтверждена.",
      "Удаление локальной регистрации не подтверждено.",
      "Запрос к серверу управления: c-1"
    ]
  },
  {
    "kind": "LOGOUT",
    "fields": {
      "cleanup": {
        "outcome": "CLEANUP_OUTCOME_REMOTE_UNCONFIRMED",
        "localRegistrationRemoved": true,
        "controlRequestId": "c-1"
      }
    },
    "en": [
      "Remote cleanup NOT confirmed.",
      "Local registration removed.",
      "Control request: c-1"
    ],
    "ru": [
      "Удалённая очистка НЕ подтверждена.",
      "Локальная регистрация удалена.",
      "Запрос к серверу управления: c-1"
    ]
  },
  {
    "kind": "LOGOUT",
    "fields": {
      "cleanup": {
        "outcome": "CLEANUP_OUTCOME_NOT_REGISTERED",
        "localRegistrationRemoved": false,
        "controlRequestId": "c-1"
      }
    },
    "en": [
      "No registration to clean up.",
      "Local registration not reported removed.",
      "Control request: c-1"
    ],
    "ru": [
      "Регистрация для очистки отсутствует.",
      "Удаление локальной регистрации не подтверждено.",
      "Запрос к серверу управления: c-1"
    ]
  },
  {
    "kind": "LOGOUT",
    "fields": {
      "cleanup": {
        "outcome": "CLEANUP_OUTCOME_UNSPECIFIED",
        "localRegistrationRemoved": false,
        "controlRequestId": "c-1"
      }
    },
    "en": [
      "Remote cleanup outcome unknown.",
      "Local registration not reported removed.",
      "Control request: c-1"
    ],
    "ru": [
      "Результат удалённой очистки неизвестен.",
      "Удаление локальной регистрации не подтверждено.",
      "Запрос к серверу управления: c-1"
    ]
  },
  {
    "kind": "CONNECT",
    "state": "FAILED",
    "fields": {
      "failure": {
        "code": "ERROR_CODE_REMOTE_CLEANUP_REQUIRED",
        "actionOwner": "ACTION_OWNER_ACCESS_ADMINISTRATOR",
        "retryable": false,
        "reasonKey": "secret-reason",
        "controlRequestId": "c-2"
      }
    },
    "en": [
      "Failure: Remote cleanup still required",
      "Action owner: Access administrator",
      "Do not automatically retry this operation.",
      "Control request: c-2"
    ],
    "ru": [
      "Ошибка: Удалённая очистка по-прежнему требуется",
      "Ответственный за действие: Администратор доступа",
      "Не повторяйте эту операцию автоматически.",
      "Запрос к серверу управления: c-2"
    ]
  },
  {
    "kind": "CONNECT",
    "state": "FAILED",
    "fields": {
      "failure": {
        "code": "ERROR_CODE_REMOTE_CLEANUP_REQUIRED",
        "actionOwner": "ACTION_OWNER_ACCESS_ADMINISTRATOR",
        "retryable": true,
        "reasonKey": "secret-reason",
        "controlRequestId": "c-2"
      }
    },
    "en": [
      "Failure: Remote cleanup still required",
      "Action owner: Access administrator",
      "Retry may be possible; no command has been replayed.",
      "Control request: c-2"
    ],
    "ru": [
      "Ошибка: Удалённая очистка по-прежнему требуется",
      "Ответственный за действие: Администратор доступа",
      "Повтор может быть возможен; команда не отправлялась повторно.",
      "Запрос к серверу управления: c-2"
    ]
  },
  {
    "kind": "ENROLL",
    "state": "WAITING_FOR_USER",
    "fields": {
      "userAction": {
        "kind": "KIND_OPEN_BROWSER",
        "browserUrl": "https://example.test/secret-token"
      }
    },
    "en": [
      "Required action: Continue in your browser"
    ],
    "ru": [
      "Необходимое действие: Продолжите в браузере"
    ]
  }
]''')
          as List<dynamic>;
  for (final locale in ClientLocale.values) {
    testWidgets('US-14 operation details are entirely ${locale.name}', (
      tester,
    ) async {
      for (final raw in cases) {
        final row = raw as Map<String, dynamic>;
        final operation = ClientOperation.fromProto(
          api.Operation()..mergeFromProto3Json({
            'id': 'op-1',
            'kind': 'OPERATION_KIND_${row['kind']}',
            'state': 'OPERATION_STATE_${row['state'] ?? 'SUCCEEDED'}',
            'continuity': 'CONNECTION_CONTINUITY_UNKNOWN',
            ...row['fields'] as Map<String, dynamic>,
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ClientOperationDetails(
                  operation: operation,
                  locale: locale,
                ),
              ),
            ),
          ),
        );
        final stateLabel = switch (row['state']) {
          'FAILED' => locale.text(en: 'Failed', ru: 'Ошибка'),
          'WAITING_FOR_USER' => locale.text(
            en: 'Waiting for required action',
            ru: 'Ожидает необходимого действия',
          ),
          _ => locale.text(en: 'Completed', ru: 'Завершено'),
        };
        final actual = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(ClientOperationDetails),
                matching: find.byType(Text),
              ),
            )
            .map((text) => text.data)
            .toList();
        expect(actual, [
          stateLabel,
          locale.text(
            en: 'Connection continuity: Unknown',
            ru: 'Непрерывность соединения: Неизвестно',
          ),
          ...row[locale.name] as List<dynamic>,
        ], reason: '${row['kind']} / ${row['state']} / ${locale.name}');
        expect(actual.join(' '), isNot(contains('secret-')));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
