import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'client_session.dart';
import 'client_locale.dart';
import 'client_bundle_destination.dart';
import 'client_session_panel.dart';
import 'client_state_controller.dart';
import 'client_tray.dart';

Directory clientJournalDirectory(String endpoint) {
  final home =
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  if (home == null || home.isEmpty || !Directory(home).isAbsolute) {
    throw StateError('Caller-private home directory is required');
  }
  final identity = sha256.convert(
    utf8.encode(Platform.isWindows ? endpoint.toLowerCase() : endpoint),
  );
  return Directory('$home/.endlessnet/ui-intents/$identity');
}

/// Native desktop entrypoint. Runtime state comes only from ClientSession/v0.
class ClientDesktopApp extends StatefulWidget {
  const ClientDesktopApp({
    super.key,
    required this.session,
    this.desktopIntegration = true,
    this.showWindow = true,
    this.showSignal,
    this.onExit,
    this.uiBuild,
    this.initialLocale = ClientLocale.en,
  });
  final ClientSession session;
  final ClientLocale initialLocale;
  final api.BuildIdentity? uiBuild;
  final bool desktopIntegration;
  final bool showWindow;
  final Future<DateTime?> Function()? showSignal;
  final Future<void> Function()? onExit;
  @override
  State<ClientDesktopApp> createState() => _ClientDesktopAppState();
}

enum _DesktopNotice { tray, integration, runtime }

class _ClientDesktopAppState extends State<ClientDesktopApp>
    with WindowListener, TrayListener {
  final _navigator = GlobalKey<NavigatorState>();
  Timer? _signals;
  DateTime? _lastSignal;
  bool _busy = false;
  _DesktopNotice? _notice;
  late ClientLocale _locale;
  String _text(String en, String ru) => _locale.text(en: en, ru: ru);
  String get _noticeText => switch (_notice!) {
    _DesktopNotice.tray => _text(
      'Tray update unavailable. Use the application window.',
      'Обновление значка в трее недоступно. Используйте окно приложения.',
    ),
    _DesktopNotice.integration => _text(
      'Desktop integration is unavailable. Runtime access remains separate.',
      'Интеграция с рабочим столом недоступна. Доступ к службе не зависит от неё.',
    ),
    _DesktopNotice.runtime => _text(
      'Native runtime is unavailable or incompatible. No fallback was used.',
      'Локальная служба недоступна или несовместима. Альтернативное подключение не использовалось.',
    ),
  };
  late final ClientTray _tray;
  bool _trayReady = false;
  bool _trayUpdating = false;
  bool _trayDirty = false;
  ClientSession get session => widget.session;

  Future<bool> _exportBundle(String requestId, void Function() checkContext) {
    final originalSession = session;
    final state = originalSession.state;
    final cacheEpoch = state.cacheEpoch;
    final profileEpoch = state.domainEpoch(api.Domain.DOMAIN_PROFILES);
    final sessionEpoch = state.domainEpoch(api.Domain.DOMAIN_SESSION);
    void check() {
      checkContext();
      if (!mounted ||
          !identical(session, originalSession) ||
          state.link != ClientLinkState.ready ||
          state.cacheEpoch != cacheEpoch ||
          state.domainEpoch(api.Domain.DOMAIN_PROFILES) != profileEpoch ||
          state.domainEpoch(api.Domain.DOMAIN_SESSION) != sessionEpoch) {
        throw StateError('Diagnostics export context changed');
      }
    }

    return exportClientBundleToChosenDirectory(
      requestId: requestId,
      choose: chooseClientBundleDirectory,
      save: (id, directory) async {
        check();
        await originalSession.exportDiagnosticsBundle(id, directory);
      },
      checkContext: check,
    );
  }

  @override
  void initState() {
    super.initState();
    _locale = widget.initialLocale;
    _tray = ClientTray(
      state: session.state,
      connect: () => session.submit(
        api.OperationKind.OPERATION_KIND_CONNECT,
        (commands, mutation) => commands.connect(
          api.ConnectRequest(
            mutation: mutation,
            profile: api.ProfileRef(
              profileId: session.state.snapshot!.status.activeProfileId,
            ),
          ),
        ),
      ),
      disconnect: () => session.submit(
        api.OperationKind.OPERATION_KIND_DISCONNECT,
        (commands, mutation) => commands.disconnect(
          api.DisconnectRequest(
            mutation: mutation,
            profile: api.ProfileRef(
              profileId: session.state.snapshot!.status.activeProfileId,
            ),
          ),
        ),
      ),
    )..addListener(_trayChanged);
    unawaited(_initialize());
  }

  void _trayChanged() {
    _trayDirty = true;
    if (_trayReady && mounted) unawaited(_refreshTray());
  }

  Future<void> _refreshTray() async {
    if (_trayUpdating) return;
    _trayUpdating = true;
    try {
      do {
        _trayDirty = false;
        await trayManager.setToolTip('EndlessNet: ${_tray.status}');
        if (!mounted || !_trayReady) return;
        await trayManager.setContextMenu(_tray.menu);
      } while (_trayDirty && mounted && _trayReady);
    } catch (_) {
      if (mounted) {
        setState(() => _notice = _DesktopNotice.tray);
      }
    } finally {
      _trayUpdating = false;
    }
  }

  void _setBusy(bool busy) {
    setState(() => _busy = busy);
    _tray.enabled = !busy;
  }

  Future<void> _initialize() async {
    if (widget.desktopIntegration) {
      try {
        windowManager.addListener(this);
        trayManager.addListener(this);
        await trayManager.setIcon(
          Platform.isWindows
              ? 'assets/icons/endlessnet.ico'
              : 'assets/icons/endlessnet.png',
        );
        _trayReady = true;
        await _refreshTray();
        await windowManager.waitUntilReadyToShow(
          const WindowOptions(
            title: 'EndlessNet',
            size: Size(760, 560),
            minimumSize: Size(620, 460),
            center: true,
          ),
          () async {
            if (widget.showWindow) {
              await _show();
            } else {
              await windowManager.hide();
            }
          },
        );
        _lastSignal = await widget.showSignal?.call();
        if (!mounted) return;
        _signals = Timer.periodic(
          const Duration(seconds: 1),
          (_) => unawaited(_checkSignal()),
        );
      } catch (_) {
        if (mounted) {
          setState(() => _notice = _DesktopNotice.integration);
        }
      }
    }
    if (mounted) await _connect();
  }

  Future<void> _checkSignal() async {
    final next = await widget.showSignal?.call();
    if (!mounted || next == null) return;
    final changed = _lastSignal == null || next.isAfter(_lastSignal!);
    _lastSignal = next;
    if (changed) await _show();
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onWindowClose() {
    unawaited(windowManager.hide());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_show());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem item) {
    if (item.key == 'open') unawaited(_show());
    if (item.key == 'exit') unawaited(_quit());
    if (item.key?.startsWith('connect:') == true ||
        item.key?.startsWith('disconnect:') == true) {
      unawaited(_tray.activate(item.key));
    }
  }

  Future<void> _connect() async {
    if (_busy) return;
    _setBusy(true);
    try {
      await session.connect();
    } catch (_) {
      if (mounted) {
        setState(() => _notice = _DesktopNotice.runtime);
      }
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  Future<void> _quit() async {
    if (_busy) return;
    _setBusy(true);
    var notified = false;
    try {
      final snapshot = session.state.snapshot;
      if (session.state.link == ClientLinkState.ready && snapshot != null) {
        if (snapshot.runtime.callerAccess == api.Access.ACCESS_OBSERVER ||
            snapshot.status.activeProfileId.isEmpty) {
          notified = true; // No owner/profile intent can be mutated by this UI.
        } else {
          final operation = await session.submit(
            api.OperationKind.OPERATION_KIND_NOTIFY_LIFECYCLE,
            (commands, mutation) => commands.notifyLifecycle(
              api.NotifyLifecycleRequest(
                mutation: mutation,
                profile: api.ProfileRef(
                  profileId: snapshot.status.activeProfileId,
                ),
                event: api.LifecycleEvent.LIFECYCLE_EVENT_UI_QUIT,
              ),
            ),
          );
          notified = !operation.terminal || operation.succeeded;
        }
      }
    } catch (_) {
      /* Retain an ambiguous intention; never replay on exit. */
    }
    if (!mounted) return;
    if (!notified) {
      if (widget.desktopIntegration) await _show();
      if (!mounted) return;
      final exit = await showDialog<bool>(
        context: _navigator.currentContext!,
        builder: (context) => AlertDialog(
          title: Text(
            _text(
              'Exit without confirmed runtime notification?',
              'Закрыть интерфейс без подтверждения уведомления службы?',
            ),
          ),
          content: Text(
            _text(
              'The agent may retain its current connection intent. The operation will not be replayed.',
              'Агент может сохранить текущее намерение подключения. Операция не будет отправлена повторно.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_text('Stay', 'Остаться')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_text('Exit UI', 'Закрыть интерфейс')),
            ),
          ],
        ),
      );
      if (exit != true) {
        if (mounted) _setBusy(false);
        return;
      }
    }
    _signals?.cancel();
    _trayReady = false;
    await session.close();
    await widget.onExit?.call();
    if (widget.desktopIntegration) {
      await trayManager.destroy();
      await windowManager.destroy();
    }
  }

  @override
  void dispose() {
    _signals?.cancel();
    _trayReady = false;
    _tray.removeListener(_trayChanged);
    _tray.dispose();
    if (widget.desktopIntegration) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    unawaited(session.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigator,
    title: 'EndlessNet',
    theme: ThemeData(useMaterial3: true),
    home: Scaffold(
      appBar: AppBar(
        title: const Text('EndlessNet'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _connect,
            child: Text(
              _text('Reconnect runtime', 'Переподключиться к службе'),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _quit,
            child: Text(_text('Quit', 'Выход')),
          ),
        ],
      ),
      body: Column(
        children: [
          Semantics(
            label: _text('Interface language', 'Язык интерфейса'),
            child: DropdownButton<ClientLocale>(
              key: const Key('client-ui-language'),
              value: _locale,
              items: const [
                DropdownMenuItem(
                  value: ClientLocale.en,
                  child: Text('English'),
                ),
                DropdownMenuItem(
                  value: ClientLocale.ru,
                  child: Text('Русский'),
                ),
              ],
              onChanged: (value) {
                if (value != null && value != _locale) {
                  setState(() => _locale = value);
                }
              },
            ),
          ),
          if (_notice != null)
            Semantics(liveRegion: true, child: Text(_noticeText)),
          AnimatedBuilder(
            animation: _tray,
            builder: (context, _) => _tray.notice == null
                ? const SizedBox.shrink()
                : Text(_tray.notice!),
          ),
          AnimatedBuilder(
            animation: session.state,
            builder: (context, _) => Text(
              _text(
                'Runtime: ${session.state.link.name}',
                'Служба: ${switch (session.state.link) {
                  ClientLinkState.disconnected => 'отключена',
                  ClientLinkState.awaitingSnapshot => 'ожидание состояния',
                  ClientLinkState.ready => 'готова',
                  ClientLinkState.unavailable => 'недоступна',
                }}',
              ),
            ),
          ),
          Expanded(
            child: ClientSessionPanel(
              locale: _locale,
              session: session,
              uiBuild: widget.uiBuild,
              exportBundle: widget.desktopIntegration && Platform.isWindows
                  ? _exportBundle
                  : null,
            ),
          ),
        ],
      ),
    ),
  );
}
