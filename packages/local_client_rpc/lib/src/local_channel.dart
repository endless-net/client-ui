import 'dart:async';
import 'dart:io';

import 'package:endlessnet_client_api/client_api.dart' hide Platform;
import 'package:grpc/grpc.dart';
import 'package:http2/transport.dart';

import 'windows_pipe.dart';

/// gRPC on OS-authenticated local channels only. Never falls back to TCP/HTTP1.
class LocalClientChannel extends ClientTransportConnectorChannel {
  LocalClientChannel({String? endpoint})
    : super(
        _LocalConnector(endpoint),
        options: const ChannelOptions(
          credentials: ChannelCredentials.insecure(),
          connectTimeout: Duration(seconds: 8),
        ),
      );
}

/// Generated requests use exact producer pairing metadata, not a version range.
ClientServiceClient localServiceClient(LocalClientChannel channel) =>
    ClientServiceClient(
      channel,
      options: CallOptions(metadata: ClientContract.metadata),
    );

Future<RuntimeInfo> bootstrapLocalClient(ClientServiceClient client) async {
  final response = await client.getRuntimeInfo(
    GetRuntimeInfoRequest(),
    options: CallOptions(timeout: const Duration(seconds: 8)),
  );
  final info = response.runtime;
  if (info.protocol != ClientContract.protocol ||
      info.ipcVersion != ClientContract.version ||
      info.contractSha256 != ClientContract.sha256 ||
      info.instanceId.isEmpty) {
    throw const GrpcError.failedPrecondition('ERROR_CODE_CONTRACT_MISMATCH');
  }
  return info;
}

String validateLocalEndpoint(String? requested, {String? operatingSystem}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  if (os == 'windows') {
    final endpoint = requested ?? r'\\.\pipe\endlessnet-service';
    if (!endpoint.startsWith(r'\\.\pipe\') ||
        endpoint.length <= 9 ||
        endpoint.contains('\u0000')) {
      throw ArgumentError('IPC requires a local Windows pipe');
    }
    return endpoint;
  }
  if (os == 'linux' || os == 'macos') {
    final endpoint =
        requested ??
        (os == 'macos'
            ? '/var/run/endlessnet/client.sock'
            : '/run/endlessnet/client.sock');
    if (!endpoint.startsWith('/') || endpoint.contains('\u0000')) {
      throw ArgumentError('IPC requires an absolute Unix socket path');
    }
    return endpoint;
  }
  throw UnsupportedError('This platform requires an authorized native bridge');
}

class _LocalConnector implements ClientTransportConnector {
  _LocalConnector(String? endpoint)
    : endpoint = validateLocalEndpoint(endpoint);

  final String endpoint;
  Socket? _socket;
  WindowsPipe? _pipe;
  Future<void> _done = Future<void>.value();
  int _generation = 0;

  @override
  String get authority => 'endlessnet.local';

  @override
  Future<void> get done => _done;

  @override
  Future<ClientTransportConnection> connect() async {
    final generation = ++_generation;
    if (Platform.isWindows) {
      final pipe = await WindowsPipe.connect(endpoint);
      if (generation != _generation) {
        await pipe.close();
        throw const GrpcError.unavailable(
          'Local channel closed during connect',
        );
      }
      _pipe = pipe;
      _done = pipe.done;
      return ClientTransportConnection.viaStreams(pipe.incoming, pipe.outgoing);
    }
    final socket = await Socket.connect(
      InternetAddress(endpoint, type: InternetAddressType.unix),
      0,
      timeout: const Duration(seconds: 8),
    );
    if (generation != _generation) {
      socket.destroy();
      throw const GrpcError.unavailable('Local channel closed during connect');
    }
    _socket = socket;
    _done = socket.done.then<void>((_) {}, onError: (Object _) {});
    return ClientTransportConnection.viaSocket(socket);
  }

  @override
  void shutdown() {
    _generation++;
    _socket?.destroy();
    _socket = null;
    final pipe = _pipe;
    _pipe = null;
    if (pipe != null) unawaited(pipe.close());
  }
}
