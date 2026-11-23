import 'package:endlessnet_client_api/client_api.dart' as api;

abstract interface class DashboardClient {
  Future<api.ListDashboardSpacesResponse> dashboardSpaces(
    api.ListDashboardSpacesRequest request,
    Duration timeout,
  );

  Future<api.DashboardBoard> dashboardBoard(
    api.GetDashboardBoardRequest request,
    Duration timeout,
  );

  Future<api.DashboardBoard> replaceDashboardBoard(
    api.ReplaceDashboardBoardRequest request,
    Duration timeout,
  );
}
