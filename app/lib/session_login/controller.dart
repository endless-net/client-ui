import 'dart:async';
import 'dart:math';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart' as grpc;

import '../client/browser_consent.dart';
import '../client/call_failure.dart';
import '../client/session_login_client.dart';
import '../client/session_login_correlation.dart';

final class SessionLoginController extends ChangeNotifier {
  SessionLoginController({
    required this._client,
    required this._store,
    required String expectedContractSha256,
    required String expectedInstanceId,
    required Duration timeout,
    required this._now,
    String Function()? requestId,
    this.automaticPolling = true,
  }) : _digest = expectedContractSha256,
       _instance = expectedInstanceId,
       _timeout = timeout,
       _requestId = requestId ?? _uuid {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(_digest) ||
        _digest == '0' * 64 ||
        _instance.isEmpty ||
        timeout <= Duration.zero ||
        timeout > const Duration(seconds: 30)) {
      throw ArgumentError('Invalid session login configuration');
    }
  }
  final SessionLoginClient _client;
  final SessionLoginCorrelationStore _store;
  final String _digest, _instance;
  final Duration _timeout;
  final DateTime Function() _now;
  final String Function() _requestId;
  final bool automaticPolling;
  api.Profile? _profile;
  api.SnapshotMetadata? _metadata;
  api.Session? _session;
  api.SessionLoginAttempt? _attempt;
  SessionLoginCorrelation? _correlation;
  String _node = '', _problem = '';
  bool _busy = false, _ready = false, _disposed = false, _registered = false;
  int _epoch = 0;
  Timer? _timer;

  bool get busy => _busy;
  bool get registered => _registered;
  String get problem => _problem;
  api.SessionLoginAttempt? get attempt => _attempt == null
      ? null
      : api.SessionLoginAttempt.fromBuffer(_attempt!.writeToBuffer());
  bool get sessionActive =>
      _ready &&
      _session?.state == api.SessionState.SESSION_STATE_ACTIVE &&
      _session!.hasExpiresAt() &&
      _now().isBefore(_session!.expiresAt.toDateTime());
  DateTime? get activeUntil =>
      sessionActive ? _session!.expiresAt.toDateTime() : null;

  bool get sessionExpired =>
      _ready &&
      (_session?.state == api.SessionState.SESSION_STATE_EXPIRED ||
          _session?.state == api.SessionState.SESSION_STATE_ACTIVE &&
              _session!.hasExpiresAt() &&
              !_now().isBefore(_session!.expiresAt.toDateTime()));
  bool _connectionLoginRequired = false;
  bool get connectionLoginRequired => _connectionLoginRequired;

  void observeConnectionLoginRequired(bool required) {
    if (_connectionLoginRequired == required) return;
    _connectionLoginRequired = required;
    _emit();
  }

  bool get canStart =>
      _ready &&
      !_busy &&
      (!sessionActive || connectionLoginRequired) &&
      (_correlation == null ||
          _attempt != null &&
              !_now().isBefore(_attempt!.deadline.toDateTime()));
  bool get canRetryOriginal =>
      _ready && !_busy && _correlation != null && _attempt == null;
  bool _current(int epoch) => !_disposed && epoch == _epoch;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  api.ProfileRef get _ref => api.ProfileRef(profileId: _profile!.id);

  Uri? get browserAction {
    final a = _attempt;
    if (!_ready ||
        _busy ||
        a == null ||
        a.phase !=
            api.SessionLoginPhase.SESSION_LOGIN_PHASE_AWAITING_CONFIRMATION ||
        !a.hasBrowserAction() ||
        !a.browserAction.hasExpiresAt() ||
        !_now().isBefore(a.deadline.toDateTime()) ||
        !_now().isBefore(a.browserAction.expiresAt.toDateTime())) {
      return null;
    }
    final url = browserConsentUri(
      a.browserAction.verificationUrl,
      _profile!.controlOrigin,
    );
    return url != null && url.toString().length <= 8192 ? url : null;
  }

  Future<void> bind(api.Profile profile) async {
    if (_disposed) return;
    _epoch++;
    _timer?.cancel();
    _profile = api.Profile.fromBuffer(profile.writeToBuffer());
    _correlation = null;
    _attempt = null;
    _metadata = null;
    _session = null;
    _node = '';
    _busy = false;
    _registered = false;
    await refresh();
  }

  void _checkMetadata(api.SnapshotMetadata value) {
    if (value.instanceId != _instance ||
        BigInt.parse(value.revision.toStringUnsigned()) <= BigInt.zero ||
        _metadata != null &&
            BigInt.parse(value.revision.toStringUnsigned()) <
                BigInt.parse(_metadata!.revision.toStringUnsigned())) {
      throw ClientCallFailure.protocol();
    }
    _metadata = api.SnapshotMetadata.fromBuffer(value.writeToBuffer());
  }

  Future<void> _readContext(int epoch) async {
    final runtime = await _client.runtimeInfo(_timeout).timeout(_timeout);
    if (!_current(epoch)) return;
    final capability = runtime.capabilities.where(
      (c) => c.capability == api.Capability.CAPABILITY_SESSION_LOGIN,
    );
    if (runtime.instanceId != _instance ||
        runtime.contractSha256 != _digest ||
        runtime.protocol != 'endlessnet-client-ipc' ||
        runtime.ipcVersion != 0 ||
        runtime.callerAccess != api.Access.ACCESS_OWNER ||
        capability.length != 1 ||
        capability.single.restriction.availability !=
            api.Availability.AVAILABILITY_AVAILABLE) {
      throw ClientCallFailure.protocol();
    }
    final status = await _client.status(_timeout).timeout(_timeout);
    if (!_current(epoch)) return;
    if (!status.hasMetadata() ||
        status.metadata.instanceId != _instance ||
        status.activeProfileId != _profile!.id ||
        status.nodeId.isEmpty) {
      throw ClientCallFailure.protocol();
    }
    if (_node.isNotEmpty && _node != status.nodeId) {
      throw ClientCallFailure.protocol();
    }
    _node = status.nodeId;
    _registered = true;
    final response = await _client
        .session(api.GetSessionRequest(profile: _ref), _timeout)
        .timeout(_timeout);
    if (!_current(epoch)) return;
    if (!response.hasSession() || !response.hasMetadata()) {
      throw ClientCallFailure.protocol();
    }
    _checkMetadata(response.metadata);
    _session = api.Session.fromBuffer(response.session.writeToBuffer());
    _correlation = await _store.readSessionLogin(
      _profile!.id,
      _profile!.controlOrigin,
    );
    if (!_current(epoch)) return;
    if (_correlation != null && _correlation!.nodeId != _node) {
      throw ClientCallFailure.protocol();
    }
    if (_correlation == null && response.hasLoginAttempt()) {
      final a = response.loginAttempt;
      _validateAttempt(a, a.requestId);
      final c = SessionLoginCorrelation(
        profileId: _profile!.id,
        controlOrigin: _profile!.controlOrigin,
        nodeId: _node,
        requestId: a.requestId,
      );
      await _store.saveSessionLogin(c);
      if (!_current(epoch)) return;
      _correlation = c;
    }
    if (_correlation != null) {
      if (response.hasLoginAttempt() &&
          response.loginAttempt.requestId == _correlation!.requestId) {
        _accept(response.loginAttempt);
      } else {
        var originalFound = false;
        try {
          final a = await _client
              .sessionLogin(
                api.GetSessionLoginRequest(
                  profile: _ref,
                  requestId: _correlation!.requestId,
                ),
                _timeout,
              )
              .timeout(_timeout);
          originalFound = true;
          if (!_current(epoch)) return;
          _accept(a);
          if (response.hasLoginAttempt() &&
              !_now().isBefore(a.deadline.toDateTime()) &&
              response.loginAttempt.hasCreatedAt() &&
              response.loginAttempt.createdAt.toDateTime().isAfter(
                a.createdAt.toDateTime(),
              )) {
            // A known older receipt may be superseded by another explicit caller.
            // NotFound never reaches this path: an unacknowledged local UUID stays selected.
            final fresh = await _client
                .session(api.GetSessionRequest(profile: _ref), _timeout)
                .timeout(_timeout);
            if (!_current(epoch)) return;
            if (!fresh.hasMetadata() ||
                !fresh.hasSession() ||
                !fresh.hasLoginAttempt() ||
                fresh.loginAttempt.requestId !=
                    response.loginAttempt.requestId ||
                !fresh.loginAttempt.createdAt.toDateTime().isAfter(
                  a.createdAt.toDateTime(),
                )) {
              throw ClientCallFailure.protocol();
            }
            _checkMetadata(fresh.metadata);
            _validateAttempt(fresh.loginAttempt, fresh.loginAttempt.requestId);
            final selected = SessionLoginCorrelation(
              profileId: _profile!.id,
              controlOrigin: _profile!.controlOrigin,
              nodeId: _node,
              requestId: fresh.loginAttempt.requestId,
            );
            await _store.saveSessionLogin(selected);
            if (!_current(epoch)) return;
            _correlation = selected;
            _attempt = null;
            _session = api.Session.fromBuffer(fresh.session.writeToBuffer());
            _accept(fresh.loginAttempt);
          }
        } on ClientCallFailure catch (e) {
          if (e.transportCode != grpc.StatusCode.notFound || originalFound) {
            rethrow;
          }
          if (_current(epoch)) {
            _attempt = null;
            _problem = 'Сохранённый запрос ещё не найден. Можно повторить тот же запрос.';
          }
        }
      }
    }
  }

  Future<void> refresh() async {
    if (_disposed || _busy || _profile == null) return;
    final epoch = _epoch;
    _timer?.cancel();
    _busy = true;
    _ready = false;
    _problem = '';
    _emit();
    try {
      await _readContext(epoch);
      if (_current(epoch)) _ready = true;
    } on ClientCallFailure {
      if (_current(epoch)) {
        _ready = false;
        _problem = 'Не удалось проверить сессию. Повторите проверку подключения к службе.';
      }
    } catch (_) {
      if (_current(epoch)) {
        _problem = 'Не удалось прочитать сохранённый вход. Запрос не заменён.';
      }
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _emit();
        _schedule();
      }
    }
  }

  Future<void> start({bool retryOriginal = false}) async {
    if (retryOriginal ? !canRetryOriginal : !canStart) return;
    final epoch = _epoch;
    _busy = true;
    _timer?.cancel();
    _problem = '';
    _emit();
    try {
      // Fresh authority/CAS before a mutation; no automatic mutation on reopen.
      await _readContext(epoch);
      if (!_current(epoch)) return;
      if (!retryOriginal &&
          ((sessionActive && !connectionLoginRequired) ||
              _correlation != null &&
                  (_attempt == null ||
                      _now().isBefore(_attempt!.deadline.toDateTime())))) {
        return;
      }
      if (!retryOriginal) {
        final c = SessionLoginCorrelation(
          profileId: _profile!.id,
          controlOrigin: _profile!.controlOrigin,
          nodeId: _node,
          requestId: _requestId(),
        );
        if (c.requestId == _correlation?.requestId) {
          throw ClientCallFailure.protocol();
        }
        await _store.saveSessionLogin(c);
        if (!_current(epoch)) return;
        _correlation = c;
        _attempt = null;
      } else {
        await _store.saveSessionLogin(_correlation!);
        if (!_current(epoch)) return;
      }
      final result = await _client
          .startSessionLogin(
            api.StartSessionLoginRequest(
              profile: _ref,
              requestId: _correlation!.requestId,
              mutation: api.MutationContext(
                expectedInstanceId: _metadata!.instanceId,
                expectedRevision: _metadata!.revision,
              ),
            ),
            _timeout,
          )
          .timeout(_timeout);
      if (_current(epoch)) {
        _accept(result);
        _ready = true;
      }
    } catch (_) {
      if (_current(epoch)) {
        _ready = false;
        _problem = 'Исход входа не подтверждён. Проверьте сохранённый запрос; новый автоматически не создаётся.';
      }
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _emit();
        _schedule();
      }
    }
  }

  void _validateAttempt(api.SessionLoginAttempt a, String request) {
    if (a.requestId != request ||
        a.profileId != _profile!.id ||
        a.attemptId.isEmpty ||
        !a.hasMetadata() ||
        !a.hasCreatedAt() ||
        !a.hasDeadline() ||
        a.deadline.toDateTime().difference(a.createdAt.toDateTime()) <=
            Duration.zero ||
        a.deadline.toDateTime().difference(a.createdAt.toDateTime()) >
            const Duration(minutes: 10) ||
        a.phase == api.SessionLoginPhase.SESSION_LOGIN_PHASE_UNSPECIFIED ||
        !api.SessionLoginPhase.values.contains(a.phase) ||
        a.pollAfterSeconds > 30 ||
        a.phase == api.SessionLoginPhase.SESSION_LOGIN_PHASE_SUCCEEDED &&
            (!a.hasSession() ||
                !a.session.hasExpiresAt() ||
                !const [
                  api.SessionState.SESSION_STATE_ACTIVE,
                  api.SessionState.SESSION_STATE_EXPIRED,
                ].contains(a.session.state))) {
      throw ClientCallFailure.protocol();
    }
  }

  void _accept(api.SessionLoginAttempt a) {
    _validateAttempt(a, _correlation!.requestId);
    final old = _attempt;
    if (old != null &&
        old.requestId == a.requestId &&
        (old.attemptId != a.attemptId ||
            old.createdAt != a.createdAt ||
            old.deadline != a.deadline)) {
      throw ClientCallFailure.protocol();
    }
    _checkMetadata(a.metadata);
    _attempt = api.SessionLoginAttempt.fromBuffer(a.writeToBuffer());
  }

  void _schedule() {
    if (!automaticPolling || !_ready || _disposed) return;
    final now = _now();
    Duration? delay;
    if (sessionActive) {
      delay = _session!.expiresAt.toDateTime().difference(now);
    }
    final a = _attempt;
    if (a != null && a.pollAfterSeconds > 0) {
      final remaining = a.deadline.toDateTime().difference(now);
      if (remaining > Duration.zero) {
        final interval = Duration(seconds: a.pollAfterSeconds);
        final poll = interval < remaining ? interval : remaining;
        if (delay == null || poll < delay) delay = poll;
      }
    }
    if (delay != null) _timer = Timer(delay, refresh);
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
    _timer?.cancel();
    super.dispose();
  }
}
