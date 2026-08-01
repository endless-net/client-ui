class ServiceIPCPath {
  static const status = '/status';
  static const events = '/events';
  static const enroll = '/enroll';
  static const connect = '/connect';
  static const serverIdentity = '/server-identity';
  static const trustServer = '/server-identity/trust';
  static const disconnect = '/disconnect';
  static const logout = '/logout';
  static const localForget = '/logout/local';
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
    localForget,
    networks,
    selectNetwork,
    diagnostics,
    diagnosticsBundle,
    recentLogs,
  ];
}

class ServiceIPCMetadata {
  static const protocol = 'endlessnet-client-ipc';
  static const version = 2;
  static const minimumSupportedVersion = 2;
  static const protocolHeader = 'X-EndlessNet-IPC-Protocol';
  static const versionHeader = 'X-EndlessNet-IPC-Version';
  static const minimumVersionHeader = 'X-EndlessNet-IPC-Min-Supported-Version';
}

abstract final class ServiceIPCErrorCode {
  static const requestFailed = 'request_failed';
  static const ownerRequired = 'owner_required';
  static const administratorRequired = 'administrator_required';
  static const remoteCleanupRequired = 'remote_cleanup_required';
  static const localForgetConfirmationRequired =
      'local_forget_confirmation_required';
  static const recoveryOperationInvalid = 'recovery_operation_invalid';
  static const recoveryOperationIDFailed = 'recovery_operation_id_failed';
  static const localForgetFailed = 'local_forget_failed';
  static const serverIdentityConfirmationMismatch =
      'server_identity_confirmation_mismatch';
}

abstract final class ServiceIPCPrivilege {
  static const observer = 'observer';
  static const owner = 'owner';
  static const administrator = 'administrator';

  static const requiredByPath = <String, String>{
    ServiceIPCPath.status: observer,
    ServiceIPCPath.events: observer,
    ServiceIPCPath.enroll: owner,
    ServiceIPCPath.connect: owner,
    ServiceIPCPath.serverIdentity: observer,
    ServiceIPCPath.trustServer: administrator,
    ServiceIPCPath.disconnect: owner,
    ServiceIPCPath.logout: owner,
    ServiceIPCPath.localForget: administrator,
    ServiceIPCPath.networks: observer,
    ServiceIPCPath.selectNetwork: owner,
    ServiceIPCPath.diagnostics: owner,
    ServiceIPCPath.diagnosticsBundle: owner,
    ServiceIPCPath.recentLogs: owner,
  };
}

class ServiceState {
  static const connected = 'Connected';
  static const disconnected = 'Disconnected';
  static const degraded = 'Degraded';
  static const error = 'Error';
  static const needsEnrollment = 'NeedsEnrollment';
  static const needsApproval = 'NeedsApproval';
  static const serverIdentityChanged = 'ServerIdentityChanged';
  static const recovering = 'Recovering';
  static const recoveryBlocked = 'RecoveryBlocked';
  static const policyBlocked = 'PolicyBlocked';
  static const needsLogin = 'NeedsLogin';

  static const all = <String>[
    connected,
    disconnected,
    degraded,
    error,
    needsEnrollment,
    needsApproval,
    serverIdentityChanged,
    recovering,
    recoveryBlocked,
    policyBlocked,
    needsLogin,
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
  static const recovering = 'recovering';
  static const recoveryBlocked = 'recovery_blocked';
  static const policyBlocked = 'policy_blocked';
  static const needsLogin = 'needs_login';

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
    recovering,
    recoveryBlocked,
    policyBlocked,
    needsLogin,
  ];
}

abstract final class RecoveryOperation {
  static const trustServerIdentity = 'trust_server_identity';
  static const forgetLocalEnrollment = 'forget_local_enrollment';

  static const all = <String>[trustServerIdentity, forgetLocalEnrollment];
}

abstract final class RecoveryOperationOutcome {
  static const accepted = 'accepted';
  static const alreadyApplied = 'already_applied';
  static const completed = 'completed';

  static const all = <String>[accepted, alreadyApplied, completed];
}

abstract final class LogoutOutcome {
  static const remoteCleanupConfirmed = 'remote_cleanup_confirmed';
  static const remoteCleanupUnconfirmed = 'remote_cleanup_unconfirmed';

  static const all = <String>[remoteCleanupConfirmed, remoteCleanupUnconfirmed];
}

class ConnectionIntentState {
  static const connected = 'connected';
  static const disconnected = 'disconnected';

  static const all = <String>[connected, disconnected];
}

class ServiceStatus {
  ServiceStatus(this.payload);

  final Map<String, dynamic>? payload;

  ServiceAgentStatus get agent =>
      ServiceAgentStatus.fromValue(payload?['agent']);

  int? get peerCount => _intValue(payload?['peer_count']);

  PeerDevicesStatus get peerDevices {
    final authoritativePeerCount = peerCount;
    if (authoritativePeerCount == 0) {
      return const PeerDevicesStatus(
        state: PeerDevicesState.confirmedEmpty,
        paths: [],
      );
    }

    final agentStatus = agent;
    if (!agentStatus.present || agentStatus.peers.isEmpty) {
      return const PeerDevicesStatus(
        state: PeerDevicesState.refreshing,
        paths: [],
      );
    }

    return PeerDevicesStatus(
      state: PeerDevicesState.available,
      paths: agentStatus.peers,
    );
  }

  List<PeerPathStatus> get peerPaths => peerDevices.paths;

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

  bool get recovering => state(fallback: '') == ServiceState.recovering;

  bool get needsLogin => state(fallback: '') == ServiceState.needsLogin;

  bool get recoveryBlocked =>
      state(fallback: '') == ServiceState.recoveryBlocked;

  bool get policyBlocked => state(fallback: '') == ServiceState.policyBlocked;

  RecoveryStatus get recovery => RecoveryStatus.fromValue(payload?['recovery']);

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

class RecoveryStatus {
  const RecoveryStatus({
    required this.operationID,
    required this.state,
    required this.errorCode,
    required this.requestID,
    required this.retryable,
  });

  factory RecoveryStatus.fromValue(Object? value) {
    final payload = _mapValue(value);
    return RecoveryStatus(
      operationID: _valueText(payload?['operation_id'], ''),
      state: _valueText(payload?['state'], ''),
      errorCode: _valueText(payload?['error_code'], ''),
      requestID: _valueText(payload?['request_id'], ''),
      retryable: payload?['retryable'] == true,
    );
  }

  final String operationID;
  final String state;
  final String errorCode;
  final String requestID;
  final bool retryable;
}

class LogoutResponse {
  LogoutResponse(this.payload) : status = ServiceStatus(payload);

  final Map<String, dynamic> payload;
  final ServiceStatus status;

  String get state => _valueText(payload['state'], '');
  String get controlState => _valueText(payload['control_state'], '');
  String get outcome => _valueText(payload['outcome'], '');
  String get remoteRequestID => _valueText(payload['remote_request_id'], '');

  bool get remoteCleanupUnconfirmed =>
      outcome == LogoutOutcome.remoteCleanupUnconfirmed;
}

class EnrollmentResponse {
  EnrollmentResponse(this.payload)
    : status = ServiceStatus(payload),
      wireGuardApply = WireGuardApplyResult.fromValue(
        payload['wireguard_apply'],
      );

  final Map<String, dynamic> payload;
  final ServiceStatus status;
  final WireGuardApplyResult? wireGuardApply;

  bool get pending =>
      status.state(fallback: '') == ServiceState.needsApproval ||
      _valueText(payload['control_state'], '') == ControlState.pendingApproval;

  String get approvalURL => _valueText(payload['approval_url'], '');
}

class WireGuardApplyResult {
  WireGuardApplyResult({
    required this.ok,
    required this.method,
    required this.interfaceName,
    required this.changed,
    required this.skipped,
    required this.reason,
    required this.downError,
    required this.upError,
    required this.syncError,
    required this.routeError,
  });

  static WireGuardApplyResult? fromValue(Object? value) {
    final payload = _mapValue(value);
    if (payload == null) {
      return null;
    }
    return WireGuardApplyResult(
      ok: payload['ok'] == true,
      method: _valueText(payload['method'], ''),
      interfaceName: _valueText(payload['interface'], ''),
      changed: payload['changed'] == true,
      skipped: payload['skipped'] == true,
      reason: _valueText(payload['reason'], ''),
      downError: _valueText(payload['down_error'], ''),
      upError: _valueText(payload['up_error'], ''),
      syncError: _valueText(payload['sync_error'], ''),
      routeError: _valueText(payload['route_error'], ''),
    );
  }

  final bool ok;
  final String method;
  final String interfaceName;
  final bool changed;
  final bool skipped;
  final String reason;
  final String downError;
  final String upError;
  final String syncError;
  final String routeError;
}

enum PeerDevicesState { available, refreshing, confirmedEmpty }

class PeerDevicesStatus {
  const PeerDevicesStatus({required this.state, required this.paths});

  final PeerDevicesState state;
  final List<PeerPathStatus> paths;
}

class ServiceAgentStatus {
  ServiceAgentStatus({
    required this.present,
    required this.snapshotState,
    required this.mapRevision,
    required this.targetMapRevision,
    required this.generatedAt,
    required this.stunOK,
    required this.relayOK,
    required this.selectedPathCounts,
    required this.peers,
  });

  factory ServiceAgentStatus.fromValue(Object? value) {
    final payload = _mapValue(value);
    final counts = <String, int>{};
    final rawCounts = _mapValue(payload?['selected_path_counts']);
    rawCounts?.forEach((key, value) {
      final count = _intValue(value);
      if (key.trim().isNotEmpty && count != null) {
        counts[key.trim().toLowerCase()] = count;
      }
    });
    final peers = _mapList(
      payload?['peers'],
    ).map(PeerPathStatus.fromMap).toList(growable: false);
    if (counts.isEmpty) {
      for (final peer in peers) {
        final path = peer.selectedPath.toLowerCase();
        if (path.isNotEmpty) {
          counts[path] = (counts[path] ?? 0) + 1;
        }
      }
    }
    final present = payload?['state_present'] == true;
    final snapshotState = _valueText(payload?['snapshot_state'], '');
    return ServiceAgentStatus(
      present: present,
      snapshotState: AgentSnapshotState.all.contains(snapshotState)
          ? snapshotState
          : present
          ? AgentSnapshotState.current
          : AgentSnapshotState.absent,
      mapRevision: _intValue(payload?['map_revision']),
      targetMapRevision: _intValue(payload?['target_map_revision']),
      generatedAt: _valueText(payload?['generated_at'], ''),
      stunOK: _boolValue(payload?['stun_ok']),
      relayOK: _boolValue(payload?['relay_ok']),
      selectedPathCounts: counts,
      peers: peers,
    );
  }

  final bool present;
  final String snapshotState;
  final int? mapRevision;
  final int? targetMapRevision;
  final String generatedAt;
  final bool? stunOK;
  final bool? relayOK;
  final Map<String, int> selectedPathCounts;
  final List<PeerPathStatus> peers;

  bool get isPreviousSnapshot => snapshotState == AgentSnapshotState.previous;
}

abstract final class AgentSnapshotState {
  static const absent = 'absent';
  static const current = 'current';
  static const previous = 'previous';
  static const all = {absent, current, previous};
}

class PeerPathStatus {
  PeerPathStatus({
    required this.peerID,
    required this.hostname,
    required this.selectedPath,
    required this.selectedEndpoint,
    required this.selectionReason,
    required this.lastTransitionAt,
    required this.direct,
    required this.relay,
    required this.candidates,
  });

  factory PeerPathStatus.fromMap(Map<String, dynamic> payload) {
    return PeerPathStatus(
      peerID: _valueText(payload['peer_id'], ''),
      hostname: _valueText(payload['hostname'], ''),
      selectedPath: _valueText(payload['selected_path'], 'none'),
      selectedEndpoint: _valueText(payload['selected_endpoint'], ''),
      selectionReason: _valueText(payload['selection_reason'], ''),
      lastTransitionAt: _valueText(payload['last_transition_at'], ''),
      direct: PathCandidateStatus.fromValue(payload['direct']),
      relay: PathCandidateStatus.fromValue(payload['relay']),
      candidates: _mapList(
        payload['candidates'],
      ).map(PathCandidateStatus.fromMap).toList(growable: false),
    );
  }

  final String peerID;
  final String hostname;
  final String selectedPath;
  final String selectedEndpoint;
  final String selectionReason;
  final String lastTransitionAt;
  final PathCandidateStatus direct;
  final PathCandidateStatus relay;
  final List<PathCandidateStatus> candidates;

  String get displayName => hostname.isNotEmpty ? hostname : peerID;
}

class PathCandidateStatus {
  PathCandidateStatus({
    required this.type,
    required this.tier,
    required this.state,
    required this.endpoint,
    required this.relayID,
    required this.protocol,
    required this.rttMS,
    required this.checkedAt,
    required this.lastReachableAt,
    required this.consecutiveFailures,
    required this.reason,
  });

  factory PathCandidateStatus.fromValue(Object? value) {
    final payload = _mapValue(value);
    if (payload == null) {
      return PathCandidateStatus.fromMap(const {});
    }
    return PathCandidateStatus.fromMap(payload);
  }

  factory PathCandidateStatus.fromMap(Map<String, dynamic> payload) {
    return PathCandidateStatus(
      type: _valueText(payload['type'], ''),
      tier: _valueText(payload['tier'], ''),
      state: _valueText(payload['state'], ''),
      endpoint: _valueText(payload['endpoint'], ''),
      relayID: _valueText(payload['relay_id'], ''),
      protocol: _valueText(payload['protocol'], ''),
      rttMS: _doubleValue(payload['rtt_ms']),
      checkedAt: _valueText(payload['checked_at'], ''),
      lastReachableAt: _valueText(payload['last_reachable_at'], ''),
      consecutiveFailures: _intValue(payload['consecutive_failures']) ?? 0,
      reason: _valueText(payload['reason'], ''),
    );
  }

  final String type;
  final String tier;
  final String state;
  final String endpoint;
  final String relayID;
  final String protocol;
  final double? rttMS;
  final String checkedAt;
  final String lastReachableAt;
  final int consecutiveFailures;
  final String reason;

  bool get hasData =>
      type.isNotEmpty ||
      state.isNotEmpty ||
      endpoint.isNotEmpty ||
      reason.isNotEmpty;
}

class ServiceDiagnostics {
  ServiceDiagnostics(this.payload);

  final Map<String, dynamic> payload;

  Map<String, dynamic>? get diagnostics => _mapValue(payload['diagnostics']);

  ServiceStatus get status => ServiceStatus(_mapValue(diagnostics?['status']));

  ServiceAgentStatus get agent => status.agent;

  String get generatedAt => _valueText(diagnostics?['generated_at'], '');

  List<PeerPathStatus> get paths => status.peerPaths;
}

String _valueText(Object? value, String fallback) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == '<nil>' || text == 'null') {
    return fallback;
  }
  return text;
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, child) => MapEntry(key.toString(), child));
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map(_mapValue).whereType<Map<String, dynamic>>().toList();
}

bool? _boolValue(Object? value) => value is bool ? value : null;

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

double? _doubleValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '');
}
