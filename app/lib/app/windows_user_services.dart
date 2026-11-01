import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../client/correlation_journal.dart';
import '../client/windows_pipe_config.dart';

final class WindowsUserStateDirectory {
  WindowsUserStateDirectory._(
    this.file,
    this.createdEmpty,
    this._library,
    this._guard,
  );
  final File file;
  final bool createdEmpty;
  final DynamicLibrary _library;
  Pointer<Void> _guard;

  static Future<WindowsUserStateDirectory> open(String libraryPath) async {
    if (!Platform.isWindows ||
        Abi.current() != Abi.windowsX64 ||
        !isWindowsPipeLibraryPath(libraryPath)) {
      throw const CorrelationStoreFailure(CorrelationStoreProblem.inaccessible);
    }
    try {
      final library = DynamicLibrary.open(libraryPath);
      if (library.providesSymbol('en_ui_open_private_state_fixture')) {
        throw const CorrelationStoreFailure(
          CorrelationStoreProblem.inaccessible,
        );
      }
      final (path, address, created) = await Isolate.run(
        () => _openState(libraryPath),
      );
      return WindowsUserStateDirectory._(
        File(path),
        created,
        library,
        Pointer.fromAddress(address),
      );
    } catch (_) {
      throw const CorrelationStoreFailure(CorrelationStoreProblem.inaccessible);
    }
  }

  void close() {
    if (_guard == nullptr) return;
    final close = _library
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('en_ui_close_private_state');
    close(_guard);
    _guard = nullptr;
  }
}

(String, int, bool) _openState(String libraryPath) {
  final library = DynamicLibrary.open(libraryPath);
  final open = library
      .lookupFunction<
        Int32 Function(
          Pointer<Utf16>,
          Uint32,
          Pointer<Pointer<Void>>,
          Pointer<Int32>,
          Pointer<Uint32>,
        ),
        int Function(
          Pointer<Utf16>,
          int,
          Pointer<Pointer<Void>>,
          Pointer<Int32>,
          Pointer<Uint32>,
        )
      >('en_ui_open_private_state');
  final path = calloc<Uint16>(32768).cast<Utf16>();
  final guard = calloc<Pointer<Void>>();
  final error = calloc<Uint32>();
  final created = calloc<Int32>();
  try {
    if (open(path, 32768, guard, created, error) == 0 ||
        guard.value == nullptr) {
      throw const CorrelationStoreFailure(CorrelationStoreProblem.inaccessible);
    }
    try {
      return (path.toDartString(), guard.value.address, created.value != 0);
    } catch (_) {
      library.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)
      >('en_ui_close_private_state')(guard.value);
      rethrow;
    }
  } finally {
    calloc.free(path);
    calloc.free(guard);
    calloc.free(error);
    calloc.free(created);
  }
}

// Called only by the enrollment view's explicit current validated URL action.
Future<bool> openWindowsBrowser(Uri url, String libraryPath) async {
  if (!Platform.isWindows ||
      Abi.current() != Abi.windowsX64 ||
      !isWindowsPipeLibraryPath(libraryPath) ||
      url.scheme != 'https' ||
      url.host.isEmpty ||
      url.userInfo.isNotEmpty ||
      url.hasQuery ||
      url.hasFragment ||
      url.toString().length > 8192) {
    return false;
  }
  try {
    final text = url.toString();
    return await Isolate.run(() {
      final library = DynamicLibrary.open(libraryPath);
      final open = library
          .lookupFunction<
            Int32 Function(Pointer<Utf16>, Pointer<Uint32>),
            int Function(Pointer<Utf16>, Pointer<Uint32>)
          >('en_ui_open_browser');
      final uri = text.toNativeUtf16(allocator: calloc);
      final error = calloc<Uint32>();
      try {
        return open(uri, error) != 0;
      } finally {
        calloc.free(uri);
        calloc.free(error);
      }
    });
  } catch (_) {
    return false;
  }
}
