import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;

import 'client_deadline_notifications.dart';
import 'client_locale.dart';
import 'client_state_controller.dart';
import 'client_update_notifications.dart';
import 'client_update_notification_source.dart';

enum ClientNotificationDeliveryResult {
  delivered,
  permissionDenied,
  unsupported,
  unavailable,
  failed,
}

/// Adapter receives fixed display text only, not a snapshot or profile ID.
typedef DeliverClientNotification =
    Future<ClientNotificationDeliveryResult> Function(
      String title,
      String body,
    );

/// Serializes delivery from validated state. No automatic permission prompts,
/// retry loop: a failed delivery requires explicit [retry]. Update metadata has
/// a one-shot expiration timer, with no automatic discovery retry.
final class ClientNotificationDelivery extends ChangeNotifier {
  ClientNotificationDelivery({
    required this.state,
    required this.deliver,
    required ClientLocale locale,
    required bool enabled,
    api.BuildIdentity? uiBuild,
    Future<api.UpdateInfo> Function()? loadUpdates,
    DateTime Function()? now,
  }) : _locale = locale,
       _enabled = enabled {
    if (uiBuild != null && loadUpdates != null) {
      _updates = ClientUpdateNotificationSource(
        state: state,
        uiBuild: uiBuild,
        load: loadUpdates,
        enabled: enabled,
        now: now,
      )..addListener(_changed);
    }
    state.addListener(_changed);
    _changed();
  }

  final ClientStateController state;
  final DeliverClientNotification deliver;
  final _planner = ClientDeadlineNotifications();
  ClientLocale _locale;
  bool _enabled;
  bool _disposed = false;
  bool _running = false;
  ClientUpdateNotificationSource? _updates;
  Object? _failedNotice;
  List<Object> _pending = const [];
  ClientNotificationDeliveryResult? _result;

  ClientNotificationDeliveryResult? get result => _result;
  bool get enabled => _enabled;
  bool get updateLookupFailed => _updates?.failed ?? false;

  set locale(ClientLocale value) {
    if (_disposed) return;
    _locale = value; // Already handed-off text cannot be recalled or replayed.
  }

  set enabled(bool value) {
    if (_disposed || value == _enabled) return;
    _enabled = value;
    _updates?.enabled = value;
    _changed();
  }

  void retry() {
    if (_disposed || _running) return;
    _failedNotice = null;
    _updates?.retry();
    _changed();
  }

  void _changed() {
    if (_disposed) return;
    _pending = _planned();
    if (!_pending.contains(_failedNotice)) {
      _failedNotice = null;
      _result = null;
    }
    notifyListeners();
    if (!_running) unawaited(_drain());
  }

  List<Object> _planned() => [
    ..._planner.observe(
      snapshot: state.snapshot,
      ready: state.link == ClientLinkState.ready,
      enabled: _enabled,
    ),
    ?_updates?.notice,
  ];

  Future<void> _drain() async {
    _running = true;
    try {
      while (!_disposed && _pending.isNotEmpty) {
        final notice = _pending.first;
        if (identical(notice, _failedNotice)) break;
        ClientNotificationDeliveryResult outcome;
        try {
          final (title, body) = switch (notice) {
            ClientDeadlineNotice n => (n.title(_locale), n.body(_locale)),
            ClientUpdateNotice n => (n.title(_locale), n.body(_locale)),
            _ => throw StateError('Unknown notification'),
          };
          outcome = await deliver(title, body);
        } catch (_) {
          outcome = ClientNotificationDeliveryResult.failed;
        }
        if (_disposed) break;
        // _changed runs during delivery, invalidating old receipts immediately.
        // A late completion must not alter a newer context or disabled state.
        if (!_pending.contains(notice)) continue;
        _result = outcome;
        if (outcome != ClientNotificationDeliveryResult.delivered) {
          _failedNotice = notice;
          notifyListeners();
          break;
        }
        if (notice is ClientDeadlineNotice) _planner.acknowledge(notice);
        if (notice is ClientUpdateNotice) _updates?.acknowledge(notice);
        _pending = _planned();
        notifyListeners();
      }
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    state.removeListener(_changed);
    _planner.clear();
    _updates?.removeListener(_changed);
    _updates?.dispose();
    _pending = const [];
    _failedNotice = null;
    super.dispose();
  }
}
