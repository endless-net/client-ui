import 'package:endlessnet_client_api/client_api.dart' as api;
import 'client_operation.dart';
import 'client_privileged_recovery.dart';
import 'client_session.dart';
import 'client_state_controller.dart';

extension ClientPrivilegedSession on ClientSession {
  /// ShellExecute/UAC does not provide a trusted stdout channel. Reconcile by
  /// the original request ID using the caller's authenticated local connection.
  /// A failed wait/exit can still mean accepted work; it never causes a replay.
  Future<ClientOperation> submitPrivilegedViaLookup(
    api.OperationKind kind,
    ClientPrivilegedRecovery Function(api.MutationContext) prepare,
    Future<ClientElevationOutcome> Function(ClientPrivilegedRecovery) launch,
  ) => submit(kind, (commands, mutation) async {
    final contextEpoch = state.contextEpoch;
    if (state.snapshot!.runtime.callerAccess == api.Access.ACCESS_OBSERVER) {
      throw StateError('Privileged recovery requires the local owner context');
    }
    final request = prepare(mutation);
    if (request.kind != kind ||
        request.mutation != mutation ||
        request.profileId != state.snapshot!.status.activeProfileId) {
      throw StateError(
        'Privileged request does not match the retained context',
      );
    }
    final outcome = await launch(request);
    if (outcome == ClientElevationOutcome.canceled) {
      throw StateError('Elevation canceled; no runtime outcome is confirmed');
    }
    if (state.link != ClientLinkState.ready ||
        state.contextEpoch != contextEpoch) {
      throw StateError(
        'Client context changed during elevation; recover the intention',
      );
    }
    return request.validateOperation(
      await commands.recoverByRequestId(mutation.requestId, kind),
    );
  });
}
