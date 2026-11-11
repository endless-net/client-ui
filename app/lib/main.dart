import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/windows_runtime_platform.dart';

import 'dart:io';

import 'update/windows_installer.dart';

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MainApp(
      platform: WindowsUiRuntimePlatform(arguments),
      openUpdates: Platform.isWindows ? openWindowsUpdates : null,
    ),
  );
}
