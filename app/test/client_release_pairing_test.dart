@Tags(['short'])
library;

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
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

  test('descriptor pairing rejects missing, textual and retired inputs', () {
    for (final bytes in [
      <int>[],
      utf8.encode(api.ClientContract.sha256),
      utf8.encode(jsonEncode({'sha256': api.ClientContract.sha256})),
      utf8.encode('openapi: 3.0.3\ninfo:\n  version: 2\n'),
      <int>[0x0a, 0x02, 0x0d, 0x0a, 0xff, 0x00],
    ]) {
      expect(_matchesDescriptor(bytes), isFalse);
    }
  });

  final descriptor = Platform.environment['ENDLESSNET_IPC_DESCRIPTOR'];
  final required =
      Platform.environment['ENDLESSNET_REQUIRE_RELEASE_DESCRIPTOR'] == 'true';
  test(
    'resolved released descriptor bytes equal the generated Dart contract',
    () {
      expect(descriptor, isNotNull, reason: 'Released descriptor is required');
      expect(
        descriptor,
        isNotEmpty,
        reason: 'Released descriptor path is empty',
      );
      final bytes = File(descriptor!).readAsBytesSync();
      expect(_matchesDescriptor(bytes), isTrue);
      final modified = List<int>.from(bytes);
      modified[modified.length ~/ 2] ^= 1;
      expect(_matchesDescriptor(modified), isFalse);
      expect(_matchesDescriptor([...bytes, 0]), isFalse);
      expect(_matchesDescriptor(bytes.sublist(1)), isFalse);
    },
    skip: descriptor == null && !required
        ? 'Released descriptor is provided by the verified release resolver'
        : false,
  );
}

bool _matchesDescriptor(List<int> bytes) =>
    bytes.isNotEmpty &&
    sha256.convert(bytes).toString() == api.ClientContract.sha256;
