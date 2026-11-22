import 'dart:convert';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import '../client/call_failure.dart';
import '../mcp/protocol.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({
    super.key,
    required this.diagnostics,
    required this.readServiceLogs,
  });

  final UiDiagnostics diagnostics;
  final Future<api.ListRecentLogsResponse?> Function(String pageToken)
  readServiceLogs;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final _serviceLogs = <api.LogEntry>[];
  late List<Json> _uiLogs;
  String _nextPage = '';
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _uiLogs = widget.diagnostics.snapshot();
    _loadServiceLogs();
  }

  Future<void> _loadServiceLogs({String pageToken = ''}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.readServiceLogs(pageToken);
      if (!mounted) return;
      setState(() {
        if (page == null) {
          _error = 'Служба Client недоступна.';
          return;
        }
        if (pageToken.isEmpty) _serviceLogs.clear();
        _serviceLogs.addAll(page.logs);
        _nextPage = page.page.nextPageToken;
      });
    } on ClientCallFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = switch (failure.reasonKey) {
          'ui.permission_required' => 'Журнал доступен владельцу установки.',
          'ui.stale_state' ||
          'client.state.stale' => 'Страница устарела. Обновите журнал.',
          'ui.unsupported' =>
            'Эта версия службы Client не предоставляет журнал.',
          _ => 'Не удалось прочитать журнал службы Client.',
        };
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Журналы'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Служба Client'),
            Tab(text: 'Интерфейс'),
          ],
        ),
      ),
      body: SafeArea(child: TabBarView(children: [_serviceTab(), _uiTab()])),
    ),
  );

  Widget _serviceTab() => Column(
    children: [
      _refreshBar(_loading ? null : () => _loadServiceLogs()),
      if (_loading) const LinearProgressIndicator(),
      if (_error case final error?)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      Expanded(
        child: _serviceLogs.isEmpty
            ? Center(
                child: !_loading && _error == null
                    ? const Text('Записей службы пока нет.')
                    : null,
              )
            : ListView.builder(
                key: const PageStorageKey('service-logs'),
                itemCount: _serviceLogs.length + (_nextPage.isEmpty ? 0 : 1),
                itemBuilder: (context, index) {
                  if (index == _serviceLogs.length) {
                    return Center(
                      child: TextButton(
                        onPressed: _loading || _error != null
                            ? null
                            : () => _loadServiceLogs(pageToken: _nextPage),
                        child: const Text('Показать ещё'),
                      ),
                    );
                  }
                  final entry = _serviceLogs[index];
                  return _entry(
                    entry.timestamp.toDateTime().toUtc().toIso8601String(),
                    entry.message,
                  );
                },
              ),
      ),
    ],
  );

  Widget _uiTab() => Column(
    children: [
      _refreshBar(
        () => setState(() => _uiLogs = widget.diagnostics.snapshot()),
      ),
      Expanded(
        child: _uiLogs.isEmpty
            ? const Center(child: Text('Событий интерфейса пока нет.'))
            : ListView.builder(
                key: const PageStorageKey('ui-logs'),
                itemCount: _uiLogs.length,
                itemBuilder: (context, index) {
                  final entry = _uiLogs[_uiLogs.length - 1 - index];
                  final state = entry['state'];
                  final message = '${entry['component']} · ${entry['event']}';
                  return _entry(
                    entry['time'] as String,
                    state == null ? message : '$message\n${jsonEncode(state)}',
                  );
                },
              ),
      ),
    ],
  );

  Widget _refreshBar(VoidCallback? refresh) => Align(
    alignment: AlignmentDirectional.centerEnd,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: OutlinedButton.icon(
        onPressed: refresh,
        icon: const Icon(Icons.refresh),
        label: const Text('Обновить'),
      ),
    ),
  );

  Widget _entry(String time, String message) =>
      ListTile(title: SelectableText(message), subtitle: Text(time));
}
