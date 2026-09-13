import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('endlessnet/ui-diagnostics-destination');

bool supportsClientBundleDestination(String operatingSystem) =>
    operatingSystem == 'windows' ||
    operatingSystem == 'linux' ||
    operatingSystem == 'macos';

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
  Future<void> Function()? release,
}) async {
  checkContext();
  final directory = await choose();
  try {
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
  } finally {
    if (directory != null) await release?.call();
  }
}

const _macChannel = MethodChannel('endlessnet/ui-diagnostics-macos');

/// A short-lived native grant, never a bookmark or persisted folder path.
Future<bool> exportClientBundleToMacDirectory({
  required String requestId,
  required Future<void> Function(String, Directory) save,
  required void Function() checkContext,
}) async {
  String? lease;
  Future<void> release() async {
    final id = lease;
    lease = null;
    if (id != null) {
      await _macChannel.invokeMethod<void>('releaseDirectory', id);
    }
  }

  return exportClientBundleToChosenDirectory(
    requestId: requestId,
    choose: () async {
      final response = await _macChannel.invokeMethod<Object?>(
        'chooseDirectory',
      );
      if (response == null) return null;
      if (response is! Map ||
          response['lease'] is! String ||
          (response['lease'] as String).isEmpty) {
        throw const FormatException('Invalid destination lease');
      }
      lease = response['lease'] as String;
      try {
        final path = response['path'];
        if (response.length != 2 ||
            path is! String ||
            path.isEmpty ||
            path.contains('\u0000') ||
            !Directory(path).isAbsolute) {
          throw const FormatException('Invalid diagnostics destination');
        }
        return Directory(path);
      } catch (_) {
        await release();
        rethrow;
      }
    },
    save: save,
    checkContext: checkContext,
    release: release,
  );
}
