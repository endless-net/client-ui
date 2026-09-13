import 'package:endlessnet_client_api/client_api.dart' as api;

/// One immutable preferences/policy projection. A mixed revision must be
/// refreshed explicitly, not rendered as if it were one authoritative view.
final class ClientPreferences {
  ClientPreferences._(this.preferences, this.managed);
  final api.Preferences preferences;
  final List<api.ManagedSetting> managed;
}

Future<ClientPreferences> readClientPreferences({
  required String instanceId,
  required String profileId,
  required Future<api.GetPreferencesResponse> Function(
    api.GetPreferencesRequest,
  )
  get,
  required Future<api.ListManagedSettingsResponse> Function(
    api.ListManagedSettingsRequest,
  )
  listManaged,
  required void Function() checkContext,
}) async {
  if (instanceId.isEmpty || profileId.isEmpty) {
    throw const FormatException('Preferences require an explicit context');
  }
  checkContext();
  final response = await get(
    api.GetPreferencesRequest(profile: api.ProfileRef(profileId: profileId)),
  );
  checkContext();
  if (!response.hasPreferences() ||
      !response.preferences.hasMetadata() ||
      response.preferences.profileId != profileId ||
      response.preferences.metadata.instanceId != instanceId ||
      response.preferences.metadata.revision <= 0) {
    throw const FormatException('Invalid preferences context');
  }
  // Clone before the second await, including optional false and absent fields.
  final preferences = api.Preferences.fromBuffer(
    response.preferences.writeToBuffer(),
  )..freeze();
  final policies = await listManaged(
    api.ListManagedSettingsRequest(
      profile: api.ProfileRef(profileId: profileId),
    ),
  );
  checkContext();
  if (!policies.hasMetadata() ||
      policies.metadata.instanceId != instanceId ||
      policies.metadata.revision != preferences.metadata.revision) {
    throw const FormatException('Inconsistent preferences policy revision');
  }
  final keys = <api.PreferenceKey>{};
  for (final setting in policies.settings) {
    if (setting.key == api.PreferenceKey.PREFERENCE_KEY_UNSPECIFIED ||
        !keys.add(setting.key) ||
        !setting.hasControl()) {
      throw const FormatException('Invalid managed preference');
    }
    final boolean =
        setting.key == api.PreferenceKey.PREFERENCE_KEY_ALLOW_INBOUND ||
        setting.key == api.PreferenceKey.PREFERENCE_KEY_ACCEPT_DNS ||
        setting.key == api.PreferenceKey.PREFERENCE_KEY_ACCEPT_ROUTES;
    if (boolean ? !setting.hasBooleanValue() : !setting.hasLifecycleValue()) {
      throw const FormatException('Invalid managed preference value kind');
    }
  }
  return ClientPreferences._(
    preferences,
    List.unmodifiable([
      for (final setting in policies.settings)
        api.ManagedSetting.fromBuffer(setting.writeToBuffer())..freeze(),
    ]),
  );
}
