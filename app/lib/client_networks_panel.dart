import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_networks.dart';
import 'client_locale.dart';
import 'client_operation.dart';
import 'client_state_controller.dart';

class ClientNetworksPanel extends StatefulWidget {
  const ClientNetworksPanel({
    super.key,
    required this.state,
    required this.load,
    required this.select,
    this.locale = ClientLocale.en,
  });
  final ClientLocale locale;
  final ClientStateController state;
  final Future<ClientNetworkCatalog> Function() load;
  final Future<ClientOperation> Function(String profileId, String networkId)
  select;
  @override
  State<ClientNetworksPanel> createState() => _ClientNetworksPanelState();
}

enum _NetworkNotice { accepted, result, unknown }

class _ClientNetworksPanelState extends State<ClientNetworksPanel> {
  ClientNetworkCatalog? _catalog;
  ClientStateController? _catalogState;
  String? _profileId;
  int? _profilesDomain;
  int? _epoch;
  int? _domain;
  bool _busy = false;
  _NetworkNotice? _notice;
  String _text(String en, String ru) => widget.locale.text(en: en, ru: ru);
  String _noticeText(_NetworkNotice notice) => switch (notice) {
    _NetworkNotice.accepted => _text(
      'Network selection accepted. Recover the operation for its result.',
      'Выбор сети принят. Восстановите операцию, чтобы узнать результат.',
    ),
    _NetworkNotice.result => _text(
      'Network selection result received. Refresh runtime status.',
      'Получен результат выбора сети. Обновите состояние клиента.',
    ),
    _NetworkNotice.unknown => _text(
      'Network request could not be confirmed. Recover any pending selection before retrying.',
      'Не удалось подтвердить запрос сети. Восстановите незавершённый выбор сети перед повторной попыткой.',
    ),
  };
  bool get _owner =>
      mounted &&
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess !=
          api.Access.ACCESS_OBSERVER &&
      widget.state.snapshot!.status.activeProfileId.isNotEmpty;
  bool get _current =>
      _owner &&
      identical(_catalogState, widget.state) &&
      _profileId == widget.state.snapshot!.status.activeProfileId &&
      _profilesDomain == widget.state.domainEpoch(api.Domain.DOMAIN_PROFILES) &&
      _epoch == widget.state.cacheEpoch &&
      _domain == widget.state.domainEpoch(api.Domain.DOMAIN_NETWORKS);

  Future<void> _run([String? id]) async {
    if (_busy || !_owner) return;
    if (id != null &&
        (!_current ||
            _catalog == null ||
            !_catalog!.networks.any(
              (n) =>
                  n.id == id &&
                  id != _catalog!.selectedNetworkId &&
                  n.selection.availability ==
                      api.Availability.AVAILABILITY_AVAILABLE,
            ))) {
      return;
    }
    final profileId = widget.state.snapshot!.status.activeProfileId;
    setState(() {
      _catalogState = widget.state;
      _profileId = profileId;
      _profilesDomain = widget.state.domainEpoch(api.Domain.DOMAIN_PROFILES);
      _epoch = widget.state.cacheEpoch;
      _domain = widget.state.domainEpoch(api.Domain.DOMAIN_NETWORKS);
      _busy = true;
      _notice = null;
      _catalog = null;
    });
    try {
      if (id == null) {
        final catalog = await widget.load();
        if (!mounted || !_current || catalog.profileId != profileId) return;
        setState(() => _catalog = catalog);
      } else {
        final operation = await widget.select(profileId, id);
        if (!mounted || !_current) return;
        setState(
          () => _notice = operation.terminal
              ? _NetworkNotice.result
              : _NetworkNotice.accepted,
        );
      }
    } catch (_) {
      if (!mounted || !_current) return;
      setState(() => _notice = _NetworkNotice.unknown);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final renderedState = widget.state;
      final renderedSnapshot = widget.state.snapshot;
      final renderedCatalog = _catalog;
      final epoch = widget.state.cacheEpoch;
      final networks = widget.state.domainEpoch(api.Domain.DOMAIN_NETWORKS);
      final profiles = widget.state.domainEpoch(api.Domain.DOMAIN_PROFILES);
      bool current() =>
          mounted &&
          identical(widget.state, renderedState) &&
          identical(widget.state.snapshot, renderedSnapshot) &&
          identical(_catalog, renderedCatalog) &&
          widget.state.cacheEpoch == epoch &&
          widget.state.domainEpoch(api.Domain.DOMAIN_NETWORKS) == networks &&
          widget.state.domainEpoch(api.Domain.DOMAIN_PROFILES) == profiles;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton(
            key: const Key('client-load-networks'),
            onPressed: _owner && !_busy
                ? () {
                    if (current()) _run();
                  }
                : null,
            child: Text(_text('Refresh networks', 'Обновить сети')),
          ),
          if (_current && _notice != null)
            Semantics(liveRegion: true, child: Text(_noticeText(_notice!))),
          if (_current && _catalog != null) ...[
            if (_catalog!.networks.isEmpty)
              Text(_text('No networks', 'Нет сетей')),
            for (final network in _catalog!.networks)
              ListTile(
                title: Text(network.name),
                subtitle: Text(network.id),
                trailing: network.id == _catalog!.selectedNetworkId
                    ? Text(_text('Selected', 'Выбрана'))
                    : TextButton(
                        key: ValueKey('select-network-${network.id}'),
                        onPressed:
                            !_busy &&
                                network.selection.availability ==
                                    api.Availability.AVAILABILITY_AVAILABLE
                            ? () {
                                if (current()) _run(network.id);
                              }
                            : null,
                        child: Text(_text('Select', 'Выбрать')),
                      ),
              ),
          ],
        ],
      );
    },
  );
}
