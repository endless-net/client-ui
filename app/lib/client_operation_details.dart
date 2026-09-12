import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'client_operation.dart';

/// Render only typed result fields. Never serialize a whole operation: browser
/// URLs and future sensitive fields must not leak into diagnostic output.
class ClientOperationDetails extends StatelessWidget {
  const ClientOperationDetails({super.key, required this.operation});
  final ClientOperation operation;

  @override
  Widget build(BuildContext context) {
    final value = operation.value;
    final lines = <String>[value.state.name];
    if (value.continuity !=
        api.ConnectionContinuity.CONNECTION_CONTINUITY_UNSPECIFIED) {
      lines.add('Connection continuity: ${value.continuity.name}');
    }
    switch (value.whichOutcome()) {
      case api.Operation_Outcome.failure:
        lines.add('Failure: ${value.failure.code.name}');
        lines.add('Action owner: ${value.failure.actionOwner.name}');
        lines.add(
          value.failure.retryable
              ? 'Retry may be possible; no command has been replayed.'
              : 'Do not automatically retry this operation.',
        );
        if (value.failure.controlRequestId.isNotEmpty) {
          lines.add('Control request: ${value.failure.controlRequestId}');
        }
      case api.Operation_Outcome.change:
        lines.add(
          value.change.changed
              ? 'Change reported by service.'
              : 'No change reported by service.',
        );
      case api.Operation_Outcome.enrollment:
        lines.add('Enrollment profile: ${value.enrollment.profileId}');
        lines.add('Enrollment node: ${value.enrollment.nodeId}');
      case api.Operation_Outcome.selection:
        lines.add(
          value.selection.selectedId.isEmpty
              ? 'Exit-node selection cleared.'
              : 'Result ID: ${value.selection.selectedId}',
        );
      case api.Operation_Outcome.cleanup:
        lines.add(switch (value.cleanup.outcome) {
          api.CleanupOutcome.CLEANUP_OUTCOME_REMOTE_CONFIRMED =>
            'Remote cleanup confirmed.',
          api.CleanupOutcome.CLEANUP_OUTCOME_REMOTE_UNCONFIRMED =>
            'Remote cleanup NOT confirmed.',
          api.CleanupOutcome.CLEANUP_OUTCOME_NOT_REGISTERED =>
            'No registration to clean up.',
          _ => 'Remote cleanup outcome unknown.',
        });
        lines.add(
          value.cleanup.localRegistrationRemoved
              ? 'Local registration removed.'
              : 'Local registration not reported removed.',
        );
        if (value.cleanup.controlRequestId.isNotEmpty) {
          lines.add('Control request: ${value.cleanup.controlRequestId}');
        }
      case api.Operation_Outcome.renewal:
        // The status stream remains authoritative for active session state.
        lines.add('Session renewal result received. Refresh session status.');
      case api.Operation_Outcome.bundle:
        lines.add('Diagnostics bundle ready: ${value.bundle.sizeBytes} bytes.');
        lines.add('Download requires the caller-bound bundle RPC.');
      case api.Operation_Outcome.notSet:
        if (value.hasUserAction()) {
          lines.add('Required action: ${value.userAction.kind.name}');
        }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final line in lines) Text(line)],
    );
  }
}
