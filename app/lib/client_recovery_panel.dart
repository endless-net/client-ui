import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_locale.dart';
import 'client_operation_labels.dart';
import 'client_operation.dart';
import 'client_operation_details.dart';
import 'client_state_controller.dart';

/// Lookup and explicit acknowledgement only: this surface never replays work.
class ClientRecoveryPanel extends StatefulWidget {
  const ClientRecoveryPanel({
    super.key,
    required this.state,
    required this.recover,
    required this.acknowledge,
    this.openBrowser,
    this.exportBundle,
    this.locale = ClientLocale.en,
  });
  final ClientLocale locale;
  final ClientStateController state;
  final Future<List<ClientOperation>> Function() recover;
  final Future<void> Function(ClientOperation) acknowledge;
  final Future<bool> Function(Uri)? openBrowser;

  /// Adapter chooses a native destination, re-reads via ClientSession and calls
  /// checkContext across every await. False means user cancellation, not success.
  final Future<bool> Function(String requestId, void Function() checkContext)?
  exportBundle;

  @override
  State<ClientRecoveryPanel> createState() => _ClientRecoveryPanelState();
}

class _ClientRecoveryPanelState extends State<ClientRecoveryPanel> {
  List<ClientOperation> _results = [];
  _RecoveryNotice? _notice;
  int? _epoch;
  bool _busy = false;

  bool get _owner =>
      mounted &&
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess != api.Access.ACCESS_OBSERVER;

  Future<void> _openBrowser(ClientOperation displayed) async {
    if (_busy ||
        !_owner ||
        _epoch != widget.state.cacheEpoch ||
        widget.openBrowser == null) {
      return;
    }
    final epoch = widget.state.cacheEpoch;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      // Re-read the operation immediately before using its sensitive action.
      // A displayed URL may have expired or been replaced since the last lookup.
      final results = await widget.recover();
      if (!mounted || !_owner || epoch != widget.state.cacheEpoch) return;
      final current = results.singleWhere(
        (op) =>
            op.value.id == displayed.value.id &&
            op.value.requestId == displayed.value.requestId,
      );
      setState(() => _results = List.unmodifiable(results));
      final value = current.value;
      if (value.state != api.OperationState.OPERATION_STATE_WAITING_FOR_USER ||
          value.userAction.kind != api.UserAction_Kind.KIND_OPEN_BROWSER) {
        throw StateError('Browser action is no longer pending');
      }
      final action = value.userAction;
      final uri = Uri.tryParse(action.browserUrl);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw StateError('Invalid browser action');
      }
      if (action.hasExpiresAt()) {
        final deadline = action.expiresAt;
        if (deadline.seconds.toInt() < -62135596800 ||
            deadline.seconds.toInt() > 253402300799 ||
            deadline.nanos < 0 ||
            deadline.nanos >= 1000000000 ||
            !DateTime.fromMicrosecondsSinceEpoch(
              deadline.seconds.toInt() * 1000000 + deadline.nanos ~/ 1000,
              isUtc: true,
            ).isAfter(DateTime.now().toUtc())) {
          throw StateError('Browser action expired');
        }
      }
      // Producer validates the URL against trusted origin/provider policy.
      // No URL, token or launch exception is logged or placed in a notice.
      final opened = await widget.openBrowser!(uri);
      if (!mounted || !_owner || epoch != widget.state.cacheEpoch) return;
      setState(
        () => _notice = opened
            ? _RecoveryNotice.browserOpened
            : _RecoveryNotice.browserUnavailable,
      );
    } catch (_) {
      if (!mounted || !_owner || epoch != widget.state.cacheEpoch) return;
      setState(() => _notice = _RecoveryNotice.browserFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(ClientOperation displayed) async {
    if (_busy ||
        !_owner ||
        _epoch != widget.state.cacheEpoch ||
        widget.exportBundle == null) {
      return;
    }
    final epoch = widget.state.cacheEpoch;
    void check() {
      if (!mounted || !_owner || epoch != widget.state.cacheEpoch) {
        throw StateError('Export context changed');
      }
    }

    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final results = await widget.recover();
      check();
      final current = results.singleWhere(
        (op) =>
            op.value.id == displayed.value.id &&
            op.value.requestId == displayed.value.requestId,
      );
      if (!current.succeeded ||
          current.value.kind !=
              api.OperationKind.OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE) {
        throw StateError('Bundle is not ready');
      }
      final saved = await widget.exportBundle!(current.value.requestId, check);
      check();
      setState(
        () => _notice = saved
            ? _RecoveryNotice.exported
            : _RecoveryNotice.exportCancelled,
      );
    } catch (_) {
      if (mounted && _owner && epoch == widget.state.cacheEpoch) {
        setState(() => _notice = _RecoveryNotice.exportFailed);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(ClientOperation? acknowledgement) async {
    if (_busy || !_owner) return;
    if (acknowledgement != null &&
        (_epoch != widget.state.cacheEpoch ||
            !_results.contains(acknowledgement))) {
      return;
    }
    final epoch = widget.state.cacheEpoch;
    setState(() {
      _busy = true;
      if (_epoch != epoch) _results = [];
      _epoch = epoch;
      _notice = null;
    });
    try {
      if (acknowledgement == null) {
        final results = await widget.recover();
        if (!mounted || widget.state.cacheEpoch != epoch || !_owner) return;
        setState(() {
          _results = List.unmodifiable(results);
          if (results.isEmpty) _notice = _RecoveryNotice.empty;
        });
      } else {
        if (!acknowledgement.terminal) return;
        await widget.acknowledge(acknowledgement);
        if (!mounted || widget.state.cacheEpoch != epoch || !_owner) return;
        setState(() {
          _results = _results
              .where(
                (op) => op.value.requestId != acknowledgement.value.requestId,
              )
              .toList();
          _notice = _RecoveryNotice.acknowledged;
        });
      }
    } catch (_) {
      if (!mounted || widget.state.cacheEpoch != epoch || !_owner) return;
      setState(() => _notice = _RecoveryNotice.recoveryFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final visible = _owner && _epoch == widget.state.cacheEpoch;
      final renderedState = widget.state;
      final renderedEpoch = widget.state.cacheEpoch;
      bool current() =>
          mounted &&
          identical(widget.state, renderedState) &&
          widget.state.cacheEpoch == renderedEpoch;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton(
            key: const Key('client-recover'),
            onPressed: _owner && !_busy
                ? () {
                    if (current()) _run(null);
                  }
                : null,
            child: Text(
              widget.locale.text(
                en: 'Recover pending operations',
                ru: 'Восстановить результаты операций',
              ),
            ),
          ),
          if (visible && _notice != null) Text(_notice!.label(widget.locale)),
          if (visible)
            for (final operation in _results)
              ListTile(
                title: Text(
                  clientOperationKindLabel(
                    operation.value.kind,
                    locale: widget.locale,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClientOperationDetails(
                      operation: operation,
                      locale: widget.locale,
                    ),
                    if (operation.succeeded &&
                        operation.value.kind ==
                            api
                                .OperationKind
                                .OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE)
                      widget.exportBundle == null
                          ? Text(
                              widget.locale.text(
                                en: 'Native export adapter is not available.',
                                ru: 'Системный адаптер экспорта недоступен.',
                              ),
                            )
                          : TextButton(
                              key: ValueKey(
                                'export-${operation.value.requestId}',
                              ),
                              onPressed: !_busy
                                  ? () {
                                      if (current() &&
                                          _results.contains(operation)) {
                                        _export(operation);
                                      }
                                    }
                                  : null,
                              child: Text(
                                widget.locale.text(
                                  en: 'Export verified bundle',
                                  ru: 'Экспортировать проверенный пакет',
                                ),
                              ),
                            ),
                    operation.terminal
                        ? TextButton(
                            key: ValueKey('ack-${operation.value.requestId}'),
                            onPressed: !_busy
                                ? () {
                                    if (current()) _run(operation);
                                  }
                                : null,
                            child: Text(
                              widget.locale.text(
                                en: 'Acknowledge result',
                                ru: 'Подтвердить результат',
                              ),
                            ),
                          )
                        : operation.value.userAction.kind ==
                                  api.UserAction_Kind.KIND_OPEN_BROWSER &&
                              widget.openBrowser != null
                        ? TextButton(
                            key: ValueKey(
                              'browser-${operation.value.requestId}',
                            ),
                            onPressed: !_busy
                                ? () {
                                    if (current() &&
                                        _results.contains(operation)) {
                                      _openBrowser(operation);
                                    }
                                  }
                                : null,
                            child: Text(
                              widget.locale.text(
                                en: 'Open browser',
                                ru: 'Открыть браузер',
                              ),
                            ),
                          )
                        : Text(
                            widget.locale.text(
                              en: 'Still pending',
                              ru: 'Ещё выполняется',
                            ),
                          ),
                  ],
                ),
              ),
        ],
      );
    },
  );
}

// Store state, not translated text, so an existing notice follows locale changes.
enum _RecoveryNotice {
  browserOpened,
  browserUnavailable,
  browserFailed,
  exported,
  exportCancelled,
  exportFailed,
  empty,
  acknowledged,
  recoveryFailed;

  String label(ClientLocale locale) => switch (this) {
    _RecoveryNotice.browserOpened => locale.text(
      en: 'Browser opened. The operation is still pending; recover its result.',
      ru: 'Браузер открыт. Операция ещё выполняется; запросите её результат.',
    ),
    _RecoveryNotice.browserUnavailable => locale.text(
      en: 'Browser could not be opened. The operation is retained.',
      ru: 'Не удалось открыть браузер. Операция сохранена.',
    ),
    _RecoveryNotice.browserFailed => locale.text(
      en: 'Browser action could not be completed. Refresh the operation; no command was replayed.',
      ru: 'Не удалось выполнить действие в браузере. Обновите операцию; команда не отправлялась повторно.',
    ),
    _RecoveryNotice.exported => locale.text(
      en: 'Verified bundle exported. The operation is retained.',
      ru: 'Проверенный пакет экспортирован. Операция сохранена.',
    ),
    _RecoveryNotice.exportCancelled => locale.text(
      en: 'Export cancelled. The operation is retained.',
      ru: 'Экспорт отменён. Операция сохранена.',
    ),
    _RecoveryNotice.exportFailed => locale.text(
      en: 'Export could not complete. The operation is retained.',
      ru: 'Не удалось завершить экспорт. Операция сохранена.',
    ),
    _RecoveryNotice.empty => locale.text(
      en: 'No pending intentions.',
      ru: 'Нет незавершённых намерений.',
    ),
    _RecoveryNotice.acknowledged => locale.text(
      en: 'Result acknowledged. No command was replayed.',
      ru: 'Результат подтверждён. Команда не отправлялась повторно.',
    ),
    _RecoveryNotice.recoveryFailed => locale.text(
      en: 'Recovery could not complete. Pending intentions are retained.',
      ru: 'Не удалось восстановить результаты. Незавершённые намерения сохранены.',
    ),
  };
}
