import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_operation.dart';
import 'client_locale.dart';
import 'client_operation_labels.dart';

/// Render only typed result fields. Never serialize a whole operation: browser
/// URLs and future sensitive fields must not leak into diagnostic output.
class ClientOperationDetails extends StatelessWidget {
  const ClientOperationDetails({
    super.key,
    required this.operation,
    this.locale = ClientLocale.en,
  });
  final ClientLocale locale;
  final ClientOperation operation;

  @override
  Widget build(BuildContext context) {
    final value = operation.value;
    final lines = <String>[
      clientOperationStateLabel(value.state, locale: locale),
    ];
    if (value.continuity !=
        api.ConnectionContinuity.CONNECTION_CONTINUITY_UNSPECIFIED) {
      lines.add(
        locale.text(
          en: 'Connection continuity: ${clientContinuityLabel(value.continuity, locale: locale)}',
          ru: 'Непрерывность соединения: ${clientContinuityLabel(value.continuity, locale: locale)}',
        ),
      );
    }
    switch (value.whichOutcome()) {
      case api.Operation_Outcome.failure:
        lines.add(
          locale.text(
            en: 'Failure: ${clientFailureLabel(value.failure.code, locale: locale)}',
            ru: 'Ошибка: ${clientFailureLabel(value.failure.code, locale: locale)}',
          ),
        );
        lines.add(
          locale.text(
            en: 'Action owner: ${clientActionOwnerLabel(value.failure.actionOwner, locale: locale)}',
            ru: 'Ответственный за действие: ${clientActionOwnerLabel(value.failure.actionOwner, locale: locale)}',
          ),
        );
        lines.add(
          value.failure.retryable
              ? locale.text(
                  en: 'Retry may be possible; no command has been replayed.',
                  ru: 'Повтор может быть возможен; команда не отправлялась повторно.',
                )
              : locale.text(
                  en: 'Do not automatically retry this operation.',
                  ru: 'Не повторяйте эту операцию автоматически.',
                ),
        );
        if (value.failure.controlRequestId.isNotEmpty) {
          lines.add(
            locale.text(
              en: 'Control request: ${value.failure.controlRequestId}',
              ru: 'Запрос к серверу управления: ${value.failure.controlRequestId}',
            ),
          );
        }
      case api.Operation_Outcome.change:
        lines.add(
          value.change.changed
              ? locale.text(
                  en: 'Change reported by service.',
                  ru: 'Служба сообщила об изменении.',
                )
              : locale.text(
                  en: 'No change reported by service.',
                  ru: 'Служба сообщила об отсутствии изменений.',
                ),
        );
      case api.Operation_Outcome.enrollment:
        lines.add(
          locale.text(
            en: 'Enrollment profile: ${value.enrollment.profileId}',
            ru: 'Профиль регистрации: ${value.enrollment.profileId}',
          ),
        );
        lines.add(
          locale.text(
            en: 'Enrollment node: ${value.enrollment.nodeId}',
            ru: 'Узел регистрации: ${value.enrollment.nodeId}',
          ),
        );
      case api.Operation_Outcome.selection:
        lines.add(
          value.selection.selectedId.isEmpty
              ? locale.text(
                  en: 'Exit-node selection cleared.',
                  ru: 'Выбор выходного узла сброшен.',
                )
              : locale.text(
                  en: 'Result ID: ${value.selection.selectedId}',
                  ru: 'Идентификатор результата: ${value.selection.selectedId}',
                ),
        );
      case api.Operation_Outcome.cleanup:
        lines.add(switch (value.cleanup.outcome) {
          api.CleanupOutcome.CLEANUP_OUTCOME_REMOTE_CONFIRMED => locale.text(
            en: 'Remote cleanup confirmed.',
            ru: 'Удалённая очистка подтверждена.',
          ),
          api.CleanupOutcome.CLEANUP_OUTCOME_REMOTE_UNCONFIRMED => locale.text(
            en: 'Remote cleanup NOT confirmed.',
            ru: 'Удалённая очистка НЕ подтверждена.',
          ),
          api.CleanupOutcome.CLEANUP_OUTCOME_NOT_REGISTERED => locale.text(
            en: 'No registration to clean up.',
            ru: 'Регистрация для очистки отсутствует.',
          ),
          _ => locale.text(
            en: 'Remote cleanup outcome unknown.',
            ru: 'Результат удалённой очистки неизвестен.',
          ),
        });
        lines.add(
          value.cleanup.localRegistrationRemoved
              ? locale.text(
                  en: 'Local registration removed.',
                  ru: 'Локальная регистрация удалена.',
                )
              : locale.text(
                  en: 'Local registration not reported removed.',
                  ru: 'Удаление локальной регистрации не подтверждено.',
                ),
        );
        if (value.cleanup.controlRequestId.isNotEmpty) {
          lines.add(
            locale.text(
              en: 'Control request: ${value.cleanup.controlRequestId}',
              ru: 'Запрос к серверу управления: ${value.cleanup.controlRequestId}',
            ),
          );
        }
      case api.Operation_Outcome.renewal:
        // The status stream remains authoritative for active session state.
        lines.add(
          locale.text(
            en: 'Session renewal result received. Refresh session status.',
            ru: 'Получен результат продления сессии. Обновите состояние сессии.',
          ),
        );
      case api.Operation_Outcome.bundle:
        lines.add(
          locale.text(
            en: 'Diagnostics bundle ready: ${value.bundle.sizeBytes} bytes.',
            ru: 'Диагностический пакет готов: ${value.bundle.sizeBytes} байт.',
          ),
        );
        lines.add(
          locale.text(
            en: 'Download requires the caller-bound bundle RPC.',
            ru: 'Загрузка требует вызова API пакета от имени исходного пользователя.',
          ),
        );
      case api.Operation_Outcome.notSet:
        if (value.hasUserAction()) {
          lines.add(
            locale.text(
              en: 'Required action: ${clientRequiredActionLabel(value.userAction.kind, locale: locale)}',
              ru: 'Необходимое действие: ${clientRequiredActionLabel(value.userAction.kind, locale: locale)}',
            ),
          );
        }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final line in lines) Text(line)],
    );
  }
}
