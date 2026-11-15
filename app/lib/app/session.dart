import 'dart:async';

import 'package:endlessnet_client_api/client_api.dart' as api;

import '../client/enrollment_client.dart';
import '../client/connectivity_client.dart';
import '../connectivity/controller.dart';
import '../revocation/controller.dart';
import '../client/revocation_client.dart';
import '../client/revocation_correlation.dart';
import '../client/session_login_client.dart';
import '../client/session_login_correlation.dart';
import '../session_login/controller.dart';
import '../enrollment/controller.dart';
import '../enrollment/server_trust_controller.dart';
import 'launch_config.dart';

// Own UI resource boundaries; production uses the verified Windows adapters.
// Test implementations do not participate in main's platform selection.
final class UiClientConnection {
  UiClientConnection(this.client, this.close, {required this.connectivity});
  final EnrollmentClient client;
  final ConnectivityClient connectivity;
  final Future<void> Function() close;
}

final class UiCorrelationStorage {
  UiCorrelationStorage(this.store, this.close);
  final CorrelationStore store;
  final Future<void> Function() close;
}

abstract interface class UiRuntimePlatform {
  Future<UiLaunchConfig> readConfig();
  Future<UiClientConnection> connect(UiLaunchConfig config);
  Future<UiCorrelationStorage> openStorage(UiLaunchConfig config);
  Future<bool> openBrowser(Uri url);
}

final class UiStartupCancelled implements Exception {
  const UiStartupCancelled();
}

final class UiCleanupFailure implements Exception {
  const UiCleanupFailure();
}

final class UiSession {
  UiSession._(this.config, this._platform, this._connection, this._storage)
    : enrollment = EnrollmentController(
        client: _connection.client,
        store: _storage.store,
        expectedContractSha256: config.contractSha256,
        now: DateTime.now,
        callTimeout: config.rpcTimeout,
        recoveryPollInterval: config.pollInterval,
        restoreInstalledAttempt: true,
      ),
      trust = ServerTrustController(
        client: _connection.client,
        expectedContractSha256: config.contractSha256,
        callTimeout: config.rpcTimeout,
      ),
      connectivity = ConnectivityController(
        client: _connection.connectivity,
        expectedContractSha256: config.contractSha256,
        expectedInstanceId: config.pipe.instanceId,
        readTimeout: config.rpcTimeout,
        pollInterval: config.pollInterval,
      ),
      sessionLogin =
          _connection.client is SessionLoginClient &&
              _storage.store is SessionLoginCorrelationStore
          ? SessionLoginController(
              client: _connection.client as SessionLoginClient,
              store: _storage.store as SessionLoginCorrelationStore,
              expectedContractSha256: config.contractSha256,
              expectedInstanceId: config.pipe.instanceId,
              timeout: config.rpcTimeout,
              now: DateTime.now,
            )
          : null,
      revocation =
          _connection.client is RevocationClient &&
              _storage.store is RevocationCorrelationStore
          ? RevocationController(
              client: _connection.client as RevocationClient,
              store: _storage.store as RevocationCorrelationStore,
              expectedContractSha256: config.contractSha256,
              expectedInstanceId: config.pipe.instanceId,
              timeout: config.rpcTimeout,
            )
          : null {
    enrollment.addListener(_observeEnrollment);
    sessionLogin?.addListener(_observeSession);
  }

  final UiLaunchConfig config;
  final UiRuntimePlatform _platform;
  final UiClientConnection _connection;
  final UiCorrelationStorage _storage;
  final EnrollmentController enrollment;
  final ServerTrustController trust;
  final ConnectivityController connectivity;
  final RevocationController? revocation;
  final SessionLoginController? sessionLogin;
  String _sessionLoginPhase = '';
  void _observeSession() {
    final a = sessionLogin?.attempt;
    final phase = '${a?.attemptId}:${a?.phase}';
    if (_sessionLoginPhase != phase) {
      _sessionLoginPhase = phase;
      if (a?.phase == api.SessionLoginPhase.SESSION_LOGIN_PHASE_SUCCEEDED) {
        unawaited(connectivity.refresh());
      }
    }
  }

  String _revocationNodeContext = '';
  Future<void>? _initialization;
  Future<void>? _closing;
  bool get closed => _closing != null;
  bool _connectAfterEnrollment = false;

  Future<void> startEnrollment(String hostname, api.EnrollmentMode mode) async {
    if (closed || !enrollment.canEnroll) return;
    _connectAfterEnrollment = true;
    await enrollment.start(hostname, mode);
  }

  Future<void> _syncConnectivity() async {
    await connectivity.refresh();
    if (closed || !_connectAfterEnrollment || !enrollment.registeredConfirmed) {
      return;
    }
    _connectAfterEnrollment = false;
    await connectivity.connect();
  }

  void _observeEnrollment() {
    trust.observeLocalState(
      enrollment.profile,
      enrollment.localSnapshot,
      reasonKey: enrollment.reasonKey,
      available:
          enrollment.link == EnrollmentLinkState.available &&
          !enrollment.callRejected,
    );
    unawaited(_syncConnectivity());
    final node = enrollment.currentAttempt?.nodeId ?? '';
    if (node != _revocationNodeContext) {
      _revocationNodeContext = node;
      if (node.isNotEmpty && revocation != null) {
        unawaited(revocation!.refresh());
      }
      if (node.isNotEmpty && sessionLogin != null) {
        unawaited(sessionLogin!.refresh());
      }
    }
  }

  static Future<UiSession> open(
    UiRuntimePlatform platform, {
    required bool Function() cancelled,
  }) async {
    UiClientConnection? connection;
    UiCorrelationStorage? storage;
    void current() {
      if (cancelled()) throw const UiStartupCancelled();
    }

    try {
      current();
      final config = await platform.readConfig();
      current();
      connection = await platform.connect(config);
      current();
      storage = await platform.openStorage(config);
      current();
      return UiSession._(config, platform, connection, storage);
    } catch (_) {
      // Close every successfully acquired resource even if another close fails.
      try {
        try {
          await connection?.close();
        } finally {
          await storage?.close();
        }
      } catch (_) {
        throw const UiCleanupFailure();
      }
      rethrow;
    }
  }

  // Only reads/restores the durable original UUID; never automatically Enrolls,
  // opens a browser or accepts a server announcement.
  Future<void> initialize() {
    if (closed) return Future.value();
    return _initialization ??= () async {
      await enrollment.bind(config.profile);
      if (!closed) await connectivity.bind(config.profile);
      if (!closed) await revocation?.bind(config.profile);
      if (!closed) await sessionLogin?.bind(config.profile);
    }();
  }

  Future<bool> openBrowser(Uri url) async {
    if (closed || url != enrollment.browserAction) return false;
    return _platform.openBrowser(url);
  }

  Future<bool> openSessionBrowser(Uri url) async {
    if (closed || url != sessionLogin?.browserAction) return false;
    return _platform.openBrowser(url);
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    enrollment.removeListener(_observeEnrollment);
    enrollment.dispose();
    trust.dispose();
    connectivity.dispose();
    revocation?.dispose();
    sessionLogin?.removeListener(_observeSession);
    sessionLogin?.dispose();
    return _closing = () async {
      try {
        await _connection.close();
      } finally {
        await _storage.close();
      }
    }();
  }
}
