import 'package:endlessnet_client_api/client_api.dart' as api;

abstract interface class RecentLogsClient {
  Future<api.ListRecentLogsResponse> recentLogs(
    api.ListRecentLogsRequest request,
    Duration timeout,
  );
}
