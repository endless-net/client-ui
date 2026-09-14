import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'client_state_controller.dart';
import 'client_update_info.dart';
import 'client_update_notifications.dart';

/// One read per context/invalidation or explicit retry, never a polling loop.
final class ClientUpdateNotificationSource extends ChangeNotifier {
  ClientUpdateNotificationSource({
    required this.state,
    required api.BuildIdentity uiBuild,
    required this.load,
    required bool enabled,
    DateTime Function()? now,
  }) : uiBuild = api.BuildIdentity.fromBuffer(uiBuild.writeToBuffer())
         ..freeze(),
       _enabled = enabled,
       _now = now ?? DateTime.now {
    state.addListener(_changed);
    _changed();
  }
  final ClientStateController state;
  final api.BuildIdentity uiBuild;
  final Future<api.UpdateInfo> Function() load;
  final DateTime Function() _now;
  final _planner = ClientUpdateNotifications();
  bool _enabled;
  bool _disposed = false;
  bool _loading = false;
  bool _attempted = false;
  bool failed = false;
  int _generation = 0;
  String? _key;
  api.UpdateInfo? _info;
  ClientUpdateNotice? notice;
  Timer? _expiry;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _changed();
  }

  void retry() {
    if (_disposed || _loading || !failed) return;
    _attempted = false;
    failed = false;
    _changed();
  }

  void _changed() {
    if (_disposed) return;
    final snapshot = state.snapshot;
    final allowed =
        _enabled &&
        state.link == ClientLinkState.ready &&
        snapshot != null &&
        snapshot.runtime.callerAccess != api.Access.ACCESS_OBSERVER;
    final key = allowed
        ? '${state.contextEpoch}:${state.domainEpoch(api.Domain.DOMAIN_UPDATES)}'
        : null;
    if (key != _key) {
      _key = key;
      _generation++;
      _attempted = false;
      failed = false;
      _info = null;
      _expiry?.cancel();
      _expiry = null;
    }
    notice = _observe();
    notifyListeners();
    if (key != null && !_loading && !_attempted) {
      _attempted = true;
      _loading = true;
      unawaited(_read(_generation));
    }
  }

  ClientUpdateNotice? _observe() => _planner.observe(
    snapshot: state.snapshot,
    info: _info,
    uiBuild: uiBuild,
    ready: state.link == ClientLinkState.ready,
    enabled: _enabled,
    now: _now(),
  );

  Future<void> _read(int generation) async {
    try {
      final result = await load();
      if (_disposed || generation != _generation) return;
      final snapshot = state.snapshot!;
      final info = validateClientUpdateInfo(
        source: result,
        instanceId: snapshot.runtime.instanceId,
        installedRuntime: snapshot.runtime.build,
        reportedUi: uiBuild,
        now: _now,
      );
      if (info.metadata.revision < snapshot.status.metadata.revision) {
        throw const FormatException('Stale update notice projection');
      }
      _info = info;
      if (info.hasAvailable()) {
        final remaining = info.available.expiresAt.toDateTime().difference(
          _now().toUtc(),
        );
        if (remaining <= Duration.zero) {
          throw const FormatException('Expired update notice');
        }
        _expiry = Timer(remaining, () {
          if (_disposed || generation != _generation) return;
          _info = null;
          _changed(); // Expiration withdraws a notice; it never polls for a new one.
        });
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _info = null;
        failed = true;
      }
    } finally {
      _loading = false;
      if (!_disposed) _changed();
    }
  }

  bool acknowledge(ClientUpdateNotice value) {
    final accepted = _planner.acknowledge(value, _now());
    notice = _observe(); // Also withdraw expired metadata before another send.
    return accepted;
  }

  bool acceptsReceipt(ClientUpdateNotice value) =>
      !_disposed && _planner.acceptsReceipt(value, _now());

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _expiry?.cancel();
    state.removeListener(_changed);
    _planner.clear();
    notice = null;
    super.dispose();
  }
}
