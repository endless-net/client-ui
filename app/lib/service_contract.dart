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
  static const serverIdentityChanged = 'ServerIdentityChanged';
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
  static const serverIdentityChanged = 'server_identity_changed';
}

class ConnectionIntentState {
  static const connected = 'connected';
  static const disconnected = 'disconnected';
}

class ServiceStatus {
  ServiceStatus(this.payload);

  final Map<String, dynamic>? payload;

  ServiceAgentStatus get agent =>
      ServiceAgentStatus.fromValue(payload?['agent']);

  List<PeerPathStatus> get peerPaths => agent.peers;

  String state({required String fallback}) {
    return _valueText(payload?['state'] ?? payload?['control_state'], fallback);
  }

  bool get connected => _sameState(state(fallback: ''), ServiceState.connected);

  String get lastError =>
      _valueText(_nestedValue(payload, 'agent', 'last_error'), '');

  bool get serverIdentityChanged =>
      lastError.toLowerCase().contains('server map signing key changed') ||
      _sameState(state(fallback: ''), ServiceState.serverIdentityChanged) ||
      _sameState(
        _valueText(payload?['control_state'], ''),
        ControlState.serverIdentityChanged,
      );

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

class ServiceAgentStatus {
  ServiceAgentStatus({
    required this.present,
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
    return ServiceAgentStatus(
      present: payload != null && payload['state_present'] != false,
      generatedAt: _valueText(payload?['generated_at'], ''),
      stunOK: _boolValue(payload?['stun_ok']),
      relayOK: _boolValue(payload?['relay_ok']),
      selectedPathCounts: counts,
      peers: peers,
    );
  }

  final bool present;
  final String generatedAt;
  final bool? stunOK;
  final bool? relayOK;
  final Map<String, int> selectedPathCounts;
  final List<PeerPathStatus> peers;
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

  Map<String, dynamic>? get agentState => _mapValue(payload['agent_state']);

  ServiceStatus get status => ServiceStatus(_mapValue(payload['status']));

  String get generatedAt => _valueText(payload['generated_at'], '');

  List<PeerPathStatus> get paths {
    final state = agentState;
    final paths = _mapList(
      state?['paths'],
    ).map(PeerPathStatus.fromMap).toList(growable: false);
    return paths.isNotEmpty ? paths : status.peerPaths;
  }

  STUNDiagnostics get stun => STUNDiagnostics.fromValue(agentState?['stun']);
}

class STUNDiagnostics {
  STUNDiagnostics({
    required this.present,
    required this.ok,
    required this.classification,
    required this.totalEndpoints,
    required this.reachableEndpoints,
    required this.mappedAddresses,
    required this.results,
    required this.portMappings,
    required this.error,
  });

  factory STUNDiagnostics.fromValue(Object? value) {
    final payload = _mapValue(value);
    final nat = _mapValue(payload?['nat']);
    return STUNDiagnostics(
      present: payload != null,
      ok: _boolValue(payload?['ok']),
      classification: _valueText(nat?['classification'], ''),
      totalEndpoints: _intValue(nat?['total_endpoints']) ?? 0,
      reachableEndpoints: _intValue(nat?['reachable_endpoints']) ?? 0,
      mappedAddresses: _stringList(nat?['mapped_addresses']),
      results: _mapList(
        payload?['results'],
      ).map(STUNResult.fromMap).toList(growable: false),
      portMappings: _mapList(
        payload?['port_mappings'],
      ).map(PortMappingStatus.fromMap).toList(growable: false),
      error: _valueText(payload?['error'] ?? nat?['error'], ''),
    );
  }

  final bool present;
  final bool? ok;
  final String classification;
  final int totalEndpoints;
  final int reachableEndpoints;
  final List<String> mappedAddresses;
  final List<STUNResult> results;
  final List<PortMappingStatus> portMappings;
  final String error;
}

class STUNResult {
  STUNResult({
    required this.id,
    required this.address,
    required this.reachable,
    required this.mappedAddress,
    required this.durationNanoseconds,
    required this.error,
  });

  factory STUNResult.fromMap(Map<String, dynamic> payload) {
    return STUNResult(
      id: _valueText(payload['id'], ''),
      address: _valueText(payload['addr'], ''),
      reachable: payload['reachable'] == true,
      mappedAddress: _valueText(payload['mapped_address'], ''),
      durationNanoseconds: _intValue(payload['duration']),
      error: _valueText(payload['error'], ''),
    );
  }

  final String id;
  final String address;
  final bool reachable;
  final String mappedAddress;
  final int? durationNanoseconds;
  final String error;
}

class PortMappingStatus {
  PortMappingStatus({
    required this.protocol,
    required this.gateway,
    required this.ok,
    required this.internalPort,
    required this.externalPort,
    required this.externalAddress,
    required this.mappedEndpoint,
    required this.lifetimeSeconds,
    required this.error,
  });

  factory PortMappingStatus.fromMap(Map<String, dynamic> payload) {
    return PortMappingStatus(
      protocol: _valueText(payload['protocol'], ''),
      gateway: _valueText(payload['gateway'], ''),
      ok: payload['ok'] == true,
      internalPort: _intValue(payload['internal_port']) ?? 0,
      externalPort: _intValue(payload['external_port']) ?? 0,
      externalAddress: _valueText(payload['external_address'], ''),
      mappedEndpoint: _valueText(payload['mapped_endpoint'], ''),
      lifetimeSeconds: _intValue(payload['lifetime_seconds']) ?? 0,
      error: _valueText(payload['error'], ''),
    );
  }

  final String protocol;
  final String gateway;
  final bool ok;
  final int internalPort;
  final int externalPort;
  final String externalAddress;
  final String mappedEndpoint;
  final int lifetimeSeconds;
  final String error;
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

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value
      .map((item) => _valueText(item, ''))
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
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
