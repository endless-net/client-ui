import 'dart:collection';
import 'dart:convert';

import 'recovery_log.dart';

typedef Json = Map<String, Object?>;
typedef InvokeTool = Future<Json> Function(String name, Json arguments);

const _tools = {
  'app_status': 'Read the current state of the open EndlessNet app.',
  'logs_read':
      'Read recent UI diagnostics or the saved local recovery history.',
  'client_logs_read':
      'Read recent redacted logs from the local Client service.',
  'connectivity_refresh': 'Refresh status through the app’s local Client API.',
  'connectivity_connect': 'Request Connect through the open app.',
  'connectivity_disconnect': 'Request Disconnect through the open app.',
};

const _logArguments = {
  'after': {'type': 'integer', 'minimum': 0},
  'limit': {'type': 'integer', 'minimum': 1, 'maximum': 100},
  'source': {
    'type': 'string',
    'enum': ['recovery'],
  },
};

const _clientLogArguments = {
  'pageToken': {'type': 'string', 'maxLength': 512},
  'limit': {'type': 'integer', 'minimum': 1, 'maximum': 100},
};

final class UiDiagnostics {
  final recovery = RecoveryLog();
  final _entries = ListQueue<Json>();
  int _sequence = 0;

  List<Json> snapshot() =>
      [..._entries, ...recovery.snapshot()]
        ..sort((a, b) => (a['time'] as String).compareTo(b['time'] as String));

  void record(String component, String event, [Json? state]) {
    if (_entries.length == 256) _entries.removeFirst();
    _entries.add({
      'sequence': ++_sequence,
      'time': DateTime.now().toUtc().toIso8601String(),
      'component': component,
      'event': event,
      'state': ?state,
    });
  }

  Json read(Json arguments) {
    final after = arguments['after'] as int? ?? 0;
    final limit = arguments['limit'] as int? ?? 50;
    if (arguments['source'] == 'recovery') return recovery.read(after, limit);
    final entries = _entries
        .where((entry) => (entry['sequence'] as int) > after)
        .take(limit)
        .toList(growable: false);
    final next = entries.isEmpty ? after : entries.last['sequence'] as int;
    return {
      'entries': entries,
      'nextCursor': next,
      'hasMore': next < _sequence,
      'historyGap':
          _entries.isNotEmpty &&
          after < (_entries.first['sequence'] as int) - 1,
      'cursorAhead': after > _sequence,
    };
  }
}

/// One JSON-RPC lifecycle per authorized pipe. Authorization is owned by
/// the Windows transport, while tool readiness is owned by the live UI.
final class UiMcpSession {
  UiMcpSession(this.invoke);
  final InvokeTool invoke;
  bool _initialized = false;
  bool _ready = false;
  final _pending = <Object>{};

  Future<Json?> handle(Json request) async {
    final id = request['id'];
    final method = request['method'];
    final params = request['params'];
    Json error(int code, String message, {Object? errorId}) => {
      'jsonrpc': '2.0',
      'id': errorId,
      'error': {'code': code, 'message': message},
    };
    Json result(Json value) => {'jsonrpc': '2.0', 'id': id, 'result': value};
    Json fail(int code, String message) => error(code, message, errorId: id);

    if (request['jsonrpc'] != '2.0' ||
        method is! String ||
        (request.containsKey('id') && id is! String && id is! int)) {
      return error(-32600, 'Invalid Request');
    }
    if (id == null) {
      if (_initialized && method == 'notifications/initialized') _ready = true;
      return null;
    }
    if (params != null && params is! Json) {
      return fail(-32602, 'Invalid params');
    }

    switch (method) {
      case 'initialize':
        if (_initialized ||
            params is! Json ||
            params['protocolVersion'] is! String ||
            params['capabilities'] is! Json ||
            params['clientInfo'] is! Json) {
          return fail(-32602, 'Invalid initialization');
        }
        _initialized = true;
        return result({
          'protocolVersion': '2025-11-25',
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'endlessnet-client-ui', 'version': '0.1.0'},
        });
      case 'ping':
        return result({});
    }
    if (!_ready) return fail(-32002, 'MCP session is not initialized');
    switch (method) {
      case 'tools/list':
        return result({
          'tools': [
            for (final entry in _tools.entries)
              {
                'name': entry.key,
                'description': entry.value,
                'inputSchema': {
                  'type': 'object',
                  'properties': switch (entry.key) {
                    'logs_read' => _logArguments,
                    'client_logs_read' => _clientLogArguments,
                    _ => {},
                  },
                  'additionalProperties': false,
                },
                'annotations': {
                  'readOnlyHint': !_isMutation(entry.key),
                  'openWorldHint': false,
                },
              },
          ],
        });
      case 'tools/call':
        final values = params is Json ? params : const <String, Object?>{};
        final name = values['name'];
        final arguments = values['arguments'] ?? const <String, Object?>{};
        if (name is! String ||
            !_tools.containsKey(name) ||
            arguments is! Json ||
            !_validArguments(name, arguments)) {
          return fail(-32602, 'Unknown tool or invalid arguments');
        }
        if (_pending.contains(id)) return fail(-32600, 'Duplicate request ID');
        if (_pending.length >= 8) return fail(-32000, 'MCP session is busy');
        _pending.add(id);
        try {
          final value = await invoke(name, arguments);
          return result({
            'content': [
              {'type': 'text', 'text': jsonEncode(value)},
            ],
            'structuredContent': value,
            if (value.containsKey('error')) 'isError': true,
          });
        } catch (_) {
          return fail(-32603, 'App operation failed');
        } finally {
          _pending.remove(id);
        }
      default:
        return fail(-32601, 'Method not found');
    }
  }

  static bool _isMutation(String name) =>
      name == 'connectivity_connect' || name == 'connectivity_disconnect';

  static bool _validArguments(String name, Json arguments) {
    if (name != 'logs_read' && name != 'client_logs_read') {
      return arguments.isEmpty;
    }
    return arguments.entries.every(
      (entry) => switch ((entry.key, entry.value)) {
        ('after', final int number) => name == 'logs_read' && number >= 0,
        ('pageToken', final String token) =>
          name == 'client_logs_read' && token.length <= 512,
        ('source', 'recovery') => name == 'logs_read',
        ('limit', final int number) => number >= 1 && number <= 100,
        _ => false,
      },
    );
  }
}
