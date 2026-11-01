import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:grpc/grpc.dart' as grpc;

// Только safe code и producer Failure; raw message/trailers/details не сохраняются.
final class ClientCallFailure implements Exception {
  ClientCallFailure._(this.transportCode, this._failure);

  factory ClientCallFailure.fromGrpc(
    grpc.GrpcError error,
    int maxFailureBytes,
  ) {
    api.Failure? selected;
    var count = 0;
    if ((error.details?.length ?? 0) <= 16) {
      for (final detail in error.details ?? const []) {
        api.Failure? value;
        try {
          // grpc5.1.0 decodes wire details into its own non-exported Any
          // class. Public protobuf reflection recognizes the standard WKT;
          // no import from grpc/src or duplicate Client/google.rpc DTO.
          if (detail.info_.qualifiedMessageName == 'google.protobuf.Any' &&
              detail.getField(1) == 'type.googleapis.com/client.v0.Failure') {
            count++;
            final payload = detail.getField(2);
            if (payload is List<int> && payload.length <= maxFailureBytes) {
              value = api.Failure.fromBuffer(payload);
            }
          } else if (detail is api.Failure) {
            count++;
            final bytes = detail.writeToBuffer();
            if (bytes.length <= maxFailureBytes) {
              value = api.Failure.fromBuffer(bytes);
            }
          }
        } catch (_) {
          count++;
        }
        if (value != null &&
            value.code != api.ErrorCode.ERROR_CODE_UNSPECIFIED &&
            RegExp(r'^[a-z][a-z0-9_.-]{0,127}$').hasMatch(value.reasonKey)) {
          selected = value;
        }
      }
    }
    return ClientCallFailure._(error.code, count == 1 ? selected : null);
  }

  factory ClientCallFailure.protocol() =>
      ClientCallFailure._(grpc.StatusCode.dataLoss, null);
  final int transportCode;
  final api.Failure? _failure;
  api.Failure? get failure => _failure == null
      ? null
      : api.Failure.fromBuffer(_failure.writeToBuffer());

  // Rejection этой invocation не доказывает отсутствие ранее committed Node.
  // Deadline/cancel/unavailable/internal всегда остаются unknown outcome.
  bool get definiteRejection => const {
    grpc.StatusCode.invalidArgument,
    grpc.StatusCode.unauthenticated,
    grpc.StatusCode.permissionDenied,
    grpc.StatusCode.failedPrecondition,
    grpc.StatusCode.aborted,
    grpc.StatusCode.resourceExhausted,
    grpc.StatusCode.unimplemented,
  }.contains(transportCode);

  String get reasonKey =>
      _failure?.reasonKey ??
      switch (transportCode) {
        grpc.StatusCode.permissionDenied ||
        grpc.StatusCode.unauthenticated => 'ui.permission_required',
        grpc.StatusCode.aborted => 'ui.stale_state',
        grpc.StatusCode.invalidArgument => 'ui.invalid_argument',
        grpc.StatusCode.unimplemented => 'ui.unsupported',
        _ => 'ui.client_rejected',
      };

  @override
  String toString() => 'ClientCallFailure';
}
