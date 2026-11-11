import 'dart:io';
import 'dart:typed_data';

import 'package:endlessnet_client_ui/app/launch_config.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) throw ArgumentError('Expected UI policy path');
  UiLaunchConfig.decode(
    Uint8List.fromList(File(arguments.single).readAsBytesSync()),
    nativeLibraryPath: r'C:\validation\endlessnet_windows_pipe.dll',
    runtimeInstance: '11111111-1111-4111-8111-111111111111',
  );
}
