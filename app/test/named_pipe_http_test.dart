import 'dart:convert';
import 'dart:typed_data';

import 'package:endlessnet/named_pipe_http.dart';
import 'package:endlessnet/main.dart';
import 'package:endlessnet/service_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses content-length JSON response', () {
    const body = '{"state":"Connected"}';
    final raw = Uint8List.fromList(
      ascii.encode(
        'HTTP/1.1 200 OK\r\n'
        'Content-Type: application/json\r\n'
        'Content-Length: ${body.length}\r\n'
        '\r\n'
        '$body',
      ),
    );

    final response = parseNamedPipeHttpResponse(raw);

    expect(response.statusCode, 200);
    expect(utf8.decode(response.body), body);
  });

  test('decodes chunked JSON response', () {
    const first = '{"state":';
    const second = '"Connected"}';
    final raw = Uint8List.fromList(
      ascii.encode(
        'HTTP/1.1 200 OK\r\n'
        'Transfer-Encoding: chunked\r\n'
        '\r\n'
        '${first.length.toRadixString(16)}\r\n$first\r\n'
        '${second.length.toRadixString(16)}\r\n$second\r\n'
        '0\r\n\r\n',
      ),
    );

    final response = parseNamedPipeHttpResponse(raw);

    expect(response.statusCode, 200);
    expect(utf8.decode(response.body), '$first$second');
  });

  test('reads hello then immediate status_changed from event snapshot', () {
    final hello = jsonEncode({
      'ipc_protocol': ServiceIPCMetadata.protocol,
      'ipc_version': ServiceIPCMetadata.version,
      'ipc_min_supported_version': ServiceIPCMetadata.minimumSupportedVersion,
      'ipc_negotiated_version': ServiceIPCMetadata.version,
      'event_type': 'hello',
      'sequence': 1,
    });
    final status = {
      'ipc_protocol': ServiceIPCMetadata.protocol,
      'ipc_version': ServiceIPCMetadata.version,
      'ipc_min_supported_version': ServiceIPCMetadata.minimumSupportedVersion,
      'ipc_negotiated_version': ServiceIPCMetadata.version,
      'state': ServiceState.recovering,
      'control_state': ControlState.recovering,
    };
    final changed = jsonEncode({
      'ipc_protocol': ServiceIPCMetadata.protocol,
      'ipc_version': ServiceIPCMetadata.version,
      'ipc_min_supported_version': ServiceIPCMetadata.minimumSupportedVersion,
      'ipc_negotiated_version': ServiceIPCMetadata.version,
      'event_type': 'status_changed',
      'sequence': 2,
      'status': status,
    });
    final body = '$hello\n$changed\n';
    final raw = Uint8List.fromList(
      utf8.encode(
        'HTTP/1.1 200 OK\r\n'
        'Content-Type: application/x-ndjson\r\n'
        'Content-Length: ${utf8.encode(body).length}\r\n'
        '\r\n'
        '$body',
      ),
    );

    expect(tryParseEventStatusSnapshot(raw), status);
  });

  test('event snapshot waits for a complete status line', () {
    const hello = '{"event_type":"hello"}\n';
    const partial = '{"event_type":"status_changed","status":';
    final raw = Uint8List.fromList(
      utf8.encode(
        'HTTP/1.1 200 OK\r\n'
        'Content-Type: application/x-ndjson\r\n\r\n'
        '$hello$partial',
      ),
    );

    expect(tryParseEventStatusSnapshot(raw), isNull);
  });

  test('rejects truncated response body', () {
    final raw = Uint8List.fromList(
      ascii.encode(
        'HTTP/1.1 200 OK\r\n'
        'Content-Length: 20\r\n'
        '\r\n'
        '{}',
      ),
    );

    expect(
      () => parseNamedPipeHttpResponse(raw),
      throwsA(isA<FormatException>()),
    );
  });

  test('validates negotiated IPC metadata', () {
    expect(
      () => validateIPCEnvelope({
        'ipc_protocol': ServiceIPCMetadata.protocol,
        'ipc_version': ServiceIPCMetadata.version,
        'ipc_min_supported_version': ServiceIPCMetadata.minimumSupportedVersion,
        'ipc_negotiated_version': ServiceIPCMetadata.version,
      }, requireNegotiated: true),
      returnsNormally,
    );
    expect(
      () => validateIPCEnvelope({
        'ipc_protocol': ServiceIPCMetadata.protocol,
        'ipc_version': ServiceIPCMetadata.version,
        'ipc_min_supported_version': ServiceIPCMetadata.minimumSupportedVersion,
      }, requireNegotiated: true),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => validateIPCEnvelope({
        'ipc_protocol': ServiceIPCMetadata.protocol,
        'ipc_version': 1,
        'ipc_min_supported_version': 1,
        'ipc_negotiated_version': 1,
      }, requireNegotiated: true),
      throwsA(isA<FormatException>()),
    );
  });

  test('service IPC errors retain the current contract error code', () {
    const error = ServiceIPCException(
      statusCode: 403,
      errorCode: ServiceIPCErrorCode.ownerRequired,
      message: 'device enrollment is owned by another local user',
    );

    expect(error, isA<Exception>());
    expect(error.statusCode, 403);
    expect(error.code, 'owner_required');
  });

  test('app bridge maps UI actions directly to service IPC', () async {
    final ipc = _RecordingNamedPipeHttpClient();
    final bridge = EndlessNetClientBridge(
      config: AppConfig.parse(const []),
      logger: AppLogger('', enabled: false),
      ipc: ipc,
    );

    await bridge.status();
    await bridge.connect();
    await bridge.disconnect();
    await bridge.diagnosticsBundle(logLimit: 100);
    await bridge.selectNetwork('net-1');
    await bridge.trustServer('https://api.example.test', 'key-1');
    await bridge.localForget();
    await bridge.enroll(
      EnrollmentRequest(
        token: 'join-secret',
        server: 'https://api.example.test',
        mode: 'workstation',
      ),
    );
    await bridge.enroll(
      EnrollmentRequest(token: '', server: '', mode: 'workstation'),
    );

    expect(ipc.calls, [
      const _IPCCall('GET', ServiceIPCPath.status, null),
      const _IPCCall('POST', ServiceIPCPath.connect, {}),
      const _IPCCall('POST', ServiceIPCPath.disconnect, {}),
      const _IPCCall('POST', ServiceIPCPath.diagnosticsBundle, {
        'log_limit': 100,
      }),
      const _IPCCall('POST', ServiceIPCPath.selectNetwork, {
        'network_id': 'net-1',
      }),
      const _IPCCall('POST', ServiceIPCPath.trustServer, {
        'confirmed_control_origin': 'https://api.example.test',
        'confirmed_key_id': 'key-1',
      }),
      const _IPCCall('POST', ServiceIPCPath.localForget, {'confirmed': true}),
      const _IPCCall('POST', ServiceIPCPath.enroll, {
        'enroll_token': 'join-secret',
        'server': 'https://api.example.test',
        'mode': 'workstation',
      }),
      const _IPCCall('POST', ServiceIPCPath.enroll, {'mode': 'workstation'}),
    ]);
    expect(ipc.lastRequestTimeout, const Duration(minutes: 2));
  });
}

class _RecordingNamedPipeHttpClient extends NamedPipeHttpClient {
  _RecordingNamedPipeHttpClient()
    : super(
        pipePath: r'\\.\pipe\endlessnet-test',
        timeout: const Duration(seconds: 1),
      );

  final calls = <_IPCCall>[];
  Duration? lastRequestTimeout;

  @override
  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration? requestTimeout,
  }) async {
    calls.add(_IPCCall(method, path, body));
    lastRequestTimeout = requestTimeout;
    return {'ok': true};
  }
}

class _IPCCall {
  const _IPCCall(this.method, this.path, this.body);

  final String method;
  final String path;
  final Map<String, dynamic>? body;

  @override
  bool operator ==(Object other) =>
      other is _IPCCall &&
      method == other.method &&
      path == other.path &&
      _mapsEqual(body, other.body);

  @override
  int get hashCode => Object.hash(method, path, body?.toString());
}

bool _mapsEqual(Map<String, dynamic>? a, Map<String, dynamic>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}
