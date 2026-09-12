import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http2/transport.dart';

/// Deterministic transport probe, with no socket, Go host or timing race.
/// Exit 1 means late response headers still kill the shared connection.
Future<void> main() async {
  final incoming = StreamController<List<int>>();
  final outgoing = StreamController<List<int>>();
  final bytes = <int>[];
  final output = outgoing.stream.listen(bytes.addAll);
  final client = ClientTransportConnection.viaStreams(
    incoming.stream,
    outgoing.sink,
  );
  final frames = StreamIterator(client.onFrameReceived);
  final initialFrame = frames.moveNext();
  // Empty server SETTINGS frame.
  incoming.add([0, 0, 0, 4, 0, 0, 0, 0, 0]);
  await client.onInitialPeerSettingsReceived;
  await initialFrame;
  final stream = client.makeRequest([
    Header.ascii(':method', 'POST'),
    Header.ascii(':scheme', 'http'),
    Header.ascii(':authority', 'synthetic.local'),
    Header.ascii(':path', '/probe'),
  ], endStream: true);
  stream.terminate();
  // HPACK indexed :status=200, END_HEADERS | END_STREAM on the canceled ID.
  // Headers were already in flight when the peer received our RST_STREAM.
  incoming.add([0, 0, 1, 1, 5, 0, 0, 0, stream.id, 0x88]);
  await frames.moveNext().timeout(const Duration(seconds: 2));
  var survived = client.isOpen;
  if (survived) {
    final next = client.makeRequest([
      Header.ascii(':method', 'POST'),
      Header.ascii(':scheme', 'http'),
      Header.ascii(':authority', 'synthetic.local'),
      Header.ascii(':path', '/next'),
    ], endStream: true);
    final response = next.incomingMessages.toList();
    incoming.add([0, 0, 1, 1, 5, 0, 0, 0, next.id, 0x88]);
    final messages = await response.timeout(const Duration(seconds: 2));
    survived = messages.length == 1 && messages.single is HeadersStreamMessage;
  }
  await client.terminate();
  await frames.cancel();
  await incoming.close();
  await output.cancel();

  // The client preface is 24 bytes. Decode only synthetic GOAWAY debug text.
  for (var offset = 24; offset + 9 <= bytes.length;) {
    final length =
        (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
    final end = offset + 9 + length;
    if (end > bytes.length) break;
    if (bytes[offset + 3] == 7 && length >= 8) {
      stdout.writeln(utf8.decode(bytes.sublist(offset + 17, end)));
    }
    offset = end;
  }
  stdout.writeln('Connection survived canceled-stream headers: $survived');
  exitCode = survived ? 0 : 1;
}
