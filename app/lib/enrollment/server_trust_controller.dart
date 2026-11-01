import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/foundation.dart';

import '../client/call_failure.dart';
import '../client/enrollment_client.dart';

enum ServerTrustState {
  detached,
  loading,
  ready,
  confirming,
  unavailable,
  mismatch,
}

// UI observation/confirmation only. Client re-fetches the current announcement
// and enforces actual OS administrator authority and snapshot CAS at the RPC.
final class ServerTrustController extends ChangeNotifier {
  ServerTrustController({
    required this._client,
    required String expectedContractSha256,
    required Duration callTimeout,
  }) : _digest = expectedContractSha256,
       _timeout = callTimeout {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(_digest) ||
        _digest == '0' * 64 ||
        callTimeout <= Duration.zero ||
        callTimeout > const Duration(seconds: 30)) {
      throw ArgumentError('trust controller configuration');
    }
  }
  final EnrollmentClient _client;
  final String _digest;
  final Duration _timeout;
  api.Profile? _profile;
  api.RuntimeInfo? _runtime;
  api.GetServerIdentityResponse? _observation;
  api.SnapshotMetadata? _latest;
  ServerTrustState _state = ServerTrustState.detached;
  String _reason = '';
  bool _unknown = false;
  bool _confirmBlocked = false;
  bool _disposed = false;
  int _epoch = 0;
  api.Profile? _localProfile;
  api.SnapshotMetadata? _localMetadata;
  (String?, String?, String?, String?, String, bool)? _localSignal;

  ServerTrustState get state => _state;
  String get reasonKey => _reason;
  bool get unknownOutcome => _unknown;
  bool get busy =>
      _state == ServerTrustState.loading ||
      _state == ServerTrustState.confirming;
  api.GetServerIdentityResponse? get observation => _observation == null
      ? null
      : api.GetServerIdentityResponse.fromBuffer(_observation!.writeToBuffer());
  // Display hint only; never transmitted as a caller/admin claim.
  bool get administratorAvailable =>
      _runtime?.callerAccess == api.Access.ACCESS_ADMINISTRATOR;
  bool get canRefresh =>
      !_disposed && !busy && _profile != null && _runtime != null;
  bool get trusted =>
      !_disposed &&
      _state == ServerTrustState.ready &&
      !_unknown &&
      _observation != null &&
      !_observation!.identity.changed &&
      _observation!.identity.trustedKeyId ==
          _observation!.identity.announcedKeyId;
  bool get canConfirm =>
      !_disposed &&
      _state == ServerTrustState.ready &&
      !_unknown &&
      !_confirmBlocked &&
      administratorAvailable &&
      _observation != null &&
      _observation!.identity.changed;

  bool _current(int epoch) => !_disposed && _epoch == epoch;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _call<T>(Future<T> future) => future.timeout(_timeout);

  // Invalidation only: the enrollment view never grants trust. A new local
  // observation fences stale dialogs and in-flight reads, without another RPC.
  void observeLocalState(
    api.Profile? profile,
    api.SnapshotMetadata? metadata, {
    required String reasonKey,
    required bool available,
  }) {
    if (_disposed) return;
    final signal = (
      profile?.id,
      profile?.controlOrigin,
      metadata?.instanceId,
      metadata?.revision.toStringUnsigned(),
      reasonKey,
      available,
    );
    final changed = signal != _localSignal;
    _localSignal = signal;
    _localProfile = profile == null
        ? null
        : api.Profile.fromBuffer(profile.writeToBuffer());
    _localMetadata = metadata == null
        ? null
        : api.SnapshotMetadata.fromBuffer(metadata.writeToBuffer());
    if (_profile == null || !changed) return;
    final foreign =
        profile?.id != _profile!.id ||
        profile?.controlOrigin != _profile!.controlOrigin ||
        (metadata != null &&
            _runtime != null &&
            metadata.instanceId != _runtime!.instanceId);
    final newer =
        metadata != null &&
        _latest != null &&
        BigInt.parse(metadata.revision.toStringUnsigned()) >
            BigInt.parse(_latest!.revision.toStringUnsigned());
    if (!foreign &&
        !newer &&
        available &&
        !reasonKey.startsWith('client.server_identity.')) {
      return;
    }
    _unknown = _unknown || _state == ServerTrustState.confirming;
    ++_epoch;
    _observation = null;
    _confirmBlocked = true;
    _state = foreign ? ServerTrustState.detached : ServerTrustState.unavailable;
    _reason = 'ui.server_identity.stale_confirmation';
    if (foreign) {
      _profile = null;
      _runtime = null;
      _latest = null;
    }
    _emit();
  }

  Future<void> bind(api.Profile profile) async {
    if (_disposed) return;
    final epoch = ++_epoch;
    final bound = api.Profile.fromBuffer(profile.writeToBuffer());
    _profile = bound;
    _runtime = null;
    _observation = null;
    _latest = null;
    _unknown = false;
    _confirmBlocked = false;
    _state = ServerTrustState.loading;
    _reason = '';
    _emit();
    try {
      final origin = Uri.tryParse(bound.controlOrigin);
      if ((_localSignal != null &&
              (bound.id != _localProfile?.id ||
                  bound.controlOrigin != _localProfile?.controlOrigin)) ||
          bound.id.isEmpty ||
          origin == null ||
          origin.scheme != 'https' ||
          origin.userInfo.isNotEmpty ||
          origin.hasFragment ||
          origin.hasQuery ||
          origin.origin != bound.controlOrigin) {
        throw ClientCallFailure.protocol();
      }
      final runtime = await _call(_client.runtimeInfo(_timeout));
      if (!_current(epoch)) return;
      if (runtime.instanceId.isEmpty ||
          runtime.contractSha256 != _digest ||
          runtime.protocol != 'endlessnet-client-ipc' ||
          runtime.ipcVersion != 0) {
        _state = ServerTrustState.mismatch;
        _reason = 'ui.contract_mismatch';
        return;
      }
      _runtime = api.RuntimeInfo.fromBuffer(runtime.writeToBuffer());
      await _read(epoch);
    } on ClientCallFailure catch (error) {
      if (_current(epoch)) _failed(error);
    } catch (_) {
      if (_current(epoch)) _failed(null);
    } finally {
      if (_current(epoch)) _emit();
    }
  }

  bool _revisionAtLeast(api.SnapshotMetadata value) =>
      value.instanceId == _runtime?.instanceId &&
      value.instanceId.isNotEmpty &&
      (_latest == null ||
          BigInt.parse(value.revision.toStringUnsigned()) >=
              BigInt.parse(_latest!.revision.toStringUnsigned()));

  Future<void> _read(int epoch) async {
    final bound = _profile!;
    final response = await _call(
      _client.serverIdentity(
        api.GetServerIdentityRequest(
          profile: api.ProfileRef(profileId: bound.id),
        ),
        _timeout,
      ),
    );
    if (!_current(epoch)) return;
    final identity = response.identity;
    if (!response.hasIdentity() ||
        !response.hasMetadata() ||
        !_revisionAtLeast(response.metadata) ||
        (_localProfile?.id == bound.id &&
            _localProfile?.controlOrigin == bound.controlOrigin &&
            _localMetadata != null &&
            (response.metadata.instanceId != _localMetadata!.instanceId ||
                BigInt.parse(response.metadata.revision.toStringUnsigned()) <
                    BigInt.parse(
                      _localMetadata!.revision.toStringUnsigned(),
                    ))) ||
        identity.profileId != bound.id ||
        identity.controlOrigin != bound.controlOrigin ||
        identity.announcedKeyId.isEmpty ||
        identity.announcementId.isEmpty ||
        (!identity.changed &&
            identity.trustedKeyId != identity.announcedKeyId)) {
      throw ClientCallFailure.protocol();
    }
    _observation = api.GetServerIdentityResponse.fromBuffer(
      response.writeToBuffer(),
    );
    _latest = api.SnapshotMetadata.fromBuffer(
      response.metadata.writeToBuffer(),
    );
    _state = ServerTrustState.ready;
    _reason = '';
    _unknown = false;
  }

  Future<void> refresh() async {
    if (_disposed || busy || _profile == null || _runtime == null) return;
    final epoch = _epoch;
    _state = ServerTrustState.loading;
    _observation = null;
    _confirmBlocked = true;
    _emit();
    try {
      await _read(epoch);
      if (_current(epoch)) _confirmBlocked = false;
    } on ClientCallFailure catch (error) {
      if (_current(epoch)) _failed(error);
    } catch (_) {
      if (_current(epoch)) _failed(null);
    } finally {
      if (_current(epoch)) _emit();
    }
  }

  Future<bool> confirm(api.GetServerIdentityResponse displayed) async {
    if (_disposed || !canConfirm) return false;
    if (!listEquals(displayed.writeToBuffer(), _observation!.writeToBuffer())) {
      _observation = null;
      _confirmBlocked = true;
      _reason = 'ui.server_identity.stale_confirmation';
      _emit();
      return false;
    }
    final epoch = _epoch;
    final observed = _observation!;
    final identity = observed.identity;
    final request = api.TrustServerIdentityRequest(
      mutation: api.MutationContext(
        expectedInstanceId: observed.metadata.instanceId,
        expectedRevision: observed.metadata.revision,
      ),
      profile: api.ProfileRef(profileId: identity.profileId),
      confirmedControlOrigin: identity.controlOrigin,
      confirmedKeyId: identity.announcedKeyId,
      confirmedAnnouncementId: identity.announcementId,
    );
    _state = ServerTrustState.confirming;
    _observation = null;
    _confirmBlocked = true;
    _reason = '';
    _emit();
    var acknowledged = false;
    try {
      // A ChangeResult, including changed=true, is not the current trust snapshot.
      await _call(_client.trustIdentity(request, _timeout));
      acknowledged = true;
      if (!_current(epoch)) return false;
      await _read(epoch);
      if (!_current(epoch)) return false;
      if (!trusted ||
          _observation!.identity.announcementId != identity.announcementId ||
          _observation!.identity.announcedKeyId != identity.announcedKeyId) {
        _unknown = true;
        _reason = 'ui.server_identity.trust_unknown';
      }
    } on ClientCallFailure catch (error) {
      if (_current(epoch)) {
        _unknown = acknowledged || !error.definiteRejection;
        _failed(error);
        if (_unknown) _reason = 'ui.server_identity.trust_unknown';
      }
    } catch (_) {
      if (_current(epoch)) {
        _unknown = true;
        _failed(null);
        _reason = 'ui.server_identity.trust_unknown';
      }
    } finally {
      if (_current(epoch)) _emit();
    }
    return _current(epoch) && trusted;
  }

  void _failed(ClientCallFailure? error) {
    _observation = null;
    _confirmBlocked = true;
    _state = ServerTrustState.unavailable;
    _reason = error?.definiteRejection == true
        ? error!.reasonKey
        : 'ui.server_identity.unavailable';
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}
