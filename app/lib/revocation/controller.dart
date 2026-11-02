import 'dart:math';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart' as grpc;

import '../client/call_failure.dart';
import '../client/revocation_client.dart';
import '../client/revocation_correlation.dart';

final class RevocationController extends ChangeNotifier {
  RevocationController({
    required this._client,
    required this._store,
    required String expectedContractSha256,
    required String expectedInstanceId,
    required Duration timeout,
    String Function()? commandId,
  }) : _digest = expectedContractSha256,
       _instance = expectedInstanceId,
       _timeout = timeout > const Duration(seconds: 10)
           ? const Duration(seconds: 10)
           : timeout,
       _commandId = commandId ?? _uuid {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(_digest) ||
        _digest == '0' * 64 ||
        _instance.isEmpty ||
        timeout <= Duration.zero ||
        timeout > const Duration(seconds: 30)) {
      throw ArgumentError('Invalid revocation configuration');
    }
  }
  final RevocationClient _client;
  final RevocationCorrelationStore _store;
  final String _digest, _instance;
  final Duration _timeout;
  final String Function() _commandId;
  api.Profile? _profile;
  api.SnapshotMetadata? _metadata;
  List<api.NodeRevocationTarget> _targets = [];
  RevocationCorrelation? _correlation;
  api.NodeRevocationResult? _result;
  bool _busy = false, _ready = false, _disposed = false;
  int _epoch = 0;
  String _problem = '';
  bool get busy => _busy;
  bool get canChoose =>
      _ready && !_busy && (_correlation == null || _correlation!.resolved);
  bool get hasOriginal => _correlation != null;
  String get problem => _problem;
  List<api.NodeRevocationTarget> get targets => _targets
      .map((t) => api.NodeRevocationTarget.fromBuffer(t.writeToBuffer()))
      .toList();
  api.NodeRevocationResult? get result => _result == null
      ? null
      : api.NodeRevocationResult.fromBuffer(_result!.writeToBuffer());
  bool _current(int epoch) => !_disposed && epoch == _epoch;
  void _emit() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> bind(api.Profile profile) async {
    if (_disposed) {
      return;
    }
    _epoch++;
    _profile = api.Profile.fromBuffer(profile.writeToBuffer());
    _correlation = null;
    _result = null;
    _targets = [];
    _ready = false;
    _busy = false;
    await refresh();
  }

  Future<void> refresh() async {
    if (_disposed || _busy || _profile == null) {
      return;
    }
    final epoch = _epoch;
    _busy = true;
    _ready = false;
    _result = null;
    _problem = '';
    _emit();
    try {
      final runtime = await _client.runtimeInfo(_timeout).timeout(_timeout);
      if (!_current(epoch)) {
        return;
      }
      if (runtime.contractSha256 != _digest ||
          runtime.instanceId != _instance ||
          runtime.protocol != 'endlessnet-client-ipc' ||
          runtime.ipcVersion != 0 ||
          (runtime.callerAccess != api.Access.ACCESS_OWNER &&
              runtime.callerAccess != api.Access.ACCESS_ADMINISTRATOR)) {
        throw ClientCallFailure.protocol();
      }
      final snapshot = await _client.status(_timeout).timeout(_timeout);
      if (!_current(epoch)) {
        return;
      }
      if (snapshot.activeProfileId != _profile!.id ||
          snapshot.accountId.isEmpty ||
          snapshot.network.id.isEmpty ||
          snapshot.nodeId.isEmpty) {
        throw ClientCallFailure.protocol();
      }
      final stored = await _store.readRevocation(
        _profile!.id,
        _profile!.controlOrigin,
      );
      if (!_current(epoch)) {
        return;
      }
      _correlation = stored;
      final list = await _client
          .revocationTargets(
            api.ListNodeRevocationTargetsRequest(
              profile: api.ProfileRef(profileId: _profile!.id),
            ),
            _timeout,
          )
          .timeout(_timeout);
      if (!_current(epoch)) {
        return;
      }
      if (!list.hasMetadata() ||
          list.metadata.instanceId != _instance ||
          BigInt.parse(list.metadata.revision.toStringUnsigned()) <=
              BigInt.zero) {
        throw ClientCallFailure.protocol();
      }
      final seen = <String>{};
      for (final target in list.targets) {
        if (target.accountId != snapshot.accountId ||
            target.networkId != snapshot.network.id ||
            target.nodeId.isEmpty ||
            !seen.add(target.nodeId) ||
            BigInt.parse(target.networkRevision.toStringUnsigned()) <=
                BigInt.zero) {
          throw ClientCallFailure.protocol();
        }
      }
      _metadata = list.metadata;
      _targets = list.targets
          .map((t) => api.NodeRevocationTarget.fromBuffer(t.writeToBuffer()))
          .toList();
      _ready = true;
      if (stored != null) {
        await _query(epoch);
      }
    } catch (_) {
      if (_current(epoch)) {
        _ready = false;
        _targets = [];
        _problem = 'Не удалось получить текущее состояние отзыва. Проверьте подключение и права.';
      }
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _emit();
      }
    }
  }

  Future<void> revoke(api.NodeRevocationTarget selected) async {
    if (!canChoose ||
        !_targets.any(
          (t) => listEquals(t.writeToBuffer(), selected.writeToBuffer()),
        )) {
      return;
    }
    final epoch = _epoch;
    _busy = true;
    _problem = '';
    _result = null;
    _emit();
    try {
      final record = RevocationCorrelation(
        profileId: _profile!.id,
        controlOrigin: _profile!.controlOrigin,
        commandId: _commandId(),
        target: selected,
      );
      await _store.saveRevocation(record);
      if (!_current(epoch)) {
        return;
      }
      _correlation =
          record; // Only durable correlation permits the first mutation.
      await _send(epoch);
    } catch (_) {
      if (_current(epoch)) {
        _problem = 'Не удалось сохранить или проверить исходную команду. Новый отзыв не подтверждён.';
      }
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _emit();
      }
    }
  }

  Future<void> retryOriginal() async {
    if (_disposed || _busy || !_ready || _correlation == null) {
      return;
    }
    final epoch = _epoch;
    _busy = true;
    _problem = '';
    _emit();
    try {
      await _send(epoch);
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _emit();
      }
    }
  }

  Future<void> queryOriginal() async {
    if (_disposed || _busy || !_ready || _correlation == null) {
      return;
    }
    final epoch = _epoch;
    _busy = true;
    _emit();
    try {
      await _query(epoch);
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _emit();
      }
    }
  }

  Future<void> _send(int epoch) async {
    final c = _correlation!;
    try {
      final response = await _client
          .revokeNode(
            api.RevokeNodeAccessRequest(
              profile: api.ProfileRef(profileId: c.profileId),
              commandId: c.commandId,
              target: c.target,
              mutation: api.MutationContext(
                expectedInstanceId: _metadata!.instanceId,
                expectedRevision: _metadata!.revision,
              ),
            ),
            _timeout,
          )
          .timeout(_timeout);
      if (_current(epoch)) {
        await _accept(response, epoch);
      }
    } on ClientCallFailure catch (error) {
      if (!_current(epoch)) {
        return;
      }
      _result = null;
      if (error.transportCode == grpc.StatusCode.aborted &&
          error.reasonKey == 'client.revocation.command_conflict') {
        try {
          await _store.saveRevocation(c.resolve());
          if (_current(epoch)) {
            _correlation = c.resolve();
          }
        } catch (_) {
          /* Keep the unresolved original if the flush failed. */
        }
        _problem =
            'Состояние изменилось. Обновите список и подтвердите отзыв заново.';
      } else {
        _problem = 'Исход команды неизвестен. Проверьте исходную команду; повтор сохранит ту же регистрацию.';
      }
    } catch (_) {
      if (_current(epoch)) {
        _result = null;
        _problem = 'Исход команды неизвестен. Проверьте исходную команду; повтор сохранит ту же регистрацию.';
      }
    }
  }

  Future<void> _query(int epoch) async {
    final c = _correlation!;
    try {
      final response = await _client
          .nodeRevocation(
            api.GetNodeRevocationRequest(
              profile: api.ProfileRef(profileId: c.profileId),
              commandId: c.commandId,
            ),
            _timeout,
          )
          .timeout(_timeout);
      if (_current(epoch)) {
        await _accept(response, epoch);
      }
    } catch (_) {
      if (_current(epoch)) {
        _result = null;
        _problem =
            'Текущий исход не подтверждён. Сохранённая команда не заменена.';
      }
    }
  }

  Future<void> _accept(api.NodeRevocationResult result, int epoch) async {
    final c = _correlation!;
    if (result.profileId != c.profileId ||
        result.commandId != c.commandId ||
        !result.hasTarget() ||
        !listEquals(result.target.writeToBuffer(), c.target.writeToBuffer())) {
      throw ClientCallFailure.protocol();
    }
    if (result.phase == api.NodeRevocationPhase.NODE_REVOCATION_PHASE_UNKNOWN) {
      if (result.hasAcceptedAt() ||
          result.hasEnforceBy() ||
          result.committedNetworkRevision.toStringUnsigned() != '0') {
        throw ClientCallFailure.protocol();
      }
      _result = api.NodeRevocationResult.fromBuffer(result.writeToBuffer());
      _problem = 'Исход команды неизвестен. Проверьте исходную команду.';
      return;
    }
    if (result.phase !=
            api.NodeRevocationPhase.NODE_REVOCATION_PHASE_ACCEPTED ||
        !result.hasAcceptedAt() ||
        !result.hasEnforceBy() ||
        result.enforceBy.toDateTime().difference(
              result.acceptedAt.toDateTime(),
            ) !=
            const Duration(seconds: 300) ||
        BigInt.parse(result.committedNetworkRevision.toStringUnsigned()) <=
            BigInt.parse(c.target.networkRevision.toStringUnsigned())) {
      throw ClientCallFailure.protocol();
    }
    await _store.saveRevocation(c.resolve());
    if (_current(epoch)) {
      _correlation = c.resolve();
      _result = api.NodeRevocationResult.fromBuffer(result.writeToBuffer());
      _problem = '';
    }
  }

  static String _uuid() {
    final random = Random.secure();
    final b = List.generate(16, (_) => random.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}
