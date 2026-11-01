import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/client/correlation_journal.dart';
import 'package:endlessnet_client_ui/client/enrollment_client.dart';
import 'package:endlessnet_client_ui/client/windows_correlation_store.dart';

// Explicit native Windows fixture, excluded from declared baseline unit tests.
const profile = 'fixture-profile';
const origin = 'https://control.example';
const uuid = '00000000-0000-4000-8000-000000000001';
final until = DateTime.utc(2026, 10, 30, 12, 2, 0, 123, 456);
EnrollmentCorrelation correlation({DateTime? deadline}) =>
    EnrollmentCorrelation(
      profileId: profile,
      controlOrigin: origin,
      requestId: uuid,
      hostname: 'fixture-host',
      mode: api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION,
      recoveryDeadline: deadline,
    );
void require(bool condition) {
  if (!condition) throw StateError('Windows correlation fixture failed');
}

Future<void> child(String action, File file) async {
  if (action == 'locked') {
    try {
      final unexpected = await openWindowsCorrelationStore(
        file,
        maxBytes: 8192,
      );
      await unexpected.close();
      throw StateError('lock unexpectedly acquired');
    } on CorrelationStoreFailure {
      stdout.writeln('LOCKED');
      return;
    }
  }
  final store = await openWindowsCorrelationStore(file, maxBytes: 8192);
  if (action == 'write') {
    await store.save(correlation());
    stdout.writeln('WRITTEN');
    await stdout.flush();
    // Exit after acknowledged flush without graceful store.close(). OS releases lock.
    exit(0);
  }
  final saved = await store.read(profile, origin);
  require(saved?.requestId == uuid);
  if (action == 'update') {
    await store.save(correlation(deadline: until));
    stdout.writeln('UPDATED');
  } else {
    require(
      saved?.recoveryDeadline ==
          (action == 'read-short'
              ? until.subtract(const Duration(seconds: 30))
              : until),
    );
    stdout.writeln('READ');
  }
  await store.close();
}

Future<String> invoke(String action, File file) async {
  final packages = File('.dart_tool/package_config.json').absolute.uri
      .toString();
  final process = await Process.start(Platform.resolvedExecutable, [
    '--packages=$packages',
    Platform.script.toFilePath(),
    action,
    file.path,
  ], runInShell: false);
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  final timer = Timer(const Duration(seconds: 30), () {
    process.kill();
  });
  try {
    final code = await process.exitCode;
    final text = await output;
    final err = await errors;
    require(code == 0 && err.isEmpty);
    return text.trim();
  } finally {
    timer.cancel();
  }
}

Future<void> main(List<String> args) async {
  if (!Platform.isWindows) throw UnsupportedError('native Windows only');
  if (args.isNotEmpty) {
    await child(args[0], File(args[1]));
    return;
  }
  final temp = await Directory.systemTemp.resolveSymbolicLinks();
  final root = await Directory(temp).createTemp('endlessnet-ui-correlation-');
  final resolved = await root.resolveSymbolicLinks();
  require(
    resolved.startsWith('$temp${Platform.pathSeparator}') &&
        root.path == resolved &&
        root.uri.pathSegments
            .where((p) => p.isNotEmpty)
            .last
            .startsWith('endlessnet-ui-correlation-'),
  );
  try {
    final file = File('${root.path}${Platform.pathSeparator}correlation.bin');
    require(await invoke('write', file) == 'WRITTEN');
    final held = await openWindowsCorrelationStore(file, maxBytes: 8192);
    require(await invoke('locked', file) == 'LOCKED');
    await held.close();
    require(await invoke('update', file) == 'UPDATED');
    require(await invoke('read', file) == 'READ');
    final shortFile = File(
      '${root.path}${Platform.pathSeparator}shortened.bin',
    );
    final shortStore = await openWindowsCorrelationStore(
      shortFile,
      maxBytes: 8192,
    );
    await shortStore.save(correlation(deadline: until));
    await shortStore.save(
      correlation(deadline: until.subtract(const Duration(seconds: 30))),
    );
    try {
      await shortStore.save(correlation(deadline: until));
      throw StateError('shortened deadline extended');
    } on CorrelationStoreFailure catch (error) {
      require(error.problem == CorrelationStoreProblem.conflict);
    }
    await shortStore.close();
    require(await invoke('read-short', shortFile) == 'READ');
    final before = await file.readAsBytes();
    final reopened = await openWindowsCorrelationStore(file, maxBytes: 8192);
    try {
      await reopened.save(
        correlation(deadline: until.add(const Duration(seconds: 1))),
      );
      throw StateError('deadline extended');
    } on CorrelationStoreFailure catch (error) {
      require(error.problem == CorrelationStoreProblem.conflict);
    }
    await reopened.close();
    require(base64Encode(await file.readAsBytes()) == base64Encode(before));
    await file.writeAsBytes([0, 0], mode: FileMode.append, flush: true);
    final damaged = await file.readAsBytes();
    try {
      final unexpected = await openWindowsCorrelationStore(
        file,
        maxBytes: 8192,
      );
      await unexpected.close();
      throw StateError('partial frame accepted');
    } on CorrelationStoreFailure catch (error) {
      require(error.problem == CorrelationStoreProblem.corrupt);
    }
    require(base64Encode(await file.readAsBytes()) == base64Encode(damaged));
    final empty = File(
      '${root.path}${Platform.pathSeparator}existing-empty.bin',
    );
    await empty.writeAsBytes([], flush: true);
    try {
      final unexpected = await openWindowsCorrelationStore(
        empty,
        maxBytes: 8192,
      );
      await unexpected.close();
      throw StateError('existing empty file reset');
    } on CorrelationStoreFailure catch (error) {
      require(error.problem == CorrelationStoreProblem.corrupt);
    }
    stdout.writeln('WINDOWS_CORRELATION_RESTART_LOCK_FLUSH_CORRUPTION_PASS');
  } finally {
    // Recheck the exact temporary root before recursive fixture cleanup.
    require(
      await root.resolveSymbolicLinks() == resolved &&
          resolved.startsWith('$temp${Platform.pathSeparator}'),
    );
    await root.delete(recursive: true);
  }
}
