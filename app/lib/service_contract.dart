class ServiceIPCPath {
  static const status = '/status';
  static const events = '/events';
  static const enroll = '/enroll';
  static const connect = '/connect';
  static const serverIdentity = '/server-identity';
  static const trustServer = '/server-identity/trust';
  static const disconnect = '/disconnect';
  static const logout = '/logout';
  static const networks = '/networks';
  static const selectNetwork = '/network/select';
  static const diagnostics = '/diagnostics';
  static const recentLogs = '/logs/recent';
}

class ServiceState {
  static const connected = 'Connected';
  static const disconnected = 'Disconnected';
  static const connecting = 'Connecting';
  static const updating = 'Updating';
  static const degraded = 'Degraded';
  static const error = 'Error';
  static const needsEnrollment = 'NeedsEnrollment';
  static const needsApproval = 'NeedsApproval';
}

class ControlState {
  static const connecting = 'connecting';
  static const updating = 'updating';
  static const syncing = 'syncing';
  static const needsApproval = 'needs_approval';
  static const approvalRequired = 'approval_required';
  static const pendingApproval = 'pending_approval';
  static const degraded = 'degraded';
  static const offlineCache = 'offline_cache';
  static const disconnected = 'disconnected';
  static const notRegistered = 'not_registered';
  static const ready = 'ready';
  static const registered = 'registered';
  static const error = 'error';
  static const cacheInvalid = 'cache_invalid';
}

class ConnectionIntentState {
  static const connected = 'connected';
  static const disconnected = 'disconnected';
}

class ServiceStatus {
  ServiceStatus(this.payload);

  final Map<String, dynamic>? payload;

  String state({required String fallback}) {
    return _valueText(payload?['state'] ?? payload?['control_state'], fallback);
  }

  bool get connected => _sameState(state(fallback: ''), ServiceState.connected);

  String get lastError =>
      _valueText(_nestedValue(payload, 'agent', 'last_error'), '');

  bool get serverIdentityChanged =>
      lastError.toLowerCase().contains('server map signing key changed');

  bool get needsEnrollment =>
      _sameState(state(fallback: ''), ServiceState.needsEnrollment) ||
      _sameState(
        _valueText(payload?['control_state'], ''),
        ControlState.notRegistered,
      );

  bool get userDisconnected =>
      payload?['user_disconnected'] == true ||
      _sameState(
        _valueText(payload?['control_state'], ''),
        ControlState.disconnected,
      ) ||
      _sameState(
        _valueText(
          _nestedValue(payload, 'connection_intent', 'desired_state'),
          '',
        ),
        ConnectionIntentState.disconnected,
      );

  bool get deviceEnrolled {
    if (payload == null || needsEnrollment) {
      return false;
    }
    final markers = [
      payload?['account_id'],
      payload?['node_id'],
      payload?['network_id'],
      payload?['overlay_ip'],
      _nestedValue(payload, 'agent', 'node_id'),
      _nestedValue(payload, 'agent', 'network_id'),
      _nestedValue(payload, 'agent', 'overlay_ip'),
    ];
    return markers.any((value) => _valueText(value, '').isNotEmpty);
  }
}

bool _sameState(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

Object? _nestedValue(Map<String, dynamic>? payload, String key, String nested) {
  final child = payload?[key];
  if (child is Map) {
    return child[nested];
  }
  return null;
}

String _valueText(Object? value, String fallback) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == '<nil>' || text == 'null') {
    return fallback;
  }
  return text;
}
