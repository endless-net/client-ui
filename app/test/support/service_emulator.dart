import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Starts an isolated service emulator for a component or end-to-end test.
///
/// Each instance owns a unique named pipe, temporary scenario, ready signal,
/// and redacted request journal, so test workers do not share mutable state.
class ServiceEmulatorProcess {
  ServiceEmulatorProcess._({
    required this.process,
    required this.directory,
    required this.pipe,
    required this.requestsFile,
    required this.output,
    required this.stdoutDone,
    required this.stderrDone,
  });

  final Process process;
  final Directory directory;
  final String pipe;
  final File requestsFile;
  final StringBuffer output;
  final Future<void> stdoutDone;
  final Future<void> stderrDone;

  static Future<ServiceEmulatorProcess> start(
    String executable, {
    Map<String, dynamic>? scenario,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'endlessnet-service-emulator-',
    );
    final suffix = '${pid}_${DateTime.now().microsecondsSinceEpoch}';
    final pipe = r'\\.\pipe\endlessnet-service-emulator-' + suffix;
    final readyFile = File(
      '${directory.path}${Platform.pathSeparator}ready.json',
    );
    final requestsFile = File(
      '${directory.path}${Platform.pathSeparator}requests.jsonl',
    );
    final arguments = <String>[
      '--pipe',
      pipe,
      '--ready-file',
      readyFile.path,
      '--requests-file',
      requestsFile.path,
    ];
    if (scenario != null) {
      final scenarioFile = File(
        '${directory.path}${Platform.pathSeparator}scenario.json',
      );
      await scenarioFile.writeAsString(jsonEncode(scenario), flush: true);
      arguments.addAll(['--scenario', scenarioFile.path]);
    }

    final process = await Process.start(executable, arguments);
    final output = StringBuffer();
    final stdoutDone = process.stdout
        .transform(utf8.decoder)
        .listen(output.write)
        .asFuture<void>();
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .listen(output.write)
        .asFuture<void>();
    int? exitCode;
    unawaited(process.exitCode.then((value) => exitCode = value));

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!await readyFile.exists()) {
      if (exitCode != null) {
        await Future.wait([stdoutDone, stderrDone]);
        await directory.delete(recursive: true);
        throw StateError(
          'service emulator exited with $exitCode before readiness:\n$output',
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        process.kill();
        await process.exitCode;
        await Future.wait([stdoutDone, stderrDone]);
        await directory.delete(recursive: true);
        throw TimeoutException(
          'service emulator readiness timed out:\n$output',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }

    return ServiceEmulatorProcess._(
      process: process,
      directory: directory,
      pipe: pipe,
      requestsFile: requestsFile,
      output: output,
      stdoutDone: stdoutDone,
      stderrDone: stderrDone,
    );
  }

  Future<List<Map<String, dynamic>>> interactions() async {
    final contents = await requestsFile.readAsLines();
    return contents
        .where((line) => line.trim().isNotEmpty)
        .map(
          (line) => (jsonDecode(line) as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        )
        .toList();
  }

  Future<void> stop() async {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    await Future.wait([stdoutDone, stderrDone]);
    for (var attempt = 0; attempt < 20 && await directory.exists(); attempt++) {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        if (attempt == 19) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }
}
