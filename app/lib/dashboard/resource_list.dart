import 'dart:async';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import '../client/connectivity_client.dart';

class NetworkResourceList extends StatefulWidget {
  const NetworkResourceList({
    super.key,
    required this.client,
    required this.timeout,
    required this.status,
  });
  final ResourceClient client;
  final Duration timeout;
  final api.Status status;
  @override
  State<NetworkResourceList> createState() => _ResourceListState();
}

class _ResourceListState extends State<NetworkResourceList> {
  final _rows = <api.Resource>[];
  final _tokens = <String>{};
  bool _busy = false, _loaded = false, _failed = false;
  bool _refreshPending = false;
  String _next = '';

  @override
  void didUpdateWidget(NetworkResourceList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.status;
    final current = widget.status;
    if ((!_loaded && !_busy && !_failed) ||
        (old.agent.generatedAt == current.agent.generatedAt &&
            old.agent.mapRevision == current.agent.mapRevision &&
            old.agent.targetMapRevision == current.agent.targetMapRevision &&
            old.metadata.revision == current.metadata.revision)) {
      return;
    }
    _rows.clear();
    _next = '';
    if (_busy) {
      _refreshPending = true;
    } else {
      unawaited(_read(''));
    }
  }

  Future<void> _read(String token) async {
    if (_busy) return;
    final snapshot = widget.status;
    setState(() {
      _busy = true;
      _failed = false;
      if (token.isEmpty) {
        _tokens.clear();
        _rows.clear();
        _loaded = false;
        _next = '';
      }
    });
    try {
      final r = await widget.client
          .listResources(
            api.ListResourcesRequest(
              profile: api.ProfileRef(profileId: snapshot.activeProfileId),
              page: api.PageRequest(pageToken: token, pageSize: 50),
            ),
            widget.timeout,
          )
          .timeout(widget.timeout);
      if (!mounted || _refreshPending) return;
      final ids = _rows.map((row) => row.id).toSet();
      final cursor = r.page.nextPageToken;
      if (r.page.metadata.instanceId != snapshot.metadata.instanceId ||
          r.page.metadata.revision != widget.status.metadata.revision ||
          r.resources.length > 50 ||
          (cursor.isNotEmpty &&
              (r.resources.isEmpty || !_tokens.add(cursor))) ||
          r.resources.any(
            (row) =>
                row.networkId != snapshot.network.id ||
                row.id.isEmpty ||
                !ids.add(row.id),
          )) {
        throw const FormatException('resource snapshot');
      }
      setState(() {
        _rows.addAll(r.resources);
        _next = cursor;
        _loaded = true;
      });
    } catch (_) {
      if (mounted && !_refreshPending) {
        setState(() {
          _rows.clear();
          _loaded = false;
          _next = '';
          _failed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_refreshPending) {
          _refreshPending = false;
          unawaited(_read(''));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton(
        onPressed: _busy ? null : () => _read(''),
        child: Text(
          _loaded || _failed
              ? 'Обновить ресурсы сети'
              : 'Показать ресурсы сети',
        ),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_failed)
        const Text('Не удалось получить актуальный список ресурсов.'),
      if (_loaded && _rows.isEmpty)
        const Text('В текущей карте нет назначенных ресурсов.'),
      for (final row in _rows)
        ListTile(
          title: Text(row.displayName),
          subtitle: Text(
            [
              if (row.hasSubnet()) row.subnet.cidr,
              if (row.hasHost() && row.host.hostname.isNotEmpty)
                row.host.hostname,
              if (row.hasHost()) ...row.host.addresses,
              switch (row.availability.availability) {
                api.Availability.AVAILABILITY_AVAILABLE => 'Путь установлен',
                api.Availability.AVAILABILITY_TEMPORARILY_UNAVAILABLE =>
                  'Путь недоступен',
                _ => 'Состояние пути неизвестно',
              },
            ].join(' · '),
          ),
        ),
      if (_next.isNotEmpty)
        TextButton(
          onPressed: _busy ? null : () => _read(_next),
          child: const Text('Ещё ресурсы'),
        ),
    ],
  );
}
