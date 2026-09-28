import 'package:endlessnet/client_deep_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enrollment deep link accepts only supported fields and modes', () {
    final uri = Uri.parse(
      'endlessnet://enroll?enroll_token=sample&hostname=workstation&mode=server',
    );
    expect(parseClientDeepLink(uri), uri);
  });

  test('unsupported, ambiguous, and malformed links are rejected', () {
    for (final value in [
      'https://example.test',
      'endlessnet://other',
      'endlessnet://enroll?mode=unknown',
      'endlessnet://enroll?hostname=one&hostname=two',
      'endlessnet://enroll?token=unsupported',
      'endlessnet://enroll?hostname=%FF',
    ]) {
      final uri = Uri.parse(value);
      expect(parseClientDeepLink(uri), isNull, reason: value);
    }
  });
}
