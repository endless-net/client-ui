import 'package:flutter_test/flutter_test.dart';

import 'package:endlessnet_tray/main.dart';

void main() {
  test('parseEnrollment accepts EndlessNet deep links', () {
    final request = parseEnrollment(
      'endlessnet://enroll?join_token=enj_test_token&server=https%3A%2F%2Fapi.example.test&mode=server',
      '',
      'workstation',
    );

    expect(request.token, 'enj_test_token');
    expect(request.server, 'https://api.example.test');
    expect(request.mode, 'server');
  });

  test('parseEnrollment extracts pasted token text', () {
    final request = parseEnrollment(
      'connect with enr_pasted_secret now',
      'https://api.endlessnet.ru',
      '',
    );

    expect(request.token, 'enr_pasted_secret');
    expect(request.server, 'https://api.endlessnet.ru');
    expect(request.mode, 'workstation');
  });

  test('redactText removes enrollment tokens and credentials', () {
    final redacted = redactText(
      'token=enr_secret private_key: abc Bearer bearer-secret endlessnet://enroll?token=enj_secret',
    );

    expect(redacted, isNot(contains('enr_secret')));
    expect(redacted, isNot(contains('abc')));
    expect(redacted, isNot(contains('bearer-secret')));
    expect(redacted, isNot(contains('enj_secret')));
  });
}
