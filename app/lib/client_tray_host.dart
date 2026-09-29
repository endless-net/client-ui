import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';

import 'client_tray.dart';

abstract interface class ClientTrayHost {
  Future<void> setIcon(
    String asset, {
    required void Function() onPrimaryClick,
    required void Function() onSecondaryClick,
  });
  Future<void> setTooltip(String tooltip);
  Future<void> setMenu(ClientTrayMenu menu, void Function(String?) onActivate);
  Future<void> openContextMenu();
  bool hasFiniteBounds();
  Future<void> destroy();
}

class NativeClientTrayHost implements ClientTrayHost {
  TrayIcon? _icon;
  Menu? _menu;
  List<MenuItem> _items = [];

  TrayIcon get _registeredIcon =>
      _icon ?? (throw StateError('Tray icon is not registered'));

  @override
  Future<void> setIcon(
    String asset, {
    required void Function() onPrimaryClick,
    required void Function() onSecondaryClick,
  }) async {
    final icon = TrayIcon.create();
    if (icon == null) throw StateError('Tray icon creation failed');
    try {
      icon.icon = ImageAsset.fromAsset(asset);
      icon.setContextMenuTrigger(ContextMenuTrigger.none);
      icon.addListener((event) {
        if (event is TrayIconClickedEvent) onPrimaryClick();
        if (event is TrayIconRightClickedEvent) onSecondaryClick();
      });
      if (!icon.setVisible(true)) {
        throw StateError('Tray icon is unavailable');
      }
      _icon = icon;
    } catch (_) {
      icon.dispose();
      rethrow;
    }
  }

  @override
  Future<void> setTooltip(String tooltip) async {
    _registeredIcon.setTooltip(tooltip);
  }

  @override
  Future<void> setMenu(
    ClientTrayMenu projection,
    void Function(String?) onActivate,
  ) async {
    final menu = Menu.create();
    if (menu == null) throw StateError('Tray menu creation failed');
    final items = <MenuItem>[];
    try {
      for (final entry in projection.items) {
        final item = MenuItem.createWithLabelAndType(
          entry.label,
          MenuItemType.normal,
        );
        if (item == null) throw StateError('Tray menu item creation failed');
        item.isEnabled = !entry.disabled;
        final key = entry.key;
        if (key != null) {
          item.addListener((event) {
            if (event is MenuItemClickedEvent) onActivate(key);
          });
        }
        menu.addItem(item);
        items.add(item);
      }
      _registeredIcon.setContextMenu(menu);
    } catch (_) {
      for (final item in items) {
        item.dispose();
      }
      menu.dispose();
      rethrow;
    }
    final previousMenu = _menu;
    final previousItems = _items;
    _menu = menu;
    _items = items;
    previousMenu?.dispose();
    for (final item in previousItems) {
      item.dispose();
    }
  }

  @override
  Future<void> openContextMenu() async {
    if (!_registeredIcon.openContextMenu()) {
      throw StateError('Tray menu could not open');
    }
  }

  @override
  bool hasFiniteBounds() {
    final bounds = _icon?.getBounds();
    return bounds != null &&
        bounds.left.isFinite &&
        bounds.top.isFinite &&
        bounds.width.isFinite &&
        bounds.height.isFinite &&
        bounds.width > 0 &&
        bounds.height > 0;
  }

  @override
  Future<void> destroy() async {
    final icon = _icon;
    _icon = null;
    icon?.dispose();
    _menu?.dispose();
    _menu = null;
    for (final item in _items) {
      item.dispose();
    }
    _items = [];
  }
}

Future<bool> readClientTrayHostAvailability(
  String platform, {
  ClientTrayHost? host,
}) async {
  if (platform == 'macos') {
    try {
      return host?.hasFiniteBounds() ?? false;
    } catch (_) {
      return false;
    }
  }
  if (platform != 'linux' && platform != 'windows') return false;
  try {
    final shellAvailable = await const MethodChannel(
          'endlessnet/ui-tray-host',
        ).invokeMethod<Object?>('isAvailable') ==
        true;
    if (!shellAvailable) return false;
    if (platform == 'windows') return host?.hasFiniteBounds() ?? false;
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> prepareClientTrayRegistration(String platform) async {
  if (platform == 'linux' || platform == 'macos') return true;
  if (platform != 'windows') return false;
  try {
    return await const MethodChannel(
          'endlessnet/ui-tray-host',
        ).invokeMethod<Object?>('prepareRegistration') ==
        true;
  } catch (_) {
    return false;
  }
}

bool _usesExplicitPopup(String platform) => switch (platform) {
  'windows' || 'macos' => true,
  'linux' => false,
  _ => throw UnsupportedError('Unsupported desktop tray host'),
};

/// Read the current projection only after the tooltip call has completed.
Future<void> updateClientTrayMenu({
  required String platform,
  required String tooltip,
  required ClientTrayMenu Function() menu,
  required bool Function() isCurrent,
  ClientTrayHost? host,
  void Function(String?)? onActivate,
  Future<void> Function(String)? setTooltip,
  Future<void> Function(ClientTrayMenu)? setMenu,
}) async {
  _usesExplicitPopup(platform);
  if (!isCurrent()) return;
  await (setTooltip ?? host!.setTooltip)(tooltip);
  if (!isCurrent()) return;
  await (setMenu ?? (value) => host!.setMenu(value, onActivate!))(menu());
}

/// Linux's StatusNotifierItem panel opens its installed menu itself.
Future<void> popUpClientTrayMenu({
  required String platform,
  required bool Function() isCurrent,
  ClientTrayHost? host,
  Future<void> Function()? popup,
}) async {
  if (!_usesExplicitPopup(platform) || !isCurrent()) return;
  await (popup ?? host!.openContextMenu)();
}
