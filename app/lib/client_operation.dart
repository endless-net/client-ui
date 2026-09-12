import 'package:endlessnet_client_api/client_api.dart' as api;

/// Consumer validation of the producer's operation envelope. This does not
/// prove that the requested effect happened in the OS or control plane.
final class ClientOperation {
  ClientOperation._(this.value);

  final api.Operation value;

  static final _successOutcomes = <api.OperationKind, api.Operation_Outcome>{
    api.OperationKind.OPERATION_KIND_ENROLL: api.Operation_Outcome.enrollment,
    api.OperationKind.OPERATION_KIND_CONNECT: api.Operation_Outcome.change,
    api.OperationKind.OPERATION_KIND_DISCONNECT: api.Operation_Outcome.change,
    api.OperationKind.OPERATION_KIND_TRUST_SERVER_IDENTITY:
        api.Operation_Outcome.change,
    api.OperationKind.OPERATION_KIND_LOGOUT: api.Operation_Outcome.cleanup,
    api.OperationKind.OPERATION_KIND_FORGET_LOCAL_ENROLLMENT:
        api.Operation_Outcome.cleanup,
    api.OperationKind.OPERATION_KIND_SELECT_NETWORK:
        api.Operation_Outcome.selection,
    api.OperationKind.OPERATION_KIND_CREATE_DIAGNOSTICS_BUNDLE:
        api.Operation_Outcome.bundle,
    api.OperationKind.OPERATION_KIND_CREATE_PROFILE:
        api.Operation_Outcome.selection,
    api.OperationKind.OPERATION_KIND_SELECT_PROFILE:
        api.Operation_Outcome.selection,
    api.OperationKind.OPERATION_KIND_RENAME_PROFILE:
        api.Operation_Outcome.change,
    api.OperationKind.OPERATION_KIND_REMOVE_PROFILE:
        api.Operation_Outcome.change,
    api.OperationKind.OPERATION_KIND_RENEW_SESSION:
        api.Operation_Outcome.renewal,
    api.OperationKind.OPERATION_KIND_SELECT_EXIT_NODE:
        api.Operation_Outcome.selection,
    api.OperationKind.OPERATION_KIND_CLEAR_EXIT_NODE:
        api.Operation_Outcome.selection,
    api.OperationKind.OPERATION_KIND_SET_PREFERENCES:
        api.Operation_Outcome.change,
    api.OperationKind.OPERATION_KIND_RESET_PREFERENCES:
        api.Operation_Outcome.change,
    api.OperationKind.OPERATION_KIND_SET_RESOURCE_ENABLED:
        api.Operation_Outcome.change,
    api.OperationKind.OPERATION_KIND_NOTIFY_LIFECYCLE:
        api.Operation_Outcome.change,
  };

  factory ClientOperation.fromProto(api.Operation source) {
    final value = api.Operation.fromBuffer(source.writeToBuffer());
    if (value.id.isEmpty || !_successOutcomes.containsKey(value.kind)) {
      throw const FormatException('Invalid v0 operation identity or kind');
    }
    final outcome = value.whichOutcome();
    if (value.hasUserAction() &&
        value.state != api.OperationState.OPERATION_STATE_WAITING_FOR_USER) {
      throw const FormatException('User action is only valid while waiting');
    }
    switch (value.state) {
      case api.OperationState.OPERATION_STATE_PENDING:
      case api.OperationState.OPERATION_STATE_RUNNING:
      case api.OperationState.OPERATION_STATE_WAITING_FOR_USER:
        if (outcome != api.Operation_Outcome.notSet) {
          throw const FormatException('Nonterminal operation has an outcome');
        }
        if (value.state ==
                api.OperationState.OPERATION_STATE_WAITING_FOR_USER &&
            (!value.hasUserAction() ||
                value.userAction.kind ==
                    api.UserAction_Kind.KIND_UNSPECIFIED)) {
          throw const FormatException('Waiting operation lacks a typed action');
        }
      case api.OperationState.OPERATION_STATE_FAILED:
      case api.OperationState.OPERATION_STATE_CANCELLED:
        if (outcome != api.Operation_Outcome.failure ||
            value.failure.code == api.ErrorCode.ERROR_CODE_UNSPECIFIED) {
          throw const FormatException('Failed operation lacks a typed failure');
        }
      case api.OperationState.OPERATION_STATE_SUCCEEDED:
        if (value.continuity ==
            api.ConnectionContinuity.CONNECTION_CONTINUITY_UNSPECIFIED) {
          throw const FormatException('Success lacks explicit continuity');
        }
        if (outcome != _successOutcomes[value.kind]) {
          throw const FormatException(
            'Success outcome does not match operation kind',
          );
        }
        if (outcome == api.Operation_Outcome.selection &&
            value.kind != api.OperationKind.OPERATION_KIND_CLEAR_EXIT_NODE &&
            value.selection.selectedId.isEmpty) {
          throw const FormatException('Selection success lacks an ID');
        }
      default:
        throw const FormatException('Invalid v0 operation state');
    }
    return ClientOperation._(value..freeze());
  }

  bool get terminal => {
    api.OperationState.OPERATION_STATE_SUCCEEDED,
    api.OperationState.OPERATION_STATE_FAILED,
    api.OperationState.OPERATION_STATE_CANCELLED,
  }.contains(value.state);

  bool get succeeded =>
      value.state == api.OperationState.OPERATION_STATE_SUCCEEDED;
}
