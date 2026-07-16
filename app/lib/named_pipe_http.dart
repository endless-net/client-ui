import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

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
    if (parsed.statusCode < 200 || parsed.statusCode >= 300) {
      throw StateError(
        _firstNonEmpty([
          payload['error']?.toString(),
          payload['message']?.toString(),
          'EndlessNet service request failed with HTTP ${parsed.statusCode}.',
        ]),
      );
    }
    return payload;
  }
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
      }
      if (result.value) {
        if (read.value == 0) {
          break;
        }
        continue;
      }
      if (result.error == ERROR_BROKEN_PIPE) {
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

String _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return 'EndlessNet service request failed.';
}
