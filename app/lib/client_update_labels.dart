import 'package:endlessnet_client_api/client_api.dart' as api;
import 'client_locale.dart';

String updateStateLabel(api.UpdateState value, ClientLocale locale) =>
    switch (value) {
      api.UpdateState.UPDATE_STATE_UNKNOWN => locale.text(
        en: 'Unknown',
        ru: 'Неизвестно',
      ),
      api.UpdateState.UPDATE_STATE_UP_TO_DATE => locale.text(
        en: 'Up to date',
        ru: 'Актуальная версия',
      ),
      api.UpdateState.UPDATE_STATE_AVAILABLE => locale.text(
        en: 'Available',
        ru: 'Доступно',
      ),
      api.UpdateState.UPDATE_STATE_EXTERNAL_MANAGER_REQUIRED => locale.text(
        en: 'External manager required',
        ru: 'Требуется внешний менеджер',
      ),
      api.UpdateState.UPDATE_STATE_SOURCE_UNAVAILABLE => locale.text(
        en: 'Source unavailable',
        ru: 'Источник недоступен',
      ),
      api.UpdateState.UPDATE_STATE_VERIFICATION_FAILED => locale.text(
        en: 'Verification failed',
        ru: 'Проверка не пройдена',
      ),
      _ => locale.text(en: 'Not specified', ru: 'Не указано'),
    };

String compatibilityLabel(api.CompatibilityState value, ClientLocale locale) =>
    switch (value) {
      api.CompatibilityState.COMPATIBILITY_STATE_COMPATIBLE => locale.text(
        en: 'Compatible',
        ru: 'Совместимо',
      ),
      api.CompatibilityState.COMPATIBILITY_STATE_INCOMPATIBLE => locale.text(
        en: 'Incompatible',
        ru: 'Несовместимо',
      ),
      api.CompatibilityState.COMPATIBILITY_STATE_UNKNOWN => locale.text(
        en: 'Unknown',
        ru: 'Неизвестно',
      ),
      _ => locale.text(en: 'Not specified', ru: 'Не указано'),
    };

String updateClassificationLabel(
  api.UpdateClassification value,
  ClientLocale locale,
) => switch (value) {
  api.UpdateClassification.UPDATE_CLASSIFICATION_ORDINARY => locale.text(
    en: 'Ordinary',
    ru: 'Обычное',
  ),
  api.UpdateClassification.UPDATE_CLASSIFICATION_SECURITY => locale.text(
    en: 'Security',
    ru: 'Обновление безопасности',
  ),
  api.UpdateClassification.UPDATE_CLASSIFICATION_MANDATORY => locale.text(
    en: 'Mandatory',
    ru: 'Обязательное',
  ),
  _ => locale.text(en: 'Not specified', ru: 'Не указано'),
};

String distributionLabel(api.DistributionChannel value, ClientLocale locale) =>
    switch (value) {
      api.DistributionChannel.DISTRIBUTION_CHANNEL_VENDOR_PACKAGE =>
        locale.text(en: 'Vendor package', ru: 'Пакет поставщика'),
      api.DistributionChannel.DISTRIBUTION_CHANNEL_PACKAGE_MANAGER =>
        locale.text(en: 'Package manager', ru: 'Пакетный менеджер'),
      api.DistributionChannel.DISTRIBUTION_CHANNEL_APP_STORE => locale.text(
        en: 'App store',
        ru: 'Магазин приложений',
      ),
      api.DistributionChannel.DISTRIBUTION_CHANNEL_ENTERPRISE => locale.text(
        en: 'Enterprise',
        ru: 'Корпоративный канал',
      ),
      _ => locale.text(en: 'Not specified', ru: 'Не указано'),
    };

String buildPlatformLabel(
  api.Platform value,
  ClientLocale locale,
) => switch (value) {
  api.Platform.PLATFORM_WINDOWS => locale.text(en: 'Windows', ru: 'Windows'),
  api.Platform.PLATFORM_MACOS => locale.text(en: 'macOS', ru: 'macOS'),
  api.Platform.PLATFORM_LINUX => locale.text(en: 'Linux', ru: 'Linux'),
  api.Platform.PLATFORM_ANDROID => locale.text(en: 'Android', ru: 'Android'),
  api.Platform.PLATFORM_IOS => locale.text(en: 'iOS', ru: 'iOS'),
  _ => locale.text(en: 'Not specified', ru: 'Не указано'),
};

String updateAvailabilityLabel(api.Availability value, ClientLocale locale) =>
    switch (value) {
      api.Availability.AVAILABILITY_AVAILABLE => locale.text(
        en: 'Available',
        ru: 'Доступно',
      ),
      api.Availability.AVAILABILITY_UNSUPPORTED => locale.text(
        en: 'Unsupported',
        ru: 'Не поддерживается',
      ),
      api.Availability.AVAILABILITY_POLICY_BLOCKED => locale.text(
        en: 'Blocked by policy',
        ru: 'Заблокировано политикой',
      ),
      api.Availability.AVAILABILITY_PERMISSION_REQUIRED => locale.text(
        en: 'Permission required',
        ru: 'Требуется разрешение',
      ),
      api.Availability.AVAILABILITY_TEMPORARILY_UNAVAILABLE => locale.text(
        en: 'Temporarily unavailable',
        ru: 'Временно недоступно',
      ),
      _ => locale.text(en: 'Not specified', ru: 'Не указано'),
    };
