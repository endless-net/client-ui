import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import 'client_desktop_app.dart';
import 'client_build_target.dart';
import 'client_intent_journal.dart';
import 'client_locale.dart';
import 'client_locale_store.dart';
import 'client_notification_store.dart';
import 'client_session.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_local_client_rpc/local_client_rpc.dart';

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
const _appTarget = String.fromEnvironment('ENDLESSNET_TARGET');
const _defaultDebugLogDir = '~/.endlessnet/logs';
const _showSignalPath = '~/.endlessnet/endlessnet.show';

RandomAccessFile? _instanceLock;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  late final AppConfig config;
  try {
    config = AppConfig.parse(args);
  } catch (_) {
    stderr.writeln(
      'Invalid desktop startup arguments. Use native panels for enrollment.',
    );
    exit(64);
  }
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
  final endpoint = config.endpoint;
  final session = ClientSession(
    endpoint: endpoint,
    journal: ClientIntentJournal(clientJournalDirectory(endpoint)),
  );
  ClientLocaleStore? localeStore;
  var locale = ClientLocale.en;
  var localeReadFailed = false;
  try {
    localeStore = ClientLocaleStore(clientLocaleDirectory());
    locale = await localeStore.read() ?? ClientLocale.en;
  } catch (_) {
    localeReadFailed = true;
  }
  ClientNotificationStore? notificationStore;
  var notifications = false;
  var notificationReadFailed = false;
  try {
    notificationStore = ClientNotificationStore(clientLocaleDirectory());
    notifications = await notificationStore.read() ?? false;
  } catch (_) {
    notificationReadFailed = true;
  }
  runApp(
    ClientDesktopApp(
      initialLocale: locale,
      initialNotifications: notifications,
      notificationReadFailed: notificationReadFailed,
      saveNotifications: (value) async {
        final store = notificationStore;
        if (store == null) {
          throw StateError('UI notification storage unavailable');
        }
        await store.write(value);
      },
      localeReadFailed: localeReadFailed,
      saveLocale: (value) async {
        final store = localeStore;
        if (store == null) throw StateError('UI language storage unavailable');
        await store.write(value);
      },
      session: session,
      uiBuild: desktopBuildIdentity(),
      showWindow: config.showWindow,
      showSignal: showSignalWriteTime,
      onExit: () async {
        await logger.close();
        await _instanceLock?.close();
        _instanceLock = null;
      },
    ),
  );
}

String _resolvedBuildTarget({String? buildTarget, Abi? processAbi}) {
  final configuredTarget = buildTarget ?? _appTarget;
  return configuredTarget.isEmpty
      ? nativeClientBuildTarget(processAbi ?? Abi.current())
      : configuredTarget;
}

String versionText({String? buildTarget, Abi? processAbi}) {
  return 'endlessnet $_appVersion\n'
      'commit: $_appCommit\n'
      'built: $_appBuildDate\n'
      'target: ${_resolvedBuildTarget(buildTarget: buildTarget, processAbi: processAbi)}\n';
}

api.BuildIdentity desktopBuildIdentity({String? buildTarget, Abi? processAbi}) {
  final target = _resolvedBuildTarget(
    buildTarget: buildTarget,
    processAbi: processAbi,
  ).split('/');
  return api.BuildIdentity(
    version: _appVersion,
    commit: _appCommit,
    buildDate: _appBuildDate,
    platform: switch (target.first) {
      'windows' => api.Platform.PLATFORM_WINDOWS,
      'linux' => api.Platform.PLATFORM_LINUX,
      'darwin' || 'macos' => api.Platform.PLATFORM_MACOS,
      'android' => api.Platform.PLATFORM_ANDROID,
      'ios' => api.Platform.PLATFORM_IOS,
      _ => api.Platform.PLATFORM_UNSPECIFIED,
    },
    architecture: target.length == 2 ? target.last : '',
  )..freeze();
}

class AppConfig {
  AppConfig({
    required this.endpoint,
    required this.showWindow,
    required this.debug,
    required this.debugLogDir,
    required this.showVersion,
    required this.safeArgs,
  });
  final String endpoint;
  final bool showWindow;
  final bool debug;
  final String debugLogDir;
  final bool showVersion;
  final List<String> safeArgs;

  static AppConfig parse(List<String> args) {
    String? endpoint;
    var showWindow = false;
    var debug = false;
    var debugLogDir = _defaultDebugLogDir;
    var showVersion = false;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String value() {
        if (i + 1 >= args.length ||
            args[i + 1].trim().isEmpty ||
            args[i + 1].startsWith('--')) {
          throw const FormatException('A nonempty option value is required');
        }
        return args[++i];
      }

      switch (arg) {
        case '--endpoint':
        case '--ipc-pipe':
          endpoint = value();
        case '--show-window':
          showWindow = true;
        case '--debug':
          debug = true;
        case '--debug-log-dir':
          debugLogDir = value();
        case '--version':
        case 'version':
          showVersion = true;
        default:
          throw const FormatException('Unsupported desktop startup option');
      }
    }
    return AppConfig(
      endpoint: validateLocalEndpoint(endpoint),
      showWindow: showWindow,
      debug: debug,
      debugLogDir: debugLogDir,
      showVersion: showVersion,
      safeArgs: List.unmodifiable(redactArgs(args)),
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
    _write('ERROR', '$message: operation failed');
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
  if (!Platform.isWindows) return;
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

Future<DateTime?> showSignalWriteTime() async {
  try {
    final file = File(resolveUserPath(_showSignalPath));
    if (!await file.exists()) {
      return null;
    }
    return await file.lastModified();
  } catch (_) {
    return null;
  }
}
