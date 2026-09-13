import 'package:endlessnet_client_api/client_api.dart' as api;

// Closed producer enums only. Never derive UI text from arbitrary reason keys,
// transport messages or an enum's wire name.
String clientOperationStateLabel(api.OperationState state) => switch (state) {
  api.OperationState.OPERATION_STATE_PENDING => 'Pending',
  api.OperationState.OPERATION_STATE_RUNNING => 'In progress',
  api.OperationState.OPERATION_STATE_WAITING_FOR_USER =>
    'Waiting for required action',
  api.OperationState.OPERATION_STATE_SUCCEEDED => 'Completed',
  api.OperationState.OPERATION_STATE_FAILED => 'Failed',
  api.OperationState.OPERATION_STATE_CANCELLED => 'Cancelled',
  _ => 'Unknown',
};

String clientContinuityLabel(api.ConnectionContinuity value) => switch (value) {
  api.ConnectionContinuity.CONNECTION_CONTINUITY_NOT_APPLICABLE =>
    'Not applicable',
  api.ConnectionContinuity.CONNECTION_CONTINUITY_PRESERVED => 'Preserved',
  api.ConnectionContinuity.CONNECTION_CONTINUITY_INTERRUPTED => 'Interrupted',
  _ => 'Unknown',
};

String clientActionOwnerLabel(api.ActionOwner value) => switch (value) {
  api.ActionOwner.ACTION_OWNER_USER => 'You',
  api.ActionOwner.ACTION_OWNER_DEVICE_ADMINISTRATOR => 'Device administrator',
  api.ActionOwner.ACTION_OWNER_ACCESS_ADMINISTRATOR => 'Access administrator',
  api.ActionOwner.ACTION_OWNER_SUPPORT => 'Support',
  _ => 'Unknown',
};

String clientRequiredActionLabel(api.UserAction_Kind value) => switch (value) {
  api.UserAction_Kind.KIND_OPEN_BROWSER => 'Continue in your browser',
  api.UserAction_Kind.KIND_WAIT_FOR_APPROVAL => 'Wait for approval',
  api.UserAction_Kind.KIND_GRANT_VPN_PERMISSION => 'Grant VPN permission',
  api.UserAction_Kind.KIND_USE_PRIVILEGED_HELPER => 'Use the privileged helper',
  api.UserAction_Kind.KIND_CONTACT_ACCESS_ADMINISTRATOR =>
    'Contact your access administrator',
  _ => 'Unknown',
};

String clientFailureLabel(api.ErrorCode value) => switch (value) {
  api.ErrorCode.ERROR_CODE_INVALID_ARGUMENT => 'Invalid input',
  api.ErrorCode.ERROR_CODE_UNAUTHENTICATED => 'Authentication required',
  api.ErrorCode.ERROR_CODE_OWNER_REQUIRED => 'Installation owner required',
  api.ErrorCode.ERROR_CODE_ADMINISTRATOR_REQUIRED =>
    'Device administrator required',
  api.ErrorCode.ERROR_CODE_UNSUPPORTED => 'Not supported',
  api.ErrorCode.ERROR_CODE_NOT_FOUND => 'Not found',
  api.ErrorCode.ERROR_CODE_STALE_STATE => 'Runtime state changed',
  api.ErrorCode.ERROR_CODE_POLICY_BLOCKED => 'Blocked by policy',
  api.ErrorCode.ERROR_CODE_PERMISSION_REQUIRED => 'Permission required',
  api.ErrorCode.ERROR_CODE_BUSY => 'Runtime busy',
  api.ErrorCode.ERROR_CODE_LIMIT_EXCEEDED => 'Limit exceeded',
  api.ErrorCode.ERROR_CODE_UNAVAILABLE => 'Unavailable',
  api.ErrorCode.ERROR_CODE_DEADLINE_EXCEEDED => 'Request deadline exceeded',
  api.ErrorCode.ERROR_CODE_CANCELLED => 'Request cancelled',
  api.ErrorCode.ERROR_CODE_INTERNAL => 'Internal runtime error',
  api.ErrorCode.ERROR_CODE_NEEDS_ENROLLMENT => 'Device enrollment required',
  api.ErrorCode.ERROR_CODE_NEEDS_LOGIN => 'Login required',
  api.ErrorCode.ERROR_CODE_APPROVAL_REQUIRED => 'Approval required',
  api.ErrorCode.ERROR_CODE_APPROVAL_REJECTED => 'Approval rejected',
  api.ErrorCode.ERROR_CODE_SERVER_IDENTITY_CHANGED => 'Server identity changed',
  api.ErrorCode.ERROR_CODE_IDENTITY_CONFIRMATION_MISMATCH =>
    'Server identity confirmation no longer matches',
  api.ErrorCode.ERROR_CODE_REMOTE_CLEANUP_REQUIRED =>
    'Remote cleanup still required',
  api.ErrorCode.ERROR_CODE_LOCAL_FORGET_CONFIRMATION_REQUIRED =>
    'Local removal confirmation required',
  api.ErrorCode.ERROR_CODE_APPLY_FAILED => 'Runtime could not apply the change',
  api.ErrorCode.ERROR_CODE_PROFILE_ACTIVE => 'Profile is active',
  api.ErrorCode.ERROR_CODE_RESOURCE_CONFLICT => 'Resource conflict',
  api.ErrorCode.ERROR_CODE_CONTRACT_MISMATCH => 'Incompatible client contract',
  _ => 'Unknown failure',
};
