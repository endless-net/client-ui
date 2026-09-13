@Tags(['short'])
library;

import 'dart:io';
import 'package:endlessnet/client_linux_autostart.dart';
import 'package:endlessnet/client_autostart_setting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Exec quoting escapes both desktop string and command layers', () {
    expect(
      clientAutostartExec('/opt/Endless Net/client'),
      '"/opt/Endless Net/client"',
    );
    expect(
      clientAutostartExec(r'/opt/$name`"\%f'),
      r'"/opt/\\$name\\`\\"\\\\%%f"',
    );
    for (final path in ['relative', '/a=b', '/a\nb', '/a\u0000b']) {
      expect(() => clientAutostartExec(path), throwsFormatException);
    }
  });
  test('XDG directory selection requires absolute paths', () {
    expect(
      clientLinuxAutostartDirectory({
        'XDG_CONFIG_HOME': '/config',
        'HOME': '/home/a',
      }).path,
      '/config/autostart',
    );
    expect(
      clientLinuxAutostartDirectory({'HOME': '/home/a'}).path,
      '/home/a/.config/autostart',
    );
    for (final env in [
      <String, String>{},
      {'HOME': 'relative'},
      {'XDG_CONFIG_HOME': 'relative', 'HOME': '/home/a'},
    ]) {
      expect(() => clientLinuxAutostartDirectory(env), throwsFormatException);
    }
  });
  for (final scenario in ['round trip', 'ordered', 'foreign', 'directory']) {
    test('own autostart file: $scenario', () async {
      final directory = await Directory.systemTemp.createTemp('en-autostart-');
      try {
        final store = ClientLinuxAutostart(
          directory,
          '/opt/Endless Net/endlessnet',
        );
        final file = File.fromUri(
          directory.uri.resolve('endlessnet.app.desktop'),
        );
        if (scenario == 'foreign') {
          await file.writeAsString('[Desktop Entry]\nExec=/other\n');
          await expectLater(store.setEnabled(true), throwsFormatException);
          expect(await file.readAsString(), '[Desktop Entry]\nExec=/other\n');
        } else if (scenario == 'directory') {
          await Directory(file.path).create();
          await expectLater(store.setEnabled(false), throwsFormatException);
          expect(await Directory(file.path).exists(), isTrue);
        } else {
          expect(await store.read(), ClientAutostartSetting.notConfigured);
          if (scenario == 'ordered') {
            final first = store.setEnabled(true);
            final second = store.setEnabled(false);
            expect(await first, ClientAutostartSetting.enabled);
            expect(await second, ClientAutostartSetting.disabled);
          } else {
            expect(
              await store.setEnabled(true),
              ClientAutostartSetting.enabled,
            );
            expect(
              await ClientLinuxAutostart(
                directory,
                '/opt/Endless Net/endlessnet',
              ).read(),
              ClientAutostartSetting.enabled,
            );
            expect(
              await store.setEnabled(false),
              ClientAutostartSetting.disabled,
            );
          }
          final content = await file.readAsString();
          expect(content, contains('Hidden=true\n'));
          expect(content, contains('Exec="/opt/Endless Net/endlessnet"\n'));
          expect(content, isNot(contains('--connect')));
          expect(await directory.list().length, 1);
        }
      } finally {
        await directory.delete(recursive: true);
      }
    });
  }
}
