import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_peers.dart';
import 'client_locale.dart';
import 'client_peer_labels.dart';
import 'client_state_controller.dart';

class ClientPeersPanel extends StatefulWidget {
  const ClientPeersPanel({
    super.key,
    required this.state,
    required this.load,
    this.locale = ClientLocale.en,
    this.compact = false,
  });
  final ClientLocale locale;
  final bool compact;
  final ClientStateController state;
  final Future<ClientPeerCatalog> Function(String search) load;

  @override
  State<ClientPeersPanel> createState() => _ClientPeersPanelState();
}

class _ClientPeersPanelState extends State<ClientPeersPanel> {
  final _search = TextEditingController();
  ClientPeerCatalog? _catalog;
  bool _failed = false;
  String _text(String en, String ru) => widget.locale.text(en: en, ru: ru);
  String get _missing => _text('not reported', 'не сообщено');
  late String _context;
  var _serial = 0;
  var _busy = false;

  bool get _allowed =>
      mounted &&
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess !=
          api.Access.ACCESS_OBSERVER &&
      widget.state.snapshot!.status.activeProfileId.isNotEmpty;

  String get _key =>
      '${widget.state.cacheEpoch}:$_allowed:'
      '${widget.state.domainEpoch(api.Domain.DOMAIN_PEERS)}:'
      '${widget.state.domainEpoch(api.Domain.DOMAIN_NETWORKS)}:'
      '${widget.state.domainEpoch(api.Domain.DOMAIN_PROFILES)}';

  void _reset() {
    _serial++;
    _catalog = null;
    _failed = false;
    _busy = false;
  }

  void _scheduleRefresh() {
    if (!widget.compact) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _allowed && !_busy && _catalog == null && !_failed) {
        _load();
      }
    });
  }

  void _changed() {
    if (_context == _key) return;
    setState(() {
      _context = _key;
      _reset();
      _search.clear();
    });
    _scheduleRefresh();
  }

  @override
  void initState() {
    super.initState();
    _context = _key;
    widget.state.addListener(_changed);
    _scheduleRefresh();
  }

  @override
  void didUpdateWidget(covariant ClientPeersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_changed);
      widget.state.addListener(_changed);
      _context = _key;
      _reset();
      _search.clear();
      _scheduleRefresh();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_allowed || _busy) return;
    final key = _key;
    final query = _search.text;
    final serial = ++_serial;
    setState(() {
      _busy = true;
      _catalog = null;
      _failed = false;
    });
    bool current() =>
        mounted &&
        _allowed &&
        key == _key &&
        serial == _serial &&
        query == _search.text;
    try {
      final result = await widget.load(query);
      if (!current()) return;
      final snapshot = widget.state.snapshot!;
      if (result.search != query ||
          result.profileId != snapshot.status.activeProfileId ||
          result.metadata.instanceId != snapshot.runtime.instanceId ||
          result.metadata.revision < snapshot.status.metadata.revision) {
        throw StateError('Stale peer catalog');
      }
      setState(() => _catalog = result);
    } catch (_) {
      if (current()) {
        setState(() => _failed = true);
      }
    } finally {
      if (current()) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.compact
      ? _summary(context)
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(header: true, child: Text(_text('Peers', 'Устройства'))),
            TextField(
              key: const Key('client-peer-search'),
              controller: _search,
              enabled: _allowed,
              decoration: InputDecoration(
                labelText: _text('Search peers', 'Поиск устройств'),
              ),
              onChanged: (_) => setState(_reset),
            ),
            OutlinedButton(
              key: const Key('client-load-peers'),
              onPressed: _allowed && !_busy ? _load : null,
              child: Text(
                _busy
                    ? _text('Loading peers…', 'Загрузка устройств…')
                    : _text('Refresh peers', 'Обновить устройства'),
              ),
            ),
            if (_failed)
              Semantics(
                liveRegion: true,
                child: Text(
                  _text(
                    'Peer information could not be confirmed. Refresh to try again.',
                    'Не удалось подтвердить сведения об устройствах. Обновите список, чтобы повторить попытку.',
                  ),
                ),
              ),
            if (_catalog case final catalog?) ...[
              Text(
                '${_text('Snapshot', 'Состояние снимка')}: ${peerSnapshotLabel(catalog.snapshotState, widget.locale)}',
              ),
              Text(
                '${_text('Applied map', 'Применённая карта')}: ${catalog.mapRevision}; ${_text('target map', 'целевая карта')}: ${catalog.targetMapRevision}',
              ),
              Text(
                _text(
                  'Runtime observations; this screen does not probe peers.',
                  'Наблюдения службы; этот экран не проверяет доступность устройств.',
                ),
              ),
              if (catalog.peers.isEmpty)
                Text(
                  _text(
                    'No peers in this response.',
                    'В этом ответе нет устройств.',
                  ),
                ),
              for (final peer in catalog.peers)
                ExpansionTile(
                  key: ValueKey('client-peer-${peer.id}'),
                  title: Text(peer.hostname.isEmpty ? peer.id : peer.hostname),
                  subtitle: Text(
                    'ID: ${peer.id}\n${_text('Selected path', 'Выбранный путь')}: ${peerPathLabel(peer.selectedPath, widget.locale)}',
                  ),
                  children: [
                    Text(
                      '${_text('Overlay addresses', 'Адреса оверлейной сети')}: ${peer.overlayAddresses.join(', ')}',
                    ),
                    Text(
                      '${_text('Selected endpoint', 'Выбранный адрес подключения')}: ${peer.selectedEndpoint.isEmpty ? _missing : peer.selectedEndpoint}',
                    ),
                    Text(
                      '${_text('Selection reason', 'Код причины выбора')}: ${peer.selectionReasonKey.isEmpty ? _missing : peer.selectionReasonKey}',
                    ),
                    Text(
                      '${_text('Last transition', 'Последний переход')}: ${peer.hasLastTransitionAt() ? peer.lastTransitionAt.toProto3Json() : _missing}',
                    ),
                    if (peer.candidates.isEmpty)
                      Text(
                        _text(
                          'No path candidates reported.',
                          'Варианты пути не сообщены.',
                        ),
                      ),
                    for (final candidate in peer.candidates)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          '${_text('Candidate', 'Вариант пути')}: ${peerPathLabel(candidate.kind, widget.locale)}; ${peerHealthLabel(candidate.health, widget.locale)}\n'
                          '${_text('Endpoint', 'Адрес подключения')}: ${candidate.endpoint}; ${_text('relay', 'ретранслятор')}: ${candidate.relayId}\n'
                          '${_text('Protocol', 'Протокол')}: ${candidate.protocol}; ${_text('tier', 'уровень')}: ${candidate.tier}; ${_text('priority', 'приоритет')}: ${candidate.priority}\n'
                          'RTT: ${candidate.hasRtt() ? candidate.rtt.toProto3Json() : _missing}\n'
                          '${_text('Checked', 'Проверено')}: ${candidate.hasCheckedAt() ? candidate.checkedAt.toProto3Json() : _missing}\n'
                          '${_text('Last reachable', 'Последняя доступность')}: ${candidate.hasLastReachableAt() ? candidate.lastReachableAt.toProto3Json() : _missing}\n'
                          '${_text('Consecutive failures', 'Ошибок подряд')}: ${candidate.consecutiveFailures}; ${_text('reason', 'код причины')}: ${candidate.reasonKey}',
                        ),
                      ),
                  ],
                ),
            ],
          ],
        );
  Widget _summary(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _text('Network devices', 'Устройства в сети'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_catalog != null) Text('${_catalog!.peers.length}'),
              IconButton(
                key: const Key('home-refresh-peers'),
                tooltip: _text('Refresh peers', 'Обновить устройства'),
                onPressed: _allowed && !_busy ? _load : null,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (!_allowed)
            Text(
              _text(
                'Select a profile to see its devices.',
                'Выберите профиль, чтобы увидеть устройства.',
              ),
            ),
          if (_failed)
            Text(
              _text(
                'Device list unavailable. Try refreshing.',
                'Список устройств недоступен. Попробуйте обновить.',
              ),
            ),
          if (_allowed && !_busy && !_failed && _catalog == null)
            Text(
              _text(
                'Device list has not been loaded.',
                'Список устройств ещё не загружен.',
              ),
            ),
          if (_catalog case final catalog?) ...[
            if (catalog.snapshotState !=
                api.AgentSnapshotState.AGENT_SNAPSHOT_STATE_CURRENT)
              Text(
                '${_text('Snapshot', 'Состояние снимка')}: ${peerSnapshotLabel(catalog.snapshotState, widget.locale)}',
              ),
            if (catalog.peers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _text(
                    'No devices in this network yet.',
                    'В этой сети пока нет устройств.',
                  ),
                ),
              ),
            for (final peer in catalog.peers.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: Icon(
                      Icons.computer_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      peer.hostname.isEmpty ? peer.id : peer.hostname,
                    ),
                    subtitle: Text(
                      [
                        if (peer.overlayAddresses.isNotEmpty)
                          peer.overlayAddresses.join(', '),
                        peerPathLabel(peer.selectedPath, widget.locale),
                      ].join(' · '),
                    ),
                  ),
                ),
              ),
            if (catalog.peers.length > 5)
              Text(
                _text(
                  'More devices are available on the Network page.',
                  'Остальные устройства доступны в разделе «Сеть».',
                ),
              ),
          ],
        ],
      ),
    ),
  );
}
