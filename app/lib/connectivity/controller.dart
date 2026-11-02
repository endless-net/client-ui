import 'dart:async';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/foundation.dart';

import '../client/call_failure.dart';
import '../client/connectivity_client.dart';

enum ConnectivityLink { detached, loading, available, unavailable, mismatch }

final class ConnectivityController extends ChangeNotifier {
  ConnectivityController({
    required this._client,
    required String expectedContractSha256,
    required String expectedInstanceId,
    required Duration readTimeout,
    required Duration pollInterval,
    this.automaticPolling = true,
  }) : _digest = expectedContractSha256,
       _instance = expectedInstanceId,
       _timeout = readTimeout,
       _interval = pollInterval {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(_digest) ||
        _digest == '0' * 64 ||
        _instance.isEmpty ||
        _timeout <= Duration.zero ||
        _timeout > const Duration(seconds: 30) ||
        _interval < const Duration(seconds: 1) ||
        _interval > const Duration(seconds: 30)) {
      throw ArgumentError('Invalid connectivity configuration');
    }
  }

  final ConnectivityClient _client;
  final String _digest, _instance;
  final Duration _timeout, _interval;
  final bool automaticPolling;
  api.Profile? _profile;
  api.RuntimeInfo? _runtime;
  api.Status? _snapshot;
  api.Failure? _failure;
  Future<void>? _reading;
  Timer? _timer;
  var _epoch = 0;
  var _readVersion = 0;
  var _disposed = false;
  var _mutating = false;
  var _fresh = false;
  var _uncertain = false;
  var _hadDeviceContext = false;
  var _link = ConnectivityLink.detached;

  ConnectivityLink get link => _link;
  bool get busy => _mutating || _link == ConnectivityLink.loading;
  bool get fresh => _fresh && !_mutating;
  bool get uncertain => _uncertain;
  bool get hasDeviceContext => _hadDeviceContext;
  api.Status? get snapshot => _snapshot == null
      ? null
      : api.Status.fromBuffer(_snapshot!.writeToBuffer());
  api.Failure? get failure => _failure == null
      ? null
      : api.Failure.fromBuffer(_failure!.writeToBuffer());
  api.Restriction? get restriction {
    final capabilities = _runtime?.capabilities
        .where((v) => v.capability == api.Capability.CAPABILITY_CONNECTION)
        .toList();
    if (capabilities == null || capabilities.length != 1) return null;
    return api.Restriction.fromBuffer(
      capabilities.single.restriction.writeToBuffer(),
    );
  }

  bool get supported => restriction != null;
  bool get _eligible =>
      !_disposed &&
      _fresh &&
      _link == ConnectivityLink.available &&
      restriction?.availability == api.Availability.AVAILABILITY_AVAILABLE &&
      (_runtime?.callerAccess == api.Access.ACCESS_OWNER ||
          _runtime?.callerAccess == api.Access.ACCESS_ADMINISTRATOR) &&
      _snapshot?.activeProfileId == _profile?.id &&
      (_snapshot?.nodeId.isNotEmpty ?? false) &&
      (_snapshot?.network.id.isNotEmpty ?? false) &&
      (_snapshot?.storedState.nodeCredentialPresent ?? false);
  bool get canConnect => !_mutating && _connectAllowed;
  bool get _connectAllowed =>
      _eligible &&
      _snapshot?.serviceState !=
          api.ServiceState.SERVICE_STATE_POLICY_BLOCKED &&
      (_snapshot?.intent.desiredState !=
              api.DesiredState.DESIRED_STATE_CONNECTED ||
          _snapshot?.serviceState == api.ServiceState.SERVICE_STATE_ERROR);
  bool get canDisconnect => !_mutating && _disconnectAllowed;
  bool get _disconnectAllowed =>
      _eligible &&
      (_snapshot?.intent.desiredState ==
              api.DesiredState.DESIRED_STATE_CONNECTED ||
          _snapshot?.connectionPhase !=
              api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED);

  bool _current(int epoch) => !_disposed && _epoch == epoch;
  bool _currentRead(int epoch, int version) =>
      _current(epoch) && _readVersion == version;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> bind(api.Profile profile) async {
    if (_disposed) return;
    final epoch = ++_epoch;
    ++_readVersion;
    _timer?.cancel();
    _timer = null;
    _profile = api.Profile.fromBuffer(profile.writeToBuffer());
    _runtime = null;
    _snapshot = null;
    _failure = null;
    _fresh = false;
    _uncertain = false;
    _mutating = false;
    _hadDeviceContext = false;
    _reading = null;
    _link = ConnectivityLink.loading;
    _emit();
    await _read(epoch);
    if (_current(epoch) && automaticPolling) {
      _timer = Timer.periodic(_interval, (_) => unawaited(refresh()));
    }
  }

  Future<void> refresh() {
    if (_disposed || _profile == null || _mutating) return Future.value();
    return _read(_epoch);
  }

  Future<void> resume() async {
    if (_disposed) return Future.value();
    ++_readVersion;
    _fresh = false;
    _emit();
    await _reading;
    if (!_disposed) await refresh();
  }

  Future<void> _read(int epoch) {
    if (_reading != null) return _reading!;
    final operation = _fetch(epoch, _readVersion);
    _reading = operation;
    return operation.whenComplete(() {
      if (_current(epoch) && identical(_reading, operation)) _reading = null;
    });
  }

  Future<void> _fetch(int epoch, int version) async {
    try {
      final runtime = await _client.runtimeInfo(_timeout).timeout(_timeout);
      if (!_currentRead(epoch, version)) return;
      if (runtime.instanceId != _instance ||
          runtime.contractSha256 != _digest ||
          runtime.protocol != 'endlessnet-client-ipc' ||
          runtime.ipcVersion != 0) {
        _link = ConnectivityLink.mismatch;
        _runtime = null;
        _snapshot = null;
        _fresh = false;
        return;
      }
      final value = await _client.status(_timeout).timeout(_timeout);
      if (!_currentRead(epoch, version)) return;
      final revision = BigInt.parse(value.metadata.revision.toStringUnsigned());
      final previous = _snapshot?.metadata;
      if (!value.hasMetadata() ||
          value.metadata.instanceId != _instance ||
          revision == BigInt.zero ||
          previous != null &&
              revision < BigInt.parse(previous.revision.toStringUnsigned()) ||
          value.activeProfileId.isNotEmpty &&
              value.activeProfileId != _profile!.id) {
        throw ClientCallFailure.protocol();
      }
      _runtime = api.RuntimeInfo.fromBuffer(runtime.writeToBuffer());
      _snapshot = api.Status.fromBuffer(value.writeToBuffer());
      _hadDeviceContext = _hadDeviceContext || value.nodeId.isNotEmpty;
      _fresh = true;
      _link = ConnectivityLink.available;
      _uncertain = false;
    } catch (_) {
      if (_currentRead(epoch, version)) {
        _fresh = false;
        _link = ConnectivityLink.unavailable;
      }
    } finally {
      if (_currentRead(epoch, version)) _emit();
    }
  }

  Future<void> connect() => _command(true);
  Future<void> disconnect() => _command(false);

  Future<void> _command(bool connect) async {
    if (connect ? !canConnect : !canDisconnect) return;
    final epoch = _epoch;
    _mutating = true;
    _failure = null;
    _uncertain = false;
    _emit();
    try {
      // Join an older read before freezing a mutation; no pre-command response
      // can overwrite the reconciliation read after an accepted command.
      await _reading;
      if (!_current(epoch) ||
          !(connect ? _connectAllowed : _disconnectAllowed)) {
        return;
      }
      final mutation = api.MutationContext(
        expectedInstanceId: _instance,
        expectedRevision: _snapshot!.metadata.revision,
      );
      final profile = api.ProfileRef(profileId: _profile!.id);
      _fresh = false;
      final timeout = Duration(seconds: connect ? 30 : 10);
      if (connect) {
        await _client
            .connect(
              api.ConnectRequest(
                mutation: mutation,
                profile: profile,
                async: true,
              ),
              timeout,
            )
            .timeout(timeout);
      } else {
        await _client
            .disconnect(
              api.DisconnectRequest(mutation: mutation, profile: profile),
              timeout,
            )
            .timeout(timeout);
      }
    } on ClientCallFailure catch (error) {
      if (_current(epoch)) {
        _failure = error.failure;
        _uncertain = !error.definiteRejection;
        _emit();
      }
    } catch (_) {
      if (_current(epoch)) {
        _uncertain = true;
        _emit();
      }
    } finally {
      if (_current(epoch)) {
        // ACK/timeout/stale never invents an outcome or retries a mutation.
        await _read(epoch);
        if (_current(epoch)) {
          _mutating = false;
          _emit();
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    _timer?.cancel();
    super.dispose(); // Closing the UI never sends Disconnect.
  }
}
