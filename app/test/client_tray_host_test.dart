@Tags(['short'])
library;

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:endlessnet/client_tray.dart';
import 'package:endlessnet/client_tray_host.dart';
import 'package:flutter_test/flutter_test.dart';

class _BoundsHost implements ClientTrayHost {
  _BoundsHost(this.available, {this.fail = false});

  final bool available;
  final bool fail;

  @override
  bool hasFiniteBounds() {
    if (fail) throw StateError('unavailable');
    return available;
  }

  @override
  Future<void> destroy() async {}
  @override
  Future<void> openContextMenu() async {}
  @override
  Future<void> setIcon(
    String asset, {
    required void Function() onPrimaryClick,
    required void Function() onSecondaryClick,
  }) async {}
  @override
  Future<void> setMenu(
    ClientTrayMenu menu,
    void Function(String?) onActivate,
  ) async {}
  @override
  Future<void> setTooltip(String tooltip) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('endlessnet/ui-tray-host');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
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
          expect(
            await readClientTrayHostAvailability(
              platform,
              host: platform == 'windows' ? _BoundsHost(true) : null,
            ),
            value == true,
          );
        }
      },
    );
    test('missing or failed $platform host is not an available tray', () async {
      expect(await readClientTrayHostAvailability(platform), isFalse);
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'private bus details');
      });
      expect(
        await readClientTrayHostAvailability(
          platform,
          host: platform == 'windows' ? _BoundsHost(true) : null,
        ),
        isFalse,
      );
    });
  }
  test('Windows tray availability checks the plugin-owned icon bounds', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => true);
    expect(
      await readClientTrayHostAvailability(
        'windows',
        host: _BoundsHost(true),
      ),
      isTrue,
    );
    expect(
      await readClientTrayHostAvailability(
        'windows',
        host: _BoundsHost(false),
      ),
      isFalse,
    );
    expect(
      await readClientTrayHostAvailability(
        'windows',
        host: _BoundsHost(false, fail: true),
      ),
      isFalse,
    );
  });
  test('macOS uses live tray bounds availability', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw StateError('unexpected'),
    );
    expect(
      await readClientTrayHostAvailability('macos', host: _BoundsHost(true)),
      isTrue,
    );
    expect(
      await readClientTrayHostAvailability('macos', host: _BoundsHost(false)),
      isFalse,
    );
    expect(await readClientTrayHostAvailability('android'), isFalse);
  });
  test('missing or failed macOS status item query is unavailable', () async {
    expect(await readClientTrayHostAvailability('macos'), isFalse);
    expect(
      await readClientTrayHostAvailability(
        'macos',
        host: _BoundsHost(false, fail: true),
      ),
      isFalse,
    );
  });
  for (final platform in ['windows', 'macos', 'linux']) {
    test('$platform installs menu using only supported methods', () async {
      final calls = <String>[];
      final menu = ClientTrayMenu(
        items: [ClientTrayMenuItem(label: 'Runtime status', disabled: true)],
      );
      await updateClientTrayMenu(
        platform: platform,
        tooltip: 'EndlessNet',
        menu: () => menu,
        isCurrent: () => true,
        setTooltip: (_) async {
          calls.add('tooltip');
        },
        setMenu: (value) async {
          expect(identical(value, menu), isTrue);
          calls.add('menu');
        },
      );
      expect(calls, ['tooltip', 'menu']);
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
      var currentMenu = ClientTrayMenu(
        items: [ClientTrayMenuItem(key: 'old', label: 'Old')],
      );
      ClientTrayMenu? sent;
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
      currentMenu = ClientTrayMenu(
        items: [ClientTrayMenuItem(key: 'new', label: 'New')],
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
        menu: () => ClientTrayMenu(items: []),
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
