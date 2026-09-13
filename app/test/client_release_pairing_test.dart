import 'dart:convert';
import 'dart:io';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release pairing identity equals the resolved generated SDK', () {
    final identity =
        jsonDecode(File('../contracts/client-v0.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(identity['protocol'], api.ClientContract.protocol);
    expect(identity['version'], api.ClientContract.version);
    expect(identity['sha256'], api.ClientContract.sha256);
  });
}
