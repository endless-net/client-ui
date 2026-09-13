import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_local_client_rpc/local_client_rpc.dart';

import 'client_event_stream.dart';
import 'client_mutations.dart';
import 'client_profiles.dart';
import 'client_networks.dart';
import 'client_preferences.dart';
import 'client_resources.dart';
import 'client_exit_nodes.dart';

/// Production local transport binding for the typed event consumer. The shell
/// must clear domain caches on disconnect and start a fresh subscription.
final class LocalClientEvents {
  LocalClientEvents._(this._channel, this._client, this.runtime);

  final LocalClientChannel _channel;
  final api.ClientServiceClient _client;
  final api.RuntimeInfo runtime;
  bool _closed = false;

  Future<api.ListRecentLogsResponse> listRecentLogs(
    api.ListRecentLogsRequest request,
  ) {
    if (_closed) throw StateError('Local client is closed');
    return _client.listRecentLogs(request);
  }

  Future<api.GetSupportInfoResponse> getSupportInfo(
    api.GetSupportInfoRequest request,
  ) {
    if (_closed) throw StateError('Local client is closed');
    return _client.getSupportInfo(request);
  }

  Future<api.GetUpdateInfoResponse> getUpdateInfo(
    api.GetUpdateInfoRequest request,
  ) {
    if (_closed) throw StateError('Local client is closed');
    return _client.getUpdateInfo(request);
  }

  Future<ClientExitNodes> getExitNodes(
    String profileId,
    void Function() check,
  ) => readClientExitNodes(
    instanceId: runtime.instanceId,
    profileId: profileId,
    list: _client.listExitNodes,
    get: _client.getExitNode,
    checkContext: () {
      if (_closed) throw StateError('Local client is closed');
      check();
    },
  );

  Future<ClientResourceCatalog> listResources(
    String profileId,
    String search,
    List<api.ResourceKind> kinds,
    void Function() checkContext,
  ) => readClientResources(
    _client.listResources,
    instanceId: runtime.instanceId,
    profileId: profileId,
    search: search,
    kinds: kinds,
    checkContext: () {
      if (_closed) throw StateError('Local client is closed');
      checkContext();
    },
  );

  Future<ClientPreferences> getPreferences(
    String profileId,
    void Function() checkContext,
  ) => readClientPreferences(
    instanceId: runtime.instanceId,
    profileId: profileId,
    get: _client.getPreferences,
    listManaged: _client.listManagedSettings,
    checkContext: () {
      if (_closed) throw StateError('Local client is closed');
      checkContext();
    },
  );

  Future<api.ReadDiagnosticsBundleResponse> readDiagnosticsBundle(
    api.ReadDiagnosticsBundleRequest request,
  ) {
    if (_closed) throw StateError('Local client is closed');
    return _client.readDiagnosticsBundle(request);
  }

  Future<api.GetDiagnosticsResponse> getDiagnostics(String profileId) {
    if (_closed) throw StateError('Local client is closed');
    return _client.getDiagnostics(
      api.GetDiagnosticsRequest(profile: api.ProfileRef(profileId: profileId)),
    );
  }

  Future<api.GetServerIdentityResponse> getServerIdentity(String profileId) {
    if (_closed) throw StateError('Local client is closed');
    return _client.getServerIdentity(
      api.GetServerIdentityRequest(
        profile: api.ProfileRef(profileId: profileId),
      ),
    );
  }

  Future<ClientNetworkCatalog> listNetworks(String profileId) {
    if (_closed) throw StateError('Local client is closed');
    return readClientNetworks(
      (request) => _client.listNetworks(request),
      instanceId: runtime.instanceId,
      profileId: profileId,
    );
  }

  Future<ClientProfileCatalog> listProfiles() {
    if (_closed) throw StateError('Local client is closed');
    return readClientProfiles(
      (request) => _client.listProfiles(request),
      instanceId: runtime.instanceId,
    );
  }

  ClientMutations get mutations {
    if (_closed) throw StateError('Local client is closed');
    return ClientMutations(_client, instanceId: runtime.instanceId);
  }

  static Future<LocalClientEvents> open({String? endpoint}) async {
    final channel = LocalClientChannel(endpoint: endpoint);
    try {
      final client = localServiceClient(channel);
      final info = await bootstrapLocalClient(client);
      return LocalClientEvents._(channel, client, info..freeze());
    } catch (_) {
      await channel.terminate();
      rethrow;
    }
  }

  Stream<api.WatchEventsResponse> watch() {
    if (_closed) throw StateError('Local event source is closed');
    return validateClientEvents(
      _client.watchEvents(api.WatchEventsRequest()),
    ).map((event) {
      if (event.metadata.instanceId != runtime.instanceId) {
        throw const FormatException('Runtime changed after bootstrap');
      }
      return event;
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _channel.terminate();
  }
}
