import 'dart:io';
import 'dart:isolate';

import 'client_privileged_recovery.dart';
import 'windows_elevation.dart';

const installedWindowsRecoveryHelper =
    r'C:\Program Files\EndlessNet\endlessnet-client-recovery-helper.exe';

/// Native v0 launcher. No executable, endpoint or shell can be supplied by a
/// request. Use ClientSession.submitPrivilegedViaLookup to verify the outcome.
Future<ClientElevationOutcome> launchClientWindowsRecovery(
  ClientPrivilegedRecovery request,
) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('Windows recovery adapter is unavailable');
  }
  if (!await File(installedWindowsRecoveryHelper).exists()) {
    throw StateError('Installed recovery helper is unavailable');
  }
  final arguments = request.arguments;
  final result = await Isolate.run(
    () => launchWindowsProcessElevatedAndWait(
      installedWindowsRecoveryHelper,
      arguments,
    ),
  );
  return switch (result) {
    PrivilegedHelperResult.completed => ClientElevationOutcome.exited,
    PrivilegedHelperResult.canceled => ClientElevationOutcome.canceled,
    PrivilegedHelperResult.failed => ClientElevationOutcome.unconfirmed,
  };
}
