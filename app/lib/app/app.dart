import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import '../client/correlation_journal.dart';
import '../client/windows_pipe_config.dart';
import '../enrollment/panel.dart';
import '../connectivity/panel.dart';
import '../revocation/panel.dart';
import '../update/controller.dart';
import '../update/panel.dart';
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

  @override
  void initState() {
    super.initState();
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
      updates.start();
    } catch (_) {
      if (mounted && !_closing) setState(() => _updatesUnavailable = true);
    }
  }

  void _begin() {
    if (_closing || _opening != null || _session != null) return;
    final epoch = ++_epoch;
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
      await session.initialize();
    } on UiStartupCancelled {
      // The acquisition path closed its own partial resources.
    } catch (error) {
      if (error is UiCleanupFailure) _cleanupFailed = true;
      if (mounted && !_closing && epoch == _epoch) {
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
    _updates?.dispose();
    // Detachment is not a cancellable OS exit. Still release all resources and
    // consume safe close errors; normal WM_CLOSE awaits _requestExit above.
    unawaited(_session?.close().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'EndlessNet',
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      appBar: AppBar(title: const Text('EndlessNet')),
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
                      serverTrust: _session!.trust,
                      now: DateTime.now,
                      openBrowser: _session!.openBrowser,
                      reconnect: _reconnect,
                      connectivityPanel: Column(
                        children: [
                          ConnectivityPanel(
                            controller: _session!.connectivity,
                            reconnect: _reconnect,
                          ),
                          if (_session!.revocation != null)
                            RevocationPanel(controller: _session!.revocation!),
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
    UiConfigurationProblem.missing => 'Файл настроек интерфейса не найден. Обратитесь к администратору установки.',
    UiConfigurationProblem.busy =>
      'Файл настроек занят. Повторите подключение позже.',
    UiConfigurationProblem.untrusted => 'Не удалось проверить права доступа к настройкам. Обратитесь к администратору установки.',
    UiConfigurationProblem.componentUnavailable =>
      'Компонент Windows UI недоступен. Проверьте установленную версию.',
    UiConfigurationProblem.invalid => 'Не заданы корректные настройки запуска интерфейса. Обратитесь к администратору установки.',
  },
  WindowsPipeFailure(problem: WindowsPipeProblem.authentication) => 'Не удалось подтвердить локальный клиент или версию контракта. Проверьте согласованность установки.',
  CorrelationStoreFailure() => 'Локальное хранилище восстановления недоступно. Закройте другие окна интерфейса и проверьте права и целостность файла.',
  _ => 'Не удалось подключиться к локальному клиенту. Проверьте его состояние и повторите подключение.',
};
