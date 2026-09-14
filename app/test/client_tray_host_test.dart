@Tags(['short'])
library;

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:endlessnet/client_tray_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('endlessnet/ui-tray-host');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const trayChannel = MethodChannel('tray_manager');
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(trayChannel, null);
  });
  test(
    'Windows registration preparation requires native true with no arguments',
    () async {
      for (final value in [true, false, null, 'true']) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'prepareRegistration');
          expect(call.arguments, isNull);
          return value;
        });
        expect(await prepareClientTrayRegistration('windows'), value == true);
      }
      messenger.setMockMethodCallHandler(channel, null);
      expect(await prepareClientTrayRegistration('windows'), isFalse);
      expect(await prepareClientTrayRegistration('linux'), isTrue);
      expect(await prepareClientTrayRegistration('macos'), isTrue);
      expect(await prepareClientTrayRegistration('android'), isFalse);
    },
  );
  for (final platform in ['linux', 'windows']) {
    test(
      '$platform tray availability requires an explicit native true',
      () async {
        for (final value in [true, false, null, 'true', 1]) {
          messenger.setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'isAvailable');
            expect(call.arguments, isNull);
            return value;
          });
          expect(await readClientTrayHostAvailability(platform), value == true);
        }
      },
    );
    test('missing or failed $platform host is not an available tray', () async {
      expect(await readClientTrayHostAvailability(platform), isFalse);
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'private bus details');
      });
      expect(await readClientTrayHostAvailability(platform), isFalse);
    });
  }
  test('macOS requires live finite nonempty status item bounds', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw StateError('unexpected'),
    );
    for (final size in [24.0, 0.0, -1.0, double.nan, double.infinity]) {
      messenger.setMockMethodCallHandler(trayChannel, (call) async {
        expect(call.method, 'getBounds');
        return {'x': -100.0, 'y': -200.0, 'width': size, 'height': 24.0};
      });
      expect(await readClientTrayHostAvailability('macos'), size == 24.0);
    }
    for (final value in [
      null,
      'invalid',
      <String, Object?>{},
      {'x': double.nan, 'y': 0.0, 'width': 24.0, 'height': 24.0},
      {'x': 0.0, 'y': double.infinity, 'width': 24.0, 'height': 24.0},
      {'x': 0.0, 'y': 0.0, 'width': 24.0, 'height': 0.0},
    ]) {
      messenger.setMockMethodCallHandler(trayChannel, (_) async => value);
      expect(await readClientTrayHostAvailability('macos'), isFalse);
    }
    expect(await readClientTrayHostAvailability('android'), isFalse);
  });
  test('missing or failed macOS status item query is unavailable', () async {
    expect(await readClientTrayHostAvailability('macos'), isFalse);
    messenger.setMockMethodCallHandler(trayChannel, (_) async {
      throw PlatformException(code: 'private native detail');
    });
    expect(await readClientTrayHostAvailability('macos'), isFalse);
  });
  for (final platform in ['windows', 'macos', 'linux']) {
    test('$platform installs menu using only supported methods', () async {
      final calls = <String>[];
      final menu = Menu(
        items: [MenuItem(label: 'Runtime status', disabled: true)],
      );
      await updateClientTrayMenu(
        platform: platform,
        tooltip: 'EndlessNet',
        menu: () => menu,
        isCurrent: () => true,
        setTooltip: (_) async {
          if (platform == 'linux') throw StateError('Unsupported Linux method');
          calls.add('tooltip');
        },
        setMenu: (value) async {
          expect(identical(value, menu), isTrue);
          calls.add('menu');
        },
      );
      expect(calls, [if (platform != 'linux') 'tooltip', 'menu']);
    });
    test('$platform uses only supported popup method', () async {
      var calls = 0;
      await popUpClientTrayMenu(
        platform: platform,
        isCurrent: () => true,
        popup: () async {
          calls++;
        },
      );
      expect(calls, platform == 'linux' ? 0 : 1);
    });
  }
  test('inactive host cannot update menu or open popup', () async {
    for (final platform in ['windows', 'macos', 'linux']) {
      await updateClientTrayMenu(
        platform: platform,
        tooltip: '',
        menu: () => throw StateError('Stale menu'),
        isCurrent: () => false,
        setTooltip: (_) async => throw StateError('Stale tooltip'),
        setMenu: (_) async => throw StateError('Stale menu write'),
      );
      await popUpClientTrayMenu(
        platform: platform,
        isCurrent: () => false,
        popup: () async => throw StateError('Stale popup'),
      );
    }
  });
  test('host disposal while tooltip is pending prevents menu update', () async {
    final pending = Completer<void>();
    var current = true;
    final result = updateClientTrayMenu(
      platform: 'windows',
      tooltip: '',
      menu: () => throw StateError('Stale menu'),
      isCurrent: () => current,
      setTooltip: (_) => pending.future,
      setMenu: (_) async => throw StateError('Stale write'),
    );
    current = false;
    pending.complete();
    await result;
  });
  test(
    'menu keys are obtained after asynchronous tooltip, not before',
    () async {
      final pending = Completer<void>();
      var currentMenu = Menu(
        items: [MenuItem(key: 'old', label: 'Old')],
      );
      Menu? sent;
      final result = updateClientTrayMenu(
        platform: 'macos',
        tooltip: '',
        menu: () => currentMenu,
        isCurrent: () => true,
        setTooltip: (_) => pending.future,
        setMenu: (value) async {
          sent = value;
        },
      );
      currentMenu = Menu(
        items: [MenuItem(key: 'new', label: 'New')],
      );
      pending.complete();
      await result;
      expect(identical(sent, currentMenu), isTrue);
    },
  );
  test('unknown platform is rejected rather than treated as Linux', () async {
    await expectLater(
      updateClientTrayMenu(
        platform: 'android',
        tooltip: '',
        menu: () => Menu(),
        isCurrent: () => true,
      ),
      throwsUnsupportedError,
    );
    await expectLater(
      popUpClientTrayMenu(platform: 'android', isCurrent: () => true),
      throwsUnsupportedError,
    );
  });
}
