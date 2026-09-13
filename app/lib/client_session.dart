import 'package:endlessnet_client_api/client_api.dart' as api;
import 'dart:typed_data';
import 'dart:io';
import 'client_bundle_export.dart';
import 'client_bundle_chunks.dart';

import 'client_intent_journal.dart';
import 'client_mutations.dart';
import 'client_operation.dart';
import 'client_privileged_recovery.dart';
import 'client_profiles.dart';
import 'client_networks.dart';
import 'client_preferences.dart';
import 'client_resources.dart';
import 'client_exit_nodes.dart';
import 'client_update_info.dart';
import 'client_support_info.dart';
import 'client_state_controller.dart';
import 'local_client_events.dart';

abstract interface class ClientConnection {
  Future<api.GetSupportInfoResponse> getSupportInfo(
    api.GetSupportInfoRequest request,
  );
  Future<api.GetUpdateInfoResponse> getUpdateInfo(
    api.GetUpdateInfoRequest request,
  );
  Future<ClientExitNodes> getExitNodes(String profileId, void Function() check);
  Future<ClientResourceCatalog> listResources(
    String profileId,
    String search,
    List<api.ResourceKind> kinds,
    void Function() checkContext,
  );
  Future<ClientPreferences> getPreferences(
    String profileId,
    void Function() checkContext,
  );
  Future<ClientOperation> recoverOperation(
    String requestId,
    api.OperationKind kind,
  );
  Future<api.ReadDiagnosticsBundleResponse> readDiagnosticsBundle(
    api.ReadDiagnosticsBundleRequest request,
  );
  Future<api.GetDiagnosticsResponse> getDiagnostics(String profileId);
  Future<api.GetServerIdentityResponse> getServerIdentity(String profileId);
  Future<ClientNetworkCatalog> listNetworks(String profileId);
  Future<ClientProfileCatalog> listProfiles();
  ClientMutations get mutations;
  Stream<api.WatchEventsResponse> watch();
  Future<void> close();
}

final class _LocalConnection implements ClientConnection {
  _LocalConnection(this.source);
  final LocalClientEvents source;
  @override
  Future<api.GetSupportInfoResponse> getSupportInfo(
    api.GetSupportInfoRequest request,
  ) => source.getSupportInfo(request);
  @override
  Future<api.GetUpdateInfoResponse> getUpdateInfo(
    api.GetUpdateInfoRequest request,
  ) => source.getUpdateInfo(request);
  @override
  Future<ClientExitNodes> getExitNodes(
    String profileId,
    void Function() check,
  ) => source.getExitNodes(profileId, check);
  @override
  Future<ClientResourceCatalog> listResources(
    String profileId,
    String search,
    List<api.ResourceKind> kinds,
    void Function() checkContext,
  ) => source.listResources(profileId, search, kinds, checkContext);
  @override
  Future<ClientPreferences> getPreferences(
    String profileId,
    void Function() checkContext,
  ) => source.getPreferences(profileId, checkContext);
  @override
  Future<ClientOperation> recoverOperation(
    String requestId,
    api.OperationKind kind,
  ) => source.mutations.recoverByRequestId(requestId, kind);
  @override
  Future<api.ReadDiagnosticsBundleResponse> readDiagnosticsBundle(
    api.ReadDiagnosticsBundleRequest request,
  ) => source.readDiagnosticsBundle(request);
  @override
  Future<api.GetDiagnosticsResponse> getDiagnostics(String profileId) =>
      source.getDiagnostics(profileId);
  @override
  Future<api.GetServerIdentityResponse> getServerIdentity(String profileId) =>
      source.getServerIdentity(profileId);
  @override
  Future<ClientNetworkCatalog> listNetworks(String profileId) =>
      source.listNetworks(profileId);
  @override
  Future<ClientProfileCatalog> listProfiles() => source.listProfiles();
  @override
  ClientMutations get mutations => source.mutations;
  @override
  Stream<api.WatchEventsResponse> watch() => source.watch();
  @override
  Future<void> close() => source.close();
}

/// Owns the v0 application session. Opening a channel is not ready state:
/// commands require a validated snapshot, and request IDs are persisted first.
final class ClientSession {
  ClientSession({
    required this.journal,
    Future<ClientConnection> Function()? open,
    String? endpoint,
  }) : _open =
           open ??
           (() async => _LocalConnection(
             await LocalClientEvents.open(endpoint: endpoint),
           ));

  final ClientIntentJournal journal;
  final Future<ClientConnection> Function() _open;
  final ClientStateController state = ClientStateController();
  ClientConnection? _connection;
  int _epoch = 0;
  bool _closed = false;
  final _submitting = <api.OperationKind>{};

  Future<void> connect() async {
    if (_closed) throw StateError('Client session is closed');
    final epoch = ++_epoch;
    final previous = _connection;
    _connection = null;
    await state.detach();
    await previous?.close();
    if (_closed || epoch != _epoch) return;
    ClientConnection? opened;
    try {
      final connection = await _open();
      opened = connection;
      if (_closed || epoch != _epoch) {
        await connection.close();
        return;
      }
      _connection = connection;
      await state.attach(connection.watch());
    } catch (error) {
      // A successful bootstrap can still be followed by a synchronous watch
      // failure. Do not retain that channel or close a newer concurrent one.
      if (identical(_connection, opened)) _connection = null;
      try {
        await opened?.close();
      } catch (_) {
        // Preserve the original connection failure, not a teardown diagnostic.
      }
      if (!_closed && epoch == _epoch) {
        await state.attach(Stream<api.WatchEventsResponse>.error(error));
      }
      rethrow;
    }
  }

  Future<api.SupportInfo> getSupportInfo() async {
    final connection = _connection;
    final snapshot = state.snapshot;
    if (_closed ||
        connection == null ||
        snapshot == null ||
        state.link != ClientLinkState.ready) {
      throw StateError('Support lookup requires a current runtime context');
    }
    final epoch = _epoch;
    final cache = state.cacheEpoch;
    final support = state.domainEpoch(api.Domain.DOMAIN_SUPPORT);
    void check() {
      if (_closed ||
          epoch != _epoch ||
          cache != state.cacheEpoch ||
          state.link != ClientLinkState.ready ||
          support != state.domainEpoch(api.Domain.DOMAIN_SUPPORT)) {
        throw StateError('Support context changed during read');
      }
    }

    // SupportInfo has no metadata/revision field in v0. Do not synthesize one.
    return readClientSupportInfo(
      installedRuntime: snapshot.runtime.build,
      get: connection.getSupportInfo,
      checkContext: check,
    );
  }

  Future<api.UpdateInfo> getUpdateInfo(
    api.BuildIdentity reportedUi, {
    DateTime Function()? now,
  }) async {
    final connection = _connection;
    final snapshot = state.snapshot;
    if (_closed ||
        connection == null ||
        snapshot == null ||
        state.link != ClientLinkState.ready ||
        snapshot.runtime.callerAccess == api.Access.ACCESS_OBSERVER) {
      throw StateError('Update lookup requires a current owner context');
    }
    final epoch = _epoch;
    final cache = state.cacheEpoch;
    final updates = state.domainEpoch(api.Domain.DOMAIN_UPDATES);
    void check() {
      if (_closed ||
          epoch != _epoch ||
          cache != state.cacheEpoch ||
          state.link != ClientLinkState.ready ||
          updates != state.domainEpoch(api.Domain.DOMAIN_UPDATES)) {
        throw StateError('Update context changed during read');
      }
    }

    final result = await readClientUpdateInfo(
      instanceId: snapshot.runtime.instanceId,
      installedRuntime: snapshot.runtime.build,
      reportedUi: reportedUi,
      get: connection.getUpdateInfo,
      checkContext: check,
      now: now ?? DateTime.now,
    );
    check();
    if (result.metadata.revision < state.snapshot!.status.metadata.revision) {
      throw StateError('Stale update projection');
    }
    return result;
  }

  Future<ClientOperation> submit(
    api.OperationKind kind,
    Future<ClientOperation> Function(
      ClientMutations commands,
      api.MutationContext context,
    )
    send,
  ) async {
    final connection = _connection;
    final snapshot = state.snapshot;
    if (_closed ||
        connection == null ||
        snapshot == null ||
        state.link != ClientLinkState.ready) {
      throw StateError('Mutation requires a current runtime snapshot');
    }
    final epoch = _epoch;
    final cacheEpoch = state.cacheEpoch;
    final contextEpoch = state.contextEpoch;
    if (!_submitting.add(kind)) {
      throw StateError('A submission of this kind is already in progress');
    }
    try {
      // The outbox survives reconnect/restart. A fresh UUID is not a retry of
      // an accepted or uncertain command, even if the transport is ready again.
      if ((await journal.pending()).any((intent) => intent.kind == kind)) {
        throw StateError(
          'Recover the existing intention before submitting again',
        );
      }
      return await journal.submit(kind, (intent) async {
        if (_closed ||
            epoch != _epoch ||
            state.link != ClientLinkState.ready ||
            state.cacheEpoch != cacheEpoch) {
          throw StateError('Client context changed before submission');
        }
        final operation = await send(
          connection.mutations,
          snapshot.mutationContext(intent.requestId),
        );
        if (_closed ||
            epoch != _epoch ||
            state.contextEpoch != contextEpoch ||
            state.link != ClientLinkState.ready) {
          throw StateError(
            'Client context changed after submission; recover the intention',
          );
        }
        return operation;
      });
    } finally {
      _submitting.remove(kind);
    }
  }

  /// The platform launcher must use a fixed installed executable and argument
  /// vector, never a shell. This uses the same durable outbox as direct RPC.
  Future<ClientOperation> submitPrivileged(
    api.OperationKind kind,
    ClientPrivilegedRecovery Function(api.MutationContext) prepare,
    Future<(int, String)> Function(ClientPrivilegedRecovery) launch,
  ) => submit(kind, (_, mutation) async {
    if (state.snapshot!.runtime.callerAccess == api.Access.ACCESS_OBSERVER) {
      throw StateError('Privileged recovery requires the local owner context');
    }
    final request = prepare(mutation);
    if (request.kind != kind ||
        request.mutation != mutation ||
        request.profileId != state.snapshot!.status.activeProfileId) {
      throw StateError(
        'Privileged request does not match the retained context',
      );
    }
    final (exitCode, output) = await launch(request);
    return request.decodeResult(exitCode, output);
  });

  Future<ClientExitNodes> getExitNodes() async {
    final connection = _connection;
    final snapshot = state.snapshot;
    if (_closed ||
        connection == null ||
        snapshot == null ||
        state.link != ClientLinkState.ready ||
        snapshot.runtime.callerAccess == api.Access.ACCESS_OBSERVER ||
        snapshot.status.activeProfileId.isEmpty) {
      throw StateError('Exit nodes require a current owner profile');
    }
    final epoch = _epoch;
    final cache = state.cacheEpoch;
    final domains = {
      for (final domain in [
        api.Domain.DOMAIN_EXIT_NODE,
        api.Domain.DOMAIN_PROFILES,
        api.Domain.DOMAIN_NETWORKS,
        api.Domain.DOMAIN_PEERS,
      ])
        domain: state.domainEpoch(domain),
    };
    void check() {
      if (_closed ||
          epoch != _epoch ||
          cache != state.cacheEpoch ||
          state.link != ClientLinkState.ready ||
          domains.entries.any(
            (entry) => state.domainEpoch(entry.key) != entry.value,
          )) {
        throw StateError('Exit-node context changed during read');
      }
    }

    final result = await connection.getExitNodes(
      snapshot.status.activeProfileId,
      check,
    );
    check();
    if (result.status.profileId != snapshot.status.activeProfileId ||
        result.status.metadata.instanceId != snapshot.runtime.instanceId ||
        result.status.metadata.revision <
            state.snapshot!.status.metadata.revision) {
      throw StateError('Stale exit-node status');
    }
    return result;
  }

  Future<ClientResourceCatalog> listResources({
    String search = '',
    List<api.ResourceKind> kinds = const [],
  }) async {
    final connection = _connection;
    final snapshot = state.snapshot;
    if (_closed ||
        connection == null ||
        snapshot == null ||
        state.link != ClientLinkState.ready ||
        snapshot.runtime.callerAccess == api.Access.ACCESS_OBSERVER ||
        snapshot.status.activeProfileId.isEmpty) {
      throw StateError('Resources require a current owner profile');
    }
    final epoch = _epoch;
    final cacheEpoch = state.cacheEpoch;
    final domains = {
      for (final domain in [
        api.Domain.DOMAIN_PROFILES,
        api.Domain.DOMAIN_RESOURCES,
        api.Domain.DOMAIN_NETWORKS,
      ])
        domain: state.domainEpoch(domain),
    };
    void checkContext() {
      if (_closed ||
          epoch != _epoch ||
          cacheEpoch != state.cacheEpoch ||
          state.link != ClientLinkState.ready ||
          domains.entries.any(
            (entry) => state.domainEpoch(entry.key) != entry.value,
          )) {
        throw StateError('Resource context changed during read');
      }
    }

    final result = await connection.listResources(
      snapshot.status.activeProfileId,
      search,
      List.unmodifiable(kinds),
      checkContext,
    );
    checkContext();
    if (result.profileId != snapshot.status.activeProfileId ||
        result.metadata.instanceId != snapshot.runtime.instanceId ||
        result.metadata.revision < state.snapshot!.status.metadata.revision) {
      throw StateError('Stale resource catalog');
    }
    return result;
  }

  Future<ClientPreferences> getPreferences() async {
    final connection = _connection;
    final snapshot = state.snapshot;
    if (_closed ||
        connection == null ||
        snapshot == null ||
        state.link != ClientLinkState.ready ||
        snapshot.runtime.callerAccess == api.Access.ACCESS_OBSERVER ||
        snapshot.status.activeProfileId.isEmpty) {
      throw StateError('Preferences require a current owner profile');
    }
    final epoch = _epoch;
    final cacheEpoch = state.cacheEpoch;
    final domains = {
      for (final domain in [
        api.Domain.DOMAIN_PROFILES,
        api.Domain.DOMAIN_PREFERENCES,
        api.Domain.DOMAIN_MANAGED_SETTINGS,
      ])
        domain: state.domainEpoch(domain),
    };
    void checkContext() {
      if (_closed ||
          epoch != _epoch ||
          cacheEpoch != state.cacheEpoch ||
          state.link != ClientLinkState.ready ||
          domains.entries.any(
            (entry) => state.domainEpoch(entry.key) != entry.value,
          )) {
        throw StateError('Preferences context changed during read');
      }
    }

    final result = await connection.getPreferences(
      snapshot.status.activeProfileId,
      checkContext,
    );
    checkContext();
    if (result.preferences.profileId != snapshot.status.activeProfileId ||
        result.preferences.metadata.instanceId != snapshot.runtime.instanceId ||
        result.preferences.metadata.revision <
            state.snapshot!.status.metadata.revision) {
      throw StateError('Stale preferences projection');
    }
    return result;
  }

  /// A read never grants trust. Confirmation must separately bind the exact
  /// origin/key/announcement and remain subject to producer authorization.
  Future<api.GetServerIdentityResponse> getServerIdentity() async {
    final connection = _connection;
    final snapshot = state.snapshot;
    if (_closed ||
        connection == null ||
        snapshot == null ||
        state.link != ClientLinkState.ready ||
        snapshot.runtime.callerAccess == api.Access.ACCESS_OBSERVER ||
        snapshot.status.activeProfileId.isEmpty) {
      throw StateError('Server identity requires a current owner profile');
    }
    final epoch = _epoch;
    final cacheEpoch = state.cacheEpoch;
    final identityEpoch = state.domainEpoch(api.Domain.DOMAIN_SERVER_IDENTITY);
    final profileEpoch = state.domainEpoch(api.Domain.DOMAIN_PROFILES);
    final profileId = snapshot.status.activeProfileId;
    final response = await connection.getServerIdentity(profileId);
    if (_closed ||
        epoch != _epoch ||
        cacheEpoch != state.cacheEpoch ||
        identityEpoch != state.domainEpoch(api.Domain.DOMAIN_SERVER_IDENTITY) ||
        profileEpoch != state.domainEpoch(api.Domain.DOMAIN_PROFILES) ||
        state.link != ClientLinkState.ready ||
        state.snapshot == null ||
        state.snapshot!.status.activeProfileId != profileId ||
        !response.hasIdentity() ||
        !response.hasMetadata() ||
        response.identity.profileId != profileId ||
        response.metadata.instanceId != snapshot.runtime.instanceId ||
        response.metadata.revision <= 0 ||
        response.metadata.revision < state.snapshot!.status.metadata.revision) {
      throw StateError('Invalid or stale server identity context');
    }
    return api.GetServerIdentityResponse.fromBuffer(response.writeToBuffer())
      ..freeze();
  }

  /// Preview only: no archive creation, clipboard write or upload is implicit.
  Future<api.Diagnostics> getDiagnostics() async {
    final connection = _connection;
    final snapshot = state.snapshot;
    if (_closed ||
        connection == null ||
        snapshot == null ||
        state.link != ClientLinkState.ready ||
        snapshot.runtime.callerAccess == api.Access.ACCESS_OBSERVER ||
        snapshot.status.activeProfileId.isEmpty) {
      throw StateError('Diagnostics require a current owner profile');
    }
    final epoch = _epoch;
    final cacheEpoch = state.cacheEpoch;
    // Diagnostics aggregate status, peers, routes and settings. Any domain
    // invalidation during the read invalidates the aggregate, even if repeated.
    final domains = {
      for (final domain in api.Domain.values) domain: state.domainEpoch(domain),
    };
    final profileId = snapshot.status.activeProfileId;
    final response = await connection.getDiagnostics(profileId);
    final diagnostics = response.diagnostics;
    if (_closed ||
        epoch != _epoch ||
        cacheEpoch != state.cacheEpoch ||
        domains.entries.any(
          (entry) => state.domainEpoch(entry.key) != entry.value,
        ) ||
        state.link != ClientLinkState.ready ||
        state.snapshot == null ||
        state.snapshot!.status.activeProfileId != profileId ||
        !response.hasDiagnostics() ||
        !diagnostics.hasMetadata() ||
        diagnostics.metadata.instanceId != snapshot.runtime.instanceId ||
        diagnostics.metadata.revision <= 0 ||
        diagnostics.metadata.revision <
            state.snapshot!.status.metadata.revision ||
        (diagnostics.hasStatus() &&
            (!diagnostics.status.hasMetadata() ||
                diagnostics.status.metadata.instanceId !=
                    diagnostics.metadata.instanceId ||
                diagnostics.status.metadata.revision !=
                    diagnostics.metadata.revision ||
                diagnostics.status.activeProfileId != profileId))) {
      throw StateError('Invalid or stale diagnostics context');
    }
    return api.Diagnostics.fromBuffer(diagnostics.writeToBuffer())..freeze();
  }

  /// Re-resolve a caller-authorized operation; never accept an old UI handle.
  /// Explicit destination export does not acknowledge the intention.
  Future<File> exportDiagnosticsBundle(
    String requestId,
    Directory destination,
  ) async {
    final epoch = _epoch;
    final cacheEpoch = state.cacheEpoch;
    final profileEpoch = state.domainEpoch(api.Domain.DOMAIN_PROFILES);
    final sessionEpoch = state.domainEpoch(api.Domain.DOMAIN_SESSION);
    void check() {
      if (_closed ||
          epoch != _epoch ||
          cacheEpoch != state.cacheEpoch ||
          state.link != ClientLinkState.ready ||
          profileEpoch != state.domainEpoch(api.Domain.DOMAIN_PROFILES) ||
          sessionEpoch != state.domainEpoch(api.Domain.DOMAIN_SESSION)) {
        throw StateError('Client context changed during bundle export');
      }
    }

    check();
    final content = await readDiagnosticsBundle(requestId);
    check();
    return exportClientBundle(destination, content, checkContext: check);
  }

  Future<Uint8List> readDiagnosticsBundle(String requestId) async {
    final connection = _connection;
    final snapshot = state.snapshot;
    if (_closed ||
        connection == null ||
        snapshot == null ||
        state.link != ClientLinkState.ready ||
        snapshot.runtime.callerAccess == api.Access.ACCESS_OBSERVER ||
        snapshot.status.activeProfileId.isEmpty) {
      throw StateError('Bundle read requires a current owner profile');
    }
    final epoch = _epoch;
    final cacheEpoch = state.cacheEpoch;
    final profileEpoch = state.domainEpoch(api.Domain.DOMAIN_PROFILES);
    final sessionEpoch = state.domainEpoch(api.Domain.DOMAIN_SESSION);
    void check() {
      if (_closed ||
          epoch != _epoch ||
          cacheEpoch != state.cacheEpoch ||
          state.link != ClientLinkState.ready ||
          profileEpoch != state.domainEpoch(api.Domain.DOMAIN_PROFILES) ||
          sessionEpoch != state.domainEpoch(api.Domain.DOMAIN_SESSION)) {
        throw StateError('Client context changed during bundle read');
      }
    }

    final operation = await connection.recoverOperation(
      requestId,
      api.OperationKind.OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE,
    );
    check();
    if (!operation.succeeded || !operation.value.hasBundle()) {
      throw StateError('Diagnostics bundle operation has not succeeded');
    }
    return readClientBundleChunks(
      operation.value.bundle,
      connection.readDiagnosticsBundle,
      checkContext: check,
    );
  }

  Future<ClientProfileCatalog> listProfiles() async {
    final connection = _connection;
    final snapshot = state.snapshot;
    if (_closed ||
        connection == null ||
        snapshot == null ||
        state.link != ClientLinkState.ready ||
        snapshot.runtime.callerAccess == api.Access.ACCESS_OBSERVER) {
      throw StateError('Profile catalog requires a current owner snapshot');
    }
    final epoch = _epoch;
    final cacheEpoch = state.cacheEpoch;
    final profilesEpoch = state.domainEpoch(api.Domain.DOMAIN_PROFILES);
    final catalog = await connection.listProfiles();
    if (_closed ||
        epoch != _epoch ||
        cacheEpoch != state.cacheEpoch ||
        profilesEpoch != state.domainEpoch(api.Domain.DOMAIN_PROFILES) ||
        state.link != ClientLinkState.ready ||
        state.snapshot == null ||
        catalog.metadata.instanceId != snapshot.runtime.instanceId ||
        catalog.metadata.revision < state.snapshot!.status.metadata.revision) {
      throw StateError('Client context changed during profile lookup');
    }
    return catalog;
  }

  Future<ClientNetworkCatalog> listNetworks() async {
    final connection = _connection;
    final snapshot = state.snapshot;
    if (_closed ||
        connection == null ||
        snapshot == null ||
        state.link != ClientLinkState.ready ||
        snapshot.runtime.callerAccess == api.Access.ACCESS_OBSERVER ||
        snapshot.status.activeProfileId.isEmpty) {
      throw StateError('Network catalog requires a current owner profile');
    }
    final epoch = _epoch;
    final cacheEpoch = state.cacheEpoch;
    final domainEpoch = state.domainEpoch(api.Domain.DOMAIN_NETWORKS);
    final profileId = snapshot.status.activeProfileId;
    final catalog = await connection.listNetworks(profileId);
    if (_closed ||
        epoch != _epoch ||
        cacheEpoch != state.cacheEpoch ||
        domainEpoch != state.domainEpoch(api.Domain.DOMAIN_NETWORKS) ||
        state.link != ClientLinkState.ready ||
        state.snapshot == null ||
        catalog.profileId != profileId ||
        state.snapshot!.status.activeProfileId != profileId ||
        catalog.metadata.instanceId != snapshot.runtime.instanceId ||
        catalog.metadata.revision < state.snapshot!.status.metadata.revision) {
      throw StateError('Client context changed during network lookup');
    }
    return catalog;
  }

  /// Lookup only. NOT_FOUND/authorization errors preserve the record and are
  /// surfaced for explicit recovery; never replay a command from the journal.
  Future<List<ClientOperation>> recoverPending() async {
    final connection = _connection;
    final snapshot = state.snapshot;
    if (_closed ||
        connection == null ||
        snapshot == null ||
        state.link != ClientLinkState.ready ||
        snapshot.runtime.callerAccess == api.Access.ACCESS_OBSERVER) {
      throw StateError('Operation recovery requires a current owner snapshot');
    }
    final epoch = _epoch;
    final cacheEpoch = state.cacheEpoch;
    final recovered = <ClientOperation>[];
    for (final intent in await journal.pending()) {
      if (_closed ||
          epoch != _epoch ||
          state.cacheEpoch != cacheEpoch ||
          state.link != ClientLinkState.ready) {
        throw StateError('Client context changed during recovery');
      }
      final operation = await connection.mutations.recoverByRequestId(
        intent.requestId,
        intent.kind,
      );
      if (_closed ||
          epoch != _epoch ||
          state.cacheEpoch != cacheEpoch ||
          state.link != ClientLinkState.ready) {
        throw StateError('Client context changed during recovery');
      }
      recovered.add(operation);
    }
    return List.unmodifiable(recovered);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ++_epoch;
    final connection = _connection;
    _connection = null;
    await state.detach();
    await connection?.close();
    state.dispose();
  }
}
