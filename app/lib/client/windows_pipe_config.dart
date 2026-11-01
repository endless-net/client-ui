enum WindowsPipeProblem {
  configuration,
  authentication,
  unavailable,
  io,
  timeout,
  capacity,
  closed,
}

final class WindowsPipeFailure implements Exception {
  const WindowsPipeFailure(this.problem);
  final WindowsPipeProblem problem;
  @override
  String toString() => 'WindowsPipeFailure(${problem.name})';
}

// All values originate from trusted installation/discovery config, never a URL,
// RPC response or CLI argument supplied by an unauthenticated remote peer.
final class WindowsPipeConfig {
  WindowsPipeConfig({
    required this.instanceId,
    required this.serverSid,
    required this.nativeLibraryPath,
    required this.connectTimeout,
    required this.writeTimeout,
    required this.maxPendingWriteBytes,
  }) {
    if (!isWindowsPipeLibraryPath(nativeLibraryPath) ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(instanceId) ||
        instanceId == '00000000-0000-0000-0000-000000000000' ||
        !RegExp(r'^S-1-(0|[1-9][0-9]*)(-(0|[1-9][0-9]*)){1,15}$')
            .hasMatch(serverSid) ||
        serverSid.length > 184 ||
        connectTimeout <= Duration.zero ||
        connectTimeout > const Duration(seconds: 30) ||
        writeTimeout <= Duration.zero ||
        writeTimeout > const Duration(seconds: 30) ||
        maxPendingWriteBytes < 1 ||
        maxPendingWriteBytes > 1024 * 1024) {
      throw const WindowsPipeFailure(WindowsPipeProblem.configuration);
    }
  }
  final String instanceId;
  final String serverSid;
  final String nativeLibraryPath;
  final Duration connectTimeout;
  final Duration writeTimeout;
  final int maxPendingWriteBytes;
  String get path => r'\\.\pipe\endlessnet-client-' + instanceId;
}

bool isWindowsPipeLibraryPath(String path) {
  try {
    final library = Uri.file(path, windows: true);
    return !path.contains('\u0000') &&
        library.isAbsolute &&
        library.host.isEmpty &&
        RegExp(r'^[A-Za-z]:/')
            .hasMatch(path.replaceAll(String.fromCharCode(92), '/')) &&
        library.path.endsWith('/endlessnet_windows_pipe.dll');
  } catch (_) {
    return false;
  }
}
