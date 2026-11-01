import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'windows_pipe_config.dart';

final class _Overlapped extends Struct {
  @UintPtr()
  external int internal;
  @UintPtr()
  external int internalHigh;
  @Uint32()
  external int offset;
  @Uint32()
  external int offsetHigh;
  @IntPtr()
  external int event;
}

final class _Win {
  _Win(String libraryPath) : bridge = DynamicLibrary.open(libraryPath);
  final DynamicLibrary bridge;
  final kernel = DynamicLibrary.open('kernel32.dll');
  final security = DynamicLibrary.open('advapi32.dll');
  late final createFile = bridge
      .lookupFunction<
        IntPtr Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Uint32,
          Uint32,
          Pointer<Uint32>,
        ),
        int Function(Pointer<Utf16>, int, int, int, int, Pointer<Uint32>)
      >('en_pipe_open');
  late final close = kernel
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
  late final localFree = kernel
      .lookupFunction<
        Pointer<Void> Function(Pointer<Void>),
        Pointer<Void> Function(Pointer<Void>)
      >('LocalFree');
  late final createEvent = kernel
      .lookupFunction<
        IntPtr Function(Pointer<Void>, Int32, Int32, Pointer<Utf16>),
        int Function(Pointer<Void>, int, int, Pointer<Utf16>)
      >('CreateEventW');
  late final read = bridge
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<_Overlapped>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<Uint8>,
          int,
          Pointer<Uint32>,
          Pointer<_Overlapped>,
          Pointer<Uint32>,
        )
      >('en_pipe_read');
  late final write = bridge
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint8>,
          Uint32,
          Pointer<Uint32>,
          Pointer<_Overlapped>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<Uint8>,
          int,
          Pointer<Uint32>,
          Pointer<_Overlapped>,
          Pointer<Uint32>,
        )
      >('en_pipe_write');
  late final result = bridge
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<_Overlapped>,
          Pointer<Uint32>,
          Pointer<Uint32>,
        ),
        int Function(
          int,
          Pointer<_Overlapped>,
          Pointer<Uint32>,
          Pointer<Uint32>,
        )
      >('en_pipe_result');
  late final cancel = kernel
      .lookupFunction<
        Int32 Function(IntPtr, Pointer<_Overlapped>),
        int Function(int, Pointer<_Overlapped>)
      >('CancelIoEx');
  late final getSecurity = security
      .lookupFunction<
        Uint32 Function(
          IntPtr,
          Int32,
          Uint32,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
        ),
        int Function(
          int,
          int,
          int,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
          Pointer<Pointer<Void>>,
        )
      >('GetSecurityInfo');
  late final parseSid = security
      .lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Pointer<Void>>),
        int Function(Pointer<Utf16>, Pointer<Pointer<Void>>)
      >('ConvertStringSidToSidW');
  late final equalSid = security
      .lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Void>),
        int Function(Pointer<Void>, Pointer<Void>)
      >('EqualSid');

  bool owner(int handle, String expected) {
    final text = expected.toNativeUtf16(allocator: calloc);
    final sid = calloc<Pointer<Void>>();
    final owner = calloc<Pointer<Void>>();
    final descriptor = calloc<Pointer<Void>>();
    try {
      if (parseSid(text, sid) == 0 ||
          getSecurity(
                handle,
                6,
                1,
                owner,
                nullptr,
                nullptr,
                nullptr,
                descriptor,
              ) !=
              0) {
        return false;
      }
      return owner.value != nullptr && equalSid(owner.value, sid.value) != 0;
    } finally {
      if (descriptor.value != nullptr) localFree(descriptor.value);
      if (sid.value != nullptr) localFree(sid.value);
      calloc.free(text);
      calloc.free(sid);
      calloc.free(owner);
      calloc.free(descriptor);
    }
  }
}

// One worker owns all handles/buffers. No synchronous Win32 I/O on the UI isolate.
void windowsPipeWorker((SendPort, WindowsPipeConfig) input) async {
  final (output, config) = input;
  final commands = ReceivePort();
  output.send(['control', commands.sendPort]);
  _Win? win;
  var handle = -1;
  var stopping = false;
  var cleaning = false;
  Future<void>? reading;
  Future<void>? writing;

  Future<void> cleanup() async {
    if (cleaning) return;
    cleaning = true;
    stopping = true;
    if (handle != -1) win?.cancel(handle, nullptr);
    // CancelIoEx only requests cancellation. Keep OVERLAPPED/buffers alive until
    // each operation reports completion, including ERROR_OPERATION_ABORTED.
    await Future.wait([
      if (reading != null) reading!,
      if (writing != null) writing!,
    ]);
    if (handle != -1) {
      win?.close(handle);
      handle = -1;
    }
    output.send(['closed']);
    commands.close();
  }

  void fail(WindowsPipeProblem problem) {
    output.send(['failure', problem.index]);
    unawaited(cleanup());
  }

  Future<Uint8List?> transfer(Uint8List? data) async {
    final api = win!;
    final buffer = calloc<Uint8>(65536);
    final overlapped = calloc<_Overlapped>();
    final transferred = calloc<Uint32>();
    final errorCode = calloc<Uint32>();
    overlapped.ref.event = api.createEvent(nullptr, 1, 0, nullptr);
    var pending = false;
    var timedOut = false;
    final clock = Stopwatch()..start();
    try {
      if (overlapped.ref.event == 0) {
        throw const WindowsPipeFailure(WindowsPipeProblem.io);
      }
      var offset = 0;
      do {
        if (stopping) return null;
        final size = data == null
            ? 65536
            : (data.length - offset > 65536 ? 65536 : data.length - offset);
        if (data != null) {
          buffer.asTypedList(size).setRange(0, size, data, offset);
        }
        final ok = data == null
            ? api.read(handle, buffer, size, transferred, overlapped, errorCode)
            : api.write(
                handle,
                buffer,
                size,
                transferred,
                overlapped,
                errorCode,
              );
        final error = errorCode.value;
        if (ok == 0 && error != 997) {
          if (data == null && (error == 109 || error == 233)) return null;
          throw const WindowsPipeFailure(WindowsPipeProblem.io);
        }
        // Even synchronous completion of an overlapped request is accounted for
        // through GetOverlappedResult, not the optional immediate byte count.
        pending = true;
        while (pending) {
          final completed = api.result(
            handle,
            overlapped,
            transferred,
            errorCode,
          );
          final status = errorCode.value;
          if (completed != 0 || status != 996) {
            pending = false;
            if (completed == 0) {
              if (stopping ||
                  (data == null && (status == 109 || status == 233))) {
                return null;
              }
              throw WindowsPipeFailure(
                timedOut ? WindowsPipeProblem.timeout : WindowsPipeProblem.io,
              );
            }
          } else {
            if (data != null &&
                !timedOut &&
                clock.elapsed >= config.writeTimeout) {
              timedOut = true;
              api.cancel(handle, overlapped);
            }
            await Future<void>.delayed(const Duration(milliseconds: 2));
          }
        }
        if (timedOut) {
          throw const WindowsPipeFailure(WindowsPipeProblem.timeout);
        }
        final count = transferred.value;
        if (count == 0) return null;
        if (count > size) throw const WindowsPipeFailure(WindowsPipeProblem.io);
        if (data == null) return Uint8List.fromList(buffer.asTypedList(count));
        offset += count;
        // Manual-reset event is reset by the next ReadFile/WriteFile call.
      } while (offset < data.length);
      return Uint8List(0);
    } finally {
      // All paths after ERROR_IO_PENDING leave only after terminal result.
      if (!pending) {
        if (overlapped.ref.event != 0) api.close(overlapped.ref.event);
        calloc.free(overlapped);
        calloc.free(transferred);
        calloc.free(errorCode);
        calloc.free(buffer);
      }
    }
  }

  Future<void> readOne() async {
    try {
      final data = await transfer(null);
      if (data == null) {
        unawaited(cleanup());
      } else {
        output.send([
          'data',
          TransferableTypedData.fromList([data]),
        ]);
      }
    } on WindowsPipeFailure catch (error) {
      fail(error.problem);
    } catch (error) {
      fail(WindowsPipeProblem.io);
    }
  }

  Future<void> writeOne(TransferableTypedData payload) async {
    try {
      final data = payload.materialize().asUint8List();
      if (data.length > config.maxPendingWriteBytes) {
        throw const WindowsPipeFailure(WindowsPipeProblem.capacity);
      }
      if (await transfer(data) == null) {
        unawaited(cleanup());
      } else {
        output.send(['written']);
      }
    } on WindowsPipeFailure catch (error) {
      fail(error.problem);
    } catch (error) {
      fail(WindowsPipeProblem.io);
    }
  }

  commands.listen((dynamic value) {
    if (value == 'stop') {
      unawaited(cleanup());
      return;
    }
    if (stopping || handle == -1) return;
    if (value == 'read') {
      if (reading != null) {
        fail(WindowsPipeProblem.io);
        return;
      }
      reading = readOne().whenComplete(() {
        reading = null;
      });
    } else if (value is TransferableTypedData) {
      if (writing != null) {
        fail(WindowsPipeProblem.io);
        return;
      }
      writing = writeOne(value).whenComplete(() {
        writing = null;
      });
    } else {
      fail(WindowsPipeProblem.io);
    }
  });
  try {
    if (sizeOf<IntPtr>() != 8 || sizeOf<_Overlapped>() != 32) {
      throw const WindowsPipeFailure(WindowsPipeProblem.configuration);
    }
    win = _Win(config.nativeLibraryPath);
    final path = config.path.toNativeUtf16(allocator: calloc);
    final clock = Stopwatch()..start();
    final openError = calloc<Uint32>();
    try {
      while (!stopping) {
        // Data/read-control only, no FILE_CREATE_PIPE_INSTANCE; overlapped I/O,
        // SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION, never delegation.
        handle = win.createFile(path, 0x120183, 3, 3, 0x40110000, openError);
        if (handle != -1) break;
        final error = openError.value;
        if (error != 231) {
          throw const WindowsPipeFailure(WindowsPipeProblem.unavailable);
        }
        if (clock.elapsed >= config.connectTimeout) {
          throw const WindowsPipeFailure(WindowsPipeProblem.timeout);
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    } finally {
      calloc.free(path);
      calloc.free(openError);
    }
    if (stopping) {
      await cleanup();
      return;
    }
    if (!win.owner(handle, config.serverSid)) {
      throw const WindowsPipeFailure(WindowsPipeProblem.authentication);
    }
    output.send([
      'ready',
    ]); // No HTTP2 bytes were written before owner verification.
  } on WindowsPipeFailure catch (error) {
    fail(error.problem);
  } catch (_) {
    fail(WindowsPipeProblem.io);
  }
}
