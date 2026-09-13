@Tags(['short'])
library;

import 'dart:async';
import 'dart:io';
import 'package:endlessnet/client_bundle_destination.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('endlessnet/ui-diagnostics-destination');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('only implemented desktop destination hosts are enabled', () {
    for (final os in [
      'windows',
      'linux',
      'macos',
      'android',
      'ios',
      'fuchsia',
      'unknown',
    ]) {
      expect(
        supportsClientBundleDestination(os),
        os == 'windows' || os == 'linux' || os == 'macos',
      );
    }
  });

  test(
    'missing host implementation and non-string result are not cancellation',
    () async {
      await expectLater(
        chooseClientBundleDirectory(),
        throwsA(isA<MissingPluginException>()),
      );
      messenger.setMockMethodCallHandler(channel, (_) async => 7);
      await expectLater(
        chooseClientBundleDirectory(),
        throwsA(isA<TypeError>()),
      );
    },
  );

  test('native chooser sends no operation or bundle payload', () async {
    final path = Directory.current.path;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'chooseDirectory');
      expect(call.arguments, isNull);
      return path;
    });
    expect((await chooseClientBundleDirectory())!.path, path);
  });
  test('native cancellation is distinct from failure', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await chooseClientBundleDirectory(), isNull);
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'destination_unavailable');
    });
    await expectLater(
      chooseClientBundleDirectory(),
      throwsA(isA<PlatformException>()),
    );
  });
  for (final path in ['', 'relative/path', 'bad\u0000path']) {
    test('invalid native destination is rejected (${path.length})', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => path);
      await expectLater(chooseClientBundleDirectory(), throwsFormatException);
    });
  }
  test('chooser cancellation does not read or write a bundle', () async {
    final calls = <String>[];
    expect(
      await exportClientBundleToChosenDirectory(
        requestId: 'request-a',
        choose: () async {
          calls.add('choose');
          return null;
        },
        save: (_, _) async {
          calls.add('save');
        },
        checkContext: () {
          calls.add('check');
        },
      ),
      isFalse,
    );
    expect(calls, ['check', 'choose', 'check']);
  });
  test(
    'explicit selection preserves request ID and checks across save',
    () async {
      final directory = Directory.current;
      final calls = <String>[];
      expect(
        await exportClientBundleToChosenDirectory(
          requestId: 'original-request',
          choose: () async {
            calls.add('choose');
            return directory;
          },
          save: (id, path) async {
            expect(id, 'original-request');
            expect(path.path, directory.path);
            calls.add('save');
          },
          checkContext: () {
            calls.add('check');
          },
        ),
        isTrue,
      );
      expect(calls, ['check', 'choose', 'check', 'save', 'check']);
    },
  );
  for (final boundary in ['before chooser', 'after chooser', 'after save']) {
    test(
      'context change $boundary does not report success or replay',
      () async {
        var checks = 0;
        var picks = 0;
        var saves = 0;
        final stop =
            [
              'before chooser',
              'after chooser',
              'after save',
            ].indexOf(boundary) +
            1;
        await expectLater(
          exportClientBundleToChosenDirectory(
            requestId: 'request-a',
            choose: () async {
              picks++;
              return Directory.current;
            },
            save: (_, _) async {
              saves++;
            },
            checkContext: () {
              if (++checks == stop) throw StateError('Changed');
            },
          ),
          throwsStateError,
        );
        expect(picks, stop == 1 ? 0 : 1);
        expect(saves, stop == 3 ? 1 : 0);
      },
    );
  }
  test('context invalidation while chooser is pending prevents save', () async {
    final chosen = Completer<Directory?>();
    var valid = true;
    final action = exportClientBundleToChosenDirectory(
      requestId: 'request-a',
      choose: () => chosen.future,
      save: (_, _) async => fail('Stale selection must not save'),
      checkContext: () {
        if (!valid) throw StateError('Changed');
      },
    );
    valid = false;
    chosen.complete(Directory.current);
    await expectLater(action, throwsStateError);
  });
  test('save failure propagates without retry', () async {
    var saves = 0;
    await expectLater(
      exportClientBundleToChosenDirectory(
        requestId: 'request-a',
        choose: () async => Directory.current,
        save: (_, _) async {
          saves++;
          throw StateError('Save failed');
        },
        checkContext: () {},
      ),
      throwsStateError,
    );
    expect(saves, 1);
  });
}
