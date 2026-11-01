import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'launch_config.dart';
import '../client/windows_pipe_config.dart';

Future<UiLaunchConfig> readWindowsLaunchConfig(
  String path,
  String libraryPath,
) async {
  final bytes = await readWindowsAdminFile(path, libraryPath);
  return UiLaunchConfig.decode(bytes, nativeLibraryPath: libraryPath);
}

// Exposed separately for native reader acceptance; production parses the result
// through UiLaunchConfig. No raw Win32 error/path/bytes enter diagnostics.
Future<Uint8List> readWindowsAdminFile(String path, String libraryPath) async {
  if (!Platform.isWindows || Abi.current() != Abi.windowsX64) {
    throw const UiConfigurationFailure(
      UiConfigurationProblem.unsupportedPlatform,
    );
  }
  if (path.contains('\u0000') || !isWindowsPipeLibraryPath(libraryPath)) {
    throw const UiConfigurationFailure(UiConfigurationProblem.invalid);
  }
  try {
    return await Isolate.run(() => _read(path, libraryPath));
  } on UiConfigurationFailure {
    rethrow;
  } catch (_) {
    throw const UiConfigurationFailure(
      UiConfigurationProblem.componentUnavailable,
    );
  }
}

Uint8List _read(String path, String libraryPath) {
  final library = DynamicLibrary.open(libraryPath);
  final read = library
      .lookupFunction<
        Int32 Function(
          Pointer<Utf16>,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<Uint32>,
        ),
        int Function(
          Pointer<Utf16>,
          Pointer<Uint8>,
          int,
          Pointer<Uint32>,
          Pointer<Uint32>,
        )
      >('en_ui_read_admin_config');
  final name = path.toNativeUtf16(allocator: calloc);
  final buffer = calloc<Uint8>(65536);
  final length = calloc<Uint32>();
  final error = calloc<Uint32>();
  try {
    if (read(name, buffer, 65536, length, error) == 0 || length.value > 65536) {
      throw UiConfigurationFailure(switch (error.value) {
        2 || 3 => UiConfigurationProblem.missing,
        32 || 33 => UiConfigurationProblem.busy,
        _ => UiConfigurationProblem.untrusted,
      });
    }
    return Uint8List.fromList(buffer.asTypedList(length.value));
  } finally {
    calloc.free(name);
    calloc.free(buffer);
    calloc.free(length);
    calloc.free(error);
  }
}
