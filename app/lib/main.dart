import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/windows_runtime_platform.dart';

import 'dart:io';

import 'update/windows_installer.dart';

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = WindowsUiRuntimePlatform(arguments);
  runApp(
    MainApp(
      platform: platform,
      openUpdates: Platform.isWindows ? openWindowsUpdates : null,
      openRecoveryLog: Platform.isWindows ? platform.openRecoveryLog : null,
    ),
  );
}
