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
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
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
  test('macOS uses plugin readiness without a watcher query', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw StateError('unexpected'),
    );
    expect(await readClientTrayHostAvailability('macos'), isTrue);
    expect(await readClientTrayHostAvailability('android'), isFalse);
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
