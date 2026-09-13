@Tags(['short'])
library;

import 'dart:io';
import 'package:endlessnet/client_bundle_destination.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('endlessnet/ui-diagnostics-macos');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  for (final scenario in [
    'success',
    'cancel',
    'stale',
    'save failure',
    'invalid path',
    'release failure',
  ]) {
    test('macOS grant released exactly once: $scenario', () async {
      final calls = <String>[];
      var checks = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'chooseDirectory') {
          expect(call.arguments, isNull);
          return scenario == 'cancel'
              ? null
              : {
                  'lease': 'opaque-grant',
                  'path': scenario == 'invalid path'
                      ? 'relative'
                      : Directory.current.path,
                };
        }
        expect(call.method, 'releaseDirectory');
        expect(call.arguments, 'opaque-grant');
        if (scenario == 'release failure') {
          throw PlatformException(code: 'unavailable');
        }
        return null;
      });
      final operation = exportClientBundleToMacDirectory(
        requestId: 'request-a',
        save: (request, directory) async {
          expect(request, 'request-a');
          expect(directory.path, Directory.current.path);
          calls.add('save');
          if (scenario == 'save failure') throw StateError('save failed');
        },
        checkContext: () {
          if (++checks == 2 && scenario == 'stale') {
            throw StateError('context changed');
          }
        },
      );
      if (scenario == 'success' || scenario == 'cancel') {
        expect(await operation, scenario == 'success');
      } else {
        await expectLater(
          operation,
          scenario == 'invalid path'
              ? throwsFormatException
              : scenario == 'release failure'
              ? throwsA(isA<PlatformException>())
              : throwsStateError,
        );
      }
      expect(calls, [
        'chooseDirectory',
        if (['success', 'save failure', 'release failure'].contains(scenario))
          'save',
        if (scenario != 'cancel') 'releaseDirectory',
      ]);
    });
  }
  test('invalid context before choice never opens panel', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('Must not open'),
    );
    await expectLater(
      exportClientBundleToMacDirectory(
        requestId: 'a',
        save: (_, _) async => fail('Must not save'),
        checkContext: () => throw StateError('stale'),
      ),
      throwsStateError,
    );
  });
}
