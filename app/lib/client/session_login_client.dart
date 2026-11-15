import 'package:endlessnet_client_api/client_api.dart' as api;

abstract interface class SessionLoginClient {
  Future<api.RuntimeInfo> runtimeInfo(Duration timeout);
  Future<api.Status> status(Duration timeout);
  Future<api.GetSessionResponse> session(
    api.GetSessionRequest request,
    Duration timeout,
  );
  Future<api.SessionLoginAttempt> startSessionLogin(
    api.StartSessionLoginRequest request,
    Duration timeout,
  );
  Future<api.SessionLoginAttempt> sessionLogin(
    api.GetSessionLoginRequest request,
    Duration timeout,
  );
}
