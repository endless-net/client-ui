import 'package:endlessnet_client_api/client_api.dart' as api;

/// Validates a producer-verified projection, not a manifest signature or an
/// installer result. No network destination is opened by this reader.
Future<api.UpdateInfo> readClientUpdateInfo({
  required String instanceId,
  required api.BuildIdentity installedRuntime,
  required api.BuildIdentity reportedUi,
  required Future<api.GetUpdateInfoResponse> Function(api.GetUpdateInfoRequest)
  get,
  required void Function() checkContext,
  required DateTime Function() now,
}) async {
  if (instanceId.isEmpty) {
    throw const FormatException('Update lookup requires a runtime context');
  }
  final installed = api.BuildIdentity.fromBuffer(
    installedRuntime.writeToBuffer(),
  )..freeze();
  final request = api.GetUpdateInfoRequest(
    reportedUi: api.BuildIdentity.fromBuffer(reportedUi.writeToBuffer()),
  )..freeze();
  checkContext();
  final response = await get(request);
  checkContext();
  if (!response.hasInfo()) {
    throw const FormatException('Missing update projection');
  }
  final info = api.UpdateInfo.fromBuffer(response.info.writeToBuffer());
  if (!info.hasMetadata() ||
      info.metadata.instanceId != instanceId ||
      info.metadata.revision <= 0 ||
      !info.hasInstalledRuntime() ||
      info.installedRuntime != installed ||
      !info.hasReportedUi() ||
      info.reportedUi != request.reportedUi ||
      !info.hasInstalledPair() ||
      info.installedPair.state ==
          api.CompatibilityState.COMPATIBILITY_STATE_UNSPECIFIED ||
      info.state == api.UpdateState.UPDATE_STATE_UNSPECIFIED) {
    throw const FormatException('Invalid update context or identity');
  }
  if (info.state == api.UpdateState.UPDATE_STATE_AVAILABLE &&
      !info.hasAvailable()) {
    throw const FormatException('Available update requires verified metadata');
  }
  if (info.hasAvailable()) {
    if (info.state != api.UpdateState.UPDATE_STATE_AVAILABLE &&
        info.state != api.UpdateState.UPDATE_STATE_EXTERNAL_MANAGER_REQUIRED) {
      throw const FormatException('Update metadata contradicts source state');
    }
    final update = info.available;
    final clock = now().toUtc();
    final digest = RegExp(r'^[0-9a-fA-F]{64}$');
    if (update.releaseId.isEmpty ||
        !digest.hasMatch(update.manifestSha256) ||
        update.signingKeyId.isEmpty ||
        !update.hasVerifiedAt() ||
        !update.hasExpiresAt() ||
        !_validTimestamp(
          update.verifiedAt.seconds.toInt(),
          update.verifiedAt.nanos,
        ) ||
        !_validTimestamp(
          update.expiresAt.seconds.toInt(),
          update.expiresAt.nanos,
        ) ||
        update.verifiedAt.toDateTime().isAfter(clock) ||
        !update.expiresAt.toDateTime().isAfter(clock) ||
        !update.expiresAt.toDateTime().isAfter(
          update.verifiedAt.toDateTime(),
        ) ||
        !update.hasRuntime() ||
        update.runtime.version.isEmpty ||
        update.runtime.platform != installed.platform ||
        update.runtime.architecture != installed.architecture ||
        update.pairedUiVersion.isEmpty ||
        !update.hasCompatibility() ||
        update.compatibility.state ==
            api.CompatibilityState.COMPATIBILITY_STATE_UNSPECIFIED ||
        update.compatibility.minimumIpcVersion >
            update.compatibility.maximumIpcVersion ||
        update.compatibility.acceptedContractSha256.any(
          (hash) => !digest.hasMatch(hash),
        ) ||
        update.classification ==
            api.UpdateClassification.UPDATE_CLASSIFICATION_UNSPECIFIED ||
        update.channel ==
            api.DistributionChannel.DISTRIBUTION_CHANNEL_UNSPECIFIED ||
        (update.hasMandatoryAfter() &&
            !_validTimestamp(
              update.mandatoryAfter.seconds.toInt(),
              update.mandatoryAfter.nanos,
            )) ||
        !_safeOptionalUrl(update.actionUrl) ||
        !_safeOptionalUrl(update.releaseNotesUrl)) {
      throw const FormatException('Invalid verified update projection');
    }
  }
  // Unknown/source unavailable/verification failed are preserved, never mapped
  // to UP_TO_DATE. Mandatory classification does not authorize installation.
  return info..freeze();
}

bool _validTimestamp(int seconds, int nanos) =>
    seconds >= -62135596800 &&
    seconds <= 253402300799 &&
    nanos >= 0 &&
    nanos < 1000000000;

bool _safeOptionalUrl(String value) {
  if (value.isEmpty) return true;
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}
