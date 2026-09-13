import 'package:endlessnet_client_api/client_api.dart' as api;

import 'client_locale.dart';

// Closed producer enums only. Never derive UI text from arbitrary reason keys,
// transport messages or an enum's wire name.
String clientOperationStateLabel(
  api.OperationState state, {
  ClientLocale locale = ClientLocale.en,
}) => switch (state) {
  api.OperationState.OPERATION_STATE_PENDING => locale.text(
    en: 'Pending',
    ru: 'Ожидает выполнения',
  ),
  api.OperationState.OPERATION_STATE_RUNNING => locale.text(
    en: 'In progress',
    ru: 'Выполняется',
  ),
  api.OperationState.OPERATION_STATE_WAITING_FOR_USER => locale.text(
    en: 'Waiting for required action',
    ru: 'Ожидает необходимого действия',
  ),
  api.OperationState.OPERATION_STATE_SUCCEEDED => locale.text(
    en: 'Completed',
    ru: 'Завершено',
  ),
  api.OperationState.OPERATION_STATE_FAILED => locale.text(
    en: 'Failed',
    ru: 'Ошибка',
  ),
  api.OperationState.OPERATION_STATE_CANCELLED => locale.text(
    en: 'Cancelled',
    ru: 'Отменено',
  ),
  _ => locale.text(en: 'Unknown', ru: 'Неизвестно'),
};

String clientContinuityLabel(
  api.ConnectionContinuity value, {
  ClientLocale locale = ClientLocale.en,
}) => switch (value) {
  api.ConnectionContinuity.CONNECTION_CONTINUITY_NOT_APPLICABLE => locale.text(
    en: 'Not applicable',
    ru: 'Неприменимо',
  ),
  api.ConnectionContinuity.CONNECTION_CONTINUITY_PRESERVED => locale.text(
    en: 'Preserved',
    ru: 'Сохранено',
  ),
  api.ConnectionContinuity.CONNECTION_CONTINUITY_INTERRUPTED => locale.text(
    en: 'Interrupted',
    ru: 'Прервано',
  ),
  _ => locale.text(en: 'Unknown', ru: 'Неизвестно'),
};

String clientActionOwnerLabel(
  api.ActionOwner value, {
  ClientLocale locale = ClientLocale.en,
}) => switch (value) {
  api.ActionOwner.ACTION_OWNER_USER => locale.text(en: 'You', ru: 'Вы'),
  api.ActionOwner.ACTION_OWNER_DEVICE_ADMINISTRATOR => locale.text(
    en: 'Device administrator',
    ru: 'Администратор устройства',
  ),
  api.ActionOwner.ACTION_OWNER_ACCESS_ADMINISTRATOR => locale.text(
    en: 'Access administrator',
    ru: 'Администратор доступа',
  ),
  api.ActionOwner.ACTION_OWNER_SUPPORT => locale.text(
    en: 'Support',
    ru: 'Поддержка',
  ),
  _ => locale.text(en: 'Unknown', ru: 'Неизвестно'),
};

String clientRequiredActionLabel(
  api.UserAction_Kind value, {
  ClientLocale locale = ClientLocale.en,
}) => switch (value) {
  api.UserAction_Kind.KIND_OPEN_BROWSER => locale.text(
    en: 'Continue in your browser',
    ru: 'Продолжите в браузере',
  ),
  api.UserAction_Kind.KIND_WAIT_FOR_APPROVAL => locale.text(
    en: 'Wait for approval',
    ru: 'Дождитесь одобрения',
  ),
  api.UserAction_Kind.KIND_GRANT_VPN_PERMISSION => locale.text(
    en: 'Grant VPN permission',
    ru: 'Предоставьте разрешение VPN',
  ),
  api.UserAction_Kind.KIND_USE_PRIVILEGED_HELPER => locale.text(
    en: 'Use the privileged helper',
    ru: 'Используйте привилегированный помощник',
  ),
  api.UserAction_Kind.KIND_CONTACT_ACCESS_ADMINISTRATOR => locale.text(
    en: 'Contact your access administrator',
    ru: 'Обратитесь к администратору доступа',
  ),
  _ => locale.text(en: 'Unknown', ru: 'Неизвестно'),
};

String clientFailureLabel(
  api.ErrorCode value, {
  ClientLocale locale = ClientLocale.en,
}) => switch (value) {
  api.ErrorCode.ERROR_CODE_INVALID_ARGUMENT => locale.text(
    en: 'Invalid input',
    ru: 'Некорректные данные',
  ),
  api.ErrorCode.ERROR_CODE_UNAUTHENTICATED => locale.text(
    en: 'Authentication required',
    ru: 'Требуется аутентификация',
  ),
  api.ErrorCode.ERROR_CODE_OWNER_REQUIRED => locale.text(
    en: 'Installation owner required',
    ru: 'Требуется владелец установки',
  ),
  api.ErrorCode.ERROR_CODE_ADMINISTRATOR_REQUIRED => locale.text(
    en: 'Device administrator required',
    ru: 'Требуется администратор устройства',
  ),
  api.ErrorCode.ERROR_CODE_UNSUPPORTED => locale.text(
    en: 'Not supported',
    ru: 'Не поддерживается',
  ),
  api.ErrorCode.ERROR_CODE_NOT_FOUND => locale.text(
    en: 'Not found',
    ru: 'Не найдено',
  ),
  api.ErrorCode.ERROR_CODE_STALE_STATE => locale.text(
    en: 'Runtime state changed',
    ru: 'Состояние службы изменилось',
  ),
  api.ErrorCode.ERROR_CODE_POLICY_BLOCKED => locale.text(
    en: 'Blocked by policy',
    ru: 'Заблокировано политикой',
  ),
  api.ErrorCode.ERROR_CODE_PERMISSION_REQUIRED => locale.text(
    en: 'Permission required',
    ru: 'Требуется разрешение',
  ),
  api.ErrorCode.ERROR_CODE_BUSY => locale.text(
    en: 'Runtime busy',
    ru: 'Служба занята',
  ),
  api.ErrorCode.ERROR_CODE_LIMIT_EXCEEDED => locale.text(
    en: 'Limit exceeded',
    ru: 'Превышен лимит',
  ),
  api.ErrorCode.ERROR_CODE_UNAVAILABLE => locale.text(
    en: 'Unavailable',
    ru: 'Недоступно',
  ),
  api.ErrorCode.ERROR_CODE_DEADLINE_EXCEEDED => locale.text(
    en: 'Request deadline exceeded',
    ru: 'Истекло время ожидания запроса',
  ),
  api.ErrorCode.ERROR_CODE_CANCELLED => locale.text(
    en: 'Request cancelled',
    ru: 'Запрос отменён',
  ),
  api.ErrorCode.ERROR_CODE_INTERNAL => locale.text(
    en: 'Internal runtime error',
    ru: 'Внутренняя ошибка службы',
  ),
  api.ErrorCode.ERROR_CODE_NEEDS_ENROLLMENT => locale.text(
    en: 'Device enrollment required',
    ru: 'Требуется регистрация устройства',
  ),
  api.ErrorCode.ERROR_CODE_NEEDS_LOGIN => locale.text(
    en: 'Login required',
    ru: 'Требуется вход',
  ),
  api.ErrorCode.ERROR_CODE_APPROVAL_REQUIRED => locale.text(
    en: 'Approval required',
    ru: 'Требуется одобрение',
  ),
  api.ErrorCode.ERROR_CODE_APPROVAL_REJECTED => locale.text(
    en: 'Approval rejected',
    ru: 'В одобрении отказано',
  ),
  api.ErrorCode.ERROR_CODE_SERVER_IDENTITY_CHANGED => locale.text(
    en: 'Server identity changed',
    ru: 'Идентичность сервера изменилась',
  ),
  api.ErrorCode.ERROR_CODE_IDENTITY_CONFIRMATION_MISMATCH => locale.text(
    en: 'Server identity confirmation no longer matches',
    ru: 'Подтверждение идентичности сервера больше не соответствует текущим данным',
  ),
  api.ErrorCode.ERROR_CODE_REMOTE_CLEANUP_REQUIRED => locale.text(
    en: 'Remote cleanup still required',
    ru: 'Удалённая очистка по-прежнему требуется',
  ),
  api.ErrorCode.ERROR_CODE_LOCAL_FORGET_CONFIRMATION_REQUIRED => locale.text(
    en: 'Local removal confirmation required',
    ru: 'Требуется подтверждение локального удаления',
  ),
  api.ErrorCode.ERROR_CODE_APPLY_FAILED => locale.text(
    en: 'Runtime could not apply the change',
    ru: 'Служба не смогла применить изменение',
  ),
  api.ErrorCode.ERROR_CODE_PROFILE_ACTIVE => locale.text(
    en: 'Profile is active',
    ru: 'Профиль активен',
  ),
  api.ErrorCode.ERROR_CODE_RESOURCE_CONFLICT => locale.text(
    en: 'Resource conflict',
    ru: 'Конфликт ресурсов',
  ),
  api.ErrorCode.ERROR_CODE_CONTRACT_MISMATCH => locale.text(
    en: 'Incompatible client contract',
    ru: 'Несовместимый контракт клиента',
  ),
  _ => locale.text(en: 'Unknown failure', ru: 'Неизвестная ошибка'),
};
