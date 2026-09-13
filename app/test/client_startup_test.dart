import 'dart:io';
import 'package:endlessnet/main.dart';
import 'package:endlessnet/windows_elevation.dart';
import 'package:endlessnet_local_client_rpc/local_client_rpc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reported UI build matches the executable version text', () {
    final build = desktopBuildIdentity();
    expect(build.isFrozen, isTrue);
    expect(versionText(), contains('endlessnet ${build.version}\n'));
    expect(versionText(), contains('commit: ${build.commit}\n'));
    expect(versionText(), contains('built: ${build.buildDate}\n'));
  });
  test(
    'desktop startup uses validated native endpoint and hides on autostart',
    () {
      final config = AppConfig.parse([]);
      expect(config.endpoint, validateLocalEndpoint(null));
      expect(config.showWindow, false);
      expect(config.debug, false);
      expect(AppConfig.parse(['--show-window', '--version']).showVersion, true);
      expect(AppConfig.parse(['--show-window']).showWindow, true);
    },
  );
  test('explicit local endpoint is preserved without TCP fallback', () {
    final endpoint = Platform.isWindows
        ? r'\\.\pipe\native-test'
        : '/tmp/native-test.sock';
    for (final flag in ['--endpoint', '--ipc-pipe']) {
      expect(AppConfig.parse([flag, endpoint]).endpoint, endpoint);
      expect(
        () => AppConfig.parse([flag, 'https://example.test']),
        throwsArgumentError,
      );
      expect(() => AppConfig.parse([flag]), throwsFormatException);
    }
  });
  test(
    'retired and unknown startup inputs fail without echoing enrollment data',
    () {
      for (final args in [
        ['--enroll', 'synthetic-private-value'],
        ['--elevated-enroll'],
        ['--server', 'synthetic-private-value'],
        ['--mode', 'workstation'],
        ['endlessnet://enroll?enroll_token=synthetic-private-value'],
        ['--unknown'],
      ]) {
        expect(
          () => AppConfig.parse(args),
          throwsA(
            isA<FormatException>().having(
              (error) => error.toString(),
              'safe error',
              isNot(contains('synthetic-private-value')),
            ),
          ),
        );
      }
    },
  );
  test('startup logging redacts secret tokens and deep links', () {
    expect(
      redactArgs([
        '--token',
        'synthetic-private-value',
        'endlessnet://enroll?x=y',
      ]),
      ['--token', '[redacted]', '[redacted-deeplink]'],
    );
    final text = redactText(
      'Bearer abc.def enr_example token=synthetic-private-value',
    );
    expect(text, isNot(contains('synthetic-private-value')));
    expect(text, isNot(contains('abc.def')));
    expect(text, isNot(contains('enr_example')));
  });
  test('platform-neutral user paths resolve the native log directory', () {
    expect(resolveUserPath('~/.endlessnet/logs'), contains('.endlessnet/logs'));
    expect(
      AppConfig.parse(['--debug', '--debug-log-dir', 'logs']).debugLogDir,
      'logs',
    );
    expect(
      () => AppConfig.parse(['--debug-log-dir', '--show-window']),
      throwsFormatException,
    );
  });
  test('Windows argument quoting remains isolated from startup and IPC', () {
    expect(quoteWindowsCommandLineArgument('plain'), 'plain');
    expect(
      quoteWindowsCommandLineArgument(
        r'C:\Program Files\EndlessNet\helper.exe',
      ),
      r'"C:\Program Files\EndlessNet\helper.exe"',
    );
  });
}
