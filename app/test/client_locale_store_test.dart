@Tags(['short'])
library;

import 'dart:io';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_locale_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late ClientLocaleStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('en-language-test-');
    store = ClientLocaleStore(directory);
  });
  tearDown(() => directory.delete(recursive: true));
  test('missing preference does not create storage', () async {
    expect(await store.read(), isNull);
    expect(await directory.list().toList(), isEmpty);
  });
  test(
    'each locale survives a new store and replaces the previous choice',
    () async {
      for (final locale in [
        ClientLocale.ru,
        ClientLocale.en,
        ClientLocale.ru,
      ]) {
        await store.write(locale);
        expect(await ClientLocaleStore(directory).read(), locale);
        final entries = await directory.list().toList();
        expect(entries.length, 1);
        expect(await File(entries.single.path).readAsString(), locale.name);
      }
    },
  );
  test('queued writes and read retain last explicit choice', () async {
    final writes = [
      store.write(ClientLocale.ru),
      store.write(ClientLocale.en),
      store.write(ClientLocale.ru),
    ];
    final reading = store.read();
    await Future.wait(writes);
    expect(await reading, ClientLocale.ru);
  });
  test(
    'malformed and oversized settings fail without silent overwrite',
    () async {
      final file = File.fromUri(directory.uri.resolve('language'));
      for (final text in [
        '',
        'de',
        'RU',
        'en\n',
        'ru-private-data',
        'x' * 10000,
      ]) {
        await file.writeAsString(text);
        await expectLater(store.read(), throwsFormatException);
        expect(await file.readAsString(), text);
      }
      // An explicit new choice can repair a malformed UI preference.
      await store.write(ClientLocale.en);
      expect(await store.read(), ClientLocale.en);
    },
  );
  test('non-file target is preserved and failed queue can recover', () async {
    final target = Directory.fromUri(directory.uri.resolve('language'));
    await target.create();
    await expectLater(store.read(), throwsFormatException);
    await expectLater(store.write(ClientLocale.en), throwsFormatException);
    expect(await target.exists(), isTrue);
    await target.delete();
    await store.write(ClientLocale.ru);
    expect(await store.read(), ClientLocale.ru);
  });
  test('relative preference location rejected', () {
    expect(() => ClientLocaleStore(Directory('relative')), throwsArgumentError);
  });
}
