import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:endlessnet_client_api/client_api.dart' as api;

import 'client_operation.dart';

final class PendingClientIntent {
  const PendingClientIntent(this.requestId, this.kind);
  final String requestId;
  final api.OperationKind kind;
}

/// UI-owned outbox in a caller-private, installation-scoped directory chosen by
/// the platform adapter. Never point this at runtime state or a shared folder.
/// Records contain only UUID and kind, never command payloads or credentials.
base class ClientIntentJournal {
  ClientIntentJournal(this.directory, {String Function()? requestIdFactory})
    : _requestIdFactory = requestIdFactory ?? _randomRequestId;
  final Directory directory;
  final String Function() _requestIdFactory;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  Future<ClientOperation> submit(
    api.OperationKind kind,
    Future<ClientOperation> Function(PendingClientIntent intent) send,
  ) async {
    final intent = await prepare(kind);
    // Failure, timeout or app termination leaves the record available for
    // GetOperation. No retry, new ID or payload persistence occurs here.
    final result = await send(intent);
    if (result.value.requestId != intent.requestId ||
        result.value.kind != kind) {
      throw const FormatException('Journal result does not match intention');
    }
    return result;
  }

  Future<PendingClientIntent> prepare(api.OperationKind kind) async {
    if (kind == api.OperationKind.OPERATION_KIND_UNSPECIFIED) {
      throw const FormatException('Intention requires a known operation kind');
    }
    await directory.create(recursive: true);
    // Fail closed on old incomplete/corrupt records, rather than replacing them.
    if ((await pending()).length >= 4096) {
      throw StateError('Recover pending intentions before creating more');
    }
    final id = _requestIdFactory();
    final file = _file(id);
    await file.create(exclusive: true);
    await file.writeAsString(
      jsonEncode({'request_id': id, 'kind': kind.value}),
      flush: true,
    );
    return PendingClientIntent(id, kind);
  }

  static String _randomRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  File _file(String id) {
    if (!_uuid.hasMatch(id)) {
      throw const FormatException('Invalid journal UUID');
    }
    return File.fromUri(directory.absolute.uri.resolve('$id.json'));
  }

  Future<List<PendingClientIntent>> pending() async {
    if (!await directory.exists()) return [];
    final result = <PendingClientIntent>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (!entity.path.endsWith('.json')) continue;
      if (entity is! File ||
          result.length >= 4096 ||
          await entity.length() > 1024) {
        throw const FormatException('Invalid or oversized intention journal');
      }
      try {
        final data = jsonDecode(await entity.readAsString());
        if (data is! Map<String, dynamic> ||
            data.length != 2 ||
            data['request_id'] is! String ||
            data['kind'] is! int) {
          throw const FormatException();
        }
        final id = data['request_id'] as String;
        final kind = api.OperationKind.valueOf(data['kind'] as int);
        if (kind == null ||
            kind == api.OperationKind.OPERATION_KIND_UNSPECIFIED ||
            _file(id).absolute.path != entity.absolute.path) {
          throw const FormatException();
        }
        result.add(PendingClientIntent(id, kind));
      } on FormatException {
        // JSON exceptions may echo input; do not disclose corrupted contents.
        throw const FormatException('Invalid intention journal record');
      }
    }
    return List.unmodifiable(result);
  }

  /// Call only after displaying/handling a validated terminal result. An
  /// unresolved NOT_FOUND must remain pending for explicit recovery policy.
  Future<void> acknowledge(ClientOperation result) async {
    if (!result.terminal) throw StateError('Cannot acknowledge accepted work');
    final matches = (await pending()).where(
      (p) => p.requestId == result.value.requestId,
    );
    if (matches.length != 1 || matches.single.kind != result.value.kind) {
      throw const FormatException('Terminal result does not match journal');
    }
    await _file(result.value.requestId).delete();
  }
}
