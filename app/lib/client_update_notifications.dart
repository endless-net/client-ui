import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'client_locale.dart';
import 'client_runtime_snapshot.dart';
import 'client_update_info.dart';

final class ClientUpdateNotice {
  ClientUpdateNotice._(this._fingerprint, this._expires, this._classification);
  final String _fingerprint;
  final DateTime _expires;
  final api.UpdateClassification _classification;
  String title(ClientLocale locale) => 'EndlessNet';
  String body(ClientLocale locale) => switch (_classification) {
    api.UpdateClassification.UPDATE_CLASSIFICATION_SECURITY => locale.text(
      en: 'A verified security update is available. Open EndlessNet to review compatibility and update options.',
      ru: 'Доступно проверенное обновление безопасности. Откройте EndlessNet, чтобы проверить совместимость и варианты обновления.',
    ),
    api.UpdateClassification.UPDATE_CLASSIFICATION_MANDATORY => locale.text(
      en: 'A verified required update is available. Open EndlessNet to review compatibility and update options.',
      ru: 'Доступно проверенное обязательное обновление. Откройте EndlessNet, чтобы проверить совместимость и варианты обновления.',
    ),
    _ => locale.text(
      en: 'A verified update is available. Open EndlessNet to review compatibility and update options.',
      ru: 'Доступно проверенное обновление. Откройте EndlessNet, чтобы проверить совместимость и варианты обновления.',
    ),
  };
}

/// Bounded in-memory planning, not background discovery or OS delivery.
/// No URL, release/version, identity or producer reason crosses the notice API.
final class ClientUpdateNotifications {
  String? _scope;
  String? _delivered;
  ClientUpdateNotice? _current;
  String _hash(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();

  ClientUpdateNotice? observe({
    required ClientRuntimeSnapshot? snapshot,
    required api.UpdateInfo? info,
    required api.BuildIdentity uiBuild,
    required bool ready,
    required bool enabled,
    required DateTime now,
  }) {
    if (!ready || snapshot == null) {
      _current = null;
      return null;
    }
    if (snapshot.runtime.callerAccess == api.Access.ACCESS_OBSERVER) {
      clear();
      return null;
    }
    final scope = _hash([
      snapshot.runtime.instanceId,
      snapshot.runtime.callerAccess.value,
      snapshot.status.activeProfileId,
      snapshot.status.accountId,
      uiBuild.toProto3Json(),
    ]);
    if (_scope != scope) {
      clear();
      _scope = scope;
    }
    if (!enabled || info == null) {
      _current = null;
      return null;
    }
    try {
      final validated = validateClientUpdateInfo(
        source: info,
        instanceId: snapshot.runtime.instanceId,
        installedRuntime: snapshot.runtime.build,
        reportedUi: uiBuild,
        now: () => now,
      );
      if (validated.metadata.revision < snapshot.status.metadata.revision ||
          !validated.hasAvailable() ||
          (validated.hasDiscovery() &&
              validated.discovery.availability !=
                  api.Availability.AVAILABILITY_AVAILABLE)) {
        _current = null;
        return null;
      }
      final update = validated.available;
      final fingerprint = _hash([
        scope,
        update.releaseId,
        update.manifestSha256.toLowerCase(),
        update.classification.value,
      ]);
      final expires = update.expiresAt.toDateTime().toUtc();
      if (_current?._fingerprint != fingerprint ||
          _current?._expires != expires) {
        _current = ClientUpdateNotice._(
          fingerprint,
          expires,
          update.classification,
        );
      }
      return _delivered == fingerprint ? null : _current;
    } on FormatException {
      _current = null;
      return null;
    }
  }

  bool acknowledge(ClientUpdateNotice notice, DateTime now) {
    if (!identical(_current, notice) || !notice._expires.isAfter(now.toUtc())) {
      return false;
    }
    _delivered = notice._fingerprint;
    return true;
  }

  void clear() {
    _scope = null;
    _delivered = null;
    _current = null;
  }
}
