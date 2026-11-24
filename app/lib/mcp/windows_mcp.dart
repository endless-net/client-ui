import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'protocol.dart';

final class WindowsMcp extends ChangeNotifier {
  WindowsMcp(this.invoke);

  final Future<Json> Function(String, Json, bool Function()) invoke;

  late final DynamicLibrary _dll = DynamicLibrary.open(
    File(Platform.resolvedExecutable).parent.uri
        .resolve('endlessnet_windows_pipe.dll')
        .toFilePath(),
  );
  late final _enable = _dll
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'en_mcp_enable',
      );
  late final _restore = _dll
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'en_mcp_restore',
      );
  late final _disable = _dll.lookupFunction<Int Function(), int Function()>(
    'en_mcp_disable',
  );
  late final _stop = _dll.lookupFunction<Void Function(), void Function()>(
    'en_mcp_stop',
  );
  late final _active = _dll.lookupFunction<Int Function(), int Function()>(
    'en_mcp_active',
  );
  late final _readEvents = _dll
      .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
        'en_mcp_events',
      );
  late final _sendFrame = _dll
      .lookupFunction<
        Void Function(Pointer<Utf8>, Pointer<Utf8>),
        void Function(Pointer<Utf8>, Pointer<Utf8>)
      >('en_mcp_send');

  final _sessions = <String, UiMcpSession>{};
  Timer? _timer;
  String? clientId;
  bool unavailable = false;
  bool revokeFailed = false;

  String get configuration => const JsonEncoder.withIndent('  ').convert({
    'mcpServers': {
      'endlessnet-client-ui': {
        'command': Platform.resolvedExecutable,
        'args': ['--mcp-stdio', '--client', clientId],
      },
    },
  });

  void restore() => _open(() => _restore());

  void enable() => _open(() => _enable());

  void _open(Pointer<Utf8> Function() open) {
    _clearSessions();
    unavailable = false;
    revokeFailed = false;
    try {
      _active();
      final id = open();
      if (id == nullptr) throw StateError('MCP is unavailable');
      final value = id.toDartString();
      if (value.isNotEmpty) {
        clientId = value;
        _timer = Timer.periodic(
          const Duration(milliseconds: 40),
          (_) => _poll(),
        );
      }
    } catch (_) {
      unavailable = true;
    }
    notifyListeners();
  }

  void disable() {
    try {
      if (_disable() == 0) throw StateError('MCP revoke failed');
      _clearSessions();
      unavailable = false;
      revokeFailed = false;
    } catch (_) {
      revokeFailed = true;
    }
    notifyListeners();
  }

  void stop() {
    if (clientId != null) _stop();
    _clearSessions();
  }

  void _clearSessions() {
    _timer?.cancel();
    _timer = null;
    _sessions.clear();
    clientId = null;
  }

  void _poll() {
    final events = _readEvents();
    if (events == nullptr) {
      stop();
      unavailable = true;
      notifyListeners();
      return;
    }
    for (final event
        in (jsonDecode(events.toDartString()) as List).cast<Json>()) {
      final channel = event['channel'] as String;
      final payload = event['payload'];
      if (payload is! Json) {
        _sessions.remove(channel);
        continue;
      }
      final session = _sessions.putIfAbsent(channel, () {
        bool active() =>
            _sessions.containsKey(channel) &&
            clientId != null &&
            _active() != 0;
        return UiMcpSession((name, args) => invoke(name, args, active));
      });
      unawaited(_respond(channel, session, payload));
    }
  }

  Future<void> _respond(
    String channel,
    UiMcpSession session,
    Json payload,
  ) async {
    final response = await session.handle(payload);
    if (response == null || _sessions[channel] != session || _active() == 0) {
      return;
    }
    using((arena) {
      _sendFrame(
        channel.toNativeUtf8(allocator: arena),
        jsonEncode({'kind': 'mcp', 'payload': response})
            .toNativeUtf8(allocator: arena),
      );
    });
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
