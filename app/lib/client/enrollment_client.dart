import 'package:endlessnet_client_api/client_api.dart' as api;

// Adapter обязан применять deadline/cancellation к настоящему IPC call. Здесь
// только producer DTO; verified Windows pipe/channel подключается отдельно.
abstract interface class EnrollmentClient {
  Future<api.RuntimeInfo> runtimeInfo(Duration timeout);
  Future<api.Status> status(Duration timeout);
  Future<api.GetServerIdentityResponse> serverIdentity(
    api.GetServerIdentityRequest request,
    Duration timeout,
  );
  Future<api.ChangeResult> trustIdentity(
    api.TrustServerIdentityRequest request,
    Duration timeout,
  );
  Future<api.EnrollmentAttempt> enroll(
    api.EnrollRequest request,
    Duration timeout,
  );
  Future<api.ListEnrollmentTargetsResponse> targets(
    api.ListEnrollmentTargetsRequest request,
    Duration timeout,
  );
  Future<api.EnrollmentAttempt> select(
    api.SelectEnrollmentTargetRequest request,
    Duration timeout,
  );
  Future<api.EnrollmentAttempt> cancel(
    api.CancelEnrollmentAttemptRequest request,
    Duration timeout,
  );
  Future<api.EnrollmentAttempt> attempt(
    api.GetEnrollmentAttemptRequest request,
    Duration timeout,
  );
}

// Только UI correlation, никогда native grants, ключи или server credentials.
final class EnrollmentCorrelation {
  const EnrollmentCorrelation({
    required this.profileId,
    required this.controlOrigin,
    required this.requestId,
    required this.hostname,
    required this.mode,
    this.recoveryDeadline,
  });

  final String profileId;
  final String controlOrigin;
  final String requestId;
  final String hostname;
  final api.EnrollmentMode mode;
  final DateTime? recoveryDeadline;

  EnrollmentCorrelation uncertainUntil(DateTime deadline) =>
      EnrollmentCorrelation(
        profileId: profileId,
        controlOrigin: controlOrigin,
        requestId: requestId,
        hostname: hostname,
        mode: mode,
        recoveryDeadline:
            recoveryDeadline == null || deadline.isBefore(recoveryDeadline!)
            ? deadline
            : recoveryDeadline,
      );
}

abstract interface class CorrelationStore {
  Future<EnrollmentCorrelation?> read(String profileId, String controlOrigin);
  // Future завершается только после durable save. Ошибка запрещает Enroll.
  Future<void> save(EnrollmentCorrelation correlation);
}
