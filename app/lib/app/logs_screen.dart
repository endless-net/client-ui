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
            : ListView.separated(
                key: const PageStorageKey('service-logs'),
                itemCount: _serviceLogs.length + (_nextPage.isEmpty ? 0 : 1),
                separatorBuilder: (_, _) => const Divider(height: 1),
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
                  return _serviceEntry(_serviceLogs[index], index);
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
      if (widget.diagnostics.recovery.storageUnavailable)
        const ListTile(
          title: Text('Сохранённый журнал восстановления недоступен.'),
        ),
      if (widget.diagnostics.recovery.historyGap)
        const ListTile(title: Text('Часть истории восстановления недоступна.')),
      Expanded(
        child: _uiLogs.isEmpty
            ? const Center(child: Text('Событий интерфейса пока нет.'))
            : ListView.separated(
                key: const PageStorageKey('ui-logs'),
                itemCount: _uiLogs.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = _uiLogs[_uiLogs.length - 1 - index];
                  final state = entry['state'];
                  final message = '${entry['component']} · ${entry['event']}';
                  return _entry(
                    key: PageStorageKey((
                      entry['component'],
                      entry['sequence'],
                    )),
                    title: message,
                    summary: _formatTime(
                      DateTime.parse(entry['time'] as String),
                    ),
                    details: state is Json ? state : const {},
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

  Widget _serviceEntry(api.LogEntry entry, int index) {
    final time = _formatTime(entry.timestamp.toDateTime());
    final Json fields;
    try {
      final decoded = jsonDecode(entry.message);
      if (decoded is! Json || decoded.isEmpty) {
        return ListTile(
          title: SelectableText(entry.message),
          subtitle: Text(time),
        );
      }
      fields = decoded;
    } on FormatException {
      return ListTile(
        title: SelectableText(entry.message),
        subtitle: Text(time),
      );
    }

    final title = fields['operation'] ?? fields['msg'] ?? 'Событие службы';
    final summary = [
      time,
      for (final field in ['level', 'outcome', 'code'])
        if (fields[field] case final String value when value.isNotEmpty) value,
    ].join(' · ');
    return _entry(
      key: PageStorageKey((
        'service',
        index,
        entry.timestamp.toDateTime(),
        entry.message,
      )),
      title: '$title',
      summary: summary,
      details: {
        for (final field in fields.entries)
          if (!const {
                'time',
                'level',
                'operation',
                'outcome',
                'code',
              }.contains(field.key) &&
              (field.key != 'msg' || field.value != title))
            field.key: field.value,
      },
    );
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final seconds = local
        .toIso8601String()
        .split('.')
        .first
        .replaceFirst('T', ' ');
    return '$seconds.${local.millisecond.toString().padLeft(3, '0')}';
  }

  Widget _entry({
    required Key key,
    required String title,
    required String summary,
    required Json details,
  }) {
    if (details.isEmpty) {
      return ListTile(title: SelectableText(title), subtitle: Text(summary));
    }
    return ExpansionTile(
      key: key,
      title: Text(title),
      subtitle: Text(summary),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final field in details.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '${field.key}: ${field.value is String ? field.value : jsonEncode(field.value)}',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
