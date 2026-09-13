import 'package:endlessnet_client_api/client_api.dart' as api;
import 'client_locale.dart';

String exitFamilyModeLabel(api.ExitFamilyMode value, ClientLocale locale) =>
    switch (value) {
      api.ExitFamilyMode.EXIT_FAMILY_MODE_NONE => locale.text(
        en: 'No exit',
        ru: 'Без выходного узла',
      ),
      api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV4_ONLY => locale.text(
        en: 'IPv4 only',
        ru: 'Только IPv4',
      ),
      api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV6_ONLY => locale.text(
        en: 'IPv6 only',
        ru: 'Только IPv6',
      ),
      api.ExitFamilyMode.EXIT_FAMILY_MODE_DUAL_STACK => locale.text(
        en: 'IPv4 and IPv6',
        ru: 'IPv4 и IPv6',
      ),
      _ => locale.text(en: 'Not specified', ru: 'Не указано'),
    };

String exitLanAccessLabel(
  api.LanAccess value,
  ClientLocale locale,
) => switch (value) {
  api.LanAccess.LAN_ACCESS_BLOCK => locale.text(en: 'Block', ru: 'Запретить'),
  api.LanAccess.LAN_ACCESS_ALLOW => locale.text(en: 'Allow', ru: 'Разрешить'),
  _ => locale.text(en: 'Not specified', ru: 'Не указано'),
};

String exitApplyStateLabel(api.ApplyState value, ClientLocale locale) =>
    switch (value) {
      api.ApplyState.APPLY_STATE_PENDING => locale.text(
        en: 'Pending',
        ru: 'Ожидание',
      ),
      api.ApplyState.APPLY_STATE_APPLIED => locale.text(
        en: 'Applied',
        ru: 'Применено',
      ),
      api.ApplyState.APPLY_STATE_FAILED => locale.text(
        en: 'Failed',
        ru: 'Ошибка',
      ),
      _ => locale.text(en: 'Not specified', ru: 'Не указано'),
    };
