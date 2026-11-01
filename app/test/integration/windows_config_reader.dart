import 'dart:io';

import 'package:endlessnet_client_ui/app/launch_config.dart';
import 'package:endlessnet_client_ui/app/windows_config_reader.dart';

void require(bool condition) {
  if (!condition) throw StateError('Windows config reader fixture failed');
}

Future<void> main(List<String> args) async {
  if (!Platform.isWindows || args.length != 1) {
    throw UnsupportedError('native Windows, explicit helper DLL required');
  }
  final library = args.single;
  // Read-only existing OS file whose actual owner/DACL is checked by the native
  // reader. Never print/copy its bytes into logs or the repository.
  final systemFile = File('${Platform.environment['SystemRoot']}\\win.ini');
  final bytes = await readWindowsAdminFile(systemFile.path, library);
  final expected = await systemFile.readAsBytes();
  require(bytes.length == expected.length);
  for (var i = 0; i < bytes.length; i++) {
    require(bytes[i] == expected[i]);
  }
  final temp = await Directory.systemTemp.resolveSymbolicLinks();
  final root = await Directory(temp).createTemp('endlessnet-ui-config-');
  final resolved = await root.resolveSymbolicLinks();
  require(
    resolved == root.path &&
        resolved.startsWith('$temp${Platform.pathSeparator}'),
  );
  try {
    final writable = File('${root.path}${Platform.pathSeparator}config.json');
    await writable.writeAsString('{"schema":1}', flush: true);
    for (final path in [
      writable.path,
      r'\\localhost\share\config.json',
      '${root.path}${Platform.pathSeparator}..${Platform.pathSeparator}config.json',
    ]) {
      var rejected = false;
      try {
        await readWindowsAdminFile(path, library);
      } on UiConfigurationFailure {
        rejected = true;
      }
      require(rejected);
    }
    try {
      await readWindowsAdminFile(
        '${root.path}${Platform.pathSeparator}missing.json',
        library,
      );
      throw StateError('missing config accepted');
    } on UiConfigurationFailure catch (error) {
      require(error.problem == UiConfigurationProblem.missing);
    }
    final writer = await writable.open(mode: FileMode.append);
    try {
      try {
        await readWindowsAdminFile(writable.path, library);
        throw StateError('concurrent writer accepted');
      } on UiConfigurationFailure catch (error) {
        require(error.problem == UiConfigurationProblem.busy);
      }
    } finally {
      await writer.close();
    }
    final junction = '${Platform.environment['SystemDrive']}\\Users\\All Users';
    require(
      await FileSystemEntity.type(junction, followLinks: false) ==
          FileSystemEntityType.link,
    );
    try {
      await readWindowsAdminFile('$junction\\unused-ui-config.json', library);
      throw StateError('junction traversal accepted');
    } on UiConfigurationFailure catch (error) {
      require(error.problem == UiConfigurationProblem.untrusted);
    }
    require(await writable.readAsString() == '{"schema":1}');
    stdout.writeln('WINDOWS_CONFIG_AUTHORITY_READ_NO_WRITE_PASS');
  } finally {
    require(
      await root.resolveSymbolicLinks() == resolved &&
          resolved.startsWith('$temp${Platform.pathSeparator}'),
    );
    await root.delete(recursive: true);
  }
}
