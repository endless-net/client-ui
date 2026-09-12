import 'package:endlessnet_client_api/client_api.dart' as api;

import 'client_runtime_snapshot.dart';

/// Validates one WatchEvents subscription. Reconnect must call this again with
/// a new source and discard domain caches; there is deliberately no resume ID.
/// An emitted event is a frozen copy, independent of transport buffer lifetime.
Stream<api.WatchEventsResponse> validateClientEvents(
  Stream<api.WatchEventsResponse> source,
) async* {
  api.WatchEventsResponse? previous;
  api.RuntimeInfo? runtime;
  await for (final input in source) {
    final event = api.WatchEventsResponse.fromBuffer(input.writeToBuffer());
    if (previous == null) {
      runtime = ClientRuntimeSnapshot.fromEvent(event).runtime;
    } else {
      if (!event.hasMetadata() ||
          event.sequence <= previous.sequence ||
          event.metadata.instanceId != runtime!.instanceId ||
          event.metadata.revision < previous.metadata.revision) {
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
        final operation = event.operationChanged;
        if (runtime.callerAccess == api.Access.ACCESS_OBSERVER ||
            operation.id.isEmpty ||
            operation.kind == api.OperationKind.OPERATION_KIND_UNSPECIFIED ||
            operation.state == api.OperationState.OPERATION_STATE_UNSPECIFIED) {
          throw const FormatException('Invalid v0 operation event');
        }
      } else if (event.hasSessionChanged()) {
        if (runtime.callerAccess == api.Access.ACCESS_OBSERVER) {
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
    yield event;
  }
  // EOF is not a healthy subscription, even if the last status was Connected.
  throw const ClientEventStreamEnded();
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
