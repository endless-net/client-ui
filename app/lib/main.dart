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

import 'named_pipe_http.dart';
import 'service_contract.dart';

const _appTitle = 'EndlessNet';
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
const _defaultAdminURL = 'https://admin.endlessnet.ru/';
const _showSignalPath = r'~\.endlessnet\endlessnet.show';
const _defaultEnrollmentPollInterval = Duration(seconds: 2);
const _defaultEnrollmentPollTimeout = Duration(minutes: 10);
const _defaultConnectionPollInterval = Duration(seconds: 1);
const _defaultConnectionPollTimeout = Duration(seconds: 30);

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
  if (config.elevatedEnrollment) {
    await _runEnrollmentAndExit(config, bridge, logger);
    exit(exitCode);
  }
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
  return 'endlessnet $_appVersion\n'
      'commit: $_appCommit\n'
      'built: $_appBuildDate\n'
      'target: $_appTarget\n';
}

Future<void> _runEnrollmentAndExit(
  AppConfig config,
  EndlessNetClientBridge bridge,
  AppLogger logger,
) async {
  EnrollmentRequest? request;
  try {
    request = config.enrollText.trim().isEmpty
        ? EnrollmentRequest(token: '', server: config.server, mode: config.mode)
        : parseEnrollment(config.enrollText, config.server, config.mode);
    var payload = await bridge.enroll(request);
    logger.info('enrollment request completed');
    final approvalURL = enrollmentApprovalURL(payload);
    if (approvalURL.isNotEmpty) {
      final opened = await launchExternalURL(Uri.parse(approvalURL));
      if (!opened) {
        throw StateError(
          'Windows could not open the device connection page in your default browser.',
        );
      }
      logger.info('device connection page opened');
    }
    final deadline = DateTime.now().add(_defaultEnrollmentPollTimeout);
    while (isEnrollmentPending(payload) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_defaultEnrollmentPollInterval);
      payload = await bridge.status();
    }
    if (isEnrollmentPending(payload)) {
      throw StateError('Device connection timed out. Try again.');
    }
    if (!ServiceStatus(payload).deviceEnrolled) {
      throw StateError('The service did not complete device enrollment.');
    }
    logger.info('enrollment completed');
  } catch (err, stack) {
    if (!config.elevatedEnrollment &&
        Platform.isWindows &&
        request != null &&
        requiresAdministratorElevation(err)) {
      try {
        final launched = await launchElevatedEnrollment(config, request);
        if (!launched) {
          throw StateError(
            'Administrator approval is required to connect this device.',
          );
        }
        logger.info('elevated enrollment process launched after owner denial');
        return;
      } catch (elevatedErr, elevatedStack) {
        logger.error(
          'failed to launch elevated enrollment',
          elevatedErr,
          elevatedStack,
        );
        await showMessageBox(
          'EndlessNet enrollment',
          safeErrorText(elevatedErr),
        );
        exitCode = 1;
        return;
      }
    }
    logger.error('enrollment failed', err, stack);
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
    required this.server,
    required this.mode,
    required this.enrollText,
    required this.elevatedEnrollment,
    required this.showWindow,
    required this.debug,
    required this.debugLogDir,
    required this.showVersion,
    required this.safeArgs,
  });

  final String pipe;
  final String adminURL;
  final String server;
  final String mode;
  final String enrollText;
  final bool elevatedEnrollment;
  final bool showWindow;
  final bool debug;
  final String debugLogDir;
  final bool showVersion;
  final List<String> safeArgs;

  static AppConfig parse(List<String> args) {
    var pipe = _defaultPipe;
    var adminURL = _defaultAdminURL;
    var server = '';
    var mode = 'workstation';
    var enrollText = '';
    var elevatedEnrollment = false;
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
      } else if (arg == '--server') {
        server = nextValue();
      } else if (arg == '--mode') {
        mode = nextValue();
      } else if (arg == '--enroll') {
        enrollText = nextValue();
      } else if (arg == '--elevated-enroll') {
        elevatedEnrollment = true;
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
      server: server.trim(),
      mode: mode.trim().isEmpty ? 'workstation' : mode.trim(),
      enrollText: enrollText.trim(),
      elevatedEnrollment: elevatedEnrollment,
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
      '${directory.path}${Platform.pathSeparator}endlessnet.log',
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
      '${lockDir.path}${Platform.pathSeparator}endlessnet.lock',
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
  var isEnrollmentLink = false;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.scheme.isNotEmpty) {
    isEnrollmentLink =
        uri.scheme.toLowerCase() == 'endlessnet' &&
        uri.host.toLowerCase() == 'enroll';
    token = uri.queryParameters['enroll_token'] ?? '';
    server = (uri.queryParameters['server'] ?? server).trim();
    mode = (uri.queryParameters['mode'] ?? mode).trim();
  }
  if (token.trim().isEmpty && !isEnrollmentLink) {
    token =
        RegExp(r'\benr_[A-Za-z0-9_-]+\b').firstMatch(trimmed)?.group(0) ?? '';
  }
  if (token.trim().isEmpty && !isEnrollmentLink) {
    throw StateError('Enrollment token is required.');
  }
  return EnrollmentRequest(
    token: token.trim(),
    server: server,
    mode: mode.isEmpty ? 'workstation' : mode,
  );
}

typedef ElevatedEnrollmentLauncher =
    Future<bool> Function(EnrollmentRequest request);

bool requiresAdministratorElevation(Object error) {
  if (error is! ServiceIPCException) {
    return false;
  }
  return error.errorCode == 'owner_required' ||
      error.errorCode == 'administrator_required';
}

Future<bool> launchElevatedEnrollment(
  AppConfig config,
  EnrollmentRequest request,
) async {
  if (!Platform.isWindows) {
    throw UnsupportedError(
      'Administrative enrollment is only supported on Windows.',
    );
  }
  return launchWindowsProcessElevated(
    Platform.resolvedExecutable,
    elevatedEnrollmentArguments(config, request),
  );
}

List<String> elevatedEnrollmentArguments(
  AppConfig config,
  EnrollmentRequest request,
) {
  final arguments = <String>[
    '--elevated-enroll',
    '--pipe',
    config.pipe,
    '--mode',
    request.mode,
  ];
  if (request.server.trim().isNotEmpty) {
    arguments.addAll(['--server', request.server.trim()]);
  }
  if (request.token.trim().isNotEmpty) {
    arguments.addAll(['--enroll', request.token.trim()]);
  }
  if (config.debug) {
    arguments.addAll(['--debug', '--debug-log-dir', config.debugLogDir]);
  }
  return arguments;
}

bool launchWindowsProcessElevated(String executable, List<String> arguments) {
  final verbPtr = 'runas'.toNativeUtf16();
  final executablePtr = executable.toNativeUtf16();
  final parametersPtr = arguments
      .map(quoteWindowsCommandLineArgument)
      .join(' ')
      .toNativeUtf16();
  try {
    final result = ShellExecute(
      null,
      PCWSTR(verbPtr),
      PCWSTR(executablePtr),
      PCWSTR(parametersPtr),
      null,
      SW_SHOWNORMAL,
    );
    return result.address > 32;
  } finally {
    calloc.free(verbPtr);
    calloc.free(executablePtr);
    calloc.free(parametersPtr);
  }
}

String quoteWindowsCommandLineArgument(String value) {
  if (value.isEmpty) {
    return '""';
  }
  if (!RegExp(r'[\s"]').hasMatch(value)) {
    return value;
  }
  final quoted = StringBuffer('"');
  var backslashes = 0;
  void writeBackslashes(int count) {
    for (var i = 0; i < count; i++) {
      quoted.write(r'\');
    }
  }

  for (final codeUnit in value.codeUnits) {
    if (codeUnit == 0x5c) {
      backslashes++;
      continue;
    }
    if (codeUnit == 0x22) {
      writeBackslashes(backslashes * 2 + 1);
      quoted.write('"');
      backslashes = 0;
      continue;
    }
    writeBackslashes(backslashes);
    backslashes = 0;
    quoted.writeCharCode(codeUnit);
  }
  writeBackslashes(backslashes * 2);
  quoted.write('"');
  return quoted.toString();
}

class EndlessNetClientBridge {
  EndlessNetClientBridge({
    required this.config,
    required this.logger,
    NamedPipeHttpClient? ipc,
  }) : _ipc =
           ipc ??
           NamedPipeHttpClient(
             pipePath: config.pipe,
             timeout: const Duration(seconds: 8),
           );

  final AppConfig config;
  final AppLogger logger;
  final NamedPipeHttpClient _ipc;

  Future<Map<String, dynamic>> status() =>
      _request('GET', ServiceIPCPath.status);
  Future<Map<String, dynamic>> connect() =>
      _request('POST', ServiceIPCPath.connect, body: {});
  Future<Map<String, dynamic>> serverIdentity() =>
      _request('GET', ServiceIPCPath.serverIdentity);
  Future<Map<String, dynamic>> trustServer(String confirmedKeyID) => _request(
    'POST',
    ServiceIPCPath.trustServer,
    body: {'confirmed': true, 'confirmed_key_id': confirmedKeyID},
  );
  Future<Map<String, dynamic>> disconnect() =>
      _request('POST', ServiceIPCPath.disconnect, body: {});
  Future<Map<String, dynamic>> logout() =>
      _request('POST', ServiceIPCPath.logout, body: {});
  Future<Map<String, dynamic>> networks() =>
      _request('GET', ServiceIPCPath.networks);
  Future<Map<String, dynamic>> diagnostics() =>
      _request('GET', ServiceIPCPath.diagnostics);
  Future<Map<String, dynamic>> diagnosticsBundle({int? logLimit}) => _request(
    'POST',
    ServiceIPCPath.diagnosticsBundle,
    body: {'log_limit': ?logLimit},
  );
  Future<Map<String, dynamic>> recentLogs() =>
      _request('GET', ServiceIPCPath.recentLogs);

  Future<Map<String, dynamic>> selectNetwork(String networkID) {
    return _request(
      'POST',
      ServiceIPCPath.selectNetwork,
      body: {'network_id': networkID},
    );
  }

  Future<Map<String, dynamic>> enroll(EnrollmentRequest request) {
    final token = request.token.trim();
    final server = request.server.trim();
    return _request(
      'POST',
      ServiceIPCPath.enroll,
      body: {
        if (token.isNotEmpty) 'enroll_token': token,
        if (server.isNotEmpty) 'server': server,
        'mode': request.mode,
      },
      timeout: const Duration(minutes: 2),
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration? timeout,
  }) async {
    logger.info('service IPC $method $path');
    final payload = await _ipc.request(
      method,
      path,
      body: body,
      requestTimeout: timeout,
    );
    logger.info('service IPC $method $path completed');
    return payload;
  }
}

class EndlessNetController extends ChangeNotifier
    with TrayListener, WindowListener {
  EndlessNetController({
    required this.config,
    required this.bridge,
    required this.logger,
    this.desktopIntegrationEnabled = true,
    Future<bool> Function(Uri uri)? externalURLLauncher,
    Future<void> Function(String title, String message)? messagePresenter,
    ElevatedEnrollmentLauncher? elevatedEnrollmentLauncher,
    bool? enrollmentElevationSupported,
    this.enrollmentPollInterval = _defaultEnrollmentPollInterval,
    this.enrollmentPollTimeout = _defaultEnrollmentPollTimeout,
    this.connectionPollInterval = _defaultConnectionPollInterval,
    this.connectionPollTimeout = _defaultConnectionPollTimeout,
  }) : externalURLLauncher = externalURLLauncher ?? launchExternalURL,
       messagePresenter = messagePresenter ?? showMessageBox,
       elevatedEnrollmentLauncher =
           elevatedEnrollmentLauncher ??
           ((request) => launchElevatedEnrollment(config, request)),
       enrollmentElevationSupported =
           enrollmentElevationSupported ?? Platform.isWindows;

  final AppConfig config;
  final EndlessNetClientBridge bridge;
  final AppLogger logger;
  final bool desktopIntegrationEnabled;
  final Future<bool> Function(Uri uri) externalURLLauncher;
  final Future<void> Function(String title, String message) messagePresenter;
  final ElevatedEnrollmentLauncher elevatedEnrollmentLauncher;
  final bool enrollmentElevationSupported;
  final Duration enrollmentPollInterval;
  final Duration enrollmentPollTimeout;
  final Duration connectionPollInterval;
  final Duration connectionPollTimeout;

  Map<String, dynamic>? statusPayload;
  String? errorText;
  bool busy = false;
  bool quitting = false;
  Timer? _refreshTimer;
  Timer? _showSignalTimer;
  Timer? _enrollmentPollTimer;
  Timer? _connectionPollTimer;
  DateTime? _enrollmentPollingStartedAt;
  DateTime? _connectionPollingStartedAt;
  bool _enrollmentPollInFlight = false;
  bool _connectionPollInFlight = false;
  DateTime? _lastShowSignalWrite;

  ServiceStatus get serviceStatus => ServiceStatus(statusPayload);
  String get state => serverIdentityChanged
      ? 'Server identity changed'
      : serviceStatus.state(
          fallback: errorText == null ? 'Loading...' : 'Service unavailable',
        );
  bool get connected => serviceStatus.connected;
  bool get serverIdentityChanged => serviceStatus.serverIdentityChanged;
  bool get deviceEnrolled => serviceStatus.deviceEnrolled;
  bool get canConnect => deviceEnrolled && !connected;
  bool get canDisconnect => deviceEnrolled && connected;
  bool get showConnectThisDevice => statusPayload != null && !deviceEnrolled;

  Future<void> initialize() async {
    if (!desktopIntegrationEnabled) {
      await refreshStatus();
      return;
    }
    trayManager.addListener(this);
    windowManager.addListener(this);
    await trayManager.setIcon('assets/icons/endlessnet.ico');
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
        if (serverIdentityChanged) {
          showWindow();
        } else {
          runAction(() => bridge.connect());
        }
      case 'disconnect':
        runAction(() => bridge.disconnect());
      case 'connect-device':
        connectDevice();
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
      if (isEnrollmentPending(payload)) {
        _startEnrollmentPolling();
      } else if (ServiceStatus(payload).deviceEnrolled) {
        _stopEnrollmentPolling();
      }
      _reconcileConnectionPolling(payload);
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
      await action();
      statusPayload = await bridge.status();
      errorText = null;
      _reconcileConnectionPolling(statusPayload!);
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

  Future<void> connect(BuildContext context) async {
    if (!serverIdentityChanged) {
      await runAction(() => bridge.connect());
      return;
    }
    busy = true;
    notifyListeners();
    try {
      final identity = await bridge.serverIdentity();
      final announcedKeyID = valueText(identity['announced_key_id']);
      if (announcedKeyID.isEmpty) {
        throw StateError('The server did not announce a signing key ID.');
      }
      busy = false;
      notifyListeners();
      if (!context.mounted) {
        return;
      }
      final confirmed = await showServerIdentityChangeDialog(
        context,
        serverURL: valueText(identity['control_plane_url'], fallback: 'server'),
        trustedKeyID: valueText(identity['trusted_key_id']),
        announcedKeyID: announcedKeyID,
      );
      if (!confirmed) {
        return;
      }
      await runAction(() => bridge.trustServer(announcedKeyID));
    } catch (err, stack) {
      errorText = safeErrorText(err);
      logger.error('server identity recovery failed', err, stack);
      await showMessageBox('EndlessNet', errorText!);
    } finally {
      busy = false;
      await _updateTray();
      notifyListeners();
    }
  }

  Future<void> _updateTray() async {
    if (!desktopIntegrationEnabled) {
      return;
    }
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
              if (showConnectThisDevice)
                MenuItem(key: 'connect-device', label: 'Connect this device'),
              if (canConnect) MenuItem(key: 'connect', label: 'Connect'),
              if (canDisconnect)
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
    if (!desktopIntegrationEnabled) {
      return;
    }
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> connectDevice() async {
    busy = true;
    errorText = null;
    notifyListeners();
    final request = _defaultEnrollmentRequest();
    try {
      final payload = await bridge.enroll(request);
      statusPayload = payload;
      if (isEnrollmentPending(payload)) {
        final connectionURL = enrollmentApprovalURL(payload);
        if (connectionURL.isEmpty) {
          throw StateError(
            'The service did not provide a device connection URL.',
          );
        }
        await _launchExternalURL(
          connectionURL,
          pageName: 'device connection page',
        );
        _startEnrollmentPolling();
        logger.info('device enrollment request created and opened');
      } else if (ServiceStatus(payload).deviceEnrolled) {
        _stopEnrollmentPolling();
        _reconcileConnectionPolling(payload);
        logger.info('device enrollment completed immediately');
      } else {
        throw StateError('The service did not start device enrollment.');
      }
    } catch (err, stack) {
      if (enrollmentElevationSupported && requiresAdministratorElevation(err)) {
        try {
          final launched = await elevatedEnrollmentLauncher(request);
          if (!launched) {
            throw StateError(
              'Administrator approval is required to connect this device.',
            );
          }
          _startEnrollmentPolling();
          logger.info('elevated device enrollment launched after owner denial');
          return;
        } catch (elevatedErr, elevatedStack) {
          errorText = safeErrorText(elevatedErr);
          logger.error(
            'elevated device enrollment failed',
            elevatedErr,
            elevatedStack,
          );
          await messagePresenter('EndlessNet', errorText!);
          return;
        }
      }
      errorText = safeErrorText(err);
      logger.error('device enrollment failed', err, stack);
      await messagePresenter('EndlessNet', errorText!);
    } finally {
      busy = false;
      await _updateTray();
      notifyListeners();
    }
  }

  Future<void> openAdminURL() async {
    await _openExternalURL(config.adminURL, pageName: 'admin console');
  }

  Future<void> _openExternalURL(
    String rawURL, {
    required String pageName,
  }) async {
    busy = true;
    errorText = null;
    notifyListeners();
    try {
      await _launchExternalURL(rawURL, pageName: pageName);
      logger.info('external URL opened page=$pageName');
    } catch (err, stack) {
      errorText = safeErrorText(err);
      logger.error('external URL launch failed page=$pageName', err, stack);
      await messagePresenter('EndlessNet', errorText!);
    } finally {
      busy = false;
      await _updateTray();
      notifyListeners();
    }
  }

  Future<void> _launchExternalURL(
    String rawURL, {
    required String pageName,
  }) async {
    final opened = await externalURLLauncher(Uri.parse(rawURL));
    if (!opened) {
      throw StateError(
        'Windows could not open the $pageName in your default browser.',
      );
    }
  }

  EnrollmentRequest _defaultEnrollmentRequest() {
    return EnrollmentRequest(
      token: '',
      server: config.server,
      mode: config.mode,
    );
  }

  void _startEnrollmentPolling() {
    _enrollmentPollingStartedAt ??= DateTime.now();
    _enrollmentPollTimer ??= Timer.periodic(
      enrollmentPollInterval,
      (_) => _pollEnrollment(),
    );
  }

  void _stopEnrollmentPolling() {
    _enrollmentPollTimer?.cancel();
    _enrollmentPollTimer = null;
    _enrollmentPollingStartedAt = null;
  }

  void _reconcileConnectionPolling(Map<String, dynamic> payload) {
    if (isConnectionSettling(payload)) {
      _startConnectionPolling();
    } else {
      _stopConnectionPolling();
    }
  }

  void _startConnectionPolling() {
    _connectionPollingStartedAt ??= DateTime.now();
    _connectionPollTimer ??= Timer.periodic(
      connectionPollInterval,
      (_) => _pollConnectionStatus(),
    );
  }

  void _stopConnectionPolling() {
    _connectionPollTimer?.cancel();
    _connectionPollTimer = null;
    _connectionPollingStartedAt = null;
  }

  Future<void> _pollConnectionStatus() async {
    if (_connectionPollInFlight || quitting || busy) {
      return;
    }
    final startedAt = _connectionPollingStartedAt;
    if (startedAt != null &&
        DateTime.now().difference(startedAt) >= connectionPollTimeout) {
      _stopConnectionPolling();
      logger.info('connection status polling stopped state=$state');
      return;
    }

    _connectionPollInFlight = true;
    try {
      final payload = await bridge.status();
      statusPayload = payload;
      errorText = null;
      _reconcileConnectionPolling(payload);
      logger.info('connection status refreshed state=$state');
    } catch (err, stack) {
      logger.error('connection status refresh failed', err, stack);
    } finally {
      _connectionPollInFlight = false;
      await _updateTray();
      notifyListeners();
    }
  }

  Future<void> _pollEnrollment() async {
    if (_enrollmentPollInFlight || quitting) {
      return;
    }
    final startedAt = _enrollmentPollingStartedAt;
    if (startedAt != null &&
        DateTime.now().difference(startedAt) >= enrollmentPollTimeout) {
      _stopEnrollmentPolling();
      errorText = 'Device connection timed out. Try Connect this device again.';
      logger.error(
        'device enrollment polling timed out',
        StateError(errorText!),
        StackTrace.current,
      );
      await _updateTray();
      notifyListeners();
      return;
    }

    _enrollmentPollInFlight = true;
    try {
      final payload = await bridge.status();
      statusPayload = payload;
      errorText = null;
      if (!isEnrollmentPending(payload)) {
        _stopEnrollmentPolling();
        if (ServiceStatus(payload).deviceEnrolled) {
          logger.info('device enrollment polling completed');
        } else {
          errorText = 'Device enrollment did not complete.';
        }
      }
      _reconcileConnectionPolling(payload);
    } catch (err, stack) {
      errorText = safeErrorText(err);
      logger.error('device enrollment polling failed', err, stack);
    } finally {
      _enrollmentPollInFlight = false;
      await _updateTray();
      notifyListeners();
    }
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
      await copyDiagnosticsPayload(payload);
      await showMessageBox('EndlessNet diagnostics', 'Diagnostics copied.');
    } catch (err, stack) {
      logger.error('copy diagnostics failed', err, stack);
      await showMessageBox('EndlessNet diagnostics', safeErrorText(err));
    }
  }

  Future<void> copyDiagnosticsPayload(Map<String, dynamic> payload) async {
    final text = const JsonEncoder.withIndent(
      '  ',
    ).convert(redactDiagnostics(payload));
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> showDiagnosticsDialog(BuildContext context) async {
    busy = true;
    errorText = null;
    notifyListeners();
    Map<String, dynamic>? payload;
    try {
      payload = await bridge.diagnostics();
      logger.info('diagnostics loaded');
    } catch (err, stack) {
      errorText = safeErrorText(err);
      logger.error('diagnostics failed', err, stack);
      await messagePresenter('EndlessNet diagnostics', errorText!);
    } finally {
      busy = false;
      notifyListeners();
    }
    if (payload == null || !context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => DiagnosticsDialog(
        payload: payload!,
        onCopy: () => copyDiagnosticsPayload(payload!),
      ),
    );
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
    _stopEnrollmentPolling();
    _stopConnectionPolling();
    await runAction(() => bridge.logout());
  }

  Future<void> exitApp() async {
    quitting = true;
    _refreshTimer?.cancel();
    _showSignalTimer?.cancel();
    _stopEnrollmentPolling();
    _stopConnectionPolling();
    if (!desktopIntegrationEnabled) {
      await logger.close();
      return;
    }
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
    final agent = controller.serviceStatus.agent;
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
                  Image.asset(
                    'assets/icons/endlessnet.png',
                    width: 36,
                    height: 36,
                  ),
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
                  if (controller.showConnectThisDevice)
                    FilledButton.icon(
                      onPressed: controller.busy
                          ? null
                          : controller.connectDevice,
                      icon: const Icon(Icons.link),
                      label: const Text('Connect this device'),
                    ),
                  if (controller.deviceEnrolled)
                    OutlinedButton.icon(
                      onPressed: controller.busy
                          ? null
                          : () => controller.connected
                                ? controller.runAction(
                                    () => controller.bridge.disconnect(),
                                  )
                                : controller.connect(context),
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
                    onPressed: controller.busy
                        ? null
                        : () => controller.showDiagnosticsDialog(context),
                    icon: const Icon(Icons.monitor_heart_outlined),
                    label: const Text('Diagnostics'),
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
                child: SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: InfoPanel(
                          title: 'This device',
                          children: [
                            InfoRow(
                              label: 'Hostname',
                              value: valueText(status?['hostname']),
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
                            InfoRow(label: 'Engine', value: 'WireGuard Go'),
                            InfoRow(
                              label: 'Paths',
                              value: selectedPathsLabel(agent),
                            ),
                            InfoRow(
                              label: 'Discovery',
                              value: discoveryHealthLabel(agent),
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

class DiagnosticsDialog extends StatelessWidget {
  const DiagnosticsDialog({
    super.key,
    required this.payload,
    required this.onCopy,
  });

  final Map<String, dynamic> payload;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    final diagnostics = ServiceDiagnostics(payload);
    final agent = diagnostics.agent;
    final paths = diagnostics.paths;
    final window = MediaQuery.sizeOf(context);
    final dialogWidth = (window.width - 96).clamp(320.0, 700.0).toDouble();
    final dialogHeight = (window.height - 180).clamp(240.0, 500.0).toDouble();
    return AlertDialog(
      title: const Text('Connectivity diagnostics'),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: ListView(
          children: [
            InfoPanel(
              title: 'Connectivity',
              children: [
                InfoRow(
                  label: 'Generated',
                  value: valueText(diagnostics.generatedAt),
                ),
                InfoRow(
                  label: 'State',
                  value: diagnostics.status.state(fallback: '-'),
                ),
                InfoRow(label: 'Paths', value: selectedPathsLabel(agent)),
                InfoRow(label: 'Discovery', value: discoveryHealthLabel(agent)),
              ],
            ),
            const SizedBox(height: 16),
            Text('Peer paths', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (paths.isEmpty)
              const Text('No peer path diagnostics are available.'),
            for (final path in paths) PeerPathDiagnosticsTile(path: path),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await onCopy();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Diagnostics copied.')),
              );
            }
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy redacted JSON'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class PeerPathDiagnosticsTile extends StatelessWidget {
  const PeerPathDiagnosticsTile({super.key, required this.path});

  final PeerPathStatus path;

  @override
  Widget build(BuildContext context) {
    final endpoint = path.selectedEndpoint.isEmpty
        ? ''
        : ' via ${path.selectedEndpoint}';
    final candidates = path.candidates.isEmpty
        ? <PathCandidateStatus>[path.direct]
        : path.candidates;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(valueText(path.displayName, fallback: 'Unknown peer')),
        subtitle: Text(
          'Selected: ${selectedPathLabel(path.selectedPath)}$endpoint',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (path.selectionReason.isNotEmpty)
            DiagnosticsLine(title: 'Selection', value: path.selectionReason),
          for (final candidate in candidates)
            DiagnosticsLine(
              title: candidateTitle(candidate),
              value: candidateHealthLabel(candidate),
            ),
          if (path.relay.hasData)
            DiagnosticsLine(
              title: 'Relay',
              value: candidateHealthLabel(path.relay),
            ),
        ],
      ),
    );
  }
}

class DiagnosticsLine extends StatelessWidget {
  const DiagnosticsLine({super.key, required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(color: Color(0xFF52647A))),
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

Future<bool> showServerIdentityChangeDialog(
  BuildContext context, {
  required String serverURL,
  required String trustedKeyID,
  required String announcedKeyID,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Server identity changed'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The signing identity for $serverURL differs from the identity previously trusted by this device.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Only continue if this server key change is expected.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                SelectableText('Previously trusted:\n$trustedKeyID'),
                const SizedBox(height: 8),
                SelectableText('Now announced:\n$announcedKeyID'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Trust and connect'),
            ),
          ],
        ),
      ) ??
      false;
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
  final agent = ServiceStatus(payload).agent;
  return [
    'State: ${valueText(payload?['state'])}',
    'Account: ${valueText(payload?['account_id'])}',
    'Network: ${networkLabel(payload)}',
    'Assigned IP: ${valueText(payload?['overlay_ip'])}',
    'Hostname: ${valueText(payload?['hostname'])}',
    'Map revision: ${valueText(payload?['map_revision'])}',
    'Peers: ${valueText(payload?['peer_count'])}',
    'Paths: ${selectedPathsLabel(agent)}',
    'Discovery: ${discoveryHealthLabel(agent)}',
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
  final logs = payload['logs'];
  if (logs is List && logs.isNotEmpty) {
    return logs
        .map((entry) {
          if (entry is! Map) {
            return '$entry';
          }
          return '${valueText(entry['timestamp'], fallback: '')} '
                  '${valueText(entry['message'], fallback: '')}'
              .trim();
        })
        .join('\n');
  }
  return 'No recent logs.';
}

String thisDeviceLabel(Map<String, dynamic>? payload) {
  if (payload == null) {
    return 'This device: loading...';
  }
  final host = valueText(payload['hostname'], fallback: 'this Windows device');
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
  return ServiceStatus(payload).peerPaths
      .take(20)
      .map((peer) {
        final name = valueText(peer.displayName, fallback: 'Unknown peer');
        return '$name - ${selectedPathLabel(peer.selectedPath)}';
      })
      .where((line) => line.trim().isNotEmpty)
      .toList();
}

String selectedPathsLabel(ServiceAgentStatus agent) {
  if (!agent.present) {
    return 'Waiting for agent state';
  }
  final labels = <String>[];
  for (final path in const ['direct', 'relay', 'none']) {
    final count = agent.selectedPathCounts[path] ?? 0;
    if (count > 0) {
      labels.add('$count ${selectedPathLabel(path).toLowerCase()}');
    }
  }
  final known = const {'direct', 'relay', 'none'};
  for (final entry in agent.selectedPathCounts.entries) {
    if (!known.contains(entry.key) && entry.value > 0) {
      labels.add('${entry.value} ${entry.key}');
    }
  }
  return labels.isEmpty ? 'No peer paths' : labels.join(' · ');
}

String discoveryHealthLabel(ServiceAgentStatus agent) {
  if (!agent.present) {
    return 'Waiting for agent state';
  }
  final stun = switch (agent.stunOK) {
    true => 'STUN reachable',
    false => 'STUN unavailable',
    null => 'STUN pending',
  };
  final relay = switch (agent.relayOK) {
    true => 'relay available',
    false => 'relay unavailable',
    null => 'relay pending',
  };
  return '$stun · $relay';
}

String selectedPathLabel(String path) {
  switch (path.trim().toLowerCase()) {
    case 'direct':
      return 'Direct';
    case 'relay':
      return 'Relay';
    case 'none':
    case '':
      return 'Offline';
    default:
      return path.trim();
  }
}

String candidateTitle(PathCandidateStatus candidate) {
  switch (candidate.tier.trim().toLowerCase()) {
    case 'lan_direct':
      return 'Local candidate';
    case 'public_direct':
      return 'Public candidate';
    case 'punched_udp':
      return 'Mapped candidate';
    case 'relay':
      return 'Relay';
  }
  return candidate.type.toLowerCase() == 'relay' ? 'Relay' : 'Direct candidate';
}

String candidateHealthLabel(PathCandidateStatus candidate) {
  final parts = <String>[candidateStateLabel(candidate.state)];
  if (candidate.endpoint.isNotEmpty) {
    parts.add(candidate.endpoint);
  }
  final rtt = candidate.rttMS;
  if (rtt != null && rtt > 0) {
    parts.add('${rtt.toStringAsFixed(rtt >= 10 ? 0 : 1)} ms');
  }
  if (candidate.consecutiveFailures > 0) {
    parts.add(
      '${candidate.consecutiveFailures} consecutive '
      '${candidate.consecutiveFailures == 1 ? 'failure' : 'failures'}',
    );
  }
  if (candidate.reason.isNotEmpty) {
    parts.add(candidate.reason);
  }
  return parts.where((part) => part.trim().isNotEmpty).join(' · ');
}

String candidateStateLabel(String state) {
  switch (state.trim().toLowerCase()) {
    case 'reachable':
      return 'Reachable';
    case 'untested':
      return 'Testing';
    case 'degraded':
      return 'Degraded';
    case 'failed':
      return 'Failed';
    case 'missing':
      return 'Unavailable';
    case '':
      return 'Unknown';
    default:
      return state.trim();
  }
}

bool isDeviceEnrolled(Map<String, dynamic>? payload) {
  return ServiceStatus(payload).deviceEnrolled;
}

bool isEnrollmentPending(Map<String, dynamic>? payload) {
  if (payload == null) {
    return false;
  }
  return valueText(payload['state'], fallback: '') ==
          ServiceState.needsApproval ||
      valueText(payload['control_state'], fallback: '') ==
          ControlState.pendingApproval;
}

bool isConnectionSettling(Map<String, dynamic>? payload) {
  if (payload == null) {
    return false;
  }
  final status = ServiceStatus(payload);
  return status.deviceEnrolled &&
      !status.connected &&
      !status.userDisconnected &&
      status.state(fallback: '') == ServiceState.degraded &&
      valueText(payload['desired_state'], fallback: '') ==
          ConnectionIntentState.connected;
}

String enrollmentApprovalURL(Map<String, dynamic>? payload) {
  return valueText(payload?['approval_url'], fallback: '');
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

Future<bool> launchExternalURL(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
