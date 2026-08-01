import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'service_contract.dart';

const _maxResponseBytes = 1 << 20;
const _readBufferSize = 64 * 1024;

class NamedPipeHttpClient {
  NamedPipeHttpClient({required this.pipePath, required this.timeout});

  final String pipePath;
  final Duration timeout;

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration? requestTimeout,
  }) async {
    final effectiveTimeout = requestTimeout ?? timeout;
    final normalizedMethod = method.trim().toUpperCase();
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final bodyText = body == null ? '' : jsonEncode(body);
    final response = await Isolate.run(
      () => namedPipeHttpExchange(
        pipePath,
        normalizedMethod,
        normalizedPath,
        bodyText,
        effectiveTimeout.inMilliseconds,
      ),
    ).timeout(effectiveTimeout + const Duration(seconds: 1));
    final parsed = parseNamedPipeHttpResponse(response);
    final payload = parsed.body.isEmpty
        ? <String, dynamic>{}
        : _decodeObject(parsed.body);
    validateIPCEnvelope(
      payload,
      requireNegotiated: parsed.statusCode >= 200 && parsed.statusCode < 300,
    );
    if (parsed.statusCode < 200 || parsed.statusCode >= 300) {
      throw ServiceIPCException(
        statusCode: parsed.statusCode,
        errorCode: _firstNonEmpty([
          payload['error_code']?.toString(),
          ServiceIPCErrorCode.requestFailed,
        ]),
        message: _firstNonEmpty([
          payload['error']?.toString(),
          'EndlessNet service request failed with HTTP ${parsed.statusCode}.',
        ]),
        requestID: payload['request_id']?.toString().trim() ?? '',
      );
    }
    return payload;
  }

  Future<Map<String, dynamic>> eventStatusSnapshot({
    Duration? requestTimeout,
  }) async {
    final effectiveTimeout = requestTimeout ?? timeout;
    final payload = await Isolate.run(
      () => namedPipeHttpEventStatusSnapshot(
        pipePath,
        effectiveTimeout.inMilliseconds,
      ),
    ).timeout(effectiveTimeout + const Duration(seconds: 1));
    validateIPCEnvelope(payload, requireNegotiated: true);
    return payload;
  }
}

class ServiceIPCException implements Exception {
  const ServiceIPCException({
    required this.statusCode,
    required this.errorCode,
    required this.message,
    this.requestID = '',
  });

  final int statusCode;
  final String errorCode;
  final String message;
  final String requestID;

  String get code => errorCode;

  @override
  String toString() => message;
}

Uint8List namedPipeHttpExchange(
  String pipePath,
  String method,
  String path,
  String bodyText,
  int timeoutMilliseconds,
) {
  final handle = _openPipe(
    pipePath,
    Duration(milliseconds: timeoutMilliseconds),
  );
  try {
    final body = utf8.encode(bodyText);
    final headers = StringBuffer()
      ..write('$method $path HTTP/1.1\r\n')
      ..write('Host: endlessnet.local\r\n')
      ..write('Accept: application/json\r\n')
      ..write(
        '${ServiceIPCMetadata.protocolHeader}: '
        '${ServiceIPCMetadata.protocol}\r\n',
      )
      ..write(
        '${ServiceIPCMetadata.versionHeader}: '
        '${ServiceIPCMetadata.version}\r\n',
      )
      ..write(
        '${ServiceIPCMetadata.minimumVersionHeader}: '
        '${ServiceIPCMetadata.minimumSupportedVersion}\r\n',
      )
      ..write('Connection: close\r\n');
    if (body.isNotEmpty) {
      headers
        ..write('Content-Type: application/json\r\n')
        ..write('Content-Length: ${body.length}\r\n');
    } else {
      headers.write('Content-Length: 0\r\n');
    }
    headers.write('\r\n');
    final request = Uint8List.fromList([
      ...ascii.encode(headers.toString()),
      ...body,
    ]);
    _writeAll(handle, request);
    return _readAll(handle);
  } finally {
    CloseHandle(handle);
  }
}

Map<String, dynamic> namedPipeHttpEventStatusSnapshot(
  String pipePath,
  int timeoutMilliseconds,
) {
  final handle = _openPipe(
    pipePath,
    Duration(milliseconds: timeoutMilliseconds),
  );
  try {
    final headers = StringBuffer()
      ..write('GET ${ServiceIPCPath.events} HTTP/1.1\r\n')
      ..write('Host: endlessnet.local\r\n')
      ..write('Accept: application/x-ndjson\r\n')
      ..write(
        '${ServiceIPCMetadata.protocolHeader}: '
        '${ServiceIPCMetadata.protocol}\r\n',
      )
      ..write(
        '${ServiceIPCMetadata.versionHeader}: '
        '${ServiceIPCMetadata.version}\r\n',
      )
      ..write(
        '${ServiceIPCMetadata.minimumVersionHeader}: '
        '${ServiceIPCMetadata.minimumSupportedVersion}\r\n',
      )
      ..write('Connection: close\r\n')
      ..write('Content-Length: 0\r\n\r\n');
    _writeAll(handle, Uint8List.fromList(ascii.encode(headers.toString())));
    return _readEventStatusSnapshot(handle);
  } finally {
    CloseHandle(handle);
  }
}

HANDLE _openPipe(String pipePath, Duration timeout) {
  if (!pipePath.startsWith(r'\\.\pipe\')) {
    throw ArgumentError.value(
      pipePath,
      'pipePath',
      'must be a local Windows named pipe',
    );
  }
  final deadline = DateTime.now().add(timeout);
  final path = pipePath.toNativeUtf16();
  try {
    while (true) {
      final result = CreateFile(
        PCWSTR(path),
        GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_MODE(0),
        null,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | SECURITY_SQOS_PRESENT | SECURITY_IMPERSONATION,
        null,
      );
      if (result.value.address != INVALID_HANDLE_VALUE.address) {
        return result.value;
      }
      if ((result.error == ERROR_PIPE_BUSY ||
              result.error == ERROR_FILE_NOT_FOUND) &&
          DateTime.now().isBefore(deadline)) {
        sleep(const Duration(milliseconds: 50));
        continue;
      }
      throw WindowsException(
        result.error.toHRESULT(),
        message: 'Cannot connect to the EndlessNet service named pipe.',
      );
    }
  } finally {
    calloc.free(path);
  }
}

void _writeAll(HANDLE handle, Uint8List data) {
  final buffer = calloc<Uint8>(data.length);
  final written = calloc<Uint32>();
  try {
    buffer.asTypedList(data.length).setAll(0, data);
    var offset = 0;
    while (offset < data.length) {
      final result = WriteFile(
        handle,
        buffer + offset,
        data.length - offset,
        written,
        null,
      );
      if (!result.value) {
        throw WindowsException(
          result.error.toHRESULT(),
          message: 'Cannot write to the EndlessNet service named pipe.',
        );
      }
      if (written.value == 0) {
        throw const FileSystemException(
          'EndlessNet service named pipe accepted zero bytes.',
        );
      }
      offset += written.value;
    }
  } finally {
    calloc.free(written);
    calloc.free(buffer);
  }
}

Uint8List _readAll(HANDLE handle) {
  final chunks = BytesBuilder(copy: false);
  final buffer = calloc<Uint8>(_readBufferSize);
  final read = calloc<Uint32>();
  try {
    while (true) {
      final result = ReadFile(handle, buffer, _readBufferSize, read, null);
      if (read.value > 0) {
        chunks.add(Uint8List.fromList(buffer.asTypedList(read.value)));
        if (chunks.length > _maxResponseBytes) {
          throw const FormatException(
            'EndlessNet service IPC response is too large.',
          );
        }
        final expectedBytes = _contentLengthResponseBytes(chunks.toBytes());
        if (expectedBytes != null) {
          if (expectedBytes > _maxResponseBytes) {
            throw const FormatException(
              'EndlessNet service IPC response is too large.',
            );
          }
          if (chunks.length >= expectedBytes) {
            break;
          }
        }
      }
      if (result.value) {
        if (read.value == 0) {
          break;
        }
        continue;
      }
      if (result.error == ERROR_BROKEN_PIPE ||
          result.error == ERROR_NO_DATA ||
          result.error == ERROR_PIPE_NOT_CONNECTED ||
          (result.error == ERROR_SUCCESS && chunks.length > 0)) {
        break;
      }
      if (result.error == ERROR_MORE_DATA) {
        continue;
      }
      throw WindowsException(
        result.error.toHRESULT(),
        message: 'Cannot read from the EndlessNet service named pipe.',
      );
    }
    return chunks.takeBytes();
  } finally {
    calloc.free(read);
    calloc.free(buffer);
  }
}

Map<String, dynamic> _readEventStatusSnapshot(HANDLE handle) {
  final chunks = BytesBuilder(copy: false);
  final buffer = calloc<Uint8>(_readBufferSize);
  final read = calloc<Uint32>();
  try {
    while (true) {
      final result = ReadFile(handle, buffer, _readBufferSize, read, null);
      if (read.value > 0) {
        chunks.add(Uint8List.fromList(buffer.asTypedList(read.value)));
        if (chunks.length > _maxResponseBytes) {
          throw const FormatException(
            'EndlessNet service event snapshot is too large.',
          );
        }
        final snapshot = tryParseEventStatusSnapshot(chunks.toBytes());
        if (snapshot != null) {
          return snapshot;
        }
      }
      if (result.value && read.value > 0) {
        continue;
      }
      if (!result.value && result.error == ERROR_MORE_DATA) {
        continue;
      }
      throw const FormatException(
        'EndlessNet service event stream ended before its status snapshot.',
      );
    }
  } finally {
    calloc.free(read);
    calloc.free(buffer);
  }
}

Map<String, dynamic>? tryParseEventStatusSnapshot(Uint8List raw) {
  final headerEnd = _indexOf(raw, const [13, 10, 13, 10]);
  if (headerEnd < 0) {
    return null;
  }
  final headerText = ascii.decode(
    raw.sublist(0, headerEnd),
    allowInvalid: false,
  );
  final lines = headerText.split('\r\n');
  final status = RegExp(
    r'^HTTP/1\.[01] ([0-9]{3})(?: |$)',
  ).firstMatch(lines.first);
  if (status == null || status.group(1) != '200') {
    throw const FormatException(
      'EndlessNet service rejected the event stream.',
    );
  }
  final headers = <String, String>{};
  for (final line in lines.skip(1)) {
    final separator = line.indexOf(':');
    if (separator <= 0) {
      throw const FormatException('Invalid EndlessNet service event header.');
    }
    headers[line.substring(0, separator).trim().toLowerCase()] = line
        .substring(separator + 1)
        .trim();
  }
  final encodedBody = Uint8List.fromList(raw.sublist(headerEnd + 4));
  final body = headers['transfer-encoding']?.toLowerCase() == 'chunked'
      ? _decodeAvailableChunkedBody(encodedBody)
      : encodedBody;
  final text = utf8.decode(body, allowMalformed: true);
  final completeTextLines = text.split('\n');
  if (!text.endsWith('\n') && completeTextLines.isNotEmpty) {
    completeTextLines.removeLast();
  }
  final eventLines = completeTextLines
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
  if (eventLines.length < 2) {
    return null;
  }
  final hello = jsonDecode(eventLines.first.trim());
  if (hello is! Map<String, dynamic> || hello['event_type'] != 'hello') {
    throw const FormatException(
      'EndlessNet service event stream did not start with hello.',
    );
  }
  for (final line in eventLines.skip(1)) {
    final decoded = jsonDecode(line.trim());
    if (decoded is Map<String, dynamic> &&
        decoded['event_type'] == 'status_changed' &&
        decoded['status'] is Map<String, dynamic>) {
      return decoded['status'] as Map<String, dynamic>;
    }
  }
  return null;
}

Uint8List _decodeAvailableChunkedBody(Uint8List encoded) {
  final decoded = BytesBuilder(copy: false);
  var offset = 0;
  while (offset < encoded.length) {
    final lineEnd = _indexOf(encoded, const [13, 10], start: offset);
    if (lineEnd < 0) {
      break;
    }
    final sizeText = ascii
        .decode(encoded.sublist(offset, lineEnd))
        .split(';')
        .first
        .trim();
    final size = int.tryParse(sizeText, radix: 16);
    if (size == null || size < 0) {
      throw const FormatException(
        'Invalid chunk size from EndlessNet service event stream.',
      );
    }
    offset = lineEnd + 2;
    if (size == 0 || offset + size + 2 > encoded.length) {
      break;
    }
    if (encoded[offset + size] != 13 || encoded[offset + size + 1] != 10) {
      throw const FormatException(
        'Invalid EndlessNet service event stream chunk.',
      );
    }
    decoded.add(encoded.sublist(offset, offset + size));
    offset += size + 2;
  }
  return decoded.takeBytes();
}

int? _contentLengthResponseBytes(Uint8List raw) {
  final headerEnd = _indexOf(raw, const [13, 10, 13, 10]);
  if (headerEnd < 0 || headerEnd > 64 * 1024) {
    return null;
  }
  final headerText = ascii.decode(
    raw.sublist(0, headerEnd),
    allowInvalid: false,
  );
  int? contentLength;
  for (final line in headerText.split('\r\n').skip(1)) {
    final colon = line.indexOf(':');
    if (colon <= 0) {
      continue;
    }
    if (line.substring(0, colon).trim().toLowerCase() != 'content-length') {
      continue;
    }
    if (contentLength != null) {
      throw const FormatException(
        'Duplicate Content-Length in EndlessNet service response.',
      );
    }
    contentLength = int.tryParse(line.substring(colon + 1).trim());
    if (contentLength == null || contentLength < 0) {
      throw const FormatException(
        'Invalid Content-Length in EndlessNet service response.',
      );
    }
  }
  if (contentLength == null) {
    return null;
  }
  return headerEnd + 4 + contentLength;
}

class NamedPipeHttpResponse {
  const NamedPipeHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Uint8List body;
}

NamedPipeHttpResponse parseNamedPipeHttpResponse(Uint8List raw) {
  final headerEnd = _indexOf(raw, const [13, 10, 13, 10]);
  if (headerEnd < 0 || headerEnd > 64 * 1024) {
    throw const FormatException(
      'Invalid EndlessNet service HTTP response headers.',
    );
  }
  final headerText = ascii.decode(
    raw.sublist(0, headerEnd),
    allowInvalid: false,
  );
  final lines = headerText.split('\r\n');
  final status = RegExp(
    r'^HTTP/1\.[01] ([0-9]{3})(?: |$)',
  ).firstMatch(lines.first);
  if (status == null) {
    throw const FormatException('Invalid EndlessNet service HTTP status line.');
  }
  final headers = <String, String>{};
  for (final line in lines.skip(1)) {
    final separator = line.indexOf(':');
    if (separator <= 0) {
      throw const FormatException('Invalid EndlessNet service HTTP header.');
    }
    headers[line.substring(0, separator).trim().toLowerCase()] = line
        .substring(separator + 1)
        .trim();
  }
  var body = Uint8List.fromList(raw.sublist(headerEnd + 4));
  if (headers['transfer-encoding']?.toLowerCase() == 'chunked') {
    body = _decodeChunkedBody(body);
  } else if (headers['content-length'] case final value?) {
    final length = int.tryParse(value);
    if (length == null || length < 0 || body.length < length) {
      throw const FormatException(
        'Invalid EndlessNet service HTTP content length.',
      );
    }
    body = Uint8List.fromList(body.sublist(0, length));
  }
  if (body.length > _maxResponseBytes) {
    throw const FormatException(
      'EndlessNet service IPC response is too large.',
    );
  }
  return NamedPipeHttpResponse(
    statusCode: int.parse(status.group(1)!),
    headers: headers,
    body: body,
  );
}

Uint8List _decodeChunkedBody(Uint8List encoded) {
  final decoded = BytesBuilder(copy: false);
  var offset = 0;
  while (true) {
    final lineEnd = _indexOf(encoded, const [13, 10], start: offset);
    if (lineEnd < 0) {
      throw const FormatException(
        'Invalid chunked EndlessNet service response.',
      );
    }
    final sizeText = ascii
        .decode(encoded.sublist(offset, lineEnd))
        .split(';')
        .first
        .trim();
    final size = int.tryParse(sizeText, radix: 16);
    if (size == null || size < 0) {
      throw const FormatException(
        'Invalid chunk size from EndlessNet service.',
      );
    }
    offset = lineEnd + 2;
    if (size == 0) {
      return decoded.takeBytes();
    }
    if (offset + size + 2 > encoded.length ||
        encoded[offset + size] != 13 ||
        encoded[offset + size + 1] != 10) {
      throw const FormatException(
        'Truncated chunked EndlessNet service response.',
      );
    }
    decoded.add(encoded.sublist(offset, offset + size));
    if (decoded.length > _maxResponseBytes) {
      throw const FormatException(
        'EndlessNet service IPC response is too large.',
      );
    }
    offset += size + 2;
  }
}

int _indexOf(Uint8List data, List<int> needle, {int start = 0}) {
  for (var i = start; i <= data.length - needle.length; i++) {
    var matches = true;
    for (var j = 0; j < needle.length; j++) {
      if (data[i + j] != needle[j]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return i;
    }
  }
  return -1;
}

Map<String, dynamic> _decodeObject(Uint8List raw) {
  final decoded = jsonDecode(utf8.decode(raw));
  if (decoded is Map<String, dynamic>) {
    return decoded;
  }
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  throw const FormatException('EndlessNet service returned non-object JSON.');
}

void validateIPCEnvelope(
  Map<String, dynamic> payload, {
  required bool requireNegotiated,
}) {
  if (payload['ipc_protocol'] != ServiceIPCMetadata.protocol) {
    throw const FormatException(
      'EndlessNet service returned an unsupported IPC protocol.',
    );
  }
  if (payload['ipc_version'] != ServiceIPCMetadata.version ||
      payload['ipc_min_supported_version'] !=
          ServiceIPCMetadata.minimumSupportedVersion) {
    throw const FormatException(
      'EndlessNet service returned an unsupported IPC version range.',
    );
  }
  final negotiated = payload['ipc_negotiated_version'];
  if (requireNegotiated && negotiated != ServiceIPCMetadata.version) {
    throw const FormatException(
      'EndlessNet service did not negotiate the required IPC version.',
    );
  }
  if (negotiated != null && negotiated != ServiceIPCMetadata.version) {
    throw const FormatException(
      'EndlessNet service returned an unsupported negotiated IPC version.',
    );
  }
}

String _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return 'EndlessNet service request failed.';
}
