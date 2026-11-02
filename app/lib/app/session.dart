import 'dart:async';

import '../client/enrollment_client.dart';
import '../client/connectivity_client.dart';
import '../connectivity/controller.dart';
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
      ) {
    enrollment.addListener(_observeEnrollment);
  }

  final UiLaunchConfig config;
  final UiRuntimePlatform _platform;
  final UiClientConnection _connection;
  final UiCorrelationStorage _storage;
  final EnrollmentController enrollment;
  final ServerTrustController trust;
  final ConnectivityController connectivity;
  Future<void>? _initialization;
  Future<void>? _closing;
  bool get closed => _closing != null;

  void _observeEnrollment() {
    trust.observeLocalState(
      enrollment.profile,
      enrollment.localSnapshot,
      reasonKey: enrollment.reasonKey,
      available:
          enrollment.link == EnrollmentLinkState.available &&
          !enrollment.callRejected,
    );
    unawaited(connectivity.refresh());
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
    }();
  }

  Future<bool> openBrowser(Uri url) async {
    if (closed || url != enrollment.browserAction) return false;
    return _platform.openBrowser(url);
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    enrollment.removeListener(_observeEnrollment);
    enrollment.dispose();
    trust.dispose();
    connectivity.dispose();
    return _closing = () async {
      try {
        await _connection.close();
      } finally {
        await _storage.close();
      }
    }();
  }
}
