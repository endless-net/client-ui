import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:endlessnet_ui/endlessnet_ui.dart';

import '../client/correlation_journal.dart';
import '../client/windows_pipe_config.dart';
import '../enrollment/panel.dart';
import '../connectivity/panel.dart';
import '../session_login/panel.dart';
import '../update/controller.dart';
import '../update/panel.dart';
import '../mcp/protocol.dart';
import '../mcp/windows_mcp.dart';
import 'launch_config.dart';
import 'session.dart';

class MainApp extends StatefulWidget {
  const MainApp({super.key, required this.platform, this.openUpdates});
  final UiRuntimePlatform platform;
  final Future<UpdateController> Function()? openUpdates;
  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late final AppLifecycleListener _lifecycle;
  UiSession? _session;
  Future<void>? _opening;
  Future<AppExitResponse>? _exit;
  String? _problem;
  bool _closing = false;
  bool _cleanupFailed = false;
  bool _reconnecting = false;
  int _epoch = 0;
  UpdateController? _updates;
  bool _updatesUnavailable = false;
  final _diagnostics = UiDiagnostics();
  WindowsMcp? _mcp;
  String? _lastConnectivity;
  String? _lastEnrollment;
  bool _sessionInitialized = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) _mcp = WindowsMcp(_invokeMcp);
    _diagnostics.record('app', 'started');
    _lifecycle = AppLifecycleListener(
      onExitRequested: _requestExit,
      onResume: () => unawaited(_session?.connectivity.resume()),
    );
    _begin();
    unawaited(_openUpdates());
  }

  Future<void> _openUpdates() async {
    final open = widget.openUpdates;
    if (open == null) return;
    try {
      final updates = await open();
      if (!mounted || _closing) {
        updates.dispose();
        return;
      }
      setState(() => _updates = updates);
      updates.addListener(_observeUpdates);
      updates.start();
    } catch (_) {
      _diagnostics.record('updates', 'unavailable');
      if (mounted && !_closing) setState(() => _updatesUnavailable = true);
    }
  }

  void _begin() {
    if (_closing || _opening != null || _session != null) return;
    final epoch = ++_epoch;
    _sessionInitialized = false;
    _diagnostics.record('app', 'openingSession');
    _problem = null;
    _opening = _open(epoch).whenComplete(() {
      _opening = null;
    });
  }

  Future<void> _open(int epoch) async {
    try {
      final session = await UiSession.open(
        widget.platform,
        cancelled: () => !mounted || _closing || epoch != _epoch,
      );
      // No await between publishing the session and checking its ownership.
      if (!mounted || _closing || epoch != _epoch) {
        await session.close();
        return;
      }
      setState(() => _session = session);
      session.connectivity.addListener(_observeConnectivity);
      session.enrollment.addListener(_observeEnrollment);
      await session.initialize();
      if (mounted && !_closing && epoch == _epoch) {
        _sessionInitialized = true;
        _diagnostics.record('app', 'sessionInitialized');
      }
    } on UiStartupCancelled {
      // The acquisition path closed its own partial resources.
    } catch (error) {
      if (error is UiCleanupFailure) _cleanupFailed = true;
      if (mounted && !_closing && epoch == _epoch) {
        _diagnostics.record('app', 'sessionUnavailable');
        setState(() => _problem = _safeProblem(error));
      }
    }
  }

  Future<AppExitResponse> _requestExit() => _exit ??= _shutdown();

  Future<void> _reconnect() async {
    if (_closing || _reconnecting || _opening != null || _session == null) {
      return;
    }
    _reconnecting = true;
    _diagnostics.record('app', 'reconnecting');
    ++_epoch;
    setState(() {});
    try {
      await _session!.close();
      if (!mounted || _closing) return;
      setState(() {
        _session = null;
        _reconnecting = false;
        _begin();
      });
    } catch (_) {
      _cleanupFailed = true;
      if (mounted && !_closing) {
        setState(
          () =>
              _problem = 'Не удалось завершить работу с локальным хранилищем.',
        );
      }
    }
  }

  Future<AppExitResponse> _shutdown() async {
    _closing = true;
    _mcp?.disable();
    ++_epoch;
    if (mounted) setState(() {});
    try {
      // Dispose controllers/cancel pipe immediately, including an active bind.
      final closed = _session?.close();
      await Future.wait<void>([?closed, ?_opening]);
      if (_cleanupFailed) throw const UiCleanupFailure();
      return AppExitResponse.exit;
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _problem = 'Не удалось завершить работу с локальным хранилищем.',
        );
      }
      return AppExitResponse.cancel;
    }
  }

  @override
  void dispose() {
    ++_epoch;
    _closing = true;
    _lifecycle.dispose();
    _mcp?.dispose();
    _updates?.dispose();
    // Detachment is not a cancellable OS exit. Still release all resources and
    // consume safe close errors; normal WM_CLOSE awaits _requestExit above.
    unawaited(_session?.close().catchError((Object _) {}));
    super.dispose();
  }

  Json _connectivityState(UiSession session) {
    final controller = session.connectivity;
    final snapshot = controller.snapshot;
    return {
      'link': controller.link.name,
      'fresh': controller.fresh,
      'busy': controller.busy,
      'uncertain': controller.uncertain,
      'canConnect': controller.canConnect,
      'canDisconnect': controller.canDisconnect,
      'failureCode': ?controller.failure?.code.name,
      'service': ?snapshot?.serviceState.name,
      'control': ?snapshot?.controlState.name,
      'phase': ?snapshot?.connectionPhase.name,
      'revision': ?snapshot?.metadata.revision.toStringUnsigned(),
      'directPaths': ?snapshot?.agent.directPathCount,
      'relayPaths': ?snapshot?.agent.relayPathCount,
    };
  }

  Json _enrollmentState(UiSession session) => {
    'link': session.enrollment.link.name,
    'registered': session.enrollment.registeredConfirmed,
    'uncertain': session.enrollment.uncertain,
  };

  void _observeConnectivity() {
    final state = _connectivityState(_session!)..remove('revision');
    final signature = jsonEncode(state);
    if (_lastConnectivity == signature) return;
    _lastConnectivity = signature;
    _diagnostics.record('connectivity', 'stateChanged', state);
  }

  void _observeEnrollment() {
    final state = _enrollmentState(_session!);
    final signature = jsonEncode(state);
    if (_lastEnrollment == signature) return;
    _lastEnrollment = signature;
    _diagnostics.record('enrollment', 'stateChanged', state);
  }

  void _observeUpdates() =>
      _diagnostics.record('updates', _updates!.status.name);

  Future<Json> _invokeMcp(
    String name,
    Json arguments,
    bool Function() authorized,
  ) async {
    if (!authorized() || _closing) return {'error': 'accessRevoked'};
    final session = _session;
    final ready =
        session != null &&
        !session.closed &&
        _sessionInitialized &&
        !_reconnecting;
    if (name == 'app_status') {
      return {
        'ui': _reconnecting
            ? 'reconnecting'
            : ready
            ? 'ready'
            : _problem != null
            ? 'unavailable'
            : 'opening',
        if (ready) 'enrollment': _enrollmentState(session),
        if (ready) 'connectivity': _connectivityState(session),
        'updates':
            _updates?.status.name ??
            (_updatesUnavailable ? 'unavailable' : 'opening'),
      };
    }
    if (name == 'logs_read') return _diagnostics.read(arguments);
    if (!ready) return {'error': 'clientSessionUnavailable'};
    if (name == 'connectivity_refresh') {
      await session.connectivity.refresh();
      if (!authorized() || _session != session || session.closed) {
        return {'error': 'sessionChanged'};
      }
      final state = _connectivityState(session);
      return {
        if (!session.connectivity.fresh) 'error': 'statusUnconfirmed',
        'connectivity': state,
      };
    }
    final outcome = await session.connectivity.requestConnection(
      name == 'connectivity_connect',
      admitted: () =>
          authorized() && _session == session && !_reconnecting && !_closing,
    );
    _diagnostics.record('mcp', name, {'outcome': outcome});
    if (!authorized() || _session != session || session.closed) {
      return {'error': 'sessionChanged', 'outcome': outcome};
    }
    return {
      'outcome': outcome,
      if (outcome != 'acknowledged') 'error': outcome,
      'connectivity': _connectivityState(session),
    };
  }

  Future<void> _showMcp(BuildContext context, WindowsMcp mcp) async {
    await showDialog<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: mcp,
        builder: (context, _) => AlertDialog(
          title: const Text('Доступ по MCP'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Разрешение открывает чтение состояния и журнала, '
                    'обновление статуса службы, подключение и отключение. '
                    'Оно действует до отзыва, замены или выхода из приложения.',
                  ),
                  if (mcp.unavailable)
                    const Text('Не удалось открыть локальный MCP-канал.'),
                  if (mcp.clientId != null) SelectableText(mcp.configuration),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
            ),
            if (mcp.clientId != null) ...[
              TextButton(
                onPressed: () => mcp.disable(),
                child: const Text('Отозвать'),
              ),
              TextButton(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: mcp.configuration)),
                child: const Text('Копировать конфигурацию'),
              ),
            ],
            FilledButton(
              onPressed: _closing ? null : mcp.enable,
              child: Text(
                mcp.clientId == null ? 'Разрешить' : 'Заменить разрешение',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EndlessNet',
    debugShowCheckedModeBanner: false,
    theme: BrandTheme.light(),
    darkTheme: BrandTheme.dark(),
    home: Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(8),
          child: BrandMark(size: 32),
        ),
        title: const Text('EndlessNet'),
        actions: [
          if (_mcp case final mcp?)
            ListenableBuilder(
              listenable: mcp,
              builder: (context, _) => TextButton(
                onPressed: _closing ? null : () => _showMcp(context, mcp),
                child: Text(mcp.clientId == null ? 'MCP' : 'MCP включён'),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _updates != null
          ? UpdatePanel(controller: _updates!)
          : _updatesUnavailable
          ? const ListTile(
              title: Text(
                'Проверка обновлений недоступна. Проверьте установленную версию UI.',
              ),
            )
          : null,
      body: Stack(
        children: [
          // Keep lifecycle observers mounted throughout Flutter's asynchronous
          // exit dispatch. Removing TextField here disposes an observer that may
          // still belong to the dispatch's captured observer list.
          TickerMode(
            enabled: !_closing && !_reconnecting,
            child: AbsorbPointer(
              absorbing: _closing || _reconnecting,
              child: _session != null
                  ? EnrollmentPanel(
                      controller: _session!.enrollment,
                      simple: true,
                      hostname: Platform.localHostname,
                      onStart: _session!.startEnrollment,
                      serverTrust: _session!.trust,
                      now: DateTime.now,
                      openBrowser: _session!.openBrowser,
                      reconnect: _reconnect,
                      connectivityPanel: Column(
                        children: [
                          if (_session!.sessionLogin != null)
                            SessionLoginPanel(
                              controller: _session!.sessionLogin!,
                              openBrowser: _session!.openSessionBrowser,
                            ),
                          ConnectivityPanel(
                            controller: _session!.connectivity,
                            reconnect: _reconnect,
                            simple: true,
                          ),
                        ],
                      ),
                    )
                  : Center(
                      child: _problem == null
                          ? const CircularProgressIndicator()
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_problem!, textAlign: TextAlign.center),
                                FilledButton(
                                  onPressed: _cleanupFailed
                                      ? null
                                      : () => setState(_begin),
                                  child: const Text('Повторить подключение'),
                                ),
                              ],
                            ),
                    ),
            ),
          ),
          if (_closing || _reconnecting)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
                child: Center(
                  child: Text(
                    _problem ??
                        (_closing ? 'Завершение работы…' : 'Переподключение…'),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

String _safeProblem(Object error) => switch (error) {
  UiConfigurationFailure(:final problem) => switch (problem) {
    UiConfigurationProblem.unsupportedPlatform =>
      'Регистрация в этой поставке доступна только в Windows.',
    UiConfigurationProblem.missing => 'Служба EndlessNet не обнаружена или ещё не запущена. Установите EndlessNet либо запустите службу и повторите подключение.',
    UiConfigurationProblem.busy =>
      'Файл настроек занят. Повторите подключение позже.',
    UiConfigurationProblem.untrusted => 'Не удалось проверить установленный EndlessNet. Повторите установку с правами администратора.',
    UiConfigurationProblem.componentUnavailable =>
      'Компонент Windows UI недоступен. Проверьте установленную версию.',
    UiConfigurationProblem.invalid => 'Не удалось прочитать настройки установленного EndlessNet. Повторите установку.',
  },
  WindowsPipeFailure(problem: WindowsPipeProblem.authentication) => 'Не удалось подтвердить локальный клиент или версию контракта. Проверьте согласованность установки.',
  CorrelationStoreFailure() => 'Локальное хранилище восстановления недоступно. Закройте другие окна интерфейса и проверьте права и целостность файла.',
  _ => 'Не удалось подключиться к локальному клиенту. Проверьте его состояние и повторите подключение.',
};
