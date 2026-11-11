import 'dart:convert';
import 'dart:typed_data';

import 'package:endlessnet_client_api/client_api.dart' as api;

import '../client/contract_identity.dart';
import '../client/windows_pipe_config.dart';

enum UiConfigurationProblem {
  invalid,
  missing,
  untrusted,
  busy,
  componentUnavailable,
  unsupportedPlatform,
}

final class UiConfigurationFailure implements Exception {
  const UiConfigurationFailure([this.problem = UiConfigurationProblem.invalid]);
  final UiConfigurationProblem problem;
  @override
  String toString() => 'UiConfigurationFailure';
}

// UI-owned launch configuration, not a Client discovery API. A trusted reader
// must verify its file authority before calling decode. No production defaults.
final class UiLaunchConfig {
  UiLaunchConfig._(
    this.pipe,
    this._profile,
    this.rpcTimeout,
    this.pollInterval,
    this.journalMaxBytes,
    this.failureMaxBytes,
  );
  final WindowsPipeConfig pipe;
  final api.Profile _profile;
  api.Profile get profile => api.Profile.fromBuffer(_profile.writeToBuffer());
  final Duration rpcTimeout;
  final Duration pollInterval;
  final int journalMaxBytes;
  final int failureMaxBytes;
  String get contractSha256 => clientContractSha256;

  static const keys = {
    'schema',
    'instance_id',
    'server_sid',
    'profile_id',
    'control_origin',
    'connect_timeout_ms',
    'write_timeout_ms',
    'rpc_timeout_ms',
    'poll_interval_seconds',
    'journal_max_bytes',
    'pending_write_max_bytes',
    'failure_max_bytes',
  };

  static UiLaunchConfig decode(
    Uint8List bytes, {
    required String nativeLibraryPath,
    String? runtimeInstance,
  }) {
    try {
      if (bytes.isEmpty || bytes.length > 65536) {
        throw const UiConfigurationFailure();
      }
      final map = _FlatJson(utf8.decode(bytes)).read();
      final expected = runtimeInstance == null
          ? keys
          : keys.difference({'instance_id'});
      if (map.length != expected.length ||
          !map.keys.toSet().containsAll(expected) ||
          map['schema'] != 1 ||
          map['schema'] is! int) {
        throw const UiConfigurationFailure();
      }
      String text(String name) {
        final value = map[name];
        if (value is! String || value.isEmpty) {
          throw const UiConfigurationFailure();
        }
        return value;
      }

      int number(String name, int min, int max) {
        final value = map[name];
        if (value is! int || value < min || value > max) {
          throw const UiConfigurationFailure();
        }
        return value;
      }

      final originText = text('control_origin');
      final origin = Uri.tryParse(originText);
      final id = text('profile_id');
      if (origin == null ||
          origin.scheme != 'https' ||
          origin.userInfo.isNotEmpty ||
          origin.hasQuery ||
          origin.hasFragment ||
          origin.origin != originText ||
          !RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
          ).hasMatch(id) ||
          id == '00000000-0000-0000-0000-000000000000') {
        throw const UiConfigurationFailure();
      }
      return UiLaunchConfig._(
        WindowsPipeConfig(
          instanceId: runtimeInstance ?? text('instance_id'),
          serverSid: text('server_sid'),
          nativeLibraryPath: nativeLibraryPath,
          connectTimeout: Duration(
            milliseconds: number('connect_timeout_ms', 1, 30000),
          ),
          writeTimeout: Duration(
            milliseconds: number('write_timeout_ms', 1, 30000),
          ),
          maxPendingWriteBytes: number(
            'pending_write_max_bytes',
            1,
            1024 * 1024,
          ),
        ),
        api.Profile(id: id, controlOrigin: originText),
        Duration(milliseconds: number('rpc_timeout_ms', 1, 30000)),
        Duration(seconds: number('poll_interval_seconds', 1, 30)),
        number('journal_max_bytes', 8192, 16 * 1024 * 1024),
        number('failure_max_bytes', 1, 65536),
      );
    } catch (_) {
      throw const UiConfigurationFailure();
    }
  }
}

// Strict flat scalar JSON. Reuse dart:convert for each string/scalar token, but
// track decoded property names before map insertion to reject duplicate keys,
// including escaped spellings. Nested objects/arrays are outside this config.
final class _FlatJson {
  _FlatJson(this.text);
  final String text;
  int pos = 0;
  Never bad() => throw const UiConfigurationFailure();
  void ws() {
    while (pos < text.length &&
        const [' ', '\t', '\r', '\n'].contains(text[pos])) {
      pos++;
    }
  }

  void take(String char) {
    ws();
    if (pos >= text.length || text[pos++] != char) bad();
  }

  String quoted() {
    ws();
    final start = pos;
    take('"');
    while (pos < text.length) {
      final char = text[pos++];
      if (char == '\\') {
        pos++;
      } else if (char == '"') {
        return jsonDecode(text.substring(start, pos)) as String;
      }
    }
    return bad();
  }

  Map<String, Object?> read() {
    final values = <String, Object?>{};
    take('{');
    ws();
    if (pos < text.length && text[pos] == '}') {
      pos++;
    } else {
      while (true) {
        final key = quoted();
        if (values.containsKey(key)) bad();
        take(':');
        ws();
        Object? value;
        if (pos < text.length && text[pos] == '"') {
          value = quoted();
        } else {
          final start = pos;
          while (pos < text.length && text[pos] != ',' && text[pos] != '}') {
            pos++;
          }
          value = jsonDecode(text.substring(start, pos));
          if (value is Map || value is List) bad();
        }
        values[key] = value;
        ws();
        if (pos >= text.length) bad();
        if (text[pos] == '}') {
          pos++;
          break;
        }
        take(',');
      }
    }
    ws();
    if (pos != text.length) bad();
    return values;
  }
}
