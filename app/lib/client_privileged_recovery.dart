import 'dart:convert';

import 'package:endlessnet_client_api/client_api.dart' as api;

import 'client_operation.dart';

/// No process outcome confirms the requested runtime effect. Even exit zero
/// must be followed by authenticated operation lookup when stdout is unavailable.
enum ClientElevationOutcome { exited, canceled, unconfirmed }

/// Public, immutable arguments for the fixed installed helper. No endpoint,
/// file path, credential or executable can be supplied through this request.
final class ClientPrivilegedRecovery {
  ClientPrivilegedRecovery._(
    this.kind,
    api.MutationContext context,
    this.profileId,
    List<String> confirmation,
  ) : mutation = (api.MutationContext.fromBuffer(context.writeToBuffer())
        ..freeze()),
      _confirmation = List.unmodifiable(confirmation) {
    if (!RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(mutation.requestId) ||
        mutation.requestId.replaceAll('-', '').replaceAll('0', '').isEmpty ||
        mutation.expectedInstanceId.isEmpty ||
        mutation.expectedRevision <= 0 ||
        profileId.trim().isEmpty) {
      throw const FormatException(
        'Recovery requires a retained request and snapshot context',
      );
    }
  }

  factory ClientPrivilegedRecovery.trust(
    api.TrustServerIdentityRequest request,
  ) {
    if (request.confirmedControlOrigin.trim().isEmpty ||
        request.confirmedKeyId.trim().isEmpty ||
        !RegExp(
          r'^[0-9a-fA-F]{64}$',
        ).hasMatch(request.confirmedAnnouncementId)) {
      throw const FormatException('Complete identity confirmation is required');
    }
    return ClientPrivilegedRecovery._(
      api.OperationKind.OPERATION_KIND_TRUST_SERVER_IDENTITY,
      request.mutation,
      request.profile.profileId,
      [
        '--confirmed-control-origin',
        request.confirmedControlOrigin,
        '--confirmed-key-id',
        request.confirmedKeyId,
        '--confirmed-announcement-id',
        request.confirmedAnnouncementId,
      ],
    );
  }

  factory ClientPrivilegedRecovery.forget(
    api.ForgetLocalEnrollmentRequest request,
  ) {
    if (!request.confirmed) {
      throw const FormatException('Local cleanup must be confirmed');
    }
    return ClientPrivilegedRecovery._(
      api.OperationKind.OPERATION_KIND_FORGET_LOCAL_ENROLLMENT,
      request.mutation,
      request.profile.profileId,
      ['--confirmed-local-forget'],
    );
  }

  final api.OperationKind kind;
  final api.MutationContext mutation;
  final String profileId;
  final List<String> _confirmation;

  List<String> get arguments => List.unmodifiable([
    '--operation',
    kind == api.OperationKind.OPERATION_KIND_TRUST_SERVER_IDENTITY
        ? 'trust-server-identity'
        : 'forget-local-enrollment',
    '--request-id',
    mutation.requestId,
    '--profile-id',
    profileId,
    '--expected-instance-id',
    mutation.expectedInstanceId,
    '--expected-revision',
    mutation.expectedRevision.toString(),
    ..._confirmation,
  ]);

  /// Exit zero means a validated operation response, not completed recovery.
  /// Missing/failed output leaves the session's original intention recoverable.
  ClientOperation decodeResult(int exitCode, String output) {
    if (output.length > 1024 * 1024) {
      throw const FormatException('Oversized helper response');
    }
    try {
      final json = jsonDecode(output);
      if (exitCode != 0) {
        final failure = api.Failure()..mergeFromProto3Json(json);
        if (failure.code == api.ErrorCode.ERROR_CODE_UNSPECIFIED) {
          throw const FormatException();
        }
        throw ClientPrivilegedFailure(failure.code);
      }
      final value = api.Operation()..mergeFromProto3Json(json);
      return validateOperation(ClientOperation.fromProto(value));
    } on ClientPrivilegedFailure {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Invalid helper response; recover the retained intention',
      );
    }
  }

  ClientOperation validateOperation(ClientOperation operation) {
    final value = operation.value;
    if (value.requestId != mutation.requestId ||
        value.kind != kind ||
        value.profileId != profileId ||
        !value.hasMetadata() ||
        value.metadata.instanceId != mutation.expectedInstanceId ||
        value.metadata.revision < mutation.expectedRevision) {
      throw const FormatException(
        'Recovery operation does not match the retained context',
      );
    }
    return operation;
  }
}

final class ClientPrivilegedFailure implements Exception {
  const ClientPrivilegedFailure(this.code);
  final api.ErrorCode code;
  @override
  String toString() => 'Privileged recovery failed: ${code.name}';
}
