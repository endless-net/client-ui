import 'dart:convert';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'client_operation.dart';
import 'client_resources.dart';
import 'client_state_controller.dart';
import 'client_locale.dart';
import 'client_resource_labels.dart';
import 'client_update_labels.dart';
import 'client_operation_labels.dart';

enum _ResourceNotice { opened, notOpened, destination, received, unknown }

class ClientResourcesPanel extends StatefulWidget {
  const ClientResourcesPanel({
    super.key,
    required this.state,
    required this.load,
    required this.setEnabled,
    this.openBrowser,
    this.locale = ClientLocale.en,
  });
  final ClientStateController state;
  final ClientLocale locale;
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
  _ResourceNotice? _notice;
  String _text(String en, String ru) => widget.locale.text(en: en, ru: ru);
  String _boolean(bool value) =>
      value ? _text('Yes', 'Да') : _text('No', 'Нет');
  String _noticeText(_ResourceNotice notice) => switch (notice) {
    _ResourceNotice.opened => _text(
      'Resource address handed to the browser. Reachability has not been verified.',
      'Адрес ресурса передан браузеру. Доступность назначения не проверена.',
    ),
    _ResourceNotice.notOpened => _text(
      'Browser could not open the resource.',
      'Браузер не смог открыть ресурс.',
    ),
    _ResourceNotice.destination => _text(
      'Resource access or destination could not be confirmed. Refresh before opening.',
      'Не удалось подтвердить доступ к ресурсу или его адрес. Обновите сведения перед открытием.',
    ),
    _ResourceNotice.received => _text(
      'Resource operation received. Recover its result and refresh effective values.',
      'Операция с ресурсом получена. Восстановите её результат и обновите фактические значения.',
    ),
    _ResourceNotice.unknown => _text(
      'Resource request could not be confirmed. Recover pending operations before retrying.',
      'Не удалось подтвердить запрос ресурса. Восстановите незавершённые операции перед повторной попыткой.',
    ),
  };
  int _query = 0;
  bool _busy = false;
  String? _seenContext;
  String get contextId =>
      '${widget.state.cacheEpoch}:'
      '${[api.Domain.DOMAIN_PROFILES, api.Domain.DOMAIN_RESOURCES, api.Domain.DOMAIN_NETWORKS].map(widget.state.domainEpoch).join(',')}';
  bool get allowed =>
      mounted &&
      widget.state.link == ClientLinkState.ready &&
      widget.state.snapshot != null &&
      widget.state.snapshot!.runtime.callerAccess !=
          api.Access.ACCESS_OBSERVER &&
      widget.state.snapshot!.status.activeProfileId.isNotEmpty &&
      widget.state.snapshot!.supports(api.Capability.CAPABILITY_RESOURCES);
  bool get current => allowed && _context == contextId;
  void _clear() {
    _busy = false;
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
        _notice = opened ? _ResourceNotice.opened : _ResourceNotice.notOpened;
      });
    } catch (_) {
      if (!mounted || !current || context != _context || query != _query) {
        return;
      }
      setState(() {
        _catalog = null;
        _notice = _ResourceNotice.destination;
      });
    } finally {
      if (mounted && query == _query) setState(() => _busy = false);
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
          _notice = _ResourceNotice.received;
        });
      }
    } catch (_) {
      if (!mounted || !current || query != _query) return;
      setState(() {
        _catalog = null;
        _notice = _ResourceNotice.unknown;
      });
    } finally {
      if (mounted && query == _query) setState(() => _busy = false);
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
              labelText: _text('Search resources', 'Поиск ресурсов'),
              errorText: utf8.encode(_search.text).length > 256
                  ? _text('Maximum 256 UTF-8 bytes', 'Не более 256 байт UTF-8')
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
                    label: Text(resourceKindLabel(kind, widget.locale)),
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
            child: Text(_text('Search resources', 'Поиск ресурсов')),
          ),
          if (current && _notice != null)
            Semantics(liveRegion: true, child: Text(_noticeText(_notice!))),
          if (current && view != null) ...[
            if (view.resources.isEmpty)
              Text(_text('No matching resources', 'Подходящих ресурсов нет')),
            for (final resource in view.resources)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(resource.displayName),
                  Text('${_text('Resource ID', 'ID ресурса')}: ${resource.id}'),
                  Text(
                    '${_text('Network ID', 'ID сети')}: ${resource.networkId}',
                  ),
                  if (widget.openBrowser != null &&
                      browserUri(resource) != null)
                    TextButton(
                      key: ValueKey('open-resource-${resource.id}'),
                      onPressed: !_busy
                          ? () {
                              if (validView()) _open(resource);
                            }
                          : null,
                      child: Text(
                        _text(
                          'Open resource in browser',
                          'Открыть ресурс в браузере',
                        ),
                        semanticsLabel: _text(
                          'Open resource ${resource.displayName}, ID ${resource.id}, in browser',
                          'Открыть ресурс ${resource.displayName}, ID ${resource.id}, в браузере',
                        ),
                      ),
                    ),
                  Text(
                    '${resourceKindLabel(resource.kind, widget.locale)}: ${_target(resource, widget.locale)}',
                  ),
                  Text(
                    '${_text('Effective', 'Фактически')}: ${_boolean(resource.enabled.effective)}; ${_text('requested', 'Запрошено')}: '
                    '${resource.enabled.hasRequested() ? _boolean(resource.enabled.requested) : _text('No override', 'Без переопределения')}',
                  ),
                  Text(
                    '${_text('Availability', 'Доступность')}: ${updateAvailabilityLabel(resource.availability.availability, widget.locale)}; ${_text('reason', 'Код причины')}: '
                    '${resource.availability.reasonKey}; ${_text('owner', 'Ответственный')}: ${clientActionOwnerLabel(resource.availability.actionOwner, locale: widget.locale)}',
                  ),
                  Text(
                    '${_text('Source', 'Источник')}: ${settingSourceLabel(resource.enabled.control.source, widget.locale)}; ${_text('locked', 'Заблокировано')}: ${_boolean(resource.enabled.control.locked)}',
                  ),
                  Text(
                    '${_text('Mutation', 'Изменение')}: ${updateAvailabilityLabel(resource.enabled.control.mutation.availability, widget.locale)}; '
                    '${_text('reason', 'Код причины')}: ${resource.enabled.control.mutation.reasonKey}; '
                    '${_text('owner', 'Ответственный')}: ${clientActionOwnerLabel(resource.enabled.control.mutation.actionOwner, locale: widget.locale)}',
                  ),
                  if (resource.overlappingResourceIds.isNotEmpty)
                    Text(
                      '${_text('Overlap', 'Пересечение')}: ${resource.overlappingResourceIds.join(', ')}; ${resource.overlapReasonKey}',
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
                            enabled
                                ? _text('Enable resource', 'Включить ресурс')
                                : _text('Disable resource', 'Отключить ресурс'),
                            semanticsLabel: enabled
                                ? _text(
                                    'Enable resource ${resource.displayName}, ID ${resource.id}',
                                    'Включить ресурс ${resource.displayName}, ID ${resource.id}',
                                  )
                                : _text(
                                    'Disable resource ${resource.displayName}, ID ${resource.id}',
                                    'Отключить ресурс ${resource.displayName}, ID ${resource.id}',
                                  ),
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

String _target(api.Resource resource, ClientLocale locale) => switch (resource
    .whichTarget()) {
  api.Resource_Target.host =>
    '${resource.host.hostname} ${resource.host.addresses.join(', ')}',
  api.Resource_Target.subnet => resource.subnet.cidr,
  api.Resource_Target.service =>
    '${resource.service.hostname}:${resource.service.port}/${resource.service.protocol}',
  api.Resource_Target.application => resource.application.displayAddress,
  _ => locale.text(en: 'Unavailable', ru: 'Недоступно'),
};
