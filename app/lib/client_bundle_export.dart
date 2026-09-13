import 'dart:io';
import 'dart:typed_data';

/// The destination is explicitly chosen by the caller, never from a producer
/// handle. Export into a fresh child directory; do not overwrite existing files.
/// Content must come from the checksum-verified session bundle reader.
Future<File> exportClientBundle(
  Directory destination,
  Uint8List verifiedContent, {
  required void Function() checkContext,
}) async {
  if (!destination.isAbsolute || verifiedContent.length > 5 * 1024 * 1024) {
    throw ArgumentError(
      'An absolute destination and bounded bundle are required',
    );
  }
  checkContext();
  final content = Uint8List.fromList(verifiedContent);
  Directory? created;
  try {
    created = await destination.createTemp('endlessnet-diagnostics-');
    checkContext();
    final file = File.fromUri(created.uri.resolve('diagnostics.bundle'));
    await file.writeAsBytes(content, flush: true);
    checkContext();
    return file;
  } catch (_) {
    // This is only the unique directory created by this invocation. Never
    // delete the selected destination or a path supplied by the producer.
    if (created != null) await created.delete(recursive: true);
    rethrow;
  }
}
