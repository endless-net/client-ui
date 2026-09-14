import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'client_exit_nodes.dart';
import 'client_exit_labels.dart';
import 'client_locale.dart';
import 'client_operation_labels.dart';
import 'client_update_labels.dart';
import 'client_operation.dart';
import 'client_state_controller.dart';

class ClientExitPanel extends StatefulWidget {
  const ClientExitPanel({
    super.key,
    required this.state,
    required this.load,
    required this.select,
    required this.clear,
    this.locale = ClientLocale.en,
  });
  final ClientStateController state;
  final ClientLocale locale;
  final Future<ClientExitNodes> Function() load;
  final Future<ClientOperation> Function(
    String,
    String,
    api.ExitFamilyMode,
    api.LanAccess,
    void Function(),
  )
  select;
  final Future<ClientOperation> Function(String, void Function()) clear;
  @override
  State<ClientExitPanel> createState() => _ClientExitPanelState();
}

enum _ExitNotice { received, unknown }

class _ClientExitPanelState extends State<ClientExitPanel> {
  ClientExitNodes? _view;
  String? _context;
  String? _node;
  api.ExitFamilyMode? _mode;
  api.LanAccess? _lan;
  bool _busy = false;
  bool _confirmClear = false;
  int _draftSerial = 0;
  bool Function()? _contextCurrent;
  _ExitNotice? _notice;
  String _text(String en, String ru) => widget.locale.text(en: en, ru: ru);
  String _boolean(bool value) =>
      value ? _text('Yes', 'Да') : _text('No', 'Нет');
  String _failure(api.ErrorCode code) =>
      code == api.ErrorCode.ERROR_CODE_UNSPECIFIED
      ? _text('Not reported', 'Не сообщена')
      : clientFailureLabel(code, locale: widget.locale);
  String get contextId =>
      '${widget.state.cacheEpoch}:'
      '${[api.Domain.DOMAIN_EXIT_NODE, api.Domain.DOMAIN_PROFILES, api.Domain.DOMAIN_NETWORKS, api.Domain.DOMAIN_PEERS].map(widget.state.domainEpoch).join(',')}';
  bool get allowed =>
      mounted &&
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess !=
          api.Access.ACCESS_OBSERVER &&
      widget.state.snapshot!.status.activeProfileId.isNotEmpty &&
      widget.state.snapshot!.supports(api.Capability.CAPABILITY_EXIT_NODE);
  bool get current =>
      allowed && _context == contextId && (_contextCurrent?.call() ?? false);
  bool get editable =>
      current &&
      _view != null &&
      !_view!.status.control.locked &&
      _view!.status.control.mutation.availability ==
          api.Availability.AVAILABILITY_AVAILABLE;
  api.ExitNode? get selected {
    for (final node in _view?.nodes ?? <api.ExitNode>[]) {
      if (node.id == _node) return node;
    }
    return null;
  }

  bool get canSelect =>
      editable &&
      selected != null &&
      selected!.selection.availability ==
          api.Availability.AVAILABILITY_AVAILABLE &&
      selected!.allowedFamilyModes.contains(_mode) &&
      selected!.allowedLanAccess.contains(_lan);
  void _discard() {
    _binding = Object();
    _busy = false;
    _draftSerial++;
    _contextCurrent = null;
    _view = null;
    _context = null;
    _node = null;
    _mode = null;
    _lan = null;
    _notice = null;
    _confirmClear = false;
  }

  void _changed() {
    if (_context != null && !current) setState(_discard);
  }

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant ClientExitPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_changed);
      widget.state.addListener(_changed);
      _discard();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    _discard();
    super.dispose();
  }

  Object _binding = Object();

  Future<void> _run({bool select = false, bool clear = false}) async {
    if (!allowed ||
        _busy ||
        (select && !canSelect) ||
        (clear && (!editable || !_confirmClear))) {
      return;
    }
    final context = contextId;
    final binding = _binding;
    final state = widget.state;
    final snapshot = state.snapshot;
    final profile = widget.state.snapshot!.status.activeProfileId;
    final node = _node;
    final mode = _mode;
    final lan = _lan;
    void check() {
      if (!mounted ||
          !identical(binding, _binding) ||
          !current ||
          context != _context) {
        throw StateError('Exit context changed');
      }
    }

    setState(() {
      _draftSerial++;
      _contextCurrent = () =>
          identical(widget.state, state) && identical(state.snapshot, snapshot);
      _context = context;
      _busy = true;
      _notice = null;
      _confirmClear = false;
    });
    try {
      if (select || clear) {
        check();
        if (select) {
          await widget.select(profile, node!, mode!, lan!, check);
        } else {
          await widget.clear(profile, check);
        }
        check();
        setState(() {
          _view = null;
          _node = null;
          _mode = null;
          _lan = null;
          _notice = _ExitNotice.received;
        });
      } else {
        setState(() {
          _view = null;
          _node = null;
          _mode = null;
          _lan = null;
        });
        final view = await widget.load();
        check();
        if (view.status.profileId != profile ||
            view.status.metadata.instanceId !=
                widget.state.snapshot!.runtime.instanceId ||
            view.status.metadata.revision <
                widget.state.snapshot!.status.metadata.revision) {
          throw const FormatException('Stale exit-node projection');
        }
        setState(() => _view = view);
      }
    } catch (_) {
      if (!mounted ||
          !identical(binding, _binding) ||
          !current ||
          context != _context) {
        return;
      }
      setState(() {
        _view = null;
        _node = null;
        _mode = null;
        _lan = null;
        _notice = _ExitNotice.unknown;
      });
    } finally {
      if (mounted && identical(binding, _binding)) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final view = _view;
      final viewContext = _context;
      final state = widget.state;
      final snapshot = state.snapshot;
      final serial = _draftSerial;
      bool validFrame() =>
          mounted &&
          identical(widget.state, state) &&
          identical(state.snapshot, snapshot) &&
          serial == _draftSerial &&
          !_busy;
      bool validView() =>
          validFrame() &&
          current &&
          identical(view, _view) &&
          viewContext == _context;
      final node = selected;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(
            key: const Key('client-load-exits'),
            onPressed: allowed && !_busy
                ? () {
                    if (validFrame()) _run();
                  }
                : null,
            child: Text(_text('Refresh exit nodes', 'Обновить выходные узлы')),
          ),
          if (current && _notice != null)
            Semantics(
              liveRegion: true,
              child: Text(switch (_notice!) {
                _ExitNotice.received => _text(
                  'Exit operation received. Recover its result and refresh both address families.',
                  'Операция выходного узла получена. Восстановите её результат и обновите состояние обоих семейств адресов.',
                ),
                _ExitNotice.unknown => _text(
                  'Exit request could not be confirmed. Recover pending operations before retrying.',
                  'Запрос выходного узла не удалось подтвердить. Восстановите незавершённые операции перед повтором.',
                ),
              }),
            ),
          if (current && view != null) ...[
            Text(
              _text(
                'Requested exit mode: ${exitFamilyModeLabel(view.status.requestedFamilyMode, widget.locale)}',
                'Запрошенный режим: ${exitFamilyModeLabel(view.status.requestedFamilyMode, widget.locale)}',
              ),
            ),
            Text(
              _text(
                'Exit apply: ${exitApplyStateLabel(view.status.applyState, widget.locale)}; failure: ${_failure(view.status.failure.code)}',
                'Применение: ${exitApplyStateLabel(view.status.applyState, widget.locale)}; ошибка: ${_failure(view.status.failure.code)}',
              ),
            ),
            for (final entry in [
              ('IPv4', view.status.ipv4),
              ('IPv6', view.status.ipv6),
            ]) ...[
              Text(
                '${entry.$1}: ${_text('requested', 'запрошено')} ${entry.$2.hasRequestedExitNodeId() ? entry.$2.requestedExitNodeId : _text('No exit', 'Без выходного узла')}; ${_text('effective', 'фактически')} ${entry.$2.hasEffectiveExitNodeId() ? entry.$2.effectiveExitNodeId : _text('No exit', 'Без выходного узла')}',
              ),
              Text(
                '${entry.$1}: ${exitApplyStateLabel(entry.$2.applyState, widget.locale)}; ${_text('reported fail-closed', 'блокировка при отказе по данным службы')}: ${_boolean(entry.$2.failClosed)}; ${_text('failure', 'ошибка')}: ${_failure(entry.$2.failure.code)}',
              ),
              if (!entry.$2.hasRequestedExitNodeId())
                Text(
                  _text(
                    'No exit is requested for ${entry.$1}; see effective state for current routing.',
                    'Для ${entry.$1} выходной узел не запрошен; текущая маршрутизация указана в фактическом состоянии.',
                  ),
                ),
            ],
            Text(
              '${_text('LAN requested', 'Локальная сеть: запрошено')}: ${exitLanAccessLabel(view.status.requestedLanAccess, widget.locale)}; ${_text('effective', 'фактически')}: ${exitLanAccessLabel(view.status.effectiveLanAccess, widget.locale)}',
            ),
            Text(
              '${_text('Exit control', 'Управление выходным узлом')}: ${updateAvailabilityLabel(view.status.control.mutation.availability, widget.locale)}; ${_text('locked', 'заблокировано')}: ${_boolean(view.status.control.locked)}; ${_text('reason', 'причина')}: ${view.status.control.mutation.reasonKey}; ${_text('owner', 'исполнитель')}: ${clientActionOwnerLabel(view.status.control.mutation.actionOwner, locale: widget.locale)}',
            ),
            DropdownButton<String>(
              itemHeight: null,
              key: const Key('client-exit-node'),
              isExpanded: true,
              value: _node,
              hint: Text(_text('Choose exit node', 'Выберите выходной узел')),
              items: [
                for (final candidate in view.nodes)
                  DropdownMenuItem(
                    value: candidate.id,
                    enabled:
                        candidate.selection.availability ==
                        api.Availability.AVAILABILITY_AVAILABLE,
                    child: Text(
                      '${candidate.displayName}: ${updateAvailabilityLabel(candidate.selection.availability, widget.locale)}',
                    ),
                  ),
              ],
              onChanged: editable && !_busy
                  ? (id) {
                      if (!validView() ||
                          !view.nodes.any(
                            (n) =>
                                n.id == id &&
                                n.selection.availability ==
                                    api.Availability.AVAILABILITY_AVAILABLE,
                          )) {
                        return;
                      }
                      setState(() {
                        _draftSerial++;
                        _node = id;
                        _mode = null;
                        _lan = null;
                        _confirmClear = false;
                      });
                    }
                  : null,
            ),
            if (node != null) ...[
              DropdownButton<api.ExitFamilyMode>(
                itemHeight: null,
                key: const Key('client-exit-mode'),
                isExpanded: true,
                value: _mode,
                hint: Text(
                  _text(
                    'Choose address families',
                    'Выберите семейства адресов',
                  ),
                ),
                items: [
                  for (final mode in node.allowedFamilyModes)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(exitFamilyModeLabel(mode, widget.locale)),
                    ),
                ],
                onChanged: editable && !_busy
                    ? (mode) {
                        if (validView() &&
                            selected == node &&
                            node.allowedFamilyModes.contains(mode)) {
                          setState(() {
                            _draftSerial++;
                            _mode = mode;
                            _confirmClear = false;
                          });
                        }
                      }
                    : null,
              ),
              DropdownButton<api.LanAccess>(
                itemHeight: null,
                key: const Key('client-exit-lan'),
                isExpanded: true,
                value: _lan,
                hint: Text(
                  _text(
                    'Choose LAN policy',
                    'Выберите политику локальной сети',
                  ),
                ),
                items: [
                  for (final lan in node.allowedLanAccess)
                    DropdownMenuItem(
                      value: lan,
                      child: Text(exitLanAccessLabel(lan, widget.locale)),
                    ),
                ],
                onChanged: editable && !_busy
                    ? (lan) {
                        if (validView() &&
                            selected == node &&
                            node.allowedLanAccess.contains(lan)) {
                          setState(() {
                            _draftSerial++;
                            _lan = lan;
                            _confirmClear = false;
                          });
                        }
                      }
                    : null,
              ),
            ],
            if (_mode == api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV4_ONLY)
              Text(
                _text(
                  'IPv6 will not be protected by this exit selection.',
                  'Этот выбор выходного узла не защитит IPv6.',
                ),
              ),
            if (_mode == api.ExitFamilyMode.EXIT_FAMILY_MODE_IPV6_ONLY)
              Text(
                _text(
                  'IPv4 will not be protected by this exit selection.',
                  'Этот выбор выходного узла не защитит IPv4.',
                ),
              ),
            FilledButton(
              key: const Key('client-select-exit'),
              onPressed: canSelect && !_busy
                  ? () {
                      if (validView()) _run(select: true);
                    }
                  : null,
              child: Text(_text('Select exit node', 'Выбрать выходной узел')),
            ),
            OutlinedButton(
              key: const Key('client-clear-exit'),
              onPressed: editable && !_busy
                  ? () {
                      if (validView()) {
                        setState(() {
                          _draftSerial++;
                          _confirmClear = true;
                        });
                      }
                    }
                  : null,
              child: Text(_text('Clear exit node', 'Сбросить выходной узел')),
            ),
            if (_confirmClear) ...[
              Text(
                _text(
                  'Clear both exit families and restore ordinary routing policy?',
                  'Сбросить выходной узел для обоих семейств адресов и восстановить обычную политику маршрутизации?',
                ),
              ),
              TextButton(
                key: const Key('client-cancel-clear-exit'),
                onPressed: !_busy
                    ? () {
                        if (validView()) {
                          setState(() {
                            _draftSerial++;
                            _confirmClear = false;
                          });
                        }
                      }
                    : null,
                child: Text(_text('Cancel', 'Отмена')),
              ),
              FilledButton(
                key: const Key('client-confirm-clear-exit'),
                onPressed: editable && !_busy
                    ? () {
                        if (validView()) _run(clear: true);
                      }
                    : null,
                child: Text(_text('Confirm clear', 'Подтвердить сброс')),
              ),
            ],
          ],
        ],
      );
    },
  );
}
