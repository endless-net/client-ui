import 'dart:async';
import 'dart:math';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/foundation.dart';

import '../client/enrollment_client.dart';
import '../client/call_failure.dart';
import '../client/correlation_journal.dart';

enum EnrollmentLinkState { detached, loading, available, unavailable, mismatch }

final class EnrollmentController extends ChangeNotifier {
  EnrollmentController({
    required this._client,
    required this._store,
    required String expectedContractSha256,
    required this._now,
    required Duration callTimeout,
    required Duration recoveryPollInterval,
    String Function()? requestId,
    this.automaticPolling = true,
  }) : _digest = expectedContractSha256,
       _timeout = callTimeout,
       _recoveryPoll = recoveryPollInterval,
       _requestId = requestId ?? _uuid {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(_digest) ||
        _digest == '0' * 64 ||
        callTimeout <= Duration.zero ||
        callTimeout > const Duration(seconds: 30) ||
        recoveryPollInterval < const Duration(seconds: 1) ||
        recoveryPollInterval > const Duration(seconds: 30)) {
      throw ArgumentError('Invalid UI Client configuration');
    }
  }

  final EnrollmentClient _client;
  final CorrelationStore _store;
  final String _digest;
  final DateTime Function() _now;
  final Duration _timeout;
  final Duration _recoveryPoll;
  final String Function() _requestId;
  final bool automaticPolling;
  api.Profile? _profile;
  api.RuntimeInfo? _runtime;
  api.Status? _status;
  api.SnapshotMetadata? _metadata;
  api.EnrollmentAttempt? _attempt;
  EnrollmentCorrelation? _correlation;
  List<api.EnrollmentTarget> _targets = [];
  api.SnapshotMetadata? _targetMetadata;
  String _nextTargetPage = '';
  int _targetPageSize = 0;
  Timer? _timer;
  int _epoch = 0;
  bool _disposed = false;
  bool _busy = false;
  bool _rejected = false;
  api.Failure? _failure;
  EnrollmentLinkState _link = EnrollmentLinkState.detached;
  String _reason = '';

  api.Profile? get profile => _profile == null
      ? null
      : api.Profile.fromBuffer(_profile!.writeToBuffer());
  EnrollmentLinkState get link => _link;
  String get reasonKey => _reason;
  bool get busy => _busy;
  bool get callRejected => _rejected;
  api.Failure? get failure => _failure == null
      ? null
      : api.Failure.fromBuffer(_failure!.writeToBuffer());
  bool get uncertain =>
      _link == EnrollmentLinkState.unavailable ||
      _attempt?.certainty ==
          api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_UNCERTAIN ||
      (_attempt != null &&
          !_terminal(_attempt!.phase) &&
          !_now().isBefore(_waitingDeadline!));
  api.EnrollmentAttempt? get currentAttempt => _attempt == null
      ? null
      : api.EnrollmentAttempt.fromBuffer(_attempt!.writeToBuffer());
  EnrollmentCorrelation? get correlation => _correlation;
  api.SnapshotMetadata? get localSnapshot => _metadata == null
      ? null
      : api.SnapshotMetadata.fromBuffer(_metadata!.writeToBuffer());

  List<api.EnrollmentTarget> get targets => List.unmodifiable(
    _targets.map((t) => api.EnrollmentTarget.fromBuffer(t.writeToBuffer())),
  );
  bool get hasNextTargetPage => _nextTargetPage.isNotEmpty;
  bool get canLoadTargets =>
      _actionReady &&
      _attempt!.certainty ==
          api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_KNOWN &&
      _attempt!.phase == api.EnrollmentPhase.ENROLLMENT_PHASE_CHOOSING_CONTEXT;
  bool get canCancel => _actionReady && !_terminal(_attempt!.phase);
  bool get _actionReady =>
      !_disposed &&
      !_busy &&
      !_rejected &&
      _link == EnrollmentLinkState.available &&
      _attempt != null &&
      _metadata != null &&
      _correlation != null &&
      _now().isBefore(_waitingDeadline!);

  api.Restriction? get enrollmentRestriction {
    final caps = _runtime?.capabilities
        .where((c) => c.capability == api.Capability.CAPABILITY_ENROLLMENT)
        .toList();
    if (caps == null || caps.length != 1) return null;
    return api.Restriction.fromBuffer(caps.single.restriction.writeToBuffer());
  }

  bool get canEnroll =>
      !_disposed &&
      !_rejected &&
      !_busy &&
      _link == EnrollmentLinkState.available &&
      _correlation == null &&
      enrollmentRestriction?.availability ==
          api.Availability.AVAILABILITY_AVAILABLE;

  bool get registeredConfirmed {
    final a = _attempt;
    final s = _status;
    return !_rejected &&
        _link == EnrollmentLinkState.available &&
        a != null &&
        s != null &&
        a.phase == api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERED &&
        a.certainty == api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_KNOWN &&
        a.nodeId.isNotEmpty &&
        a.accountId.isNotEmpty &&
        a.networkId.isNotEmpty &&
        s.activeProfileId == a.profileId &&
        s.nodeId == a.nodeId &&
        s.accountId == a.accountId &&
        s.network.id == a.networkId &&
        s.metadata.instanceId == a.metadata.instanceId &&
        _revisionAtLeast(s.metadata, a.metadata);
  }

  // Server URL не открывается автоматически и не принимается из текста ошибки.
  Uri? get browserAction {
    final a = _attempt;
    final p = _profile;
    if (_disposed ||
        _rejected ||
        _link != EnrollmentLinkState.available ||
        a == null ||
        p == null ||
        a.certainty != api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_KNOWN ||
        a.phase != api.EnrollmentPhase.ENROLLMENT_PHASE_AWAITING_LOGIN ||
        !a.hasBrowserAction() ||
        !a.browserAction.hasExpiresAt() ||
        !_now().isBefore(a.browserAction.expiresAt.toDateTime()) ||
        !_now().isBefore(_waitingDeadline!)) {
      return null;
    }
    final url = Uri.tryParse(a.browserAction.verificationUrl);
    if (url == null ||
        url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        url.hasQuery ||
        url.origin != p.controlOrigin) {
      return null;
    }
    return url;
  }

  Future<T> _call<T>(Future<T> call) => call.timeout(_timeout);
  bool _current(int epoch) => !_disposed && epoch == _epoch;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> bind(api.Profile profile) async {
    if (_disposed) return;
    final previousProfile = _profile;
    final previousMetadata = _metadata;
    final epoch = ++_epoch;
    _timer?.cancel();
    _timer = null;
    _busy = true;
    final bound = api.Profile.fromBuffer(profile.writeToBuffer());
    _profile = bound;
    _runtime = null;
    _metadata = null;
    _attempt = null;
    _status = null;
    _correlation = null;
    _clearTargets();
    _rejected = false;
    _failure = null;
    _link = EnrollmentLinkState.loading;
    _reason = '';
    _emit();
    try {
      final origin = Uri.tryParse(bound.controlOrigin);
      if (bound.id.isEmpty ||
          origin == null ||
          origin.scheme != 'https' ||
          origin.userInfo.isNotEmpty ||
          origin.hasQuery ||
          origin.hasFragment ||
          origin.origin != bound.controlOrigin) {
        throw StateError('profile');
      }
      final runtime = await _call(_client.runtimeInfo(_timeout));
      if (!_current(epoch)) return;
      if (runtime.contractSha256 != _digest ||
          runtime.instanceId.isEmpty ||
          runtime.protocol != 'endlessnet-client-ipc' ||
          runtime.ipcVersion != 0) {
        _link = EnrollmentLinkState.mismatch;
        _reason = 'ui.contract_mismatch';
        return;
      }
      _runtime = api.RuntimeInfo.fromBuffer(runtime.writeToBuffer());
      final status = await _call(_client.status(_timeout));
      if (!_current(epoch)) return;
      if (!_validMetadata(status.metadata)) throw StateError('snapshot');
      if (previousProfile?.id == bound.id &&
          previousProfile?.controlOrigin == bound.controlOrigin &&
          previousMetadata?.instanceId == runtime.instanceId &&
          !_revisionAtLeast(status.metadata, previousMetadata!)) {
        throw StateError('snapshot rollback');
      }
      _status = api.Status.fromBuffer(status.writeToBuffer());
      _metadata = api.SnapshotMetadata.fromBuffer(
        status.metadata.writeToBuffer(),
      );
      final stored = await _store.read(bound.id, bound.controlOrigin);
      if (!_current(epoch)) return;
      if (stored != null &&
          (stored.profileId != bound.id ||
              stored.controlOrigin != bound.controlOrigin ||
              !_validUuid(stored.requestId))) {
        throw StateError('correlation');
      }
      _correlation = stored;
      _link = EnrollmentLinkState.available;
      if (stored != null) {
        await _recover(epoch);
      } else if (enrollmentRestriction?.availability !=
          api.Availability.AVAILABILITY_AVAILABLE) {
        _reason = enrollmentRestriction?.reasonKey ?? 'ui.unsupported';
      }
    } on CorrelationStoreFailure {
      if (_current(epoch)) {
        _link = EnrollmentLinkState.unavailable;
        _reason = 'ui.correlation_store_failed';
      }
    } on ClientCallFailure catch (error) {
      if (_current(epoch)) {
        if (error.definiteRejection) {
          _reject(error);
        } else if (_correlation != null) {
          await _lost(epoch);
        } else {
          _link = EnrollmentLinkState.unavailable;
          _reason = 'ui.client_unavailable';
        }
      }
    } catch (_) {
      if (_current(epoch)) {
        if (_correlation != null) {
          await _lost(epoch);
        } else {
          _link = EnrollmentLinkState.unavailable;
          _reason = 'ui.client_unavailable';
        }
      }
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _emit();
        _schedule(epoch);
      }
    }
  }

  Future<void> start(String hostname, api.EnrollmentMode mode) async {
    if (!canEnroll ||
        hostname.trim().isEmpty ||
        mode == api.EnrollmentMode.ENROLLMENT_MODE_UNSPECIFIED) {
      return;
    }
    final epoch = _epoch;
    _busy = true;
    _reason = '';
    _timer?.cancel();
    _emit();
    bool saved = false;
    try {
      final record = EnrollmentCorrelation(
        profileId: _profile!.id,
        controlOrigin: _profile!.controlOrigin,
        requestId: _requestId(),
        hostname: hostname,
        mode: mode,
      );
      if (!_validUuid(record.requestId)) throw StateError('request UUID');
      await _store.save(record);
      if (!_current(epoch)) return;
      saved = true;
      _correlation = record;
      final meta = _metadata!;
      final result = await _call(
        _client.enroll(
          api.EnrollRequest(
            mutation: api.MutationContext(
              expectedInstanceId: meta.instanceId,
              expectedRevision: meta.revision,
            ),
            profile: api.ProfileRef(profileId: record.profileId),
            mode: record.mode,
            hostname: record.hostname,
            requestId: record.requestId,
          ),
          _timeout,
        ),
      );
      if (_current(epoch)) await _accept(result, epoch);
    } on CorrelationStoreFailure {
      if (_current(epoch)) {
        _clearTargets();
        _link = EnrollmentLinkState.unavailable;
        _reason = 'ui.correlation_save_failed';
      }
    } on ClientCallFailure catch (error) {
      if (_current(epoch)) {
        if (!saved) {
          _reason = 'ui.correlation_save_failed';
        } else if (error.definiteRejection) {
          _reject(error);
        } else {
          await _lost(epoch);
        }
      }
    } catch (_) {
      if (_current(epoch)) {
        if (saved) {
          await _lost(epoch);
        } else {
          _reason = 'ui.correlation_save_failed';
        }
      }
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _emit();
        _schedule(epoch);
      }
    }
  }

  Future<void> refresh() => _refresh();

  Future<void> _refresh({DateTime? automaticUntil}) async {
    if (_disposed || _busy || _profile == null) return;
    if (_correlation == null || _runtime == null) {
      await bind(_profile!);
      return;
    }
    final epoch = _epoch;
    _busy = true;
    _timer?.cancel();
    _emit();
    try {
      await _recover(epoch, automaticUntil: automaticUntil);
    } on CorrelationStoreFailure {
      if (_current(epoch)) {
        _clearTargets();
        _link = EnrollmentLinkState.unavailable;
        _reason = 'ui.correlation_save_failed';
      }
    } on ClientCallFailure catch (error) {
      if (_current(epoch)) {
        if (error.definiteRejection) {
          _reject(error);
        } else {
          await _lost(epoch);
        }
      }
    } catch (_) {
      if (_current(epoch)) await _lost(epoch);
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _emit();
        _schedule(epoch);
      }
    }
  }

  void _clearTargets() {
    _targets = [];
    _targetMetadata = null;
    _nextTargetPage = '';
    _targetPageSize = 0;
  }

  // One explicit page. No auto traversal, account guessing or token rewriting.
  Future<void> loadTargets({int pageSize = 100, bool next = false}) async {
    if (!canLoadTargets ||
        pageSize < 1 ||
        pageSize > 500 ||
        (next && (_nextTargetPage.isEmpty || pageSize != _targetPageSize))) {
      return;
    }
    final epoch = _epoch;
    final prior = _targetMetadata;
    final token = next ? _nextTargetPage : '';
    _busy = true;
    _timer?.cancel();
    _clearTargets();
    _emit();
    try {
      final response = await _call(
        _client.targets(
          api.ListEnrollmentTargetsRequest(
            profile: api.ProfileRef(profileId: _correlation!.profileId),
            attemptId: _attempt!.attemptId,
            page: api.PageRequest(pageSize: pageSize, pageToken: token),
          ),
          _timeout,
        ),
      );
      if (!_current(epoch)) return;
      final meta = response.metadata;
      if (!response.hasMetadata() ||
          !response.page.hasMetadata() ||
          !_validMetadata(meta) ||
          !_sameRevision(meta, response.page.metadata) ||
          (next && (prior == null || !_sameRevision(meta, prior))) ||
          response.targets.length > pageSize ||
          (response.page.nextPageToken.isNotEmpty &&
              response.page.nextPageToken == token)) {
        throw ClientCallFailure.protocol();
      }
      final ids = <(String, String)>{};
      for (final target in response.targets) {
        if (target.accountId.isEmpty ||
            target.networkId.isEmpty ||
            !ids.add((target.accountId, target.networkId))) {
          throw ClientCallFailure.protocol();
        }
      }
      _targets = response.targets
          .map((t) => api.EnrollmentTarget.fromBuffer(t.writeToBuffer()))
          .toList();
      _metadata = api.SnapshotMetadata.fromBuffer(meta.writeToBuffer());
      _targetMetadata = api.SnapshotMetadata.fromBuffer(meta.writeToBuffer());
      _nextTargetPage = response.page.nextPageToken;
      _targetPageSize = pageSize;
      _reason = '';
    } on ClientCallFailure catch (error) {
      if (_current(epoch)) {
        if (error.definiteRejection) {
          _reject(error);
        } else {
          await _lost(epoch);
        }
      }
    } catch (_) {
      if (_current(epoch)) await _lost(epoch);
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _emit();
        _schedule(epoch);
      }
    }
  }

  bool canSelect(String accountId, String networkId) =>
      canLoadTargets &&
      _targetMetadata != null &&
      _sameRevision(_targetMetadata!, _metadata!) &&
      _targets.any(
        (t) =>
            t.accountId == accountId &&
            t.networkId == networkId &&
            t.restriction.availability ==
                api.Availability.AVAILABILITY_AVAILABLE,
      );

  api.MutationContext _mutation() => api.MutationContext(
    expectedInstanceId: _metadata!.instanceId,
    expectedRevision: _metadata!.revision,
  );

  Future<void> selectTarget(String accountId, String networkId) async {
    if (!canSelect(accountId, networkId)) return;
    final request = api.SelectEnrollmentTargetRequest(
      mutation: _mutation(),
      profile: api.ProfileRef(profileId: _correlation!.profileId),
      attemptId: _attempt!.attemptId,
      accountId: accountId,
      networkId: networkId,
    );
    await _runAction(() async {
      final result = await _client.select(request, _timeout);
      if (result.accountId != accountId || result.networkId != networkId) {
        throw ClientCallFailure.protocol();
      }
      return result;
    });
  }

  Future<void> cancelAttempt() async {
    if (!canCancel) return;
    final request = api.CancelEnrollmentAttemptRequest(
      mutation: _mutation(),
      profile: api.ProfileRef(profileId: _correlation!.profileId),
      attemptId: _attempt!.attemptId,
    );
    await _runAction(() => _client.cancel(request, _timeout));
  }

  Future<void> _runAction(
    Future<api.EnrollmentAttempt> Function() action,
  ) async {
    final epoch = _epoch;
    _busy = true;
    _timer?.cancel();
    _clearTargets();
    _emit();
    try {
      final result = await _call(action());
      if (_current(epoch)) await _accept(result, epoch);
    } on CorrelationStoreFailure {
      if (_current(epoch)) {
        _clearTargets();
        _link = EnrollmentLinkState.unavailable;
        _reason = 'ui.correlation_save_failed';
      }
    } on ClientCallFailure catch (error) {
      if (_current(epoch)) {
        if (error.definiteRejection) {
          _reject(error);
        } else {
          await _lost(epoch);
        }
      }
    } catch (_) {
      if (_current(epoch)) await _lost(epoch);
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _emit();
        _schedule(epoch);
      }
    }
  }

  static bool _sameRevision(api.SnapshotMetadata a, api.SnapshotMetadata b) =>
      a.instanceId == b.instanceId &&
      a.revision.toStringUnsigned() == b.revision.toStringUnsigned();

  Duration _readBudget(DateTime? until) {
    if (until == null) return _timeout;
    final remaining = until.difference(_now());
    if (remaining <= Duration.zero) {
      throw TimeoutException('UI read budget expired');
    }
    return remaining < _timeout ? remaining : _timeout;
  }

  Future<void> _recover(int epoch, {DateTime? automaticUntil}) async {
    final record = _correlation!;
    final budget = _readBudget(automaticUntil);
    final result = await _client
        .attempt(
          api.GetEnrollmentAttemptRequest(
            profile: api.ProfileRef(profileId: record.profileId),
            requestId: record.requestId,
          ),
          budget,
        )
        .timeout(budget);
    if (_current(epoch)) {
      await _accept(result, epoch, automaticUntil: automaticUntil);
    }
  }

  // uint64 в SDK хранится Int64: signed comparison после 2^63 неверен.
  static bool _revisionAtLeast(
    api.SnapshotMetadata value,
    api.SnapshotMetadata previous,
  ) =>
      BigInt.parse(value.revision.toStringUnsigned()) >=
      BigInt.parse(previous.revision.toStringUnsigned());

  bool _validMetadata(api.SnapshotMetadata value) =>
      value.instanceId == _runtime?.instanceId &&
      value.instanceId.isNotEmpty &&
      (_metadata == null || _revisionAtLeast(value, _metadata!));

  Future<void> _accept(
    api.EnrollmentAttempt value,
    int epoch, {
    DateTime? automaticUntil,
  }) async {
    final record = _correlation!;
    if (value.profileId != record.profileId ||
        value.requestId != record.requestId ||
        value.attemptId.isEmpty ||
        !_validMetadata(value.metadata) ||
        !value.hasCreatedAt() ||
        !value.hasDeadline() ||
        !value.deadline.toDateTime().isAfter(value.createdAt.toDateTime()) ||
        value.deadline.toDateTime().difference(value.createdAt.toDateTime()) >
            const Duration(minutes: 22) ||
        value.phase == api.EnrollmentPhase.ENROLLMENT_PHASE_UNSPECIFIED ||
        value.certainty ==
            api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_UNSPECIFIED ||
        (value.certainty ==
                api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_UNCERTAIN &&
            !value.hasRecoveryDeadline()) ||
        (value.hasRecoveryDeadline() &&
            (!value.recoveryDeadline.toDateTime().isAfter(
                  value.createdAt.toDateTime(),
                ) ||
                value.recoveryDeadline.toDateTime().isAfter(
                  value.deadline.toDateTime(),
                ))) ||
        (_attempt != null && value.attemptId != _attempt!.attemptId) ||
        (_attempt != null &&
            (value.createdAt.seconds != _attempt!.createdAt.seconds ||
                value.createdAt.nanos != _attempt!.createdAt.nanos ||
                value.deadline.seconds != _attempt!.deadline.seconds ||
                value.deadline.nanos != _attempt!.deadline.nanos)) ||
        (_attempt != null &&
            _attempt!.accountId.isNotEmpty &&
            (value.accountId != _attempt!.accountId ||
                value.networkId != _attempt!.networkId))) {
      throw StateError('attempt binding');
    }
    if (value.hasRecoveryDeadline()) {
      await _rememberRecovery(
        epoch,
        producerDeadline: value.recoveryDeadline.toDateTime(),
      );
      if (!_current(epoch)) return;
    }
    if (_targetMetadata != null &&
        (!_sameRevision(_targetMetadata!, value.metadata) ||
            value.phase !=
                api.EnrollmentPhase.ENROLLMENT_PHASE_CHOOSING_CONTEXT)) {
      _clearTargets();
    }
    _rejected = false;
    _failure = null;
    _attempt = api.EnrollmentAttempt.fromBuffer(value.writeToBuffer());
    _metadata = api.SnapshotMetadata.fromBuffer(value.metadata.writeToBuffer());
    _link = EnrollmentLinkState.available;
    _reason = value.restriction.reasonKey;
    if (value.phase == api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERED) {
      final budget = _readBudget(automaticUntil);
      final status = await _client.status(budget).timeout(budget);
      if (!_current(epoch)) return;
      if (!_validMetadata(status.metadata)) throw StateError('snapshot');
      _status = api.Status.fromBuffer(status.writeToBuffer());
      _metadata = api.SnapshotMetadata.fromBuffer(
        status.metadata.writeToBuffer(),
      );
      if (!registeredConfirmed) _reason = 'ui.registration_snapshot_mismatch';
    }
  }

  void _reject(ClientCallFailure error) {
    _clearTargets();
    _rejected = true;
    _failure = error.failure;
    _reason = error.reasonKey;
    _link = _metadata == null
        ? EnrollmentLinkState.unavailable
        : EnrollmentLinkState.available;
  }

  Future<void> _lost(int epoch) async {
    _clearTargets();
    _rejected = false;
    _failure = null;
    _link = EnrollmentLinkState.unavailable;
    _reason = 'ui.enrollment_uncertain';
    try {
      await _rememberRecovery(epoch);
    } catch (_) {
      if (_current(epoch)) _reason = 'ui.correlation_save_failed';
    }
  }

  Future<void> _rememberRecovery(
    int epoch, {
    DateTime? producerDeadline,
  }) async {
    final record = _correlation;
    if (record != null) {
      var until = _now().toUtc().add(const Duration(minutes: 2));
      if (_attempt case final known?) {
        final total = known.deadline.toDateTime();
        if (total.isBefore(until)) until = total;
      }
      if (producerDeadline != null && producerDeadline.isBefore(until)) {
        until = producerDeadline;
      }
      final updated = record.uncertainUntil(until);
      if (updated.recoveryDeadline == record.recoveryDeadline) return;
      try {
        await _store.save(updated);
      } catch (_) {
        throw const CorrelationStoreFailure(
          CorrelationStoreProblem.inaccessible,
        );
      }
      if (_current(epoch)) _correlation = updated;
    }
  }

  DateTime? get _waitingDeadline {
    final a = _attempt;
    DateTime? deadline = a?.deadline.toDateTime();
    void limit(DateTime value) {
      if (deadline == null || value.isBefore(deadline!)) deadline = value;
    }

    if (_link == EnrollmentLinkState.unavailable ||
        a?.certainty ==
            api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_UNCERTAIN) {
      if (_correlation?.recoveryDeadline case final value?) limit(value);
      if (a != null && a.hasRecoveryDeadline()) {
        limit(a.recoveryDeadline.toDateTime());
      }
    } else if (a != null) {
      if (a.phase == api.EnrollmentPhase.ENROLLMENT_PHASE_AWAITING_LOGIN) {
        if (a.hasLoginExpiresAt()) limit(a.loginExpiresAt.toDateTime());
        if (a.hasBrowserAction() && a.browserAction.hasExpiresAt()) {
          limit(a.browserAction.expiresAt.toDateTime());
        }
      } else if (a.hasApprovalExpiresAt()) {
        limit(a.approvalExpiresAt.toDateTime());
      }
    }
    return deadline;
  }

  void _schedule(int epoch) {
    _timer?.cancel();
    _timer = null;
    if (_rejected ||
        !automaticPolling ||
        !_current(epoch) ||
        _correlation == null ||
        _reason == 'ui.correlation_save_failed' ||
        _reason == 'ui.correlation_store_failed') {
      return;
    }
    final a = _attempt;
    if (a != null &&
        a.certainty == api.EnrollmentCertainty.ENROLLMENT_CERTAINTY_KNOWN &&
        _terminal(a.phase)) {
      return;
    }
    final now = _now();
    var wait = a == null
        ? _recoveryPoll
        : Duration(seconds: a.pollAfterSeconds);
    if (wait < const Duration(seconds: 1) ||
        wait > const Duration(seconds: 30)) {
      return;
    }
    final deadline = _waitingDeadline;
    if (deadline != null) {
      final remaining = deadline.difference(now);
      if (remaining <= Duration.zero) return;
      if (remaining < wait) wait = remaining;
    }
    _timer = Timer(wait, () {
      _timer = null;
      if (!_current(epoch)) return;
      final until = _waitingDeadline;
      if (until != null && !_now().isBefore(until)) {
        _emit();
        return;
      }
      unawaited(_refresh(automaticUntil: until));
    });
  }

  static bool _terminal(api.EnrollmentPhase phase) => const {
    api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERED,
    api.EnrollmentPhase.ENROLLMENT_PHASE_DENIED,
    api.EnrollmentPhase.ENROLLMENT_PHASE_CANCELLED,
    api.EnrollmentPhase.ENROLLMENT_PHASE_EXPIRED,
  }.contains(phase);
  static bool _validUuid(String value) =>
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
          .hasMatch(value);
  static String _uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    super.dispose();
  }
}
