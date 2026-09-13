import 'package:endlessnet_client_api/client_api.dart' as api;
import 'client_locale.dart';
import 'client_state_controller.dart';

String clientTrayServiceLabel(api.ServiceState value, ClientLocale locale) =>
    switch (value) {
      api.ServiceState.SERVICE_STATE_CONNECTED => locale.text(
        en: 'Connected',
        ru: 'Подключено',
      ),
      api.ServiceState.SERVICE_STATE_DISCONNECTED => locale.text(
        en: 'Disconnected',
        ru: 'Отключено',
      ),
      api.ServiceState.SERVICE_STATE_DEGRADED => locale.text(
        en: 'Degraded',
        ru: 'Работа с ограничениями',
      ),
      api.ServiceState.SERVICE_STATE_ERROR => locale.text(
        en: 'Runtime error',
        ru: 'Ошибка службы',
      ),
      api.ServiceState.SERVICE_STATE_NEEDS_ENROLLMENT => locale.text(
        en: 'Device enrollment required',
        ru: 'Требуется регистрация устройства',
      ),
      api.ServiceState.SERVICE_STATE_NEEDS_APPROVAL => locale.text(
        en: 'Waiting for approval',
        ru: 'Ожидание одобрения',
      ),
      api.ServiceState.SERVICE_STATE_SERVER_IDENTITY_CHANGED => locale.text(
        en: 'Server identity changed',
        ru: 'Идентичность сервера изменилась',
      ),
      api.ServiceState.SERVICE_STATE_RECOVERING => locale.text(
        en: 'Recovering',
        ru: 'Восстановление',
      ),
      api.ServiceState.SERVICE_STATE_RECOVERY_BLOCKED => locale.text(
        en: 'Recovery blocked',
        ru: 'Восстановление заблокировано',
      ),
      api.ServiceState.SERVICE_STATE_POLICY_BLOCKED => locale.text(
        en: 'Blocked by policy',
        ru: 'Заблокировано политикой',
      ),
      api.ServiceState.SERVICE_STATE_NEEDS_LOGIN => locale.text(
        en: 'Login required',
        ru: 'Требуется вход',
      ),
      _ => locale.text(en: 'Unknown', ru: 'Неизвестно'),
    };

String clientLinkLabel(ClientLinkState value, ClientLocale locale) =>
    switch (value) {
      ClientLinkState.disconnected => locale.text(
        en: 'Disconnected',
        ru: 'Отключена',
      ),
      ClientLinkState.awaitingSnapshot => locale.text(
        en: 'Waiting for snapshot',
        ru: 'Ожидание состояния',
      ),
      ClientLinkState.ready => locale.text(en: 'Ready', ru: 'Готова'),
      ClientLinkState.unavailable => locale.text(
        en: 'Unavailable',
        ru: 'Недоступна',
      ),
    };
