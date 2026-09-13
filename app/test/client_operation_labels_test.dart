import 'package:endlessnet/client_operation_labels.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('US-14 operation states and continuity retain distinct meanings', () {
    expect(api.OperationState.values.map(clientOperationStateLabel), [
      'Unknown',
      'Pending',
      'In progress',
      'Waiting for required action',
      'Completed',
      'Failed',
      'Cancelled',
    ]);
    expect(api.ConnectionContinuity.values.map(clientContinuityLabel), [
      'Unknown',
      'Not applicable',
      'Preserved',
      'Interrupted',
      'Unknown',
    ]);
    expect(api.ActionOwner.values.map(clientActionOwnerLabel), [
      'Unknown',
      'You',
      'Device administrator',
      'Access administrator',
      'Support',
    ]);
    expect(api.UserAction_Kind.values.map(clientRequiredActionLabel), [
      'Unknown',
      'Continue in your browser',
      'Wait for approval',
      'Grant VPN permission',
      'Use the privileged helper',
      'Contact your access administrator',
    ]);
  });
  test('US-14 every current failure code has a distinct safe label', () {
    expect(
      clientFailureLabel(api.ErrorCode.ERROR_CODE_UNSPECIFIED),
      'Unknown failure',
    );
    final labels = api.ErrorCode.values
        .skip(1)
        .map(clientFailureLabel)
        .toList();
    expect(labels.toSet().length, labels.length);
    for (final label in labels) {
      expect(label, isNotEmpty);
      expect(label, isNot('Unknown failure'));
      expect(label, isNot(contains('_')));
    }
    expect(
      clientFailureLabel(api.ErrorCode.ERROR_CODE_REMOTE_CLEANUP_REQUIRED),
      'Remote cleanup still required',
    );
    expect(
      clientFailureLabel(api.ErrorCode.ERROR_CODE_STALE_STATE),
      'Runtime state changed',
    );
    expect(
      clientFailureLabel(api.ErrorCode.ERROR_CODE_UNAVAILABLE),
      'Unavailable',
    );
  });
}
