import 'dart:async';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/foundation.dart';

import 'client_event_stream.dart';
import 'client_runtime_snapshot.dart';

enum ClientLinkState { disconnected, awaitingSnapshot, ready, unavailable }

/// Application state for one authenticated subscription, with no HTTP DTOs.
/// The shell owns retries and platform lifecycle. Each attach is a fresh epoch.
final class ClientStateController extends ChangeNotifier {
  ClientLinkState _link = ClientLinkState.disconnected;
  ClientRuntimeSnapshot? _snapshot;
  final _operations = <String, api.Operation>{};
  final _invalidated = <(api.Domain, String)>{};
  StreamSubscription<api.WatchEventsResponse>? _subscription;
  int _epoch = 0;
  int _cacheEpoch = 0;
  int _contextEpoch = 0;
  bool _disposed = false;
  api.Failure? _failure;
  bool _invalidContract = false;

  ClientLinkState get link => _link;
  ClientRuntimeSnapshot? get snapshot => _snapshot;
  Map<String, api.Operation> get operations => Map.unmodifiable(_operations);
  Set<(api.Domain, String)> get invalidated => Set.unmodifiable(_invalidated);
  int get cacheEpoch => _cacheEpoch;

  /// Caller/profile identity lifetime, independent of full snapshot refreshes.
  int get contextEpoch => _contextEpoch;
  api.Failure? get failure => _failure;
  bool get invalidContract => _invalidContract;

  void _clear({bool contextChanged = true}) {
    _snapshot = null;
    _operations.clear();
    _invalidated.clear();
    _failure = null;
    _invalidContract = false;
    _cacheEpoch++;
    if (contextChanged) _contextEpoch++;
  }

  Future<void> attach(Stream<api.WatchEventsResponse> source) async {
    if (_disposed) throw StateError('Client state controller is disposed');
    final epoch = ++_epoch;
    final previous = _subscription;
    _subscription = null;
    _clear();
    _link = ClientLinkState.awaitingSnapshot;
    notifyListeners();
    await previous?.cancel();
    if (_disposed || epoch != _epoch) return;
    _subscription = validateClientEvents(source).listen(
      (event) {
        if (_disposed || epoch != _epoch) return;
        _accept(event);
        notifyListeners();
      },
      onError: (Object error) {
        if (_disposed || epoch != _epoch) return;
        _clear();
        _link = ClientLinkState.unavailable;
        if (error is ClientEventFailure) _failure = error.failure;
        _invalidContract = error is FormatException;
        notifyListeners();
      },
      cancelOnError: true,
    );
  }

  void _accept(api.WatchEventsResponse event) {
    if (event.hasSnapshot()) {
      // Capabilities/caller refresh also replaces the authoritative baseline.
      final next = ClientRuntimeSnapshot.fromEvent(event, initial: false);
      final old = _snapshot;
      final changed =
          old == null ||
          old.runtime.instanceId != next.runtime.instanceId ||
          old.runtime.callerAccess != next.runtime.callerAccess ||
          old.status.activeProfileId != next.status.activeProfileId ||
          old.status.accountId != next.status.accountId ||
          old.status.network.id != next.status.network.id;
      _clear(contextChanged: changed);
      _snapshot = next;
      _replaceOperations();
      _link = ClientLinkState.ready;
    } else if (event.hasStatusChanged()) {
      final old = _snapshot!;
      final status = event.statusChanged;
      if (status.activeProfileId != old.status.activeProfileId ||
          status.accountId != old.status.accountId ||
          status.network.id != old.status.network.id) {
        _invalidated.clear();
        _cacheEpoch++;
        _contextEpoch++;
      }
      _snapshot = ClientRuntimeSnapshot.fromEvent(
        api.WatchEventsResponse(
          sequence: event.sequence,
          metadata: event.metadata,
          snapshot: api.SnapshotEvent(runtime: old.runtime, status: status),
        ),
        initial: false,
      );
      _replaceOperations();
    } else if (event.hasOperationChanged()) {
      _operations[event.operationChanged.id] = event.operationChanged;
    } else if (event.hasSessionChanged()) {
      final old = _snapshot!;
      final status = api.Status.fromBuffer(old.status.writeToBuffer())
        ..session = event.sessionChanged
        ..metadata = event.metadata;
      _snapshot = ClientRuntimeSnapshot.fromEvent(
        api.WatchEventsResponse(
          sequence: event.sequence,
          metadata: event.metadata,
          snapshot: api.SnapshotEvent(runtime: old.runtime, status: status),
        ),
        initial: false,
      );
    } else if (event.hasInvalidated()) {
      _invalidated.add((event.invalidated.domain, event.invalidated.profileId));
    }
  }

  void _replaceOperations() {
    _operations
      ..clear()
      ..addEntries(
        _snapshot!.status.currentOperations.map((op) => MapEntry(op.id, op)),
      );
  }

  /// Used by explicit disconnect, caller change and platform suspension.
  Future<void> detach() async {
    ++_epoch;
    final previous = _subscription;
    _subscription = null;
    _clear();
    _link = ClientLinkState.disconnected;
    if (!_disposed) notifyListeners();
    await previous?.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(detach());
    super.dispose();
  }
}
