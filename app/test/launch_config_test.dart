import 'dart:convert';
import 'dart:typed_data';

import 'package:endlessnet_client_ui/app/launch_config.dart';
import 'package:endlessnet_client_ui/client/contract_identity.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> launchValues() => {
  'schema': 1,
  'instance_id': '1bf2f0fa-10d6-4bd7-8a2c-969596194c40',
  'server_sid': 'S-1-5-18',
  'profile_id': '0b6e11e3-3daa-4846-92ed-e07b6d8ce566',
  'control_origin': 'https://control.example',
  'connect_timeout_ms': 2000,
  'write_timeout_ms': 2000,
  'rpc_timeout_ms': 30000,
  'poll_interval_seconds': 2,
  'journal_max_bytes': 65536,
  'pending_write_max_bytes': 262144,
  'failure_max_bytes': 16384,
};
UiLaunchConfig decode(
  String text, {
  String library = r'C:\bundle\endlessnet_windows_pipe.dll',
}) => UiLaunchConfig.decode(
  Uint8List.fromList(utf8.encode(text)),
  nativeLibraryPath: library,
);

void main() {
  test('installed policy uses the current runtime instance on each read', () {
    final policy = launchValues()..remove('instance_id');
    for (final instance in [
      '34b5fbe6-9641-4c73-8ae4-974123fa2e52',
      '258d48c3-f86f-4b7f-9d14-53da3b76a628',
    ]) {
      final config = UiLaunchConfig.decode(
        Uint8List.fromList(utf8.encode(jsonEncode(policy))),
        nativeLibraryPath: r'C:\bundle\endlessnet_windows_pipe.dll',
        runtimeInstance: instance,
      );
      expect(config.pipe.instanceId, instance);
      expect(config.pipe.serverSid, 'S-1-5-18');
    }
  });

  test(
    'missing or invalid runtime cannot fall back to a persisted instance',
    () {
      final policy = launchValues()..remove('instance_id');
      for (final instance in [
        '',
        'not-an-instance',
        '00000000-0000-0000-0000-000000000000',
      ]) {
        expect(
          () => UiLaunchConfig.decode(
            Uint8List.fromList(utf8.encode(jsonEncode(policy))),
            nativeLibraryPath: r'C:\bundle\endlessnet_windows_pipe.dll',
            runtimeInstance: instance,
          ),
          throwsA(isA<UiConfigurationFailure>()),
        );
      }
      expect(
        () => decode(jsonEncode(policy)),
        throwsA(isA<UiConfigurationFailure>()),
      );
      expect(
        () => UiLaunchConfig.decode(
          Uint8List.fromList(utf8.encode(jsonEncode(launchValues()))),
          nativeLibraryPath: r'C:\bundle\endlessnet_windows_pipe.dll',
          runtimeInstance: '34b5fbe6-9641-4c73-8ae4-974123fa2e52',
        ),
        throwsA(isA<UiConfigurationFailure>()),
      );
    },
  );

  test('explicit values preserve profile and budgets; descriptor identity is compiled', () {
    final config = decode(
      const JsonEncoder.withIndent('  ').convert(launchValues()),
    );
    expect(
      config.pipe.path,
      r'\\.\pipe\endlessnet-client-1bf2f0fa-10d6-4bd7-8a2c-969596194c40',
    );
    expect(config.profile.controlOrigin, 'https://control.example');
    config.profile.controlOrigin = 'https://foreign.example';
    expect(config.profile.controlOrigin, 'https://control.example');
    expect(config.rpcTimeout, const Duration(seconds: 30));
    expect(config.journalMaxBytes, 65536);
    expect(config.contractSha256, clientContractSha256);
  });

  test('no missing/default/secret/descriptor override or nested values are accepted', () {
    for (final field in UiLaunchConfig.keys) {
      final incomplete = launchValues()..remove(field);
      expect(
        () => decode(jsonEncode(incomplete)),
        throwsA(isA<UiConfigurationFailure>()),
      );
    }
    for (final extra in [
      'access_token',
      'expected_contract_sha256',
      'deployment',
      'extra',
    ]) {
      final unknown = launchValues()..[extra] = 'must-not-escape';
      expect(
        () => decode(jsonEncode(unknown)),
        throwsA(isA<UiConfigurationFailure>()),
      );
    }
    final nested = launchValues()..['profile_id'] = {'id': 'nested'};
    expect(
      () => decode(jsonEncode(nested)),
      throwsA(isA<UiConfigurationFailure>()),
    );
    expect(
      const UiConfigurationFailure().toString().contains('must-not-escape'),
      false,
    );
  });

  test(
    'duplicate escaped keys, trailing data and malformed UTF8 fail closed',
    () {
      final valid = jsonEncode(launchValues());
      final duplicated = valid.replaceFirst('{', '{"schema":1,');
      final escaped = valid.replaceFirst('{', r'{"\u0073chema":1,');
      for (final value in [
        duplicated,
        escaped,
        '$valid {}',
        '$valid,',
        valid.replaceFirst('"schema":1', '"schema":1.0'),
        valid.replaceFirst('"schema":1', '"schema":true'),
      ]) {
        expect(() => decode(value), throwsA(isA<UiConfigurationFailure>()));
      }
      expect(
        () => UiLaunchConfig.decode(
          Uint8List.fromList([255]),
          nativeLibraryPath: r'C:\bundle\endlessnet_windows_pipe.dll',
        ),
        throwsA(isA<UiConfigurationFailure>()),
      );
    },
  );

  test(
    'invalid authority/origin/path and out-of-budget timings cannot connect',
    () {
      for (final change in <(String, Object)>[
        ('server_sid', 'caller-supplied-admin'),
        ('instance_id', '../remote'),
        ('profile_id', '00000000-0000-0000-0000-000000000000'),
        ('control_origin', 'http://control.example'),
        ('control_origin', 'https://control.example/'),
        ('control_origin', 'https://user@control.example'),
        ('rpc_timeout_ms', 30001),
        ('connect_timeout_ms', 0),
        ('poll_interval_seconds', 31),
        ('journal_max_bytes', 100),
        ('pending_write_max_bytes', 1048577),
        ('failure_max_bytes', 65537),
      ]) {
        final config = launchValues()..[change.$1] = change.$2;
        expect(
          () => decode(jsonEncode(config)),
          throwsA(isA<UiConfigurationFailure>()),
          reason: change.$1,
        );
      }
      for (final library in [
        r'\\remote\share\endlessnet_windows_pipe.dll',
        'https://remote/endlessnet_windows_pipe.dll',
        'relative.dll',
        r'C:\bundle\other.dll',
      ]) {
        expect(
          () => decode(jsonEncode(launchValues()), library: library),
          throwsA(isA<UiConfigurationFailure>()),
        );
      }
    },
  );
}
