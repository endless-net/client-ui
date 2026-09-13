import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:endlessnet_client_api/client_api.dart' show ClientContract;

/// Process harness for synthetic producer scripts, not a daemon replacement.
final class ScenarioHost {
  ScenarioHost._(this._directory, this._process, this._output, this.endpoint);

  final Directory _directory;
  final Process _process;
  final StreamIterator<String> _output;
  final String endpoint;
  final List<String> _protocolDiagnostics = [];
  Future<void>? _stderrDone;
  static const _timeout = Duration(seconds: 10);

  static Future<ScenarioHost> start(
    String executable,
    List<Object> steps, {
    bool administrator = false,
  }) async {
    // Short Unix path is required by sockaddr_un on macOS runners.
    final directory =
        await (Platform.isWindows ? Directory.systemTemp : Directory('/tmp'))
            .createTemp('en-ui-');
    final endpoint = Platform.isWindows
        ? r'\\.\pipe\en-ui-' + DateTime.now().microsecondsSinceEpoch.toString()
        : '${directory.path}/rpc.sock';
    final script = File('${directory.path}/scenario.json');
    Process? process;
    ScenarioHost? host;
    try {
      await script.writeAsString(jsonEncode({'steps': steps}));
      process = await Process.start(
        executable,
        [
          '--script',
          script.path,
          '--endpoint',
          endpoint,
          '--access',
          administrator ? 'administrator' : 'owner',
        ],
        environment: {
          // This child runs synthetic scripts only. Capture transport termination
          // reasons because grpc-dart's public error omits GOAWAY debug data.
          'GRPC_GO_LOG_SEVERITY_LEVEL': 'info',
          'GRPC_GO_LOG_VERBOSITY_LEVEL': '2',
          'GODEBUG': 'http2debug=2',
        },
      );
      host = ScenarioHost._(
        directory,
        process,
        StreamIterator<String>(
          process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter()),
        ),
        endpoint,
      );
      final diagnostics = host._protocolDiagnostics;
      host._stderrDone = process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
            // Never retain request/response/header dumps, even for fixtures.
            if (!line.contains('GOAWAY')) return;
            if (diagnostics.length == 8) diagnostics.removeAt(0);
            diagnostics.add(
              line.length > 1024 ? line.substring(0, 1024) : line,
            );
          });
      final ready = await host._event();
      if (ready['event'] != 'ready' ||
          ready['contract_sha256'] != ClientContract.sha256) {
        throw StateError('Testserver pairing/readiness failed');
      }
      return host;
    } catch (_) {
      if (host != null) {
        await host.close();
      } else {
        process?.kill();
        if (process != null) await process.exitCode.timeout(_timeout);
        if (await script.exists()) await script.delete();
        await directory.delete();
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _event() async {
    if (!await _output.moveNext().timeout(_timeout)) {
      throw StateError('Testserver ended without expected event');
    }
    return jsonDecode(_output.current) as Map<String, dynamic>;
  }

  Future<void> verify() async {
    _process.stdin.writeln('verify');
    await _process.stdin.flush();
    if ((await _event())['event'] != 'verified' ||
        await _process.exitCode.timeout(_timeout) != 0) {
      throw StateError('Testserver script verification failed');
    }
  }

  Future<void> close() async {
    _process.kill();
    await _process.exitCode.timeout(_timeout);
    await _stderrDone?.timeout(_timeout);
    for (final diagnostic in _protocolDiagnostics) {
      // ignore: avoid_print
      print('Synthetic testserver transport: $diagnostic');
    }
    await _output.cancel();
    // Only our unique test directory; a killed Unix host may leave its socket.
    await _directory.delete(recursive: true);
  }
}
