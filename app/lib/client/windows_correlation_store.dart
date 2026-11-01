import 'dart:io';
import 'dart:typed_data';

import 'correlation_journal.dart';

// Path comes from trusted per-user app storage configuration. This factory does
// not provision directories/ACLs, choose installation paths or inspect Client state.
Future<JournalCorrelationStore> openWindowsCorrelationStore(
  File file, {
  required int maxBytes,
  // Only a live native private namespace guard may authorize initialization of
  // the empty file it just created and pinned. Existing empty files fail closed.
  bool initializeCreatedEmpty = false,
}) async {
  if (!Platform.isWindows) throw UnsupportedError('Windows correlation store');
  if (!file.uri.isAbsolute) throw ArgumentError('absolute correlation path');
  if (maxBytes < 8192 || maxBytes > 16 * 1024 * 1024) {
    throw ArgumentError('correlation journal budget');
  }
  RandomAccessFile? handle;
  try {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.notFound) {
      throw const CorrelationStoreFailure(CorrelationStoreProblem.inaccessible);
    }
    handle = await file.open(mode: FileMode.append);
    // Nonblocking, full-file lock including future growth. Retained for lifetime;
    // Windows associates it with this handle, not merely this process.
    await handle.lock(FileLock.exclusive);
    final io = _WindowsJournalIO(handle);
    if (await handle.length() == 0) {
      if (type != FileSystemEntityType.notFound && !initializeCreatedEmpty) {
        throw const CorrelationStoreFailure(CorrelationStoreProblem.corrupt);
      }
      await io.append(CorrelationJournal.initialBytes);
      await io.flush();
    }
    final store = JournalCorrelationStore(io, maxBytes: maxBytes);
    // Check before exposing the store. Corrupt/partial journals are never reset.
    CorrelationJournal.decode(await io.read(maxBytes));
    await io.flush();
    return store;
  } catch (error) {
    try {
      await handle?.close();
    } catch (_) {
      /* Preserve safe error. */
    }
    if (error is CorrelationStoreFailure) rethrow;
    throw const CorrelationStoreFailure(CorrelationStoreProblem.inaccessible);
  }
}

final class _WindowsJournalIO implements CorrelationJournalIO {
  _WindowsJournalIO(this._file);
  final RandomAccessFile _file;

  @override
  Future<Uint8List> read(int maxBytes) async {
    final length = await _file.length();
    if (length > maxBytes) {
      throw const CorrelationStoreFailure(CorrelationStoreProblem.full);
    }
    await _file.setPosition(0);
    final data = Uint8List(length);
    var offset = 0;
    while (offset < length) {
      final read = await _file.readInto(data, offset);
      if (read == 0) {
        throw const CorrelationStoreFailure(CorrelationStoreProblem.corrupt);
      }
      offset += read;
    }
    return data;
  }

  @override
  Future<void> append(Uint8List bytes) async {
    await _file.setPosition(await _file.length());
    await _file.writeFrom(bytes);
  }

  @override
  Future<void> flush() async {
    await _file.flush();
  }

  @override
  Future<void> close() async {
    await _file.close();
  }
}
