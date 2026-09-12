import 'package:endlessnet_client_api/client_api.dart' as api;

import 'client_intent_journal.dart';
import 'client_mutations.dart';
import 'client_operation.dart';
import 'client_state_controller.dart';
import 'local_client_events.dart';

abstract interface class ClientConnection {
  ClientMutations get mutations;
  Stream<api.WatchEventsResponse> watch();
  Future<void> close();
}

final class _LocalConnection implements ClientConnection {
  _LocalConnection(this.source);
  final LocalClientEvents source;
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

  Future<void> connect() async {
    if (_closed) throw StateError('Client session is closed');
    final epoch = ++_epoch;
    final previous = _connection;
    _connection = null;
    await state.detach();
    await previous?.close();
    if (_closed || epoch != _epoch) return;
    try {
      final connection = await _open();
      if (_closed || epoch != _epoch) {
        await connection.close();
        return;
      }
      _connection = connection;
      await state.attach(connection.watch());
    } catch (error) {
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
    return journal.submit(kind, (intent) async {
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
          state.cacheEpoch != cacheEpoch ||
          state.link != ClientLinkState.ready) {
        throw StateError(
          'Client context changed after submission; recover the intention',
        );
      }
      return operation;
    });
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
