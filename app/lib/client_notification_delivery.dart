import 'dart:async';

import 'package:flutter/foundation.dart';

import 'client_deadline_notifications.dart';
import 'client_locale.dart';
import 'client_state_controller.dart';

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
/// timers or retry loop: a failed delivery requires explicit [retry].
final class ClientNotificationDelivery extends ChangeNotifier {
  ClientNotificationDelivery({
    required this.state,
    required this.deliver,
    required ClientLocale locale,
    required bool enabled,
  }) : _locale = locale,
       _enabled = enabled {
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
  ClientDeadlineNotice? _failedNotice;
  List<ClientDeadlineNotice> _pending = const [];
  ClientNotificationDeliveryResult? _result;

  ClientNotificationDeliveryResult? get result => _result;
  bool get enabled => _enabled;

  set locale(ClientLocale value) {
    if (_disposed) return;
    _locale = value; // Already handed-off text cannot be recalled or replayed.
  }

  set enabled(bool value) {
    if (_disposed || value == _enabled) return;
    _enabled = value;
    _changed();
  }

  void retry() {
    if (_disposed || _running) return;
    _failedNotice = null;
    _changed();
  }

  void _changed() {
    if (_disposed) return;
    _pending = _planner.observe(
      snapshot: state.snapshot,
      ready: state.link == ClientLinkState.ready,
      enabled: _enabled,
    );
    if (!_pending.contains(_failedNotice)) {
      _failedNotice = null;
      _result = null;
    }
    notifyListeners();
    if (!_running) unawaited(_drain());
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (!_disposed && _pending.isNotEmpty) {
        final notice = _pending.first;
        if (identical(notice, _failedNotice)) break;
        ClientNotificationDeliveryResult outcome;
        try {
          outcome = await deliver(notice.title(_locale), notice.body(_locale));
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
        _planner.acknowledge(notice);
        _pending = _planner.observe(
          snapshot: state.snapshot,
          ready: state.link == ClientLinkState.ready,
          enabled: _enabled,
        );
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
    _pending = const [];
    _failedNotice = null;
    super.dispose();
  }
}
