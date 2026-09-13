import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'client_session.dart';
import 'client_session_panel.dart';
import 'client_state_controller.dart';

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
  });
  final ClientSession session;
  final bool desktopIntegration;
  final bool showWindow;
  final Future<DateTime?> Function()? showSignal;
  final Future<void> Function()? onExit;
  @override
  State<ClientDesktopApp> createState() => _ClientDesktopAppState();
}

class _ClientDesktopAppState extends State<ClientDesktopApp>
    with WindowListener, TrayListener {
  final _navigator = GlobalKey<NavigatorState>();
  Timer? _signals;
  DateTime? _lastSignal;
  bool _busy = false;
  String? _notice;
  ClientSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
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
        await trayManager.setToolTip('EndlessNet');
        await trayManager.setContextMenu(
          Menu(
            items: [
              MenuItem(key: 'open', label: 'Open EndlessNet'),
              MenuItem(key: 'exit', label: 'Quit'),
            ],
          ),
        );
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
          setState(
            () => _notice =
                'Desktop integration is unavailable. Runtime access remains separate.',
          );
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
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await session.connect();
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice =
              'Native runtime is unavailable or incompatible. No fallback was used.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _quit() async {
    if (_busy) return;
    setState(() => _busy = true);
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
          title: const Text('Exit without confirmed runtime notification?'),
          content: const Text(
            'The agent may retain its current connection intent. The operation will not be replayed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Exit UI'),
            ),
          ],
        ),
      );
      if (exit != true) {
        if (mounted) setState(() => _busy = false);
        return;
      }
    }
    _signals?.cancel();
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
            child: const Text('Reconnect runtime'),
          ),
          TextButton(
            onPressed: _busy ? null : _quit,
            child: const Text('Quit'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_notice != null) Text(_notice!),
          AnimatedBuilder(
            animation: session.state,
            builder: (context, _) =>
                Text('Runtime: ${session.state.link.name}'),
          ),
          Expanded(child: ClientSessionPanel(session: session)),
        ],
      ),
    ),
  );
}
