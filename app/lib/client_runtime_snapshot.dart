import 'package:endlessnet_client_api/client_api.dart' as api;

import 'client_operation.dart';

/// Validated, immutable v0 snapshot. This is not a transport or runtime emulator.
/// Callers must discard this value when the stream or caller context changes.
final class ClientRuntimeSnapshot {
  ClientRuntimeSnapshot._(this.runtime, this.status);

  final api.RuntimeInfo runtime;
  final api.Status status;

  factory ClientRuntimeSnapshot.fromEvent(
    api.WatchEventsResponse event, {
    bool initial = true,
  }) {
    if ((initial ? event.sequence != 1 : event.sequence <= 0) ||
        !event.hasSnapshot() ||
        !event.hasMetadata() ||
        !event.snapshot.hasRuntime() ||
        !event.snapshot.hasStatus()) {
      throw const FormatException('Expected initial v0 snapshot');
    }
    final runtime = event.snapshot.runtime;
    final status = event.snapshot.status;
    if (runtime.protocol != api.ClientContract.protocol ||
        runtime.ipcVersion != api.ClientContract.version ||
        runtime.contractSha256 != api.ClientContract.sha256 ||
        runtime.instanceId.isEmpty ||
        runtime.callerAccess == api.Access.ACCESS_UNSPECIFIED) {
      throw const FormatException('Incompatible v0 runtime identity');
    }
    if (!status.hasMetadata() ||
        event.metadata.revision <= 0 ||
        event.metadata.instanceId != runtime.instanceId ||
        status.metadata.instanceId != runtime.instanceId ||
        status.metadata.revision != event.metadata.revision) {
      throw const FormatException('Inconsistent v0 snapshot metadata');
    }
    for (final operation in status.currentOperations) {
      if (ClientOperation.fromProto(operation).terminal) {
        throw const FormatException('Invalid current operation');
      }
    }
    if (runtime.callerAccess == api.Access.ACCESS_OBSERVER &&
        status.currentOperations.isNotEmpty) {
      throw const FormatException('Observer snapshot disclosed operations');
    }
    return ClientRuntimeSnapshot._(
      api.RuntimeInfo.fromBuffer(runtime.writeToBuffer())..freeze(),
      api.Status.fromBuffer(status.writeToBuffer())..freeze(),
    );
  }

  /// Missing capability is unsupported, never implicitly available.
  bool supports(api.Capability capability) => runtime.capabilities.any(
    (entry) =>
        entry.capability == capability &&
        entry.restriction.availability ==
            api.Availability.AVAILABILITY_AVAILABLE,
  );

  /// The application persists this UUID before submission. Authorization,
  /// initial ownership claims and durable deduplication remain producer-owned.
  api.MutationContext mutationContext(String requestId) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(requestId)) {
      throw const FormatException('Mutation requires a UUID request ID');
    }
    return api.MutationContext(
      requestId: requestId,
      expectedInstanceId: runtime.instanceId,
      expectedRevision: status.metadata.revision,
    );
  }
}
