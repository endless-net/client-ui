import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;

import 'enrollment_client.dart';

// UI-owned correlation only. This is neither an API DTO nor a device-key store.
abstract interface class CorrelationJournalIO {
  Future<Uint8List> read(int maxBytes);
  Future<void> append(Uint8List bytes);
  Future<void> flush();
  Future<void> close();
}

enum CorrelationStoreProblem {
  inaccessible,
  busy,
  closed,
  corrupt,
  conflict,
  full,
}

final class CorrelationStoreFailure implements Exception {
  const CorrelationStoreFailure(this.problem);
  final CorrelationStoreProblem problem;
  @override
  String toString() => 'CorrelationStoreFailure(${problem.name})';
}

// Caller supplies an already exclusively locked handle for this store lifetime.
// The Windows factory owns that contract. Memory IO is used only by unit tests.
final class JournalCorrelationStore implements CorrelationStore {
  JournalCorrelationStore(this._io, {required this.maxBytes}) {
    if (maxBytes < 8192 || maxBytes > 16 * 1024 * 1024) {
      throw ArgumentError('correlation journal budget');
    }
  }

  final CorrelationJournalIO _io;
  final int maxBytes;
  Completer<void>? _active;
  bool _closing = false;
  Future<void>? _close;

  Future<T> _run<T>(Future<T> Function() operation) async {
    if (_closing) {
      throw const CorrelationStoreFailure(CorrelationStoreProblem.closed);
    }
    if (_active != null) {
      throw const CorrelationStoreFailure(CorrelationStoreProblem.busy);
    }
    final active = Completer<void>();
    _active = active;
    try {
      return await operation();
    } on CorrelationStoreFailure {
      rethrow;
    } catch (_) {
      throw const CorrelationStoreFailure(CorrelationStoreProblem.inaccessible);
    } finally {
      _active = null;
      active.complete();
    }
  }

  @override
  Future<EnrollmentCorrelation?> read(String profileId, String controlOrigin) =>
      _run(() async {
        final rows = CorrelationJournal.decode(await _io.read(maxBytes));
        return rows[(profileId, controlOrigin)];
      });

  @override
  Future<void> save(EnrollmentCorrelation correlation) => _run(() async {
    final existing = await _io.read(maxBytes);
    final rows = CorrelationJournal.decode(existing);
    final frame = CorrelationJournal.append(existing, rows, correlation);
    if (existing.length + frame.length > maxBytes) {
      throw const CorrelationStoreFailure(CorrelationStoreProblem.full);
    }
    if (frame.isNotEmpty) await _io.append(frame);
    // Even exact replay must flush: a previous flush may have failed after write.
    await _io.flush();
  });

  Future<void> close() {
    _closing = true;
    return _close ??= () async {
      await _active?.future;
      try {
        await _io.close();
      } catch (_) {
        throw const CorrelationStoreFailure(
          CorrelationStoreProblem.inaccessible,
        );
      }
    }();
  }
}

final class CorrelationJournal {
  static const _magic = [69, 78, 85, 73, 48, 48, 51, 1]; // ENUI003, format 1.
  static Uint8List get initialBytes => Uint8List.fromList(_magic);
  static const _maxFrame = 8192;
  static const _headerBytes = 4;
  static const _hashBytes = 32;

  static Never _bad() =>
      throw const CorrelationStoreFailure(CorrelationStoreProblem.corrupt);

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static void _validate(EnrollmentCorrelation c) {
    final origin = Uri.tryParse(c.controlOrigin);
    if (c.profileId.isEmpty ||
        c.profileId.length > _maxFrame ||
        origin == null ||
        origin.scheme != 'https' ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        origin.origin != c.controlOrigin ||
        c.controlOrigin.length > _maxFrame ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(c.requestId) ||
        c.hostname.trim().isEmpty ||
        c.hostname.length > _maxFrame ||
        (c.mode == api.EnrollmentMode.ENROLLMENT_MODE_UNSPECIFIED ||
            !api.EnrollmentMode.values.contains(c.mode)) ||
        (c.recoveryDeadline != null &&
            (c.recoveryDeadline!.microsecondsSinceEpoch <= 0))) {
      _bad();
    }
  }

  static bool _immutableEqual(
    EnrollmentCorrelation a,
    EnrollmentCorrelation b,
  ) =>
      a.profileId == b.profileId &&
      a.controlOrigin == b.controlOrigin &&
      a.requestId == b.requestId &&
      a.hostname == b.hostname &&
      a.mode == b.mode;

  static void _merge(
    Map<(String, String), EnrollmentCorrelation> rows,
    EnrollmentCorrelation c,
  ) {
    _validate(c);
    final key = (c.profileId, c.controlOrigin);
    final old = rows[key];
    if (old != null &&
        (!_immutableEqual(old, c) ||
            (old.recoveryDeadline != null &&
                (c.recoveryDeadline == null ||
                    c.recoveryDeadline!.isAfter(old.recoveryDeadline!))))) {
      throw const CorrelationStoreFailure(CorrelationStoreProblem.conflict);
    }
    rows[key] = c;
  }

  static Map<(String, String), EnrollmentCorrelation> decode(Uint8List data) {
    final rows = <(String, String), EnrollmentCorrelation>{};
    if (data.isEmpty) return rows;
    if (data.length < _magic.length ||
        !_same(data.sublist(0, _magic.length), _magic)) {
      _bad();
    }
    var pos = _magic.length;
    while (pos < data.length) {
      if (data.length - pos < _headerBytes) _bad();
      final length = ByteData.sublistView(data, pos, pos + 4).getUint32(0);
      if (length == 0 ||
          length > _maxFrame ||
          data.length - pos - 4 < length + _hashBytes) {
        _bad();
      }
      final end = pos + 4 + length;
      final expected = sha256.convert(data.sublist(pos, end)).bytes;
      if (!_same(data.sublist(end, end + _hashBytes), expected)) _bad();
      final body = Uint8List.sublistView(data, pos + 4, end);
      var offset = 0;
      String field() {
        if (body.length - offset < 2) _bad();
        final size = ByteData.sublistView(
          body,
          offset,
          offset + 2,
        ).getUint16(0);
        offset += 2;
        if (body.length - offset < size) _bad();
        final value = utf8.decode(body.sublist(offset, offset + size));
        offset += size;
        return value;
      }

      try {
        final profile = field();
        final origin = field();
        final uuid = field();
        final hostname = field();
        if (body.length - offset != 12) _bad();
        final tail = ByteData.sublistView(body, offset);
        final mode = api.EnrollmentMode.valueOf(tail.getUint32(0));
        final deadline = tail.getInt64(4);
        if (mode == null || deadline < 0) _bad();
        _merge(
          rows,
          EnrollmentCorrelation(
            profileId: profile,
            controlOrigin: origin,
            requestId: uuid,
            hostname: hostname,
            mode: mode,
            recoveryDeadline: deadline == 0
                ? null
                : DateTime.fromMicrosecondsSinceEpoch(deadline, isUtc: true),
          ),
        );
      } on CorrelationStoreFailure {
        rethrow;
      } catch (_) {
        _bad();
      }
      pos = end + _hashBytes;
    }
    return rows;
  }

  static Uint8List append(
    Uint8List existing,
    Map<(String, String), EnrollmentCorrelation> rows,
    EnrollmentCorrelation c,
  ) {
    final old = rows[(c.profileId, c.controlOrigin)];
    _merge(rows, c);
    if (old != null && old.recoveryDeadline == c.recoveryDeadline) {
      return Uint8List(0);
    }
    final body = BytesBuilder(copy: false);
    for (final field in [
      c.profileId,
      c.controlOrigin,
      c.requestId,
      c.hostname,
    ]) {
      final bytes = utf8.encode(field);
      body.add((ByteData(2)..setUint16(0, bytes.length)).buffer.asUint8List());
      body.add(bytes);
    }
    body.add(
      (ByteData(12)
            ..setUint32(0, c.mode.value)
            ..setInt64(4, c.recoveryDeadline?.microsecondsSinceEpoch ?? 0))
          .buffer
          .asUint8List(),
    );
    final payload = body.takeBytes();
    if (payload.length > _maxFrame) _bad();
    final frame = BytesBuilder(copy: false)
      ..add((ByteData(4)..setUint32(0, payload.length)).buffer.asUint8List())
      ..add(payload);
    final bytes = frame.takeBytes();
    return (BytesBuilder(copy: false)
          ..add(existing.isEmpty ? _magic : const [])
          ..add(bytes)
          ..add(sha256.convert(bytes).bytes))
        .takeBytes();
  }
}
