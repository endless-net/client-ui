import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'client_session.dart';
import 'client_locale.dart';
import 'client_bundle_destination.dart';
import 'client_session_panel.dart';
import 'client_state_controller.dart';
import 'client_tray.dart';
import 'client_tray_host.dart';
import 'client_notification_delivery.dart';
import 'client_notifications_panel.dart';
import 'client_notification_permission_panel.dart';
import 'client_native_notifications.dart';
import 'client_autostart_panel.dart';
import 'client_autostart_setting.dart';
import 'client_windows_autostart.dart';

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
    this.localeReadFailed = false,
    this.saveLocale,
    this.deliverNotification,
    this.initialNotifications = false,
    this.notificationReadFailed = false,
    this.saveNotifications,
    this.requestNotificationPermission,
    this.readAutostart,
    this.writeAutostart,
    this.openWindowsAutostartSettings,
    this.openAutostartSettings,
  });
  final ClientSession session;
  final Future<ClientAutostartSetting> Function()? readAutostart;
  final Future<ClientAutostartSetting> Function(bool)? writeAutostart;
  final Future<bool> Function()? openWindowsAutostartSettings;
  final Future<bool> Function()? openAutostartSettings;
  final DeliverClientNotification? deliverNotification;
  final bool initialNotifications;
  final bool notificationReadFailed;
  final Future<void> Function(bool)? saveNotifications;
  final Future<ClientNotificationPermission> Function()?
  requestNotificationPermission;
  final ClientLocale initialLocale;
  final bool localeReadFailed;
  final Future<void> Function(ClientLocale)? saveLocale;
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
    with WindowListener, TrayListener, WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  Timer? _signals;
  DateTime? _lastSignal;
  bool _busy = false;
  bool _wasHidden = false;
  bool _resumePending = false;
  bool _exiting = false;
  _DesktopNotice? _notice;
  late ClientLocale _locale;
  bool _localeStorageFailed = false;
  int _localeChoice = 0;
  Future<void>? _localeWrites;
  Future<ClientAutostartSetting> _writeAutostart(bool enabled) async {
    if (_busy || !mounted || widget.writeAutostart == null) {
      throw StateError('UI busy');
    }
    _setBusy(true);
    try {
      return await widget.writeAutostart!(enabled);
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  Future<void>? _notificationWrites;
  bool _notificationStorageFailed = false;
  int _notificationChoice = 0;

  void _chooseNotifications(bool value) {
    if (!mounted || _busy || value == _notifications.enabled) return;
    _notifications.enabled = value;
    final choice = ++_notificationChoice;
    setState(() => _notificationStorageFailed = false);
    final save = widget.saveNotifications;
    if (save == null) return;
    final previous = _notificationWrites;
    final writing = () async {
      if (previous != null) await previous;
      try {
        await save(value);
      } catch (_) {
        if (mounted && choice == _notificationChoice) {
          setState(() => _notificationStorageFailed = true);
        }
      }
    }();
    _notificationWrites = writing;
    unawaited(
      writing.then((_) {
        if (identical(_notificationWrites, writing)) _notificationWrites = null;
      }),
    );
  }

  void _chooseLocale(ClientLocale value) {
    if (_busy || value == _locale) return;
    final choice = ++_localeChoice;
    setState(() {
      _locale = value;
      _localeStorageFailed = false;
    });
    _tray.locale = value;
    _notifications.locale = value;
    final save = widget.saveLocale;
    if (save == null) return;
    final previous = _localeWrites;
    final writing = () async {
      if (previous != null) await previous;
      try {
        await save(value);
      } catch (_) {
        if (mounted && choice == _localeChoice) {
          setState(() => _localeStorageFailed = true);
        }
      }
    }();
    _localeWrites = writing;
    unawaited(
      writing.then((_) {
        if (identical(_localeWrites, writing)) _localeWrites = null;
      }),
    );
  }

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
  late final ClientNotificationDelivery _notifications;
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

    if (Platform.isMacOS) {
      return exportClientBundleToMacDirectory(
        requestId: requestId,
        save: (id, directory) async {
          check();
          await originalSession.exportDiagnosticsBundle(id, directory);
        },
        checkContext: check,
      );
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
    WidgetsBinding.instance.addObserver(this);
    _locale = widget.initialLocale;
    _localeStorageFailed = widget.localeReadFailed;
    _notificationStorageFailed = widget.notificationReadFailed;
    _notifications = ClientNotificationDelivery(
      state: session.state,
      locale: _locale,
      enabled:
          widget.initialNotifications && widget.deliverNotification != null,
      deliver:
          widget.deliverNotification ??
          (_, _) async => ClientNotificationDeliveryResult.unsupported,
    );
    _tray = ClientTray(
      locale: _locale,
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
        await updateClientTrayMenu(
          platform: Platform.operatingSystem,
          tooltip: 'EndlessNet: ${_tray.status}',
          menu: () => _tray.menu,
          isCurrent: () => mounted && _trayReady,
        );
      } while (_trayDirty && mounted && _trayReady);
    } catch (_) {
      if (mounted) {
        setState(() {
          _trayReady = false;
          _notice = _DesktopNotice.tray;
        });
        // A failed menu must not strand a UI that was already hidden.
        if (widget.desktopIntegration) {
          try {
            await _show();
          } catch (_) {
            // Keep the tray unavailable; a later close follows the exit path.
          }
        }
      }
    } finally {
      _trayUpdating = false;
    }
  }

  void _setBusy(bool busy) {
    setState(() => _busy = busy);
    _tray.enabled = !busy;
    if (!busy && _resumePending && !_exiting) {
      _resumePending = false;
      unawaited(_connect());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _exiting) return;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _wasHidden = true;
    } else if (state == AppLifecycleState.resumed && _wasHidden) {
      _wasHidden = false;
      _resumePending = true;
      // Invalidate displayed data and outstanding reads immediately, even when
      // a UI action must finish before reconnect. This sends no runtime intent.
      unawaited(
        session.state.detach().catchError((Object _) {
          // State was already invalidated synchronously. Reconnect owns the
          // next visible outcome; do not expose subscription teardown details.
        }),
      );
      if (!_busy) {
        _resumePending = false;
        unawaited(_connect());
      }
    }
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
        if (!mounted) return;
        _trayReady = true;
        await _refreshTray();
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _trayReady = false;
          _notice = _DesktopNotice.tray;
        });
      }
      if (!mounted) return;
      try {
        await windowManager.waitUntilReadyToShow(
          const WindowOptions(
            title: 'EndlessNet',
            size: Size(760, 560),
            minimumSize: Size(620, 460),
            center: true,
          ),
        );
        if (!mounted) return;
        if (widget.showWindow || !_trayReady) {
          await _show();
        } else {
          await windowManager.hide();
        }
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
    unawaited(_closeWindow());
  }

  Future<void> _closeWindow() async {
    if (!mounted || _exiting || _busy) return;
    if (!_trayReady) {
      await _quit();
      return;
    }
    try {
      await windowManager.hide();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _trayReady = false;
        _notice = _DesktopNotice.tray;
      });
      await _quit();
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_show());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(_popUpTray());
  }

  Future<void> _popUpTray() async {
    try {
      await popUpClientTrayMenu(
        platform: Platform.operatingSystem,
        isCurrent: () => mounted && _trayReady,
      );
    } catch (_) {
      if (mounted) setState(() => _notice = _DesktopNotice.tray);
    }
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
    if (_busy || _exiting) return;
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
    _exiting = true;
    _resumePending = false;
    _signals?.cancel();
    _trayReady = false;
    final savingLocale = _localeWrites;
    final savingNotifications = _notificationWrites;
    _notifications.enabled = false;
    if (savingLocale != null) await savingLocale;
    if (savingNotifications != null) await savingNotifications;
    await session.close();
    await widget.onExit?.call();
    if (widget.desktopIntegration) {
      try {
        await trayManager.destroy();
      } catch (_) {
        // An unavailable tray must not prevent closing the application window.
      }
      await windowManager.destroy();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _signals?.cancel();
    _trayReady = false;
    _tray.removeListener(_trayChanged);
    _tray.dispose();
    _notifications.dispose();
    if (widget.desktopIntegration) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    unawaited(session.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: Locale(_locale.name),
    supportedLocales: const [Locale('en'), Locale('ru')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null && value != _locale) {
                        _chooseLocale(value);
                      }
                    },
            ),
          ),
          if (_notice != null)
            Semantics(liveRegion: true, child: Text(_noticeText)),
          if (_localeStorageFailed)
            Semantics(
              liveRegion: true,
              child: Text(
                _text(
                  'The language setting could not be read or saved. Your current choice applies to this session.',
                  'Не удалось прочитать или сохранить язык. Текущий выбор действует в этом запуске.',
                ),
              ),
            ),
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
              notifications: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.openWindowsAutostartSettings != null)
                    ClientWindowsAutostartPanel(
                      openSettings: widget.openWindowsAutostartSettings!,
                      locale: _locale,
                      enabled: !_busy,
                    ),
                  if (widget.readAutostart != null &&
                      widget.writeAutostart != null)
                    ClientAutostartPanel(
                      read: widget.readAutostart!,
                      openSettings: widget.openAutostartSettings,
                      write: _writeAutostart,
                      locale: _locale,
                      enabled: !_busy,
                    ),
                  if (widget.requestNotificationPermission != null)
                    ClientNotificationPermissionPanel(
                      request: widget.requestNotificationPermission!,
                      locale: _locale,
                      enabled: !_busy,
                    ),
                  ClientNotificationsPanel(
                    delivery: _notifications,
                    supported: widget.deliverNotification != null,
                    locale: _locale,
                    busy: _busy,
                    onChanged: _chooseNotifications,
                    persistent: widget.saveNotifications != null,
                    storageFailed: _notificationStorageFailed,
                  ),
                ],
              ),
              exportBundle:
                  widget.desktopIntegration &&
                      supportsClientBundleDestination(Platform.operatingSystem)
                  ? _exportBundle
                  : null,
            ),
          ),
        ],
      ),
    ),
  );
}
