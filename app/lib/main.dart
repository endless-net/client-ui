import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

const _appTitle = 'EndlessNet Tray';
const _appVersion = String.fromEnvironment(
  'ENDLESSNET_VERSION',
  defaultValue: 'dev',
);
const _appCommit = String.fromEnvironment(
  'ENDLESSNET_COMMIT',
  defaultValue: 'unknown',
);
const _appBuildDate = String.fromEnvironment(
  'ENDLESSNET_BUILD_DATE',
  defaultValue: 'unknown',
);
const _appTarget = String.fromEnvironment(
  'ENDLESSNET_TARGET',
  defaultValue: 'windows/amd64',
);
const _defaultPipe = r'\\.\pipe\endlessnet-service';
const _defaultDebugLogDir = r'~\.endlessnet\logs';
const _defaultAdminURL = 'https://endlessnet.ru/admin/';
const _defaultConnectURL = 'https://endlessnet.ru/admin/connect/windows';
const _showSignalPath = r'~\.endlessnet\endlessnet-tray.show';

RandomAccessFile? _instanceLock;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.parse(args);
  final logger = AppLogger(config.debugLogDir, enabled: config.debug);
  await logger.open();
  logger.info(
    'starting version=$_appVersion commit=$_appCommit args=${config.safeArgs}',
  );

  if (config.showVersion) {
    stdout.write(versionText());
    await logger.close();
    exit(0);
  }

  final bridge = EndlessNetClientBridge(config: config, logger: logger);
  if (config.enrollText.trim().isNotEmpty) {
    await _runEnrollmentAndExit(config, bridge, logger);
    exit(exitCode);
  }

  final acquired = await acquireSingleInstanceLock(logger);
  if (!acquired) {
    logger.info(
      'existing EndlessNet instance detected; showing existing window',
    );
    await requestExistingInstanceWindow(logger);
    showExistingWindow();
    await logger.close();
    exit(0);
  }

  await windowManager.ensureInitialized();
  await windowManager.setPreventClose(true);
  final controller = EndlessNetController(
    config: config,
    bridge: bridge,
    logger: logger,
  );
  runApp(EndlessNetApp(controller: controller));
  await controller.initialize();
}

String versionText() {
  return 'endlessnet-tray $_appVersion\n'
      'commit: $_appCommit\n'
      'built: $_appBuildDate\n'
      'target: $_appTarget\n';
}

Future<void> _runEnrollmentAndExit(
  AppConfig config,
  EndlessNetClientBridge bridge,
  AppLogger logger,
) async {
  try {
    final request = parseEnrollment(
      config.enrollText,
      config.server,
      config.mode,
    );
    await bridge.enroll(request);
    logger.info('deep-link enrollment completed');
    await showMessageBox(
      'EndlessNet enrollment',
      'Device enrollment completed.',
    );
  } catch (err, stack) {
    logger.error('deep-link enrollment failed', err, stack);
    await showMessageBox('EndlessNet enrollment', safeErrorText(err));
    exitCode = 1;
  } finally {
    await logger.close();
  }
}

class AppConfig {
  AppConfig({
    required this.pipe,
    required this.adminURL,
    required this.connectURL,
    required this.server,
    required this.mode,
    required this.enrollText,
    required this.showWindow,
    required this.debug,
    required this.debugLogDir,
    required this.showVersion,
    required this.safeArgs,
  });

  final String pipe;
  final String adminURL;
  final String connectURL;
  final String server;
  final String mode;
  final String enrollText;
  final bool showWindow;
  final bool debug;
  final String debugLogDir;
  final bool showVersion;
  final List<String> safeArgs;

  static AppConfig parse(List<String> args) {
    var pipe = _defaultPipe;
    var adminURL = _defaultAdminURL;
    var connectURL = _defaultConnectURL;
    var server = '';
    var mode = 'workstation';
    var enrollText = '';
    var showWindow = false;
    var debug = false;
    var debugLogDir = _defaultDebugLogDir;
    var showVersion = false;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i].trim();
      String nextValue() {
        if (i + 1 >= args.length) {
          return '';
        }
        i++;
        return args[i];
      }

      if (arg == '--pipe' || arg == '--ipc-pipe') {
        pipe = nextValue();
      } else if (arg == '--admin-url') {
        adminURL = nextValue();
      } else if (arg == '--connect-url') {
        connectURL = nextValue();
      } else if (arg == '--server') {
        server = nextValue();
      } else if (arg == '--mode') {
        mode = nextValue();
      } else if (arg == '--enroll') {
        enrollText = nextValue();
      } else if (arg == '--show-window') {
        showWindow = true;
      } else if (arg == '--debug') {
        debug = true;
      } else if (arg == '--debug-log-dir') {
        debugLogDir = nextValue();
      } else if (arg == '--version' || arg == 'version') {
        showVersion = true;
      } else if (arg.startsWith('endlessnet://')) {
        enrollText = arg;
      }
    }

    return AppConfig(
      pipe: pipe.trim().isEmpty ? _defaultPipe : pipe.trim(),
      adminURL: adminURL.trim().isEmpty ? _defaultAdminURL : adminURL.trim(),
      connectURL: connectURL.trim().isEmpty
          ? _defaultConnectURL
          : connectURL.trim(),
      server: server.trim(),
      mode: mode.trim().isEmpty ? 'workstation' : mode.trim(),
      enrollText: enrollText.trim(),
      showWindow: showWindow,
      debug: debug,
      debugLogDir: debugLogDir.trim().isEmpty
          ? _defaultDebugLogDir
          : debugLogDir.trim(),
      showVersion: showVersion,
      safeArgs: redactArgs(args),
    );
  }
}

List<String> redactArgs(List<String> args) {
  final redacted = <String>[];
  var redactNext = false;
  for (final arg in args) {
    final lower = arg.toLowerCase();
    if (redactNext) {
      redacted.add('[redacted]');
      redactNext = false;
      continue;
    }
    if (lower == '--enroll' ||
        lower.contains('token') ||
        lower.contains('secret')) {
      redacted.add(
        arg.contains('=')
            ? '${arg.substring(0, arg.indexOf('=') + 1)}[redacted]'
            : arg,
      );
      redactNext = !arg.contains('=');
      continue;
    }
    if (lower.startsWith('endlessnet://')) {
      redacted.add('[redacted-deeplink]');
      continue;
    }
    redacted.add(arg);
  }
  return redacted;
}

class AppLogger {
  AppLogger(this.dir, {required this.enabled});

  final String dir;
  final bool enabled;
  IOSink? _sink;

  Future<void> open() async {
    if (!enabled) {
      return;
    }
    final path = resolveUserPath(dir);
    final directory = Directory(path);
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}endlessnet-tray-flutter.log',
    );
    if (await file.exists() && await file.length() > 10 * 1024 * 1024) {
      final rotated = File('${file.path}.1');
      if (await rotated.exists()) {
        await rotated.delete();
      }
      await file.rename(rotated.path);
    }
    _sink = file.openWrite(mode: FileMode.append);
    info('debug logger opened path=${file.path}');
  }

  void info(String message) {
    _write('INFO', message);
  }

  void error(String message, Object err, StackTrace stack) {
    _write('ERROR', '$message: ${safeErrorText(err)}\n$stack');
  }

  void _write(String level, String message) {
    final sink = _sink;
    if (sink == null) {
      return;
    }
    final line =
        '${DateTime.now().toUtc().toIso8601String()} $level ${redactText(message)}';
    sink.writeln(line);
  }

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}

String resolveUserPath(String path) {
  var expanded = path.trim();
  Platform.environment.forEach((key, value) {
    expanded = expanded.replaceAll('%$key%', value);
  });
  if (expanded == '~' ||
      expanded.startsWith(r'~\') ||
      expanded.startsWith('~/')) {
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    if (expanded == '~') {
      return home;
    }
    return '$home${Platform.pathSeparator}${expanded.substring(2)}';
  }
  return expanded;
}

String redactText(String value) {
  return value
      .replaceAll(
        RegExp(
          r'''(token|session|secret|credential|private[_-]?key)(["'=:\s]+)([^"'\s,;}]+)''',
          caseSensitive: false,
        ),
        r'$1$2[redacted]',
      )
      .replaceAll(
        RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
        'Bearer [redacted]',
      )
      .replaceAll(
        RegExp(r'''endlessnet://[^\s"']+''', caseSensitive: false),
        '[redacted-deeplink]',
      )
      .replaceAll(RegExp(r'\b(?:enj|enr|join)_[A-Za-z0-9_-]+\b'), '[redacted]');
}

Future<bool> acquireSingleInstanceLock(AppLogger logger) async {
  try {
    final lockDir = Directory(resolveUserPath(r'~\.endlessnet'));
    await lockDir.create(recursive: true);
    final file = File(
      '${lockDir.path}${Platform.pathSeparator}endlessnet-tray.lock',
    );
    _instanceLock = await file.open(mode: FileMode.write);
    _instanceLock!.lockSync(FileLock.exclusive);
    return true;
  } catch (err, stack) {
    logger.error('single-instance lock unavailable', err, stack);
    return false;
  }
}

void showExistingWindow() {
  final title = _appTitle.toNativeUtf16();
  try {
    final result = FindWindow(null, PCWSTR(title));
    final hwnd = result.value;
    if (hwnd.address != 0) {
      ShowWindow(hwnd, SW_SHOW);
      SetForegroundWindow(hwnd);
    }
  } finally {
    calloc.free(title);
  }
}

Future<void> requestExistingInstanceWindow(AppLogger logger) async {
  try {
    final file = File(resolveUserPath(_showSignalPath));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      DateTime.now().toUtc().toIso8601String(),
      flush: true,
    );
  } catch (err, stack) {
    logger.error('failed to write existing-instance show signal', err, stack);
  }
}

class EnrollmentRequest {
  EnrollmentRequest({
    required this.token,
    required this.server,
    required this.mode,
  });

  final String token;
  final String server;
  final String mode;
}

EnrollmentRequest parseEnrollment(
  String text,
  String defaultServer,
  String defaultMode,
) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw StateError('Enrollment token is required.');
  }
  var token = '';
  var server = defaultServer.trim();
  var mode = defaultMode.trim().isEmpty ? 'workstation' : defaultMode.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.scheme.isNotEmpty) {
    token =
        uri.queryParameters['token'] ??
        uri.queryParameters['enroll_token'] ??
        uri.queryParameters['join_token'] ??
        '';
    server = (uri.queryParameters['server'] ?? server).trim();
    mode = (uri.queryParameters['mode'] ?? mode).trim();
  }
  if (token.trim().isEmpty) {
    token =
        RegExp(
          r'\b(?:enj|enr|join)_[A-Za-z0-9_-]+\b',
        ).firstMatch(trimmed)?.group(0) ??
        '';
  }
  if (token.trim().isEmpty) {
    throw StateError('Enrollment token is required.');
  }
  return EnrollmentRequest(
    token: token.trim(),
    server: server,
    mode: mode.isEmpty ? 'workstation' : mode,
  );
}

class EndlessNetClientBridge {
  EndlessNetClientBridge({required this.config, required this.logger});

  final AppConfig config;
  final AppLogger logger;

  String get clientExe {
    final dir = File(Platform.resolvedExecutable).parent.path;
    return '$dir${Platform.pathSeparator}endlessnet-client.exe';
  }

  Future<Map<String, dynamic>> status() => _serviceJSON(['status']);
  Future<Map<String, dynamic>> connect() => _serviceJSON(['connect']);
  Future<Map<String, dynamic>> disconnect() => _serviceJSON(['disconnect']);
  Future<Map<String, dynamic>> logout() => _serviceJSON(['logout']);
  Future<Map<String, dynamic>> networks() => _serviceJSON(['networks']);
  Future<Map<String, dynamic>> diagnostics() => _serviceJSON(['diagnostics']);
  Future<Map<String, dynamic>> recentLogs() => _serviceJSON(['logs-recent']);

  Future<Map<String, dynamic>> selectNetwork(String networkID) {
    return _serviceJSON(['select-network', '--network-id', networkID]);
  }

  Future<Map<String, dynamic>> enroll(EnrollmentRequest request) {
    final args = [
      'service',
      'enroll',
      '--json',
      '--ipc-pipe',
      config.pipe,
      '--join-token-file',
      '-',
      '--mode',
      request.mode,
      '--timeout',
      '2m',
    ];
    if (request.server.trim().isNotEmpty) {
      args.addAll(['--server', request.server.trim()]);
    }
    return _runJSON(args, stdinText: request.token);
  }

  Future<Map<String, dynamic>> _serviceJSON(List<String> serviceArgs) {
    return _runJSON([
      'service',
      ...serviceArgs,
      '--ipc-pipe',
      config.pipe,
      '--timeout',
      '8s',
    ]);
  }

  Future<Map<String, dynamic>> _runJSON(
    List<String> args, {
    String? stdinText,
  }) async {
    final exe = clientExe;
    logger.info('running endlessnet-client ${redactArgs(args).join(' ')}');
    if (!await File(exe).exists()) {
      throw StateError(
        'endlessnet-client.exe is missing next to the desktop app.',
      );
    }
    final process = await Process.start(
      exe,
      args,
      mode: ProcessStartMode.normal,
    );
    if (stdinText != null) {
      process.stdin.write(stdinText);
    }
    await process.stdin.close();
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode;
    final out = await stdoutFuture;
    final err = await stderrFuture;
    logger.info(
      'endlessnet-client exit=$code stdout=${out.trim().length} stderr=${err.trim().length}',
    );
    if (code != 0) {
      throw StateError(
        firstNonEmpty(
          _jsonError(out),
          err.trim(),
          out.trim(),
          'endlessnet-client failed with exit code $code',
        ),
      );
    }
    final decoded = jsonDecode(out.trim().isEmpty ? '{}' : out);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw StateError('endlessnet-client returned non-object JSON.');
  }

  String _jsonError(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {
      return '';
    }
    return '';
  }
}

class EndlessNetController extends ChangeNotifier
    with TrayListener, WindowListener {
  EndlessNetController({
    required this.config,
    required this.bridge,
    required this.logger,
  });

  final AppConfig config;
  final EndlessNetClientBridge bridge;
  final AppLogger logger;

  Map<String, dynamic>? statusPayload;
  String? errorText;
  bool busy = false;
  bool quitting = false;
  Timer? _refreshTimer;
  Timer? _showSignalTimer;
  DateTime? _lastShowSignalWrite;

  String get state => valueText(
    statusPayload?['state'] ?? statusPayload?['control_state'],
    fallback: errorText == null ? 'Loading...' : 'Service unavailable',
  );
  bool get connected => state.toLowerCase() == 'connected';

  Future<void> initialize() async {
    trayManager.addListener(this);
    windowManager.addListener(this);
    await trayManager.setIcon('assets/icons/tray.ico');
    await trayManager.setToolTip('EndlessNet: starting');
    await _setupWindow();
    _lastShowSignalWrite = await showSignalWriteTime();
    _showSignalTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => checkShowSignal(),
    );
    await refreshStatus();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => refreshStatus(silent: true),
    );
  }

  Future<void> _setupWindow() async {
    const options = WindowOptions(
      size: Size(760, 560),
      minimumSize: Size(620, 460),
      center: true,
      skipTaskbar: false,
      title: _appTitle,
      backgroundColor: Colors.transparent,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (config.showWindow) {
        await showWindow();
      } else {
        await windowManager.hide();
      }
    });
  }

  @override
  void onTrayIconMouseDown() {
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        showWindow();
      case 'connect':
        runAction(() => bridge.connect());
      case 'disconnect':
        runAction(() => bridge.disconnect());
      case 'connect-device':
        openConnectURL();
      case 'open-admin':
        openAdminURL();
      case 'status':
        showStatusDialog();
      case 'networks':
        showNetworksDialog();
      case 'copy-diagnostics':
        copyDiagnostics();
      case 'recent-logs':
        showRecentLogsDialog();
      case 'logout':
        logout();
      case 'exit':
        exitApp();
    }
  }

  @override
  void onWindowClose() {
    if (quitting) {
      windowManager.destroy();
      return;
    }
    windowManager.hide();
  }

  Future<void> refreshStatus({bool silent = false}) async {
    if (!silent) {
      busy = true;
      notifyListeners();
    }
    try {
      final payload = await bridge.status();
      statusPayload = payload;
      errorText = null;
      logger.info('status refreshed state=$state');
    } catch (err, stack) {
      errorText = safeErrorText(err);
      logger.error('status refresh failed', err, stack);
    } finally {
      busy = false;
      await _updateTray();
      notifyListeners();
    }
  }

  Future<void> runAction(Future<Map<String, dynamic>> Function() action) async {
    busy = true;
    notifyListeners();
    try {
      statusPayload = await action();
      errorText = null;
      logger.info('action completed state=$state');
    } catch (err, stack) {
      errorText = safeErrorText(err);
      logger.error('action failed', err, stack);
      await showMessageBox('EndlessNet', errorText!);
    } finally {
      busy = false;
      await _updateTray();
      notifyListeners();
    }
  }

  Future<void> _updateTray() async {
    await trayManager.setToolTip('EndlessNet: $state');
    await trayManager.setContextMenu(_buildTrayMenu());
  }

  Menu _buildTrayMenu() {
    final status = statusPayload;
    final account = valueText(status?['account_id'], fallback: 'No account');
    final thisDevice = thisDeviceLabel(status);
    final peers = peerLabels(status);
    return Menu(
      items: [
        MenuItem.checkbox(key: 'open', label: 'EndlessNet', checked: true),
        MenuItem(label: state, disabled: true),
        MenuItem.separator(),
        MenuItem.submenu(
          key: 'account',
          label: account,
          submenu: Menu(
            items: [
              MenuItem(label: 'Account: $account', disabled: true),
              MenuItem(
                label: 'Network: ${networkLabel(status)}',
                disabled: true,
              ),
              MenuItem.separator(),
              MenuItem(key: 'open-admin', label: 'Open admin console'),
              MenuItem(key: 'logout', label: 'Sign out / remove this device'),
            ],
          ),
        ),
        MenuItem(label: thisDevice, disabled: true),
        MenuItem.submenu(
          key: 'devices',
          label: 'Network devices',
          submenu: Menu(
            items: [
              if (peers.isEmpty)
                MenuItem(label: 'No peer devices', disabled: true),
              ...peers.map((peer) => MenuItem(label: peer, disabled: true)),
              MenuItem.separator(),
              MenuItem(key: 'status', label: 'Status...'),
              MenuItem(key: 'networks', label: 'Networks...'),
            ],
          ),
        ),
        MenuItem.submenu(
          key: 'exit-nodes',
          label: 'Exit nodes',
          submenu: Menu(
            items: [
              MenuItem(label: 'No exit nodes configured', disabled: true),
            ],
          ),
        ),
        MenuItem.submenu(
          key: 'preferences',
          label: 'Preferences',
          submenu: Menu(
            items: [
              MenuItem(key: 'connect-device', label: 'Connect this device'),
              MenuItem(key: 'connect', label: 'Connect'),
              MenuItem(key: 'disconnect', label: 'Disconnect'),
              MenuItem.separator(),
              MenuItem(key: 'copy-diagnostics', label: 'Copy diagnostics'),
              MenuItem(key: 'recent-logs', label: 'Recent logs'),
              MenuItem(key: 'open-admin', label: 'Open admin console'),
            ],
          ),
        ),
        MenuItem(label: 'About EndlessNet $_appVersion', disabled: true),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'Exit'),
      ],
    );
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> openConnectURL() async {
    await launchUrl(
      Uri.parse(config.connectURL),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> openAdminURL() async {
    await launchUrl(
      Uri.parse(config.adminURL),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> showStatusDialog() async {
    await refreshStatus(silent: true);
    await showMessageBox('EndlessNet status', statusSummary(statusPayload));
  }

  Future<void> showNetworksDialog() async {
    try {
      final payload = await bridge.networks();
      await showMessageBox('EndlessNet networks', networksSummary(payload));
    } catch (err, stack) {
      logger.error('networks failed', err, stack);
      await showMessageBox('EndlessNet networks', safeErrorText(err));
    }
  }

  Future<void> copyDiagnostics() async {
    try {
      final payload = await bridge.diagnostics();
      final text = const JsonEncoder.withIndent(
        '  ',
      ).convert(redactDiagnostics(payload));
      await Clipboard.setData(ClipboardData(text: text));
      await showMessageBox('EndlessNet diagnostics', 'Diagnostics copied.');
    } catch (err, stack) {
      logger.error('copy diagnostics failed', err, stack);
      await showMessageBox('EndlessNet diagnostics', safeErrorText(err));
    }
  }

  Future<void> showRecentLogsDialog() async {
    try {
      final payload = await bridge.recentLogs();
      await showMessageBox('EndlessNet logs', recentLogsSummary(payload));
    } catch (err, stack) {
      logger.error('recent logs failed', err, stack);
      await showMessageBox('EndlessNet logs', safeErrorText(err));
    }
  }

  Future<void> logout() async {
    await runAction(() => bridge.logout());
  }

  Future<void> exitApp() async {
    quitting = true;
    _refreshTimer?.cancel();
    _showSignalTimer?.cancel();
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
    await logger.close();
    await windowManager.destroy();
  }

  Future<void> checkShowSignal() async {
    final writeTime = await showSignalWriteTime();
    if (writeTime == null) {
      return;
    }
    final previous = _lastShowSignalWrite;
    _lastShowSignalWrite = writeTime;
    if (previous != null && !writeTime.isAfter(previous)) {
      return;
    }
    logger.info('show signal received from another instance');
    await showWindow();
  }
}

Future<DateTime?> showSignalWriteTime() async {
  try {
    final file = File(resolveUserPath(_showSignalPath));
    if (!await file.exists()) {
      return null;
    }
    return file.lastModified();
  } catch (_) {
    return null;
  }
}

class EndlessNetApp extends StatelessWidget {
  const EndlessNetApp({super.key, required this.controller});

  final EndlessNetController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'EndlessNet',
          navigatorKey: navigatorKey,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1B7DF0),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          home: HomeScreen(controller: controller),
        );
      },
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.controller});

  final EndlessNetController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.statusPayload;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Image.asset('assets/icons/tray.png', width: 36, height: 36),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'EndlessNet',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text('Private network client for this Windows device.'),
                      ],
                    ),
                  ),
                  StatusPill(
                    text: controller.state,
                    connected: controller.connected,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (controller.errorText != null)
                ErrorBanner(text: controller.errorText!),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: controller.busy
                        ? null
                        : controller.openConnectURL,
                    icon: const Icon(Icons.link),
                    label: const Text('Connect this device'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.busy
                        ? null
                        : () => controller.runAction(
                            () => controller.connected
                                ? controller.bridge.disconnect()
                                : controller.bridge.connect(),
                          ),
                    icon: Icon(
                      controller.connected
                          ? Icons.link_off
                          : Icons.power_settings_new,
                    ),
                    label: Text(
                      controller.connected ? 'Disconnect' : 'Connect',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.busy
                        ? null
                        : controller.showStatusDialog,
                    icon: const Icon(Icons.info_outline),
                    label: const Text('Status'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.busy ? null : controller.openAdminURL,
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('Admin console'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.busy
                        ? null
                        : () => windowManager.hide(),
                    icon: const Icon(Icons.keyboard_arrow_down),
                    label: const Text('Close to tray'),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: InfoPanel(
                        title: 'This device',
                        children: [
                          InfoRow(
                            label: 'Hostname',
                            value: valueText(
                              status?['hostname'] ??
                                  nestedValue(status, 'agent', 'hostname'),
                            ),
                          ),
                          InfoRow(
                            label: 'Overlay IP',
                            value: valueText(
                              status?['overlay_ip'] ??
                                  nestedValue(status, 'agent', 'overlay_ip'),
                            ),
                          ),
                          InfoRow(
                            label: 'Network',
                            value: networkLabel(status),
                          ),
                          InfoRow(
                            label: 'Map revision',
                            value: valueText(status?['map_revision']),
                          ),
                          InfoRow(
                            label: 'Peers',
                            value: valueText(status?['peer_count']),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: InfoPanel(
                        title: 'Network devices',
                        children: [
                          for (final peer in peerLabels(status))
                            InfoRow(label: '', value: peer),
                          if (peerLabels(status).isEmpty)
                            const Text('No peer devices.'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Text(
                    'Version $_appVersion ($_appCommit)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  if (controller.busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  TextButton.icon(
                    onPressed: controller.busy
                        ? null
                        : controller.refreshStatus,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.text, required this.connected});

  final String text;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final color = connected ? const Color(0xFF118C4F) : const Color(0xFF8A4B0B);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          text,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2A0A0)),
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFF8A1F1F))),
    );
  }
}

class InfoPanel extends StatelessWidget {
  const InfoPanel({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8E0EA)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty)
            SizedBox(
              width: 96,
              child: Text(
                label,
                style: const TextStyle(color: Color(0xFF65758B)),
              ),
            ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

Future<void> showMessageBox(String title, String message) async {
  final context = navigatorKey.currentContext;
  if (context == null) {
    showNativeMessageBox(title, message);
    return;
  }
  await windowManager.show();
  await windowManager.focus();
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: SelectableText(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

final navigatorKey = GlobalKey<NavigatorState>();

void showNativeMessageBox(String title, String message) {
  final titlePtr = title.toNativeUtf16();
  final messagePtr = message.toNativeUtf16();
  try {
    MessageBox(HWND_DESKTOP, PCWSTR(messagePtr), PCWSTR(titlePtr), MB_OK);
  } finally {
    calloc.free(titlePtr);
    calloc.free(messagePtr);
  }
}

String statusSummary(Map<String, dynamic>? payload) {
  return [
    'State: ${valueText(payload?['state'])}',
    'Account: ${valueText(payload?['account_id'])}',
    'Network: ${networkLabel(payload)}',
    'Assigned IP: ${valueText(payload?['overlay_ip'])}',
    'Hostname: ${valueText(payload?['hostname'])}',
    'Map revision: ${valueText(payload?['map_revision'])}',
    'Peers: ${valueText(payload?['peer_count'])}',
    'Last sync: ${valueText(nestedValue(payload, 'agent', 'generated_at'))}',
  ].join('\n');
}

String networksSummary(Map<String, dynamic>? payload) {
  final networks = payload?['networks'];
  if (networks is! List || networks.isEmpty) {
    return 'No enrolled networks.';
  }
  return networks
      .map(
        (item) => item is Map
            ? firstNonEmpty('${item['name'] ?? ''}', '${item['id'] ?? ''}')
            : '$item',
      )
      .join('\n');
}

String recentLogsSummary(Map<String, dynamic> payload) {
  final lines = payload['lines'];
  if (lines is List && lines.isNotEmpty) {
    return lines.map((line) => '$line').join('\n');
  }
  final logs = payload['logs'];
  if (logs is List && logs.isNotEmpty) {
    return logs.map((line) => '$line').join('\n');
  }
  return 'No recent logs.';
}

String thisDeviceLabel(Map<String, dynamic>? payload) {
  if (payload == null) {
    return 'This device: loading...';
  }
  final host = valueText(
    payload['hostname'] ?? nestedValue(payload, 'agent', 'hostname'),
    fallback: 'this Windows device',
  );
  final ip = valueText(
    payload['overlay_ip'] ?? nestedValue(payload, 'agent', 'overlay_ip'),
    fallback: '',
  );
  return ip.isEmpty ? 'This device: $host' : 'This device: $host ($ip)';
}

String networkLabel(Map<String, dynamic>? payload) {
  return firstNonEmpty(
    valueText(payload?['network_name'], fallback: ''),
    valueText(payload?['network_id'], fallback: ''),
    'default',
  );
}

List<String> peerLabels(Map<String, dynamic>? payload) {
  final peers = nestedValue(payload, 'agent', 'peers');
  if (peers is! List) {
    return const [];
  }
  return peers
      .take(20)
      .map((peer) {
        if (peer is! Map) {
          return '$peer';
        }
        final name = firstNonEmpty(
          '${peer['hostname'] ?? ''}',
          '${peer['peer_id'] ?? ''}',
        );
        final path = valueText(peer['selected_path'], fallback: 'offline');
        return path == 'none' || path == 'offline'
            ? '$name - offline'
            : '$name - $path';
      })
      .where((line) => line.trim().isNotEmpty)
      .toList();
}

Object? nestedValue(Map<String, dynamic>? payload, String key, String nested) {
  final child = payload?[key];
  if (child is Map) {
    return child[nested];
  }
  return null;
}

String valueText(Object? value, {String fallback = '-'}) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == '<nil>' || text == 'null') {
    return fallback;
  }
  return text;
}

String firstNonEmpty(String a, [String b = '', String c = '', String d = '']) {
  for (final value in [a, b, c, d]) {
    if (value.trim().isNotEmpty && value.trim() != '-') {
      return value.trim();
    }
  }
  return '';
}

Object redactDiagnostics(Object? value) {
  if (value is Map) {
    return value.map((key, child) {
      final name = key.toString().toLowerCase().replaceAll(
        RegExp(r'[-\s]'),
        '_',
      );
      if (name.contains('private_key') ||
          name.contains('credential') ||
          name.contains('token') ||
          name.contains('secret')) {
        return MapEntry(key, '[redacted]');
      }
      return MapEntry(key, redactDiagnostics(child));
    });
  }
  if (value is List) {
    return value.map(redactDiagnostics).toList();
  }
  if (value is String) {
    return redactText(value);
  }
  return value ?? {};
}

String safeErrorText(Object err) {
  return redactText(err.toString().replaceFirst('Bad state: ', '').trim());
}
