import 'dart:async';

import 'package:endlessnet_client_api/client_api.dart' as api;

import 'client_runtime_snapshot.dart';
import 'client_operation.dart';

/// A fresh validator per subscription. Event transformation forwards pause and
/// cancellation directly to the source, even while no new event is arriving.
Stream<api.WatchEventsResponse> validateClientEvents(
  Stream<api.WatchEventsResponse> source,
) => Stream<api.WatchEventsResponse>.eventTransformed(
  source,
  (sink) => _ClientEventValidator(sink),
);

final class _ClientEventValidator
    implements EventSink<api.WatchEventsResponse> {
  _ClientEventValidator(this.sink);
  final EventSink<api.WatchEventsResponse> sink;
  api.WatchEventsResponse? previous;
  api.RuntimeInfo? runtime;
  bool closed = false;

  @override
  void add(api.WatchEventsResponse input) {
    if (closed) return;
    try {
      _accept(input);
    } catch (error, stack) {
      addError(error, stack);
    }
  }

  void _accept(api.WatchEventsResponse input) {
    final event = api.WatchEventsResponse.fromBuffer(input.writeToBuffer());
    if (previous == null) {
      runtime = ClientRuntimeSnapshot.fromEvent(event).runtime;
    } else {
      if (!event.hasMetadata() ||
          event.sequence <= previous!.sequence ||
          event.metadata.instanceId != runtime!.instanceId ||
          event.metadata.revision < previous!.metadata.revision) {
        throw const FormatException('Invalid v0 stream ordering or context');
      }
      if (event.hasSnapshot()) {
        runtime = ClientRuntimeSnapshot.fromEvent(
          event,
          initial: false,
        ).runtime;
      } else if (event.hasStatusChanged()) {
        // Full status, not a partial delta. Validate against the current caller.
        ClientRuntimeSnapshot.fromEvent(
          api.WatchEventsResponse(
            sequence: event.sequence,
            metadata: event.metadata,
            snapshot: api.SnapshotEvent(
              runtime: runtime,
              status: event.statusChanged,
            ),
          ),
          initial: false,
        );
      } else if (event.hasOperationChanged()) {
        ClientOperation.fromProto(event.operationChanged);
        if (runtime!.callerAccess == api.Access.ACCESS_OBSERVER) {
          throw const FormatException('Invalid v0 operation event');
        }
      } else if (event.hasSessionChanged()) {
        if (runtime!.callerAccess == api.Access.ACCESS_OBSERVER) {
          throw const FormatException('Observer stream disclosed session');
        }
      } else if (event.hasInvalidated()) {
        if (event.invalidated.domain == api.Domain.DOMAIN_UNSPECIFIED) {
          throw const FormatException('Invalid v0 domain invalidation');
        }
      } else if (!event.hasFailure()) {
        throw const FormatException('Missing v0 event payload');
      }
    }
    if (event.hasFailure()) {
      if (event.failure.code == api.ErrorCode.ERROR_CODE_UNSPECIFIED) {
        throw const FormatException('Missing v0 stream failure code');
      }
      throw ClientEventFailure(event.failure);
    }
    previous = event..freeze();
    sink.add(event);
  }

  @override
  void addError(Object error, [StackTrace? stack]) {
    if (closed) return;
    closed = true;
    sink.addError(error, stack);
    sink.close();
  }

  @override
  void close() {
    if (closed) return;
    addError(const ClientEventStreamEnded());
  }
}

final class ClientEventFailure implements Exception {
  ClientEventFailure(api.Failure source)
    : failure = (api.Failure.fromBuffer(source.writeToBuffer())..freeze());

  final api.Failure failure;

  @override
  String toString() => 'Client event stream failed';
}

final class ClientEventStreamEnded implements Exception {
  const ClientEventStreamEnded();

  @override
  String toString() => 'Client event stream ended; fresh snapshot required';
}
