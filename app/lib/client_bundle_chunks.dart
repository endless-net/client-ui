import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:endlessnet_client_api/client_api.dart' as api;

/// Bounded transport assembly with content checksum verification. Export still
/// requires an explicit destination; this function never writes a file.
/// The caller must also reject a lost/replaced authenticated session throughout.
Future<Uint8List> readClientBundleChunks(
  api.BundleResult result,
  Future<api.ReadDiagnosticsBundleResponse> Function(
    api.ReadDiagnosticsBundleRequest,
  )
  read, {
  required void Function() checkContext,
  DateTime Function()? now,
}) async {
  final bundle = api.BundleResult.fromBuffer(result.writeToBuffer())..freeze();
  if (bundle.bundleId.isEmpty ||
      bundle.sizeBytes < 0 ||
      bundle.sizeBytes > 5 * 1024 * 1024 ||
      !bundle.hasExpiresAt() ||
      !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(bundle.sha256) ||
      bundle.expiresAt.seconds < -62135596800 ||
      bundle.expiresAt.seconds > 253402300799 ||
      bundle.expiresAt.nanos < 0 ||
      bundle.expiresAt.nanos >= 1000000000) {
    throw const FormatException('Invalid diagnostics bundle handle');
  }
  final expires = DateTime.fromMicrosecondsSinceEpoch(
    bundle.expiresAt.seconds.toInt() * 1000000 + bundle.expiresAt.nanos ~/ 1000,
    isUtc: true,
  );
  void check() {
    checkContext();
    if (!expires.isAfter((now ?? DateTime.now)().toUtc())) {
      throw StateError('Diagnostics bundle expired');
    }
  }

  final bytes = BytesBuilder(copy: true);
  var offset = bundle.sizeBytes - bundle.sizeBytes;
  while (true) {
    check();
    const maxBytes = 64 * 1024;
    final response = await read(
      api.ReadDiagnosticsBundleRequest(
        bundleId: bundle.bundleId,
        offset: offset,
        maxBytes: maxBytes,
      ),
    );
    check();
    final next = offset + response.data.length;
    if (response.data.length > maxBytes ||
        response.nextOffset != next ||
        next > bundle.sizeBytes ||
        response.eof != (next == bundle.sizeBytes) ||
        (!response.eof && response.data.isEmpty)) {
      throw const FormatException('Invalid diagnostics bundle chunk');
    }
    bytes.add(response.data);
    if (response.eof) {
      final content = bytes.takeBytes();
      if (crypto.sha256.convert(content).toString() !=
          bundle.sha256.toLowerCase()) {
        throw const FormatException('Diagnostics bundle checksum mismatch');
      }
      check();
      return content;
    }
    offset = next;
  }
}
