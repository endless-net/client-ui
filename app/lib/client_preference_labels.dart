import 'package:endlessnet_client_api/client_api.dart' as api;
import 'client_locale.dart';

String preferenceKeyLabel(api.PreferenceKey key, ClientLocale locale) =>
    switch (key) {
      api.PreferenceKey.PREFERENCE_KEY_ALLOW_INBOUND => locale.text(
        en: 'Allow inbound',
        ru: 'Разрешить входящие подключения',
      ),
      api.PreferenceKey.PREFERENCE_KEY_ACCEPT_DNS => locale.text(
        en: 'Accept DNS',
        ru: 'Принимать DNS',
      ),
      api.PreferenceKey.PREFERENCE_KEY_ACCEPT_ROUTES => locale.text(
        en: 'Accept routes',
        ru: 'Принимать маршруты',
      ),
      api.PreferenceKey.PREFERENCE_KEY_RUNTIME_START => locale.text(
        en: 'Runtime start',
        ru: 'Запуск службы',
      ),
      api.PreferenceKey.PREFERENCE_KEY_UI_QUIT => locale.text(
        en: 'Graceful UI quit',
        ru: 'Штатное закрытие интерфейса',
      ),
      api.PreferenceKey.PREFERENCE_KEY_USER_LOGOFF => locale.text(
        en: 'User logoff',
        ru: 'Выход пользователя из системы',
      ),
      api.PreferenceKey.PREFERENCE_KEY_SUSPEND => locale.text(
        en: 'Suspend',
        ru: 'Приостановка',
      ),
      api.PreferenceKey.PREFERENCE_KEY_RESUME => locale.text(
        en: 'Resume',
        ru: 'Возобновление',
      ),
      _ => locale.text(en: 'Not specified', ru: 'Не указано'),
    };

String preferenceValueLabel(Object? value, ClientLocale locale) =>
    switch (value) {
      null => locale.text(en: 'No override', ru: 'Без переопределения'),
      true => locale.text(en: 'Yes', ru: 'Да'),
      false => locale.text(en: 'No', ru: 'Нет'),
      api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_KEEP_INTENT => locale.text(
        en: 'Keep intent',
        ru: 'Сохранить намерение',
      ),
      api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_CONNECT => locale.text(
        en: 'Connect',
        ru: 'Подключить',
      ),
      api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_DISCONNECT => locale.text(
        en: 'Disconnect',
        ru: 'Отключить',
      ),
      api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_PLATFORM_MANAGED => locale.text(
        en: 'Platform managed',
        ru: 'Управляется платформой',
      ),
      api.LifecycleBehavior.LIFECYCLE_BEHAVIOR_UNSPECIFIED => locale.text(
        en: 'Not specified',
        ru: 'Не указано',
      ),
      _ => throw StateError('Unsupported preference value'),
    };
