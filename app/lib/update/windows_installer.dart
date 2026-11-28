import 'dart:io';

import 'controller.dart';
import 'releases.dart';

Future<UpdateController> openWindowsUpdates() async {
  if (!Platform.isWindows) throw const UpdateFailure();
  final script =
      '${File(Platform.resolvedExecutable).parent.path}\\install-update.ps1';
  final powershell =
      '${Platform.environment['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
  const prefix = ['-NoLogo', '-NoProfile', '-NonInteractive', '-File'];
  Future<ReleaseVersion> installedVersion() async {
    final info = await Process.run(powershell, [
      ...prefix,
      script,
      '-Mode',
      'Info',
    ]).timeout(const Duration(seconds: 30));
    if (info.exitCode != 0) throw const UpdateFailure();
    return ReleaseVersion((info.stdout as String).trim());
  }

  final version = await installedVersion();
  return UpdateController(version, GitHubReleases(), (release) async {
    final result = await Process.run(powershell, [
      ...prefix,
      script,
      '-Mode',
      'Request',
      '-Version',
      release.version.text,
    ]);
    return result.exitCode;
  }, installedVersion: installedVersion);
}
