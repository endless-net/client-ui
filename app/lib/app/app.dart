import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:endlessnet_ui/endlessnet_ui.dart';

import '../client/call_failure.dart';
import '../client/correlation_journal.dart';
import '../client/windows_pipe_config.dart';
import '../dashboard/board.dart';
import '../dashboard/home.dart';
import '../enrollment/panel.dart';
import '../connectivity/controller.dart';
import '../connectivity/panel.dart';
import '../session_login/panel.dart';
import '../update/controller.dart';
import '../update/panel.dart';
import '../mcp/protocol.dart';
import '../mcp/recovery_log.dart';
import '../mcp/windows_mcp.dart';
import 'launch_config.dart';
import 'logs_screen.dart';
import 'session.dart';

class MainApp extends StatefulWidget {
  const MainApp({
    super.key,
    required this.platform,
    this.openUpdates,
    this.openRecoveryLog,
    this.dashboardStore,
  });
  final UiRuntimePlatform platform;
  final BoardStore? dashboardStore;
  final Future<UpdateController> Function()? openUpdates;
  final Future<(File, void Function())> Function()? openRecoveryLog;
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
  Timer? _retryTimer;
  int _retryDelaySeconds = 1;
  bool _recoveringLocalClient = false;
  (ConnectivityReadFailure, WindowsPipeProblem?)? _lastReadFailure;
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
    if (Platform.isWindows) _mcp = WindowsMcp(_invokeMcp)..restore();
    if (widget.openRecoveryLog case final open?) {
      unawaited(_diagnostics.recovery.open(open));
    }
    _diagnostics.record('app', 'started');
    _lifecycle = AppLifecycleListener(
      onExitRequested: _requestExit,
      // Returning focus to a visible window does not invalidate its status.
      onShow: () => unawaited(_session?.connectivity.resume()),
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
        _observeConnectivity();
      }
    } on UiStartupCancelled {
      // The acquisition path closed its own partial resources.
    } catch (error) {
      if (error is UiCleanupFailure) _cleanupFailed = true;
      if (mounted && !_closing && epoch == _epoch) {
        _diagnostics.record('app', 'sessionUnavailable');
        final (stage, cause, rpcCode) = _openingFailure(error);
        _diagnostics.recovery.record(
          RecoveryEvent.openingFailed,
          stage: stage,
          cause: cause,
          rpcCode: rpcCode,
        );
        setState(() => _problem = _safeProblem(error));
        if (_canRetrySession(error)) _scheduleReconnect();
      }
    }
  }

  Future<AppExitResponse> _requestExit() => _exit ??= _shutdown();

  void _scheduleReconnect() {
    if (_closing || _cleanupFailed || _retryTimer != null) return;
    final delay = Duration(seconds: _retryDelaySeconds);
    _recoveringLocalClient = true;
    _diagnostics.recovery.record(
      RecoveryEvent.scheduled,
      delaySeconds: delay.inSeconds,
    );
    _retryDelaySeconds = (_retryDelaySeconds * 2).clamp(1, 30);
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_reconnect());
    });
  }

  Future<void> _reconnect() async {
    if (_closing || _cleanupFailed || _reconnecting || _opening != null) {
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    _recoveringLocalClient = true;
    _diagnostics.recovery.record(RecoveryEvent.reconnecting);
    final session = _session;
    if (session == null) {
      setState(_begin);
      return;
    }
    _reconnecting = true;
    _diagnostics.record('app', 'reconnecting');
    ++_epoch;
    setState(() {});
    try {
      await session.close();
      if (!mounted || _closing) return;
      setState(() {
        _session = null;
        _reconnecting = false;
        _begin();
      });
    } catch (_) {
      _cleanupFailed = true;
      _diagnostics.recovery.record(
        RecoveryEvent.openingFailed,
        stage: RecoveryStage.cleanup,
        cause: RecoveryCause.unknown,
      );
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
    _retryTimer?.cancel();
    _mcp?.stop();
    ++_epoch;
    if (mounted) setState(() {});
    try {
      // Dispose controllers/cancel pipe immediately, including an active bind.
      final closed = _session?.close();
      await Future.wait<void>([
        ?closed,
        ?_opening,
        _diagnostics.recovery.close(),
      ]);
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
    _retryTimer?.cancel();
    _lifecycle.dispose();
    _mcp?.dispose();
    _updates?.dispose();
    unawaited(_diagnostics.recovery.close());
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
    final session = _session!;
    final controller = session.connectivity;
    final failure = controller.readFailure;
    final pipeProblem = session.pipeProblem;
    final readFailure = failure == null ? null : (failure, pipeProblem);
    if (failure != null && readFailure != _lastReadFailure) {
      _diagnostics.recovery.record(
        RecoveryEvent.readFailed,
        stage: pipeProblem == null
            ? RecoveryStage.values.byName(failure.stage.name)
            : RecoveryStage.channel,
        cause: RecoveryCause.values.byName(
          pipeProblem?.name ?? failure.problem.name,
        ),
        rpcCode: failure.rpcCode,
      );
    }
    _lastReadFailure = readFailure;
    if (_sessionInitialized && !_reconnecting && !_closing) {
      if (controller.fresh) {
        _retryTimer?.cancel();
        _retryTimer = null;
        _retryDelaySeconds = 1;
        if (_recoveringLocalClient) {
          _recoveringLocalClient = false;
          _diagnostics.recovery.record(RecoveryEvent.recovered);
        }
      } else if (controller.link == ConnectivityLink.unavailable ||
          controller.link == ConnectivityLink.mismatch) {
        if (ClientCallFailure.isAccessDenied(failure?.rpcCode) ||
            pipeProblem == WindowsPipeProblem.authentication) {
          _retryTimer?.cancel();
          _retryTimer = null;
        } else {
          _scheduleReconnect();
        }
      }
    }
    final state = _connectivityState(session)..remove('revision');
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

  Future<api.ListRecentLogsResponse?> _readServiceLogs(String pageToken) async {
    final session = _session;
    if (session == null ||
        session.closed ||
        !_sessionInitialized ||
        _reconnecting ||
        _closing) {
      return null;
    }
    final page = await session.recentClientLogs(
      pageToken: pageToken,
      limit: 50,
    );
    if (!mounted || _closing || _session != session || session.closed) {
      return null;
    }
    if (page != null &&
        page.page.metadata.instanceId != session.config.pipe.instanceId) {
      throw ClientCallFailure.protocol();
    }
    return page;
  }

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
    if (name == 'client_logs_read') {
      try {
        final response = await session.recentClientLogs(
          pageToken: arguments['pageToken'] as String? ?? '',
          limit: arguments['limit'] as int? ?? 50,
        );
        if (!authorized() || _session != session || session.closed) {
          return {'error': 'sessionChanged'};
        }
        if (response == null) return {'error': 'clientLogsUnavailable'};
        if (response.page.metadata.instanceId !=
            session.config.pipe.instanceId) {
          return {'error': 'clientInstanceChanged'};
        }
        return {
          'source': 'client_service',
          'entries': [
            for (final entry in response.logs)
              {
                'time': entry.timestamp.toDateTime().toUtc().toIso8601String(),
                'message': entry.message,
              },
          ],
          'nextPageToken': response.page.nextPageToken,
        };
      } on ClientCallFailure catch (failure) {
        if (!authorized() || _session != session || session.closed) {
          return {'error': 'sessionChanged'};
        }
        return {'error': failure.reasonKey};
      }
    }
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
                    'Разрешение открывает чтение состояния и журналов UI и службы Client, '
                    'обновление статуса службы, подключение и отключение. '
                    'Разрешение сохраняется после перезапуска Windows и действует '
                    'до отзыва или замены. Для работы MCP нужен открытый Client UI.',
                  ),
                  if (mcp.unavailable)
                    const Text('Не удалось открыть локальный MCP-канал.'),
                  if (mcp.revokeFailed)
                    const Text('Не удалось отозвать разрешение MCP.'),
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
            if (mcp.clientId != null || mcp.unavailable)
              TextButton(
                onPressed: _closing ? null : mcp.disable,
                child: const Text('Отозвать'),
              ),
            if (mcp.clientId != null)
              TextButton(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: mcp.configuration)),
                child: const Text('Копировать конфигурацию'),
              ),
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

  Widget _startupProblem() {
    final problem = _problem;
    if (problem == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(problem, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _cleanupFailed ? null : _reconnect,
              child: const Text('Повторить подключение'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _account(UiSession? session, String host) {
    if (session == null) return _startupProblem();
    return EnrollmentPanel(
      controller: session.enrollment,
      simple: true,
      hostname: host,
      onStart: session.startEnrollment,
      serverTrust: session.trust,
      now: DateTime.now,
      openBrowser: session.openBrowser,
      reconnect: _reconnect,
      connectivityPanel: switch (session.sessionLogin) {
        final login? => SessionLoginPanel(
          controller: login,
          openBrowser: session.openSessionBrowser,
        ),
        null => null,
      },
    );
  }

  Widget _settings() => Builder(
    builder: (context) => ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('Обновления', style: Theme.of(context).textTheme.titleMedium),
        if (_updates case final updates?)
          UpdatePanel(controller: updates)
        else
          ListTile(
            title: Text(
              _updatesUnavailable
                  ? 'Проверка обновлений недоступна'
                  : 'Проверка обновлений в этом запуске не настроена',
            ),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.article_outlined),
          title: const Text('Журналы'),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => LogsScreen(
                diagnostics: _diagnostics,
                readServiceLogs: _readServiceLogs,
              ),
            ),
          ),
        ),
        if (_mcp case final mcp?)
          ListenableBuilder(
            listenable: mcp,
            builder: (context, _) => ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: Text(
                mcp.clientId == null ? 'Доступ по MCP' : 'MCP включён',
              ),
              onTap: () => _showMcp(context, mcp),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final host = Platform.localHostname;
    return MaterialApp(
      title: 'EndlessNet',
      debugShowCheckedModeBanner: false,
      theme: BrandTheme.light(),
      darkTheme: BrandTheme.dark(),
      home: DashboardHome(
        host: host,
        boardStore: widget.dashboardStore,
        serverBoard: _closing || _reconnecting ? null : session?.dashboard,
        connectivity: _closing || _reconnecting ? null : session?.connectivity,
        peers: _closing || _reconnecting ? null : session?.peers,
        peerTimeout: session?.config.rpcTimeout,
        updates: _updates,
        account: _account(session, host),
        tunnelDetails: _closing || _reconnecting
            ? const SizedBox.shrink()
            : session == null
            ? _startupProblem()
            : ListenableBuilder(
                listenable: session.connectivity,
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (session.connectivity.hasDeviceContext)
                      ConnectivityPanel(
                        controller: session.connectivity,
                        reconnect: _reconnect,
                        simple: true,
                      )
                    else
                      const Text(
                        'Сведения о туннеле пока недоступны. Регистрация и проверка службы доступны в учётной записи.',
                      ),
                  ],
                ),
              ),
        settings: _settings(),
        blockingMessage: _closing || _reconnecting
            ? _problem ?? (_closing ? 'Завершение работы…' : 'Переподключение…')
            : null,
      ),
    );
  }
}

(RecoveryStage, RecoveryCause, int?) _openingFailure(Object error) =>
    switch (error) {
      UiConfigurationFailure(:final problem) => (
        RecoveryStage.configuration,
        RecoveryCause.values.byName(problem.name),
        null,
      ),
      WindowsPipeFailure(:final problem) => (
        RecoveryStage.channel,
        RecoveryCause.values.byName(problem.name),
        null,
      ),
      CorrelationStoreFailure() => (
        RecoveryStage.storage,
        RecoveryCause.unavailable,
        null,
      ),
      UiCleanupFailure() => (
        RecoveryStage.cleanup,
        RecoveryCause.unknown,
        null,
      ),
      ClientCallFailure(:final transportCode) => (
        RecoveryStage.runtimeInfo,
        RecoveryCause.rpc,
        transportCode,
      ),
      _ => (RecoveryStage.initialization, RecoveryCause.unknown, null),
    };

bool _canRetrySession(Object error) => switch (error) {
  UiConfigurationFailure(
    problem: UiConfigurationProblem.untrusted ||
        UiConfigurationProblem.unsupportedPlatform,
  ) ||
  UiCleanupFailure() ||
  WindowsPipeFailure(problem: WindowsPipeProblem.authentication) => false,
  ClientCallFailure(:final transportCode) => !ClientCallFailure.isAccessDenied(
    transportCode,
  ),
  _ => true,
};

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
