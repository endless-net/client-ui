import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

const _blockSize = 16 * 1024;

/// Duplex overlapped I/O: a waiting ReadFile never blocks writes or the UI.
/// Cancellation completes kernel I/O before its native buffers are released.
class WindowsPipe {
  WindowsPipe._(this._handle) {
    _incoming = StreamController<List<int>>(
      onListen: () {
        _reader = _read();
      },
      onCancel: close,
      onPause: () {
        _resume ??= Completer<void>();
      },
      onResume: () {
        _resume?.complete();
        _resume = null;
      },
    );
    _writer = _write();
  }

  final HANDLE _handle;
  late final StreamController<List<int>> _incoming;
  final _outgoing = StreamController<List<int>>();
  final _closed = Completer<void>();
  Future<void>? _reader;
  late final Future<void> _writer;
  bool _closing = false;
  Completer<void>? _resume;
  int _queuedBytes = 0;
  late final _PipeSink _sink = _PipeSink(this);

  Stream<List<int>> get incoming => _incoming.stream;
  StreamSink<List<int>> get outgoing => _sink;
  Future<void> get done => _closed.future;

  static Future<WindowsPipe> connect(String endpoint) async {
    if (!Platform.isWindows ||
        !endpoint.startsWith(r'\\.\pipe\') ||
        endpoint.length <= 9 ||
        endpoint.contains('\u0000')) {
      throw ArgumentError('A local Windows pipe is required');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    final path = endpoint.toNativeUtf16();
    try {
      while (true) {
        final result = CreateFile(
          PCWSTR(path),
          GENERIC_READ | GENERIC_WRITE,
          FILE_SHARE_MODE(0),
          null,
          OPEN_EXISTING,
          FILE_FLAG_OVERLAPPED | SECURITY_SQOS_PRESENT | SECURITY_IMPERSONATION,
          null,
        );
        if (result.value.address != INVALID_HANDLE_VALUE.address) {
          return WindowsPipe._(result.value);
        }
        if ((result.error == ERROR_PIPE_BUSY ||
                result.error == ERROR_FILE_NOT_FOUND) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
          continue;
        }
        throw WindowsException(
          result.error.toHRESULT(),
          message: 'Cannot open local IPC pipe',
        );
      }
    } finally {
      calloc.free(path);
    }
  }

  Future<int> _transfer(
    Pointer<Uint8> buffer,
    int length, {
    required bool read,
  }) async {
    final overlapped = calloc<OVERLAPPED>();
    final transferred = calloc<Uint32>();
    try {
      final result = read
          ? ReadFile(_handle, buffer, length, transferred, overlapped)
          : WriteFile(_handle, buffer, length, transferred, overlapped);
      if (result.value) return transferred.value;
      if (result.error != ERROR_IO_PENDING) {
        throw WindowsException(
          result.error.toHRESULT(),
          message: 'Local IPC I/O failed',
        );
      }
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final completed = GetOverlappedResult(
          _handle,
          overlapped,
          transferred,
          false,
        );
        if (completed.value) return transferred.value;
        if (completed.error == ERROR_IO_INCOMPLETE) continue;
        throw WindowsException(
          completed.error.toHRESULT(),
          message: 'Local IPC I/O ended',
        );
      }
    } finally {
      calloc.free(transferred);
      calloc.free(overlapped);
    }
  }

  Future<void> _read() async {
    final buffer = calloc<Uint8>(_blockSize);
    try {
      while (!_closing) {
        await _resume?.future;
        if (_closing) break;
        final count = await _transfer(buffer, _blockSize, read: true);
        if (count == 0) break;
        if (!_closing)
          _incoming.add(Uint8List.fromList(buffer.asTypedList(count)));
      }
    } catch (error, stack) {
      if (!_closing) _incoming.addError(error, stack);
    } finally {
      calloc.free(buffer);
      // Do not await our own completion through close().
      unawaited(close());
    }
  }

  Future<void> _write() async {
    final buffer = calloc<Uint8>(_blockSize);
    try {
      await for (final bytes in _outgoing.stream) {
        if (_closing) break;
        var offset = 0;
        while (offset < bytes.length && !_closing) {
          final length = (bytes.length - offset).clamp(0, _blockSize);
          buffer.asTypedList(length).setRange(0, length, bytes, offset);
          final count = await _transfer(buffer, length, read: false);
          if (count == 0)
            throw const FileSystemException('Local IPC accepted zero bytes');
          offset += count;
        }
        _queuedBytes -= bytes.length;
      }
    } catch (error, stack) {
      if (!_closing) _incoming.addError(error, stack);
    } finally {
      calloc.free(buffer);
      unawaited(close());
    }
  }

  Future<void> close() {
    if (_closing) return done;
    _closing = true;
    _resume?.complete();
    _resume = null;
    CancelIoEx(_handle, null);
    unawaited(_outgoing.close());
    unawaited(_finishClose());
    return done;
  }

  Future<void> _finishClose() async {
    await Future.wait<void>([if (_reader != null) _reader!, _writer]);
    CloseHandle(_handle);
    unawaited(_incoming.close());
    _closed.complete();
  }
}

class _PipeSink implements StreamSink<List<int>> {
  _PipeSink(this.pipe);
  final WindowsPipe pipe;

  @override
  void add(List<int> data) {
    if (pipe._closing) throw StateError('Local IPC pipe is closed');
    if (pipe._queuedBytes + data.length > 4 * 1024 * 1024) {
      addError(
        const FileSystemException('Local IPC output queue limit exceeded'),
      );
      return;
    }
    pipe._queuedBytes += data.length;
    pipe._outgoing.add(Uint8List.fromList(data));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      pipe._outgoing.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future<void> close() => pipe._outgoing.close();

  @override
  Future<void> get done => pipe.done;
}
