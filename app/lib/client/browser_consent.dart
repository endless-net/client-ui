Uri? browserConsentUri(String value, String controlOrigin) {
  final url = Uri.tryParse(value);
  final origin = controlOrigin == 'https://api.endlessnet.ru'
      ? 'https://admin.endlessnet.ru'
      : controlOrigin;
  if (url == null ||
      url.scheme != 'https' ||
      url.userInfo.isNotEmpty ||
      url.hasQuery ||
      url.hasFragment ||
      url.origin != origin) {
    return null;
  }
  return url;
}
