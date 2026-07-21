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
  static const diagnosticsBundle = '/diagnostics/bundle';
  static const recentLogs = '/logs/recent';

  static const all = <String>[
    status,
    events,
    enroll,
    connect,
    serverIdentity,
    trustServer,
    disconnect,
    logout,
    networks,
    selectNetwork,
    diagnostics,
    diagnosticsBundle,
    recentLogs,
  ];
}

class ServiceIPCMetadata {
  static const protocol = 'endlessnet-client-ipc';
  static const version = 1;
  static const minimumSupportedVersion = 1;
  static const protocolHeader = 'X-EndlessNet-IPC-Protocol';
  static const versionHeader = 'X-EndlessNet-IPC-Version';
  static const minimumVersionHeader = 'X-EndlessNet-IPC-Min-Supported-Version';
}

class ServiceState {
  static const connected = 'Connected';
  static const disconnected = 'Disconnected';
  static const degraded = 'Degraded';
  static const error = 'Error';
  static const needsEnrollment = 'NeedsEnrollment';
  static const needsApproval = 'NeedsApproval';
  static const serverIdentityChanged = 'ServerIdentityChanged';

  static const all = <String>[
    connected,
    disconnected,
    degraded,
    error,
    needsEnrollment,
    needsApproval,
    serverIdentityChanged,
  ];
}

class ControlState {
  static const pendingApproval = 'pending_approval';
  static const degraded = 'degraded';
  static const offlineCache = 'offline_cache';
  static const disconnected = 'disconnected';
  static const notRegistered = 'not_registered';
  static const ready = 'ready';
  static const registered = 'registered';
  static const error = 'error';
  static const cacheInvalid = 'cache_invalid';
  static const serverIdentityChanged = 'server_identity_changed';

  static const all = <String>[
    pendingApproval,
    degraded,
    offlineCache,
    ready,
    registered,
    cacheInvalid,
    error,
    notRegistered,
    disconnected,
    serverIdentityChanged,
  ];
}

class ConnectionIntentState {
  static const connected = 'connected';
  static const disconnected = 'disconnected';

  static const all = <String>[connected, disconnected];
}

class ServiceStatus {
  ServiceStatus(this.payload);

  final Map<String, dynamic>? payload;

  String state({required String fallback}) {
    return _valueText(payload?['state'], fallback);
  }

  bool get connected => state(fallback: '') == ServiceState.connected;

  bool get serverIdentityChanged =>
      state(fallback: '') == ServiceState.serverIdentityChanged ||
      _valueText(payload?['control_state'], '') ==
          ControlState.serverIdentityChanged;

  bool get needsEnrollment =>
      state(fallback: '') == ServiceState.needsEnrollment;

  bool get userDisconnected =>
      payload?['user_disconnected'] == true ||
      _valueText(payload?['desired_state'], '') ==
          ConnectionIntentState.disconnected;

  bool get deviceEnrolled {
    if (payload == null || needsEnrollment) {
      return false;
    }
    if (payload?['node_credential_present'] == true) {
      return true;
    }
    final identifiers = [
      payload?['account_id'],
      payload?['node_id'],
      payload?['network_id'],
    ];
    return identifiers.any((value) => _valueText(value, '').isNotEmpty);
  }
}

String _valueText(Object? value, String fallback) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == '<nil>' || text == 'null') {
    return fallback;
  }
  return text;
}
