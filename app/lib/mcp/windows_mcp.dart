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
  late final _disable = _dll.lookupFunction<Void Function(), void Function()>(
    'en_mcp_disable',
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

  String get configuration => const JsonEncoder.withIndent('  ').convert({
    'mcpServers': {
      'endlessnet-client-ui': {
        'command': Platform.resolvedExecutable,
        'args': ['--mcp-stdio', '--client', clientId],
      },
    },
  });

  void enable() {
    disable(notify: false);
    try {
      // Resolve the whole interface before opening the transport.
      final close = _disable;
      _active();
      _readEvents();
      final id = _enable();
      if (id == nullptr) {
        close();
        throw StateError('MCP is unavailable');
      }
      clientId = id.toDartString();
      unavailable = false;
      _timer = Timer.periodic(const Duration(milliseconds: 40), (_) => _poll());
    } catch (_) {
      unavailable = true;
    }
    notifyListeners();
  }

  void disable({bool notify = true}) {
    _timer?.cancel();
    _timer = null;
    _sessions.clear();
    if (clientId != null) _disable();
    clientId = null;
    unavailable = false;
    if (notify) notifyListeners();
  }

  void _poll() {
    final events = _readEvents();
    if (events == nullptr) {
      disable(notify: false);
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
    disable(notify: false);
    super.dispose();
  }
}
