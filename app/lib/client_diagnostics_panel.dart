import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'client_state_controller.dart';
import 'client_operation.dart';
import 'client_locale.dart';
import 'client_diagnostics_details.dart';

enum _DiagnosticsNotice { logs, preview, succeeded, received, unknown }

String diagnosticPhaseLabel(api.ConnectionPhase phase, ClientLocale locale) =>
    switch (phase) {
      api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTED => locale.text(
        en: 'Disconnected',
        ru: 'Отключено',
      ),
      api.ConnectionPhase.CONNECTION_PHASE_CONNECTING => locale.text(
        en: 'Connecting',
        ru: 'Подключение',
      ),
      api.ConnectionPhase.CONNECTION_PHASE_CONNECTED => locale.text(
        en: 'Connected',
        ru: 'Подключено',
      ),
      api.ConnectionPhase.CONNECTION_PHASE_DISCONNECTING => locale.text(
        en: 'Disconnecting',
        ru: 'Отключение',
      ),
      _ => locale.text(en: 'Not specified', ru: 'Не указано'),
    };

/// Local inspection. Never serialize the full message into logs/clipboard:
/// diagnostics can contain addresses, pending browser actions and log entries.
class ClientDiagnosticsPanel extends StatefulWidget {
  const ClientDiagnosticsPanel({
    super.key,
    required this.state,
    required this.load,
    required this.createBundle,
    this.loadLogs,
    this.locale = ClientLocale.en,
  });
  final ClientStateController state;
  final ClientLocale locale;
  final Future<api.Diagnostics> Function() load;
  final Future<ClientOperation> Function(String profileId) createBundle;
  final Future<List<api.LogEntry>> Function()? loadLogs;
  @override
  State<ClientDiagnosticsPanel> createState() => _ClientDiagnosticsPanelState();
}

class _ClientDiagnosticsPanelState extends State<ClientDiagnosticsPanel> {
  api.Diagnostics? _preview;
  List<api.LogEntry>? _logs;
  String? _context;
  _DiagnosticsNotice? _notice;
  int _confirmationSerial = 0;
  String _text(String en, String ru) => widget.locale.text(en: en, ru: ru);
  String _noticeText(_DiagnosticsNotice notice) => switch (notice) {
    _DiagnosticsNotice.logs => _text(
      'Logs could not be read. Refresh to start a new snapshot.',
      'Не удалось прочитать журнал. Обновите его, чтобы получить новый снимок.',
    ),
    _DiagnosticsNotice.preview => _text(
      'Diagnostics could not be read.',
      'Не удалось прочитать диагностику.',
    ),
    _DiagnosticsNotice.succeeded => _text(
      'Bundle operation succeeded. Recover its handle before verified download; nothing was exported.',
      'Операция создания архива завершилась успешно. Восстановите дескриптор для проверенной загрузки; ничего не экспортировано.',
    ),
    _DiagnosticsNotice.received => _text(
      'Bundle operation received. Recover its result; archive readiness is not confirmed.',
      'Операция создания архива получена. Восстановите её результат; готовность архива не подтверждена.',
    ),
    _DiagnosticsNotice.unknown => _text(
      'Bundle creation could not be confirmed. Recover the intention before another attempt.',
      'Не удалось подтвердить создание архива. Восстановите исходное намерение перед повторной попыткой.',
    ),
  };
  bool _busy = false;
  bool _confirmBundle = false;
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_clearInvalidatedPreview);
  }

  @override
  void didUpdateWidget(covariant ClientDiagnosticsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_clearInvalidatedPreview);
      widget.state.addListener(_clearInvalidatedPreview);
      _clearPreview();
    }
  }

  void _clearPreview() {
    _preview = null;
    _logs = null;
    _notice = null;
    _confirmBundle = false;
    _confirmationSerial++;
    _context = null;
  }

  void _clearInvalidatedPreview() {
    if (_context != null && (_context != contextId || !allowed)) {
      // Drop the message itself, not just its rendered summary. It can contain
      // log entries or browser actions belonging to the former caller/profile.
      setState(_clearPreview);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_clearInvalidatedPreview);
    _clearPreview();
    super.dispose();
  }

  String get contextId =>
      '${widget.state.cacheEpoch}:${api.Domain.values.map(widget.state.domainEpoch).join(',')}';
  bool get allowed =>
      mounted &&
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess !=
          api.Access.ACCESS_OBSERVER &&
      widget.state.snapshot!.status.activeProfileId.isNotEmpty &&
      widget.state.snapshot!.supports(api.Capability.CAPABILITY_DIAGNOSTICS);

  Future<void> _loadLogs() async {
    if (!allowed || _busy || widget.loadLogs == null) return;
    final context = contextId;
    setState(() {
      _context = context;
      _logs = null;
      _notice = null;
      _busy = true;
    });
    try {
      final logs = await widget.loadLogs!();
      if (!mounted || _context != context || contextId != context || !allowed) {
        return;
      }
      setState(() => _logs = logs);
    } catch (_) {
      if (mounted && _context == context && contextId == context && allowed) {
        setState(() => _notice = _DiagnosticsNotice.logs);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    if (!allowed || _busy) return;
    final context = contextId;
    setState(() {
      _context = context;
      _busy = true;
      _preview = null;
      _notice = null;
      _confirmBundle = false;
      _confirmationSerial++;
    });
    try {
      final preview = await widget.load();
      if (!mounted || context != _context || context != contextId || !allowed) {
        return;
      }
      final snapshot = widget.state.snapshot!;
      if (!preview.hasMetadata() ||
          preview.metadata.instanceId != snapshot.runtime.instanceId ||
          preview.metadata.revision < snapshot.status.metadata.revision) {
        throw const FormatException('Invalid diagnostics context');
      }
      setState(
        () =>
            _preview = api.Diagnostics.fromBuffer(preview.writeToBuffer())
              ..freeze(),
      );
    } catch (_) {
      if (mounted && context == _context && context == contextId) {
        setState(() => _notice = _DiagnosticsNotice.preview);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (!allowed ||
        _busy ||
        !_confirmBundle ||
        _preview == null ||
        _context != contextId) {
      return;
    }
    final context = contextId;
    final profileId = widget.state.snapshot!.status.activeProfileId;
    setState(() {
      _busy = true;
      _confirmBundle = false;
      _confirmationSerial++;
      _notice = null;
    });
    try {
      final operation = await widget.createBundle(profileId);
      if (!mounted || context != _context || context != contextId || !allowed) {
        return;
      }
      setState(
        () => _notice = operation.succeeded
            ? _DiagnosticsNotice.succeeded
            : _DiagnosticsNotice.received,
      );
    } catch (_) {
      if (mounted && context == _context && context == contextId) {
        setState(() => _notice = _DiagnosticsNotice.unknown);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final preview = allowed && _context == contextId ? _preview : null;
      final originalState = widget.state;
      final snapshot = widget.state.snapshot;
      final id = contextId;
      final serial = _confirmationSerial;
      bool current() =>
          mounted &&
          identical(widget.state, originalState) &&
          identical(snapshot, widget.state.snapshot) &&
          identical(preview, _preview) &&
          id == contextId &&
          serial == _confirmationSerial;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.loadLogs != null)
            OutlinedButton(
              key: const Key('load-client-logs'),
              onPressed: allowed && !_busy ? _loadLogs : null,
              child: Text(
                _text('Read recent logs', 'Прочитать последние записи журнала'),
              ),
            ),
          if (allowed && _context == contextId && _logs != null) ...[
            Text(
              _text(
                'Recent local log window — not a complete history. Nothing uploaded.',
                'Последние записи локального журнала — не полная история. Ничего не отправлено.',
              ),
            ),
            if (_logs!.isEmpty)
              Text(
                _text(
                  'No recent log entries.',
                  'Нет последних записей журнала.',
                ),
              ),
            SizedBox(
              height: 180,
              child: ListView.builder(
                itemCount: _logs!.length,
                itemBuilder: (context, index) {
                  final entry = _logs![index];
                  return Text(
                    '${entry.timestamp.toDateTime().toUtc().toIso8601String()} ${entry.message}',
                  );
                },
              ),
            ),
          ],
          OutlinedButton(
            key: const Key('load-client-diagnostics'),
            onPressed: allowed && !_busy ? _load : null,
            child: Text(
              _text('Inspect diagnostics', 'Просмотреть диагностику'),
            ),
          ),
          if (preview != null) ...[
            Text(
              _text(
                'Local diagnostics summary — no data copied or uploaded.',
                'Сводка локальной диагностики — данные не скопированы и не отправлены.',
              ),
            ),
            Text(
              '${_text('OS', 'ОС')}: ${preview.osName} ${preview.osVersion}',
            ),
            Text('Go: ${preview.goVersion}'),
            Text(
              '${_text('Interfaces', 'Интерфейсы')}: ${preview.interfaces.length}; ${_text('routes', 'маршруты')}: ${preview.routes.length}; ${_text('peers', 'устройства')}: ${preview.peers.length}',
            ),
            Text(
              '${_text('Route conflicts', 'Конфликты маршрутов')}: ${preview.routeConflicts.length}; ${_text('failures', 'ошибки')}: ${preview.failures.length}',
            ),
            if (preview.truncated)
              Text(
                _text(
                  'Diagnostics are truncated; this is not a complete report.',
                  'Диагностика сокращена; это не полный отчёт.',
                ),
              ),
            if (preview.hasStatus())
              Text(
                '${_text('Connection phase', 'Состояние подключения')}: ${diagnosticPhaseLabel(preview.status.connectionPhase, widget.locale)}',
              ),
            Text(
              _text(
                'This is a summary. Recover the archive operation for verified download and a separate export, when supported.',
                'Это сводка. Восстановите операцию создания архива для проверенной загрузки и отдельного экспорта, если он поддерживается.',
              ),
            ),
            OutlinedButton(
              key: const Key('create-client-bundle'),
              onPressed: !_busy
                  ? () {
                      if (!current() || !allowed || _context != contextId) {
                        return;
                      }
                      setState(() {
                        _confirmBundle = true;
                        _confirmationSerial++;
                      });
                    }
                  : null,
              child: Text(
                _text(
                  'Create diagnostics archive',
                  'Создать архив диагностики',
                ),
              ),
            ),
            if (_confirmBundle) ...[
              Text(
                _text(
                  'Create a local redacted diagnostics archive? This does not upload or export it.',
                  'Создать локальный архив диагностики с удалёнными конфиденциальными данными? Это не отправляет и не экспортирует архив.',
                ),
              ),
              Wrap(
                children: [
                  TextButton(
                    key: const Key('cancel-client-bundle'),
                    onPressed: () {
                      if (current()) {
                        setState(() {
                          _confirmBundle = false;
                          _confirmationSerial++;
                        });
                      }
                    },
                    child: Text(_text('Cancel', 'Отмена')),
                  ),
                  TextButton(
                    key: const Key('confirm-client-bundle'),
                    onPressed: !_busy
                        ? () {
                            if (current()) _create();
                          }
                        : null,
                    child: Text(
                      _text(
                        'Confirm archive creation',
                        'Подтвердить создание архива',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            ClientDiagnosticsDetails(
              key: ValueKey(preview),
              diagnostics: preview,
              locale: widget.locale,
            ),
          ],
          if (_context == contextId && allowed && _notice != null)
            Semantics(liveRegion: true, child: Text(_noticeText(_notice!))),
        ],
      );
    },
  );
}
