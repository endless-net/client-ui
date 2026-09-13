import 'package:endlessnet/client_operation_labels.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'US-14 Russian operation catalog preserves roles and failure meanings',
    () {
      expect(
        api.OperationState.values.map(
          (v) => clientOperationStateLabel(v, locale: ClientLocale.ru),
        ),
        [
          'Неизвестно',
          'Ожидает выполнения',
          'Выполняется',
          'Ожидает необходимого действия',
          'Завершено',
          'Ошибка',
          'Отменено',
        ],
      );
      expect(
        api.ConnectionContinuity.values.map(
          (v) => clientContinuityLabel(v, locale: ClientLocale.ru),
        ),
        ['Неизвестно', 'Неприменимо', 'Сохранено', 'Прервано', 'Неизвестно'],
      );
      expect(
        api.ActionOwner.values.map(
          (v) => clientActionOwnerLabel(v, locale: ClientLocale.ru),
        ),
        [
          'Неизвестно',
          'Вы',
          'Администратор устройства',
          'Администратор доступа',
          'Поддержка',
        ],
      );
      expect(
        api.UserAction_Kind.values.map(
          (v) => clientRequiredActionLabel(v, locale: ClientLocale.ru),
        ),
        [
          'Неизвестно',
          'Продолжите в браузере',
          'Дождитесь одобрения',
          'Предоставьте разрешение VPN',
          'Используйте привилегированный помощник',
          'Обратитесь к администратору доступа',
        ],
      );
      expect(
        api.ErrorCode.values.map(
          (v) => clientFailureLabel(v, locale: ClientLocale.ru),
        ),
        [
          'Неизвестная ошибка',
          'Некорректные данные',
          'Требуется аутентификация',
          'Требуется владелец установки',
          'Требуется администратор устройства',
          'Не поддерживается',
          'Не найдено',
          'Состояние службы изменилось',
          'Заблокировано политикой',
          'Требуется разрешение',
          'Служба занята',
          'Превышен лимит',
          'Недоступно',
          'Истекло время ожидания запроса',
          'Запрос отменён',
          'Внутренняя ошибка службы',
          'Требуется регистрация устройства',
          'Требуется вход',
          'Требуется одобрение',
          'В одобрении отказано',
          'Идентичность сервера изменилась',
          'Подтверждение идентичности сервера больше не соответствует текущим данным',
          'Удалённая очистка по-прежнему требуется',
          'Требуется подтверждение локального удаления',
          'Служба не смогла применить изменение',
          'Профиль активен',
          'Конфликт ресурсов',
          'Несовместимый контракт клиента',
        ],
      );
    },
  );

  test('US-14 operation states and continuity retain distinct meanings', () {
    expect(api.OperationState.values.map(clientOperationStateLabel), [
      'Unknown',
      'Pending',
      'In progress',
      'Waiting for required action',
      'Completed',
      'Failed',
      'Cancelled',
    ]);
    expect(api.ConnectionContinuity.values.map(clientContinuityLabel), [
      'Unknown',
      'Not applicable',
      'Preserved',
      'Interrupted',
      'Unknown',
    ]);
    expect(api.ActionOwner.values.map(clientActionOwnerLabel), [
      'Unknown',
      'You',
      'Device administrator',
      'Access administrator',
      'Support',
    ]);
    expect(api.UserAction_Kind.values.map(clientRequiredActionLabel), [
      'Unknown',
      'Continue in your browser',
      'Wait for approval',
      'Grant VPN permission',
      'Use the privileged helper',
      'Contact your access administrator',
    ]);
  });
  test('US-14 every current failure code has a distinct safe label', () {
    expect(
      clientFailureLabel(api.ErrorCode.ERROR_CODE_UNSPECIFIED),
      'Unknown failure',
    );
    final labels = api.ErrorCode.values
        .skip(1)
        .map(clientFailureLabel)
        .toList();
    expect(labels.toSet().length, labels.length);
    for (final label in labels) {
      expect(label, isNotEmpty);
      expect(label, isNot('Unknown failure'));
      expect(label, isNot(contains('_')));
    }
    expect(
      clientFailureLabel(api.ErrorCode.ERROR_CODE_REMOTE_CLEANUP_REQUIRED),
      'Remote cleanup still required',
    );
    expect(
      clientFailureLabel(api.ErrorCode.ERROR_CODE_STALE_STATE),
      'Runtime state changed',
    );
    expect(
      clientFailureLabel(api.ErrorCode.ERROR_CODE_UNAVAILABLE),
      'Unavailable',
    );
  });
}
