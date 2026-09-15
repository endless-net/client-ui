@Tags(['short'])
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:endlessnet/client_theme_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late ClientThemeStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('en-theme-test-');
    store = ClientThemeStore(directory);
  });
  tearDown(() => directory.delete(recursive: true));
  test('missing preference does not create storage', () async {
    expect(await store.read(), isNull);
    expect(await directory.list().toList(), isEmpty);
  });
  test(
    'each theme survives a new store and replaces the previous choice',
    () async {
      for (final theme in [
        ThemeMode.dark,
        ThemeMode.light,
        ThemeMode.system,
        ThemeMode.dark,
      ]) {
        await store.write(theme);
        expect(await ClientThemeStore(directory).read(), theme);
        final entries = await directory.list().toList();
        expect(entries.length, 1);
        expect(await File(entries.single.path).readAsString(), theme.name);
      }
    },
  );
  test('queued writes and read retain last explicit choice', () async {
    final writes = [
      store.write(ThemeMode.dark),
      store.write(ThemeMode.light),
      store.write(ThemeMode.dark),
    ];
    final reading = store.read();
    await Future.wait(writes);
    expect(await reading, ThemeMode.dark);
  });
  test(
    'malformed and oversized settings fail without silent overwrite',
    () async {
      final file = File.fromUri(directory.uri.resolve('theme'));
      for (final text in [
        '',
        'blue',
        'DARK',
        'light\n',
        'system-private-data',
        'x' * 10000,
      ]) {
        await file.writeAsString(text);
        await expectLater(store.read(), throwsFormatException);
        expect(await file.readAsString(), text);
      }
      // An explicit new choice can repair a malformed UI preference.
      await store.write(ThemeMode.light);
      expect(await store.read(), ThemeMode.light);
    },
  );
  test('non-file target is preserved and failed queue can recover', () async {
    final target = Directory.fromUri(directory.uri.resolve('theme'));
    await target.create();
    await expectLater(store.read(), throwsFormatException);
    await expectLater(store.write(ThemeMode.light), throwsFormatException);
    expect(await target.exists(), isTrue);
    await target.delete();
    await store.write(ThemeMode.dark);
    expect(await store.read(), ThemeMode.dark);
  });
  test('relative preference location rejected', () {
    expect(() => ClientThemeStore(Directory('relative')), throwsArgumentError);
  });
}
