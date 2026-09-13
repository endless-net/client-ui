import 'dart:convert';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'client_operation.dart';
import 'client_resources.dart';
import 'client_state_controller.dart';

class ClientResourcesPanel extends StatefulWidget {
  const ClientResourcesPanel({
    super.key,
    required this.state,
    required this.load,
    required this.setEnabled,
    this.openBrowser,
  });
  final ClientStateController state;
  final Future<ClientResourceCatalog> Function(String, List<api.ResourceKind>)
  load;
  final Future<ClientOperation> Function(String, String, bool, void Function())
  setEnabled;
  final Future<bool> Function(Uri, void Function())? openBrowser;
  @override
  State<ClientResourcesPanel> createState() => _ClientResourcesPanelState();
}

class _ClientResourcesPanelState extends State<ClientResourcesPanel> {
  final _search = TextEditingController();
  final _kinds = <api.ResourceKind>{};
  ClientResourceCatalog? _catalog;
  String? _context;
  String? _notice;
  int _query = 0;
  bool _busy = false;
  String? _seenContext;
  String get contextId =>
      '${widget.state.cacheEpoch}:'
      '${[api.Domain.DOMAIN_PROFILES, api.Domain.DOMAIN_RESOURCES, api.Domain.DOMAIN_NETWORKS].map(widget.state.domainEpoch).join(',')}';
  bool get allowed =>
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess !=
          api.Access.ACCESS_OBSERVER &&
      widget.state.snapshot!.status.activeProfileId.isNotEmpty &&
      widget.state.snapshot!.supports(api.Capability.CAPABILITY_RESOURCES);
  bool get current => allowed && _context == contextId;
  void _clear() {
    _catalog = null;
    _notice = null;
    _context = null;
    _query++;
  }

  void _changed() {
    if (_seenContext != contextId || !allowed) {
      _seenContext = contextId;
      setState(() {
        _clear();
        _search.clear();
        _kinds.clear();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _seenContext = contextId;
    widget.state.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant ClientResourcesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_changed);
      widget.state.addListener(_changed);
      _clear();
      _search.clear();
      _kinds.clear();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_changed);
    _clear();
    _search.dispose();
    super.dispose();
  }

  bool editable(api.Resource resource) =>
      resource.availability.availability ==
          api.Availability.AVAILABILITY_AVAILABLE &&
      !resource.enabled.control.locked &&
      resource.enabled.control.mutation.availability ==
          api.Availability.AVAILABILITY_AVAILABLE;

  Uri? browserUri(api.Resource resource) {
    if (resource.kind != api.ResourceKind.RESOURCE_KIND_APPLICATION ||
        !resource.hasApplication() ||
        resource.availability.availability !=
            api.Availability.AVAILABILITY_AVAILABLE) {
      return null;
    }
    final uri = Uri.tryParse(resource.application.browserUrl);
    return uri != null &&
            uri.scheme == 'https' &&
            uri.hasAuthority &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri
        : null;
  }

  Future<void> _open(api.Resource resource) async {
    final catalog = _catalog;
    final launch = widget.openBrowser;
    final uri = browserUri(resource);
    if (_busy ||
        !current ||
        catalog == null ||
        launch == null ||
        uri == null ||
        !catalog.resources.any((r) => identical(r, resource))) {
      return;
    }
    final context = _context;
    final query = _query;
    void check() {
      if (!mounted || !current || context != _context || query != _query) {
        throw StateError('Resource context changed before browser launch');
      }
    }

    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final fresh = await widget.load(catalog.search, catalog.kinds);
      check();
      if (fresh.profileId != catalog.profileId ||
          fresh.search != catalog.search ||
          fresh.kinds.length != catalog.kinds.length ||
          !fresh.kinds.toSet().containsAll(catalog.kinds) ||
          fresh.metadata.instanceId !=
              widget.state.snapshot!.runtime.instanceId ||
          fresh.metadata.revision <
              widget.state.snapshot!.status.metadata.revision) {
        throw const FormatException('Stale resource browser query');
      }
      final matches = fresh.resources.where((r) => r.id == resource.id);
      if (matches.length != 1 ||
          browserUri(matches.single) == null ||
          matches.single.application.browserUrl !=
              resource.application.browserUrl) {
        throw StateError('Resource destination or availability changed');
      }
      check();
      final opened = await launch(uri, check);
      check();
      setState(() {
        _catalog = fresh;
        _notice = opened
            ? 'Resource opened in the browser.'
            : 'Browser could not open the resource.';
      });
    } catch (_) {
      if (!mounted || !current || context != _context || query != _query) {
        return;
      }
      setState(() {
        _catalog = null;
        _notice =
            'Resource access or destination could not be confirmed. Refresh before opening.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run({api.Resource? resource, bool? enabled}) async {
    if (_busy || !allowed || utf8.encode(_search.text).length > 256) return;
    if (resource != null &&
        (!current ||
            _catalog == null ||
            !editable(resource) ||
            !_catalog!.resources.any((r) => identical(r, resource)) ||
            enabled == null)) {
      return;
    }
    final context = contextId;
    final query = _query;
    final profile = widget.state.snapshot!.status.activeProfileId;
    final search = _search.text;
    final kinds = List<api.ResourceKind>.unmodifiable(_kinds);
    void check() {
      if (!mounted || !current || context != _context || query != _query) {
        throw StateError('Resource context changed');
      }
    }

    setState(() {
      _context = context;
      _busy = true;
      _notice = null;
    });
    try {
      if (resource == null) {
        setState(() => _catalog = null);
        final result = await widget.load(search, kinds);
        check();
        if (result.profileId != profile ||
            result.search != search ||
            result.kinds.length != kinds.length ||
            !result.kinds.toSet().containsAll(kinds) ||
            result.metadata.instanceId !=
                widget.state.snapshot!.runtime.instanceId ||
            result.metadata.revision <
                widget.state.snapshot!.status.metadata.revision) {
          throw const FormatException('Stale resource query');
        }
        setState(() => _catalog = result);
      } else {
        check();
        await widget.setEnabled(profile, resource.id, enabled!, check);
        check();
        setState(() {
          _catalog = null;
          _notice =
              'Resource operation received. Recover its result and refresh effective values.';
        });
      }
    } catch (_) {
      if (!mounted || !current || query != _query) return;
      setState(() {
        _catalog = null;
        _notice =
            'Resource request could not be confirmed. Recover pending operations before retrying.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final view = _catalog;
      final viewContext = _context;
      final query = _query;
      bool validView() =>
          current &&
          !_busy &&
          identical(view, _catalog) &&
          viewContext == _context &&
          query == _query;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('client-resource-search'),
            controller: _search,
            enabled: allowed,
            decoration: InputDecoration(
              labelText: 'Search resources',
              errorText: utf8.encode(_search.text).length > 256
                  ? 'Maximum 256 UTF-8 bytes'
                  : null,
            ),
            onChanged: (_) => setState(_clear),
          ),
          Wrap(
            children: [
              for (final kind in api.ResourceKind.values)
                if (kind != api.ResourceKind.RESOURCE_KIND_UNSPECIFIED)
                  FilterChip(
                    key: ValueKey('resource-kind-${kind.value}'),
                    label: Text(kind.name),
                    selected: _kinds.contains(kind),
                    onSelected: allowed
                        ? (selected) {
                            setState(() {
                              _clear();
                              selected ? _kinds.add(kind) : _kinds.remove(kind);
                            });
                          }
                        : null,
                  ),
            ],
          ),
          OutlinedButton(
            key: const Key('client-load-resources'),
            onPressed:
                allowed && !_busy && utf8.encode(_search.text).length <= 256
                ? () => _run()
                : null,
            child: const Text('Search resources'),
          ),
          if (current && _notice != null) Text(_notice!),
          if (current && view != null) ...[
            if (view.resources.isEmpty) const Text('No matching resources'),
            for (final resource in view.resources)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(resource.displayName),
                  if (widget.openBrowser != null &&
                      browserUri(resource) != null)
                    TextButton(
                      key: ValueKey('open-resource-${resource.id}'),
                      onPressed: !_busy
                          ? () {
                              if (validView()) _open(resource);
                            }
                          : null,
                      child: const Text('Open resource in browser'),
                    ),
                  Text('${resource.kind.name}: ${_target(resource)}'),
                  Text(
                    'Effective: ${resource.enabled.effective}; requested: '
                    '${resource.enabled.hasRequested() ? resource.enabled.requested : 'No override'}',
                  ),
                  Text(
                    'Availability: ${resource.availability.availability.name}; reason: '
                    '${resource.availability.reasonKey}; owner: ${resource.availability.actionOwner.name}',
                  ),
                  Text(
                    'Source: ${resource.enabled.control.source.name}; locked: ${resource.enabled.control.locked}',
                  ),
                  Text(
                    'Mutation: ${resource.enabled.control.mutation.availability.name}; '
                    'reason: ${resource.enabled.control.mutation.reasonKey}; '
                    'owner: ${resource.enabled.control.mutation.actionOwner.name}',
                  ),
                  if (resource.overlappingResourceIds.isNotEmpty)
                    Text(
                      'Overlap: ${resource.overlappingResourceIds.join(', ')}; ${resource.overlapReasonKey}',
                    ),
                  Wrap(
                    children: [
                      for (final enabled in [true, false])
                        TextButton(
                          key: ValueKey('resource-${resource.id}-$enabled'),
                          onPressed:
                              !_busy &&
                                  editable(resource) &&
                                  (!resource.enabled.hasRequested() ||
                                      resource.enabled.requested != enabled)
                              ? () {
                                  if (validView()) {
                                    _run(resource: resource, enabled: enabled);
                                  }
                                }
                              : null,
                          child: Text(
                            enabled ? 'Enable resource' : 'Disable resource',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
          ],
        ],
      );
    },
  );
}

String _target(api.Resource resource) => switch (resource.whichTarget()) {
  api.Resource_Target.host =>
    '${resource.host.hostname} ${resource.host.addresses.join(', ')}',
  api.Resource_Target.subnet => resource.subnet.cidr,
  api.Resource_Target.service =>
    '${resource.service.hostname}:${resource.service.port}/${resource.service.protocol}',
  api.Resource_Target.application => resource.application.displayAddress,
  _ => 'Unavailable',
};
