import 'package:endlessnet_client_api/client_api.dart' as api;

/// Source trust is enforced by the producer's configured support policy. This
/// validates the authenticated projection, not arbitrary caller-supplied links.
Future<api.SupportInfo> readClientSupportInfo({
  required api.BuildIdentity installedRuntime,
  required Future<api.GetSupportInfoResponse> Function(
    api.GetSupportInfoRequest,
  )
  get,
  required void Function() checkContext,
}) async {
  final build = api.BuildIdentity.fromBuffer(installedRuntime.writeToBuffer())
    ..freeze();
  checkContext();
  final response = await get(api.GetSupportInfoRequest()..freeze());
  checkContext();
  if (!response.hasInfo()) {
    throw const FormatException('Missing support projection');
  }
  final info = api.SupportInfo.fromBuffer(response.info.writeToBuffer());
  if (!info.hasRuntime() ||
      info.runtime != build ||
      info.productName.trim().isEmpty) {
    throw const FormatException('Invalid support runtime identity');
  }
  for (final url in [
    info.documentationUrl,
    info.supportUrl,
    info.privacyUrl,
    info.licenseUrl,
  ]) {
    if (url.isEmpty) {
      continue; // A missing configured destination is not invented.
    }
    final uri = Uri.tryParse(url);
    if (url != url.trim() ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(url) ||
        uri == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Invalid support destination');
    }
  }
  // Preserve opaque offline_help_key; never interpret it as a filesystem path.
  return info..freeze();
}
