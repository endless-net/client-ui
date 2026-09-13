import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'client_locale.dart';
import 'client_runtime_snapshot.dart';

enum ClientDeadlineNoticeKind {
  sessionExpiring,
  sessionExpired,
  credentialExpiring,
  credentialExpired,
}

/// Safe delivery payload: no profile/account IDs, deadlines, URLs or reasons.
final class ClientDeadlineNotice {
  ClientDeadlineNotice._(this.kind, this._fingerprint);
  final ClientDeadlineNoticeKind kind;
  final String _fingerprint;
  String title(ClientLocale locale) =>
      locale.text(en: 'EndlessNet', ru: 'EndlessNet');
  String body(ClientLocale locale) => switch (kind) {
    ClientDeadlineNoticeKind.sessionExpiring => locale.text(
      en: 'Your session is expiring. Open EndlessNet to review renewal options.',
      ru: 'Срок сессии истекает. Откройте EndlessNet, чтобы проверить варианты продления.',
    ),
    ClientDeadlineNoticeKind.sessionExpired => locale.text(
      en: 'Your session has expired. Open EndlessNet to review the required action.',
      ru: 'Срок сессии истёк. Откройте EndlessNet, чтобы проверить требуемое действие.',
    ),
    ClientDeadlineNoticeKind.credentialExpiring => locale.text(
      en: 'Device credentials are expiring. Open EndlessNet to review their status.',
      ru: 'Срок учётных данных устройства истекает. Откройте EndlessNet, чтобы проверить их состояние.',
    ),
    ClientDeadlineNoticeKind.credentialExpired => locale.text(
      en: 'Device credentials have expired. Open EndlessNet to review recovery options.',
      ru: 'Срок учётных данных устройства истёк. Откройте EndlessNet, чтобы проверить варианты восстановления.',
    ),
  };
}

/// In-memory delivery planning for one active caller/profile context.
/// An OS adapter must confirm successful delivery before acknowledgement.
/// Reconnect preserves delivered fingerprints, never a private snapshot.
final class ClientDeadlineNotifications {
  String? _scope;
  final _delivered = <ClientDeadlineNoticeKind, String>{};
  final _current = <ClientDeadlineNoticeKind, ClientDeadlineNotice>{};

  String _hash(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();

  List<ClientDeadlineNotice> observe({
    required ClientRuntimeSnapshot? snapshot,
    required bool ready,
    required bool enabled,
  }) {
    if (!ready || snapshot == null) {
      _current.clear(); // Any in-flight acknowledgement is now stale.
      return const [];
    }
    if (snapshot.runtime.callerAccess == api.Access.ACCESS_OBSERVER ||
        snapshot.status.activeProfileId.isEmpty) {
      clear();
      return const [];
    }
    final scope = _hash([
      snapshot.runtime.instanceId,
      snapshot.runtime.callerAccess.value,
      snapshot.status.activeProfileId,
    ]);
    if (_scope != scope) {
      clear();
      _scope = scope;
    }
    if (!enabled) {
      _current.clear();
      return const [];
    }
    final desired = <ClientDeadlineNoticeKind, String>{};
    final session = snapshot.status.session;
    final credential = snapshot.status.credential;
    void add(ClientDeadlineNoticeKind kind, Object? deadline) {
      desired[kind] = _hash([scope, kind.name, deadline]);
    }

    // Only authoritative typed states trigger notices. The UI clock and an
    // unknown deadline never manufacture expiry or a countdown.
    final sessionKind = switch (session.state) {
      api.SessionState.SESSION_STATE_EXPIRING =>
        ClientDeadlineNoticeKind.sessionExpiring,
      api.SessionState.SESSION_STATE_EXPIRED =>
        ClientDeadlineNoticeKind.sessionExpired,
      _ => null,
    };
    final credentialKind = switch (credential.state) {
      api.CredentialState.CREDENTIAL_STATE_EXPIRING =>
        ClientDeadlineNoticeKind.credentialExpiring,
      api.CredentialState.CREDENTIAL_STATE_EXPIRED =>
        ClientDeadlineNoticeKind.credentialExpired,
      _ => null,
    };
    if (sessionKind != null) {
      add(
        sessionKind,
        session.hasExpiresAt() ? session.expiresAt.toProto3Json() : null,
      );
    }
    if (credentialKind != null) {
      add(
        credentialKind,
        credential.hasExpiresAt() ? credential.expiresAt.toProto3Json() : null,
      );
    }
    _current.removeWhere((kind, value) => desired[kind] != value._fingerprint);
    for (final entry in desired.entries) {
      _current.putIfAbsent(
        entry.key,
        () => ClientDeadlineNotice._(entry.key, entry.value),
      );
    }
    return List.unmodifiable(
      _current.values.where(
        (notice) => _delivered[notice.kind] != notice._fingerprint,
      ),
    );
  }

  bool acknowledge(ClientDeadlineNotice notice) {
    if (!identical(_current[notice.kind], notice)) return false;
    _delivered[notice.kind] = notice._fingerprint;
    return true;
  }

  void clear() {
    _scope = null;
    _current.clear();
    _delivered.clear();
  }
}
