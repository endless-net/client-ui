import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:grpc/grpc.dart' as grpc;
import 'package:http2/transport.dart';

import 'grpc_enrollment_client.dart';
import 'windows_pipe_config.dart';
import 'windows_pipe_native.dart';

// Each connector opens one verified local pipe. Reconnect requires a new trusted
// discovery/config step; gRPC cannot silently reconnect this endpoint.
final class WindowsPipeConnector implements grpc.ClientTransportConnector {
  WindowsPipeConnector(this.config);
  final WindowsPipeConfig config;
  _Pipe? _pipe;
  bool _attempted = false;
  bool _shutdown = false;
  WindowsPipeFailure? _failure;
  WindowsPipeFailure? get failure => _failure ?? _pipe?._failure;
  final _done = Completer<void>();
  @override
  String get authority => 'endlessnet.local';
  @override
  Future<void> get done => _done.future;
  @override
  Future<ClientTransportConnection> connect() async {
    if (_attempted || _shutdown) {
      throw const WindowsPipeFailure(WindowsPipeProblem.closed);
    }
    _attempted = true;
    try {
      final pipe = await _Pipe.open(config);
      _pipe = pipe;
      unawaited(
        pipe.done.then((_) {
          if (!_done.isCompleted) _done.complete();
        }),
      );
      if (_shutdown) {
        pipe.stop();
        throw const WindowsPipeFailure(WindowsPipeProblem.closed);
      }
      return ClientTransportConnection.viaStreams(pipe.incoming(), pipe.output);
    } catch (error) {
      if (error is WindowsPipeFailure) _failure = error;
      if (!_done.isCompleted) _done.complete();
      rethrow;
    }
  }

  @override
  void shutdown() {
    _shutdown = true;
    _pipe?.stop();
    if (!_attempted && !_done.isCompleted) _done.complete();
  }
}

final class WindowsEnrollmentConnection {
  WindowsEnrollmentConnection._(this.client, this._channel, this._connector);
  final GrpcEnrollmentClient client;
  final grpc.ClientTransportConnectorChannel _channel;
  final WindowsPipeConnector _connector;
  Future<void> close() async {
    _connector.shutdown();
    await _channel.terminate();
    await _connector.done;
  }
}

Future<WindowsEnrollmentConnection> connectWindowsEnrollment({
  required WindowsPipeConfig config,
  required String expectedContractSha256,
  required int maxFailureBytes,
}) async {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedContractSha256) ||
      expectedContractSha256 == '0' * 64) {
    throw const WindowsPipeFailure(WindowsPipeProblem.configuration);
  }
  final connector = WindowsPipeConnector(config);
  final channel = grpc.ClientTransportConnectorChannel(
    connector,
    options: const grpc.ChannelOptions(
      credentials: grpc.ChannelCredentials.insecure(),
    ),
  );
  try {
    final client = GrpcEnrollmentClient(
      api.ClientServiceClient(channel),
      maxFailureBytes: maxFailureBytes,
    );
    final runtime = await client.runtimeInfo(config.connectTimeout);
    if (runtime.instanceId != config.instanceId ||
        runtime.contractSha256 != expectedContractSha256 ||
        runtime.protocol != 'endlessnet-client-ipc' ||
        runtime.ipcVersion != 0) {
      throw const WindowsPipeFailure(WindowsPipeProblem.authentication);
    }
    return WindowsEnrollmentConnection._(client, channel, connector);
  } catch (_) {
    connector.shutdown();
    await channel.terminate();
    await connector.done;
    if (connector.failure != null) throw connector.failure!;
    rethrow;
  }
}

final class _Pipe {
  _Pipe(this.config) {
    output = _Output(this);
  }
  final WindowsPipeConfig config;
  late final _Output output;
  final _messages = ReceivePort();
  final _exits = ReceivePort();
  final _errors = ReceivePort();
  final _ready = Completer<void>();
  final _done = Completer<void>();
  final _queue = Queue<Uint8List>();
  SendPort? _commands;
  Completer<Uint8List?>? _read;
  WindowsPipeFailure? _failure;
  int _pendingBytes = 0;
  bool _writing = false;
  bool _stopping = false;
  bool _closed = false;
  bool _outputClosed = false;
  Future<void> get done => _done.future;

  static Future<_Pipe> open(WindowsPipeConfig config) async {
    if (!Platform.isWindows || Abi.current() != Abi.windowsX64) {
      throw const WindowsPipeFailure(WindowsPipeProblem.configuration);
    }
    final pipe = _Pipe(config);
    pipe._messages.listen(pipe._message);
    pipe._exits.listen((_) {
      pipe._finish();
    });
    pipe._errors.listen((_) {
      pipe._fail(WindowsPipeProblem.io);
    });
    var spawned = false;
    // Observe bootstrap errors even if spawning itself fails first.
    unawaited(
      pipe._ready.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    try {
      await Isolate.spawn(
        windowsPipeWorker,
        (pipe._messages.sendPort, config),
        onExit: pipe._exits.sendPort,
        onError: pipe._errors.sendPort,
      );
      spawned = true;
      await pipe._ready.future.timeout(config.connectTimeout);
      return pipe;
    } catch (_) {
      if (!spawned) pipe._finish();
      pipe.stop();
      // Worker cancels/drains I/O before exit; never kill an isolate with live
      // native OVERLAPPED buffers. An open failure has no outstanding I/O.
      await pipe.done;
      rethrow;
    }
  }

  void _message(dynamic event) {
    if (_closed || event is! List || event.isEmpty) return;
    switch (event[0]) {
      case 'control':
        _commands = event[1] as SendPort;
        if (_stopping) _commands!.send('stop');
      case 'ready':
        if (!_ready.isCompleted) _ready.complete();
      case 'data':
        final read = _read;
        _read = null;
        if (read == null) {
          _fail(WindowsPipeProblem.io);
          return;
        }
        read.complete(
          (event[1] as TransferableTypedData).materialize().asUint8List(),
        );
      case 'written':
        if (!_writing || _queue.isEmpty) {
          _fail(WindowsPipeProblem.io);
          return;
        }
        _pendingBytes -= _queue.removeFirst().length;
        _writing = false;
        _drain();
      case 'failure':
        _fail(WindowsPipeProblem.values[event[1] as int]);
      case 'closed':
        _finish();
    }
  }

  void _fail(WindowsPipeProblem problem) {
    _failure ??= WindowsPipeFailure(problem);
    if (!_ready.isCompleted) _ready.completeError(_failure!);
    final read = _read;
    _read = null;
    read?.completeError(_failure!);
    stop();
  }

  void stop() {
    if (_closed || _stopping) return;
    _stopping = true;
    _commands?.send('stop');
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    if (!_ready.isCompleted) {
      _ready.completeError(
        _failure ?? const WindowsPipeFailure(WindowsPipeProblem.closed),
      );
    }
    final read = _read;
    _read = null;
    if (_failure == null) {
      read?.complete(null);
    } else {
      read?.completeError(_failure!);
    }
    _queue.clear();
    _messages.close();
    _exits.close();
    _errors.close();
    _done.complete();
  }

  Stream<List<int>> incoming() async* {
    while (!_closed && !_stopping) {
      if (_failure != null) throw _failure!;
      final read = Completer<Uint8List?>();
      _read = read;
      _commands!.send('read');
      final bytes = await read.future;
      if (bytes == null) break;
      // async* suspends on pause: at most one native read/chunk is in flight.
      yield bytes;
    }
  }

  void _add(List<int> bytes) {
    if (_closed || _stopping || _outputClosed) return;
    if (bytes.isEmpty) return;
    if (bytes.length > config.maxPendingWriteBytes - _pendingBytes) {
      _fail(WindowsPipeProblem.capacity);
      return;
    }
    _pendingBytes += bytes.length;
    _queue.add(Uint8List.fromList(bytes));
    _drain();
  }

  void _drain() {
    if (_closed || _stopping || _writing) return;
    if (_queue.isEmpty) {
      if (_outputClosed) stop();
      return;
    }
    _writing = true;
    _commands!.send(TransferableTypedData.fromList([_queue.first]));
  }
}

final class _Output implements StreamSink<List<int>> {
  _Output(this.pipe);
  final _Pipe pipe;
  @override
  void add(List<int> bytes) => pipe._add(bytes);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      pipe._fail(WindowsPipeProblem.io);
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final bytes in stream) {
      if (pipe._closed || pipe._stopping) break;
      add(bytes);
    }
  }

  @override
  Future<void> close() {
    pipe._outputClosed = true;
    pipe._drain();
    return done;
  }

  @override
  Future<void> get done => pipe.done;
}
