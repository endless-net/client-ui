import 'package:flutter/services.dart';
import 'client_autostart_setting.dart';

const _channel = MethodChannel('endlessnet/ui-autostart');

Future<ClientAutostartSetting> _invoke(String method, [bool? enabled]) async {
  try {
    return switch (await _channel.invokeMethod<String>(method, enabled)) {
      'notConfigured' => ClientAutostartSetting.notConfigured,
      'registered' => ClientAutostartSetting.registered,
      'enabled' => ClientAutostartSetting.enabled,
      'disabled' => ClientAutostartSetting.disabled,
      'requiresApproval' => ClientAutostartSetting.requiresApproval,
      'unsupported' => ClientAutostartSetting.unsupported,
      _ => throw const FormatException('Invalid autostart response'),
    };
  } on MissingPluginException {
    return ClientAutostartSetting.unsupported;
  }
}

Future<ClientAutostartSetting> readNativeClientAutostart() => _invoke('read');
Future<ClientAutostartSetting> writeNativeClientAutostart(bool enabled) =>
    _invoke('setEnabled', enabled);

/// Dispatch is not evidence of approval or of a changed registration state.
Future<bool> openNativeClientAutostartSettings() async =>
    await _channel.invokeMethod<bool>('openSettings') == true;
