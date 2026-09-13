import 'package:endlessnet_client_api/client_api.dart' as api;
import 'client_locale.dart';

String resourceKindLabel(api.ResourceKind kind, ClientLocale locale) =>
    switch (kind) {
      api.ResourceKind.RESOURCE_KIND_HOST => locale.text(
        en: 'Host',
        ru: 'Узел',
      ),
      api.ResourceKind.RESOURCE_KIND_SUBNET => locale.text(
        en: 'Subnet',
        ru: 'Подсеть',
      ),
      api.ResourceKind.RESOURCE_KIND_SERVICE => locale.text(
        en: 'Service',
        ru: 'Сервис',
      ),
      api.ResourceKind.RESOURCE_KIND_APPLICATION => locale.text(
        en: 'Application',
        ru: 'Приложение',
      ),
      _ => locale.text(en: 'Not specified', ru: 'Не указан'),
    };

String settingSourceLabel(api.SettingSource source, ClientLocale locale) =>
    switch (source) {
      api.SettingSource.SETTING_SOURCE_DEFAULT => locale.text(
        en: 'Default',
        ru: 'По умолчанию',
      ),
      api.SettingSource.SETTING_SOURCE_USER => locale.text(
        en: 'User',
        ru: 'Пользователь',
      ),
      api.SettingSource.SETTING_SOURCE_DEVICE_POLICY => locale.text(
        en: 'Device policy',
        ru: 'Политика устройства',
      ),
      api.SettingSource.SETTING_SOURCE_ACCOUNT_POLICY => locale.text(
        en: 'Account policy',
        ru: 'Политика учётной записи',
      ),
      api.SettingSource.SETTING_SOURCE_PLATFORM => locale.text(
        en: 'Platform',
        ru: 'Платформа',
      ),
      _ => locale.text(en: 'Not specified', ru: 'Не указан'),
    };
