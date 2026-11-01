import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/windows_runtime_platform.dart';

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MainApp(platform: WindowsUiRuntimePlatform(arguments)));
}
