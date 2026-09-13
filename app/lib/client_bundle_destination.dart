import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('endlessnet/ui-diagnostics-destination');

/// Native UI only: no bundle handle, credentials, or bytes cross this channel.
Future<Directory?> chooseClientBundleDirectory() async {
  final path = await _channel.invokeMethod<String>('chooseDirectory');
  if (path == null) return null;
  if (path.isEmpty || path.contains('\u0000') || !Directory(path).isAbsolute) {
    throw const FormatException('Invalid diagnostics destination');
  }
  return Directory(path);
}

/// Cancellation does not read a bundle or acknowledge an operation. The caller
/// binds checkContext to the original caller/profile/session across both awaits.
Future<bool> exportClientBundleToChosenDirectory({
  required String requestId,
  required Future<Directory?> Function() choose,
  required Future<void> Function(String, Directory) save,
  required void Function() checkContext,
}) async {
  checkContext();
  final directory = await choose();
  checkContext();
  if (directory == null) return false;
  if (!directory.isAbsolute) {
    throw const FormatException(
      'An absolute diagnostics destination is required',
    );
  }
  await save(requestId, directory);
  checkContext();
  return true;
}
