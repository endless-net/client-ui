import 'dart:io';

import '../client/windows_correlation_store.dart';
import '../client/windows_pipe.dart';
import 'launch_config.dart';
import 'session.dart';
import 'windows_config_reader.dart';
import 'windows_user_services.dart';

final class WindowsUiRuntimePlatform implements UiRuntimePlatform {
  WindowsUiRuntimePlatform(List<String> arguments)
    : _arguments = List.unmodifiable(arguments),
      _libraryPath = File(Platform.resolvedExecutable).parent.uri
          .resolve('endlessnet_windows_pipe.dll')
          .toFilePath();
  final List<String> _arguments;
  final String _libraryPath;

  @override
  Future<UiLaunchConfig> readConfig() async {
    if (!Platform.isWindows) {
      throw const UiConfigurationFailure(
        UiConfigurationProblem.unsupportedPlatform,
      );
    }
    if (_arguments.length != 2 ||
        _arguments.first != '--config' ||
        _arguments.last.isEmpty) {
      throw const UiConfigurationFailure();
    }
    return readWindowsLaunchConfig(_arguments.last, _libraryPath);
  }

  @override
  Future<UiClientConnection> connect(UiLaunchConfig config) async {
    final connection = await connectWindowsEnrollment(
      config: config.pipe,
      expectedContractSha256: config.contractSha256,
      maxFailureBytes: config.failureMaxBytes,
    );
    return UiClientConnection(connection.client, connection.close);
  }

  @override
  Future<UiCorrelationStorage> openStorage(UiLaunchConfig config) async {
    final directory = await WindowsUserStateDirectory.open(_libraryPath);
    try {
      final journal = await openWindowsCorrelationStore(
        directory.file,
        maxBytes: config.journalMaxBytes,
        initializeCreatedEmpty: directory.createdEmpty,
      );
      return UiCorrelationStorage(journal, () async {
        try {
          await journal.close();
        } finally {
          directory.close();
        }
      });
    } catch (_) {
      directory.close();
      rethrow;
    }
  }

  @override
  Future<bool> openBrowser(Uri url) => openWindowsBrowser(url, _libraryPath);
}
