import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'protocol.dart' show Json;

enum RecoveryEvent {
  readFailed,
  openingFailed,
  scheduled,
  reconnecting,
  recovered,
}

enum RecoveryStage {
  runtimeInfo,
  status,
  configuration,
  channel,
  storage,
  initialization,
  cleanup,
}

enum RecoveryCause {
  timeout,
  rpc,
  runtimeMismatch,
  missingMetadata,
  wrongInstance,
  invalidRevision,
  staleRevision,
  wrongProfile,
  unknown,
  authentication,
  unavailable,
  io,
  capacity,
  closed,
  configuration,
  invalid,
  missing,
  untrusted,
  busy,
  componentUnavailable,
  unsupportedPlatform,
}

typedef RecoveryRecord = ({
  DateTime time,
  RecoveryEvent event,
  RecoveryStage? stage,
  RecoveryCause? cause,
  int? rpcCode,
  int? delaySeconds,
});

final class RecoveryLog {
  static const _capacity = 256;
  static const _slotBytes = 512;
  final _entries = ListQueue<Json>();
  final _pending = ListQueue<RecoveryRecord>();
  RandomAccessFile? _file;
  Future<void>? _opening;
  Future<void>? _writing;
  Future<void>? _closing;
  void Function()? _release;
  int _sequence = 0;
  bool _historyGap = false;
  bool storageUnavailable = false;
  bool _closed = false;
  bool get historyGap =>
      _historyGap || (_entries.isNotEmpty && _entries.first['sequence'] != 1);

  Future<void> open(Future<(File, void Function())> Function() acquire) =>
      _opening ??= _open(acquire).whenComplete(() {
        _opening = null;
        while (_pending.isNotEmpty) {
          _append(_pending.removeFirst());
        }
        _write();
      });

  Future<void> _open(Future<(File, void Function())> Function() acquire) async {
    try {
      final (path, release) = await acquire();
      _release = release;
      final file = await path.open(mode: FileMode.append);
      _file = file;
      await file.lock(FileLock.exclusive);
      final length = await file.length();
      if (length > _capacity * _slotBytes) throw const FormatException();
      await file.setPosition(0);
      final slots = <Json>[];
      for (var pos = 0; pos < length; pos += _slotBytes) {
        final bytes = await file.read(_slotBytes);
        final end = bytes.indexOf(0);
        try {
          if (bytes.length != _slotBytes || end < 1) {
            throw const FormatException();
          }
          slots.add(_decode(utf8.decode(bytes.sublist(0, end)), pos));
        } catch (_) {
          _historyGap = true;
        }
      }
      slots.sort(
        (a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int),
      );
      _entries.addAll(slots);
      if (slots.isNotEmpty) {
        _sequence = slots.last['sequence'] as int;
        _written = _sequence;
      }
    } catch (_) {
      storageUnavailable = true;
      await _releaseStorage();
    }
  }

  void record(
    RecoveryEvent event, {
    RecoveryStage? stage,
    RecoveryCause? cause,
    int? rpcCode,
    int? delaySeconds,
  }) {
    if (_closed) return;
    final record = (
      time: DateTime.now().toUtc(),
      event: event,
      stage: stage,
      cause: cause,
      rpcCode: rpcCode,
      delaySeconds: delaySeconds,
    );
    if (_opening != null) {
      if (_pending.length == _capacity) {
        _historyGap = true;
        _pending.removeFirst();
      }
      _pending.addLast(record);
      return;
    }
    _append(record);
    _write();
  }

  void _append(RecoveryRecord record) {
    if (_entries.length == _capacity) {
      _entries.removeFirst();
      _historyGap = true;
    }
    _entries.addLast(_entry(++_sequence, record));
  }

  int _written = 0;

  void _write() {
    if (_file == null ||
        _writing != null ||
        storageUnavailable ||
        _written >= _sequence) {
      return;
    }
    _writing = _flush(_file!).whenComplete(() {
      _writing = null;
      _write();
    });
  }

  Future<void> _flush(RandomAccessFile file) async {
    try {
      while (_written < _sequence) {
        final entries = _entries
            .where((entry) => (entry['sequence'] as int) > _written)
            .toList();
        for (final entry in entries) {
          final sequence = entry['sequence'] as int;
          final bytes = utf8.encode(jsonEncode(entry));
          final slot = Uint8List(_slotBytes)..setRange(0, bytes.length, bytes);
          await file.setPosition(_position(sequence));
          await file.writeFrom(slot);
          _written = sequence;
        }
        await file.flush();
      }
    } catch (_) {
      storageUnavailable = true;
    }
  }

  List<Json> snapshot() => List.unmodifiable(_entries);

  Json read(int after, int limit) {
    final entries = _entries
        .where((e) => (e['sequence'] as int) > after)
        .take(limit)
        .toList(growable: false);
    final next = entries.isEmpty ? after : entries.last['sequence'] as int;
    return {
      'entries': entries,
      'nextCursor': next,
      'hasMore': next < _sequence,
      'historyGap':
          (_historyGap && after == 0) ||
          (_entries.isNotEmpty &&
              after < (_entries.first['sequence'] as int) - 1) ||
          (entries.isNotEmpty && next - after != entries.length),
      'cursorAhead': after > _sequence,
      'storageUnavailable': storageUnavailable,
    };
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    await _opening;
    while (_writing != null) {
      await _writing;
    }
    await _releaseStorage();
  }

  Future<void> _releaseStorage() async {
    try {
      await _file?.close();
    } catch (_) {
      storageUnavailable = true;
    } finally {
      _file = null;
      try {
        _release?.call();
      } catch (_) {
        storageUnavailable = true;
      }
      _release = null;
    }
  }

  static int _position(int sequence) =>
      ((sequence - 1) % _capacity) * _slotBytes;

  Json _decode(String text, int position) {
    final entry = jsonDecode(text) as Json;
    final sequence = entry['sequence'] as int;
    if (sequence <= 0 ||
        sequence > 9007199254740991 ||
        _position(sequence) != position) {
      throw const FormatException();
    }
    final state = entry['state'] as Json;
    final stage = state['stage'] as String?;
    final cause = state['cause'] as String?;
    final rpcCode = state['rpcCode'] as int?;
    final delay = state['delaySeconds'] as int?;
    if ((rpcCode != null && (rpcCode < 0 || rpcCode > 16)) ||
        (delay != null && (delay < 1 || delay > 30))) {
      throw const FormatException();
    }
    return _entry(sequence, (
      time: DateTime.parse(entry['time'] as String).toUtc(),
      event: RecoveryEvent.values.byName(entry['event'] as String),
      stage: stage == null ? null : RecoveryStage.values.byName(stage),
      cause: cause == null ? null : RecoveryCause.values.byName(cause),
      rpcCode: rpcCode,
      delaySeconds: delay,
    ));
  }

  Json _entry(int sequence, RecoveryRecord record) => {
    'sequence': sequence,
    'time': record.time.toIso8601String(),
    'component': 'localClientRecovery',
    'event': record.event.name,
    'state': {
      'stage': ?record.stage?.name,
      'cause': ?record.cause?.name,
      'rpcCode': ?record.rpcCode,
      'delaySeconds': ?record.delaySeconds,
    },
  };
}
