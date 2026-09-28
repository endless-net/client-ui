const _enrollmentModes = {
  'workstation',
  'server',
  'subnet_router',
  'interactive',
};

Uri? parseClientDeepLink(Uri uri) {
  try {
    if (uri.scheme != 'endlessnet' ||
        uri.host != 'enroll' ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.queryParametersAll.keys.any(
          (key) => !{'enroll_token', 'hostname', 'mode'}.contains(key),
        ) ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        !_enrollmentModes.contains(
          uri.queryParameters['mode'] ?? 'workstation',
        )) {
      return null;
    }
  } on FormatException {
    return null;
  }
  return uri;
}
