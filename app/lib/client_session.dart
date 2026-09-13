import 'package:endlessnet_client_api/client_api.dart' as api;

import 'client_intent_journal.dart';
import 'client_mutations.dart';
import 'client_operation.dart';
import 'client_profiles.dart';
import 'client_networks.dart';
import 'client_state_controller.dart';
import 'local_client_events.dart';

abstract interface class ClientConnection {
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
