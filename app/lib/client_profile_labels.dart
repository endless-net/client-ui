import 'package:endlessnet_client_api/client_api.dart' as api;
import 'client_locale.dart';

String clientProfileStateLabel(api.ProfileState state, ClientLocale locale) =>
    switch (state) {
      api.ProfileState.PROFILE_STATE_EMPTY => locale.text(
        en: 'Empty',
        ru: 'Пустой',
      ),
      api.ProfileState.PROFILE_STATE_REGISTERED => locale.text(
        en: 'Registered',
        ru: 'Зарегистрирован',
      ),
      api.ProfileState.PROFILE_STATE_NEEDS_LOGIN => locale.text(
        en: 'Sign-in required',
        ru: 'Требуется вход',
      ),
      api.ProfileState.PROFILE_STATE_NEEDS_APPROVAL => locale.text(
        en: 'Approval required',
        ru: 'Требуется одобрение',
      ),
      api.ProfileState.PROFILE_STATE_BLOCKED => locale.text(
        en: 'Blocked',
        ru: 'Заблокирован',
      ),
      _ => locale.text(en: 'Not specified', ru: 'Не указано'),
    };
