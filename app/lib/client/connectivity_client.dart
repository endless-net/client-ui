import 'package:endlessnet_client_api/client_api.dart' as api;

// The implementation applies these deadlines to the real authenticated IPC.
// Only producer DTOs cross this boundary; UI never owns daemon lifetime.
abstract interface class ConnectivityClient {
  Future<api.RuntimeInfo> runtimeInfo(Duration timeout);
  Future<api.Status> status(Duration timeout);
  Future<void> connect(api.ConnectRequest request, Duration timeout);
  Future<void> disconnect(api.DisconnectRequest request, Duration timeout);
}
