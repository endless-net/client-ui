import 'dart:ffi';
import 'dart:io';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/client/enrollment_client.dart';
import 'package:endlessnet_client_ui/client/windows_correlation_store.dart';
import 'package:endlessnet_client_ui/client/correlation_journal.dart';
import 'package:endlessnet_client_ui/app/windows_user_services.dart';
import 'package:ffi/ffi.dart';

void require(bool value) {
  if (!value) throw StateError('private user state fixture failed');
}

Future<void> main(List<String> args) async {
  if (!Platform.isWindows || args.length != 1) {
    throw UnsupportedError('explicit native fixture DLL required');
  }
  final library = DynamicLibrary.open(args.single);
  var productionRejectedFixture = false;
  try {
    await WindowsUserStateDirectory.open(args.single);
  } on CorrelationStoreFailure {
    productionRejectedFixture = true;
  }
  require(productionRejectedFixture);
  // Invalid targets return before ShellExecuteEx; this fixture never launches
  // the user's browser or contacts an identity provider.
  final launch = library
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Uint32>),
        int Function(Pointer<Utf16>, Pointer<Uint32>)
      >('en_ui_open_browser');
  for (final invalid in [
    'http://control.example/login',
    'https://control.example/\nlogin',
  ]) {
    final uri = invalid.toNativeUtf16(allocator: calloc);
    final code = calloc<Uint32>();
    try {
      require(launch(uri, code) == 0);
    } finally {
      calloc.free(uri);
      calloc.free(code);
    }
  }
  final open = library
      .lookupFunction<
        Int32 Function(
          Pointer<Utf16>,
          Pointer<Utf16>,
          Uint32,
          Pointer<Pointer<Void>>,
          Pointer<Int32>,
          Pointer<Uint32>,
        ),
        int Function(
          Pointer<Utf16>,
          Pointer<Utf16>,
          int,
          Pointer<Pointer<Void>>,
          Pointer<Int32>,
          Pointer<Uint32>,
        )
      >('en_ui_open_private_state_fixture');
  final close = library
      .lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('en_ui_close_private_state');
  final temp = await Directory.systemTemp.resolveSymbolicLinks();
  final root = await Directory(temp).createTemp('endlessnet-ui-user-state-');
  final resolved = await root.resolveSymbolicLinks();
  require(
    resolved == root.path &&
        resolved.startsWith('$temp${Platform.pathSeparator}'),
  );
  final name = root.path.toNativeUtf16(allocator: calloc);
  final path = calloc<Uint16>(32768).cast<Utf16>();
  final guard = calloc<Pointer<Void>>();
  final error = calloc<Uint32>();
  final created = calloc<Int32>();
  try {
    require(
      open(name, path, 32768, guard, created, error) != 0 && created.value != 0,
    );
    final statePath = path.toDartString();
    require(
      statePath.startsWith('${root.path}${Platform.pathSeparator}') &&
          statePath.endsWith('correlation.bin'),
    );
    var store = await openWindowsCorrelationStore(
      File(statePath),
      maxBytes: 8192,
      initializeCreatedEmpty: created.value != 0,
    );
    const requestId = '00000000-0000-4000-8000-000000000001';
    await store.save(
      const EnrollmentCorrelation(
        profileId: 'profile',
        controlOrigin: 'https://control.example',
        requestId: requestId,
        hostname: 'fixture',
        mode: api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION,
      ),
    );
    await store.close();
    // The native namespace guard outlives the journal handle and prevents a
    // rename/replacement until session cleanup releases it.
    var fileRenameBlocked = false;
    try {
      await File(statePath).rename('$statePath.moved');
    } on FileSystemException {
      fileRenameBlocked = true;
    }
    require(fileRenameBlocked);
    final parent = File(statePath).parent;
    var directoryRenameBlocked = false;
    try {
      await parent.rename('${parent.path}.moved');
    } on FileSystemException {
      directoryRenameBlocked = true;
    }
    require(directoryRenameBlocked);
    close(guard.value);
    guard.value = nullptr;
    require(
      open(name, path, 32768, guard, created, error) != 0 && created.value == 0,
    );
    store = await openWindowsCorrelationStore(File(statePath), maxBytes: 8192);
    require(
      (await store.read('profile', 'https://control.example'))!.requestId ==
          requestId,
    );
    await store.close();
    close(guard.value);
    guard.value = nullptr;
    // Widen only the fixture file ACL. Reopen must fail instead of silently
    // repairing it. No user LocalAppData or Client service files are touched.
    final changed = await Process.run(
      '${Platform.environment['SystemRoot']}\\System32\\icacls.exe',
      [statePath, '/grant', '*S-1-1-0:(R)'],
      runInShell: false,
    );
    require(changed.exitCode == 0);
    require(
      open(name, path, 32768, guard, created, error) == 0 &&
          guard.value == nullptr,
    );
    stdout.writeln('WINDOWS_PRIVATE_STATE_DACL_REOPEN_REJECT_WIDENING_PASS');
  } finally {
    if (guard.value != nullptr) close(guard.value);
    calloc.free(name);
    calloc.free(path);
    calloc.free(guard);
    calloc.free(error);
    calloc.free(created);
    require(
      await root.resolveSymbolicLinks() == resolved &&
          resolved.startsWith('$temp${Platform.pathSeparator}'),
    );
    await root.delete(recursive: true);
  }
}
