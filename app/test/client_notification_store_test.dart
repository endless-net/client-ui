@Tags(['short'])
library;

import 'dart:io';
import 'package:endlessnet/client_notification_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late ClientNotificationStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('en-notification-store-');
    store = ClientNotificationStore(directory);
  });
  tearDown(() => directory.delete(recursive: true));
  test('missing and persisted true/false across store recreation', () async {
    expect(await store.read(), isNull);
    for (final value in [true, false]) {
      await store.write(value);
      expect(await ClientNotificationStore(directory).read(), value);
    }
    expect(await directory.list().length, 1);
  });
  test('ordered writes and reads preserve last explicit choice', () async {
    final first = store.write(true);
    final second = store.write(false);
    final read = store.read();
    await Future.wait([first, second]);
    expect(await read, isFalse);
  });
  test(
    'malformed and oversized contents rejected without implicit repair',
    () async {
      final file = File.fromUri(directory.uri.resolve('notifications'));
      for (final content in ['', 'true', '1\n', '0' * 100000]) {
        await file.writeAsString(content);
        await expectLater(store.read(), throwsFormatException);
        expect(await file.readAsString(), content);
      }
      await store.write(false);
      expect(await store.read(), isFalse);
    },
  );
  test(
    'non-file preserved and failed operation does not poison queue',
    () async {
      final target = Directory.fromUri(directory.uri.resolve('notifications'));
      await target.create();
      await expectLater(store.read(), throwsFormatException);
      await expectLater(store.write(true), throwsFormatException);
      expect(await target.exists(), isTrue);
      await target.delete();
      await store.write(true);
      expect(await store.read(), isTrue);
      expect(
        () => ClientNotificationStore(Directory('relative')),
        throwsArgumentError,
      );
    },
  );
}
