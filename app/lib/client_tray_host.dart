import 'package:tray_manager/tray_manager.dart';
import 'package:flutter/services.dart';

Future<bool> readClientTrayHostAvailability(String platform) async {
  if (platform == 'macos') return true;
  if (platform != 'linux' && platform != 'windows') return false;
  try {
    return await const MethodChannel(
          'endlessnet/ui-tray-host',
        ).invokeMethod<Object?>('isAvailable') ==
        true;
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

/// tray_manager 0.5.3 Linux supports setContextMenu, but not setToolTip.
/// The menu supplier reads current keys after asynchronous tooltip delivery.
Future<void> updateClientTrayMenu({
  required String platform,
  required String tooltip,
  required Menu Function() menu,
  required bool Function() isCurrent,
  Future<void> Function(String)? setTooltip,
  Future<void> Function(Menu)? setMenu,
}) async {
  final tooltipSupported = _usesExplicitPopup(platform);
  if (!isCurrent()) return;
  if (tooltipSupported) {
    await (setTooltip ?? trayManager.setToolTip)(tooltip);
  }
  if (!isCurrent()) return;
  await (setMenu ?? trayManager.setContextMenu)(menu());
}

/// Linux's AppIndicator opens its installed menu itself, without this method.
Future<void> popUpClientTrayMenu({
  required String platform,
  required bool Function() isCurrent,
  Future<void> Function()? popup,
}) async {
  if (!_usesExplicitPopup(platform) || !isCurrent()) return;
  await (popup ?? trayManager.popUpContextMenu)();
}
