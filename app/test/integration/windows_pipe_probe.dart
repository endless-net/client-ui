import 'dart:io';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/client/call_failure.dart';
import 'package:endlessnet_client_ui/client/windows_pipe.dart';
import 'package:endlessnet_client_ui/client/windows_pipe_config.dart';
import 'package:grpc/grpc.dart' as grpc;

void require(bool value) {
  if (!value) throw StateError('Windows pipe probe failed');
}

// Invoked by Client's separate native Windows integration suite. Only controlled
// fixture values are accepted; this is not the production discovery/config path.
Future<void> main(List<String> args) async {
  require(Platform.isWindows && args.length == 4);
  final [instance, sid, digest, library] = args;
  WindowsPipeConfig config(String owner) => WindowsPipeConfig(
    instanceId: instance,
    serverSid: owner,
    nativeLibraryPath: library,
    connectTimeout: const Duration(seconds: 3),
    writeTimeout: const Duration(seconds: 2),
    maxPendingWriteBytes: 262144,
  );
  final wrongSid = sid == 'S-1-5-18' ? 'S-1-5-19' : 'S-1-5-18';
  try {
    final unexpected = await connectWindowsEnrollment(
      config: config(wrongSid),
      expectedContractSha256: digest,
      maxFailureBytes: 16384,
    );
    await unexpected.close();
    throw StateError('foreign owner accepted');
  } on WindowsPipeFailure catch (error) {
    require(error.problem == WindowsPipeProblem.authentication);
  }
  try {
    final unexpected = await connectWindowsEnrollment(
      config: config(sid),
      expectedContractSha256: 'f' * 64,
      maxFailureBytes: 16384,
    );
    await unexpected.close();
    throw StateError('foreign digest accepted');
  } on WindowsPipeFailure catch (error) {
    require(error.problem == WindowsPipeProblem.authentication);
  }
  final connected = await connectWindowsEnrollment(
    config: config(sid),
    expectedContractSha256: digest,
    maxFailureBytes: 16384,
  );
  try {
    const timeout = Duration(seconds: 2);
    final runtime = await connected.client.runtimeInfo(timeout);
    require(runtime.instanceId == instance && runtime.contractSha256 == digest);
    final status = await connected.client.status(timeout);
    require(
      status.metadata.instanceId == instance &&
          status.metadata.revision.toStringUnsigned() == '18446744073709551615',
    );
    require(status.network.name == 'x' * 131072);
    try {
      await connected.client.enroll(
        api.EnrollRequest(requestId: 'fixture-no-mutation'),
        timeout,
      );
      throw StateError('typed refusal missing');
    } on ClientCallFailure catch (error) {
      require(
        error.definiteRejection &&
            error.reasonKey == 'client.owner.required' &&
            error.failure?.code == api.ErrorCode.ERROR_CODE_OWNER_REQUIRED,
      );
      require(!error.toString().contains('fixture-raw-diagnostic'));
    }
    try {
      await connected.client.attempt(
        api.GetEnrollmentAttemptRequest(requestId: 'slow'),
        const Duration(milliseconds: 80),
      );
      throw StateError('RPC deadline missing');
    } on ClientCallFailure catch (error) {
      require(
        error.transportCode == grpc.StatusCode.deadlineExceeded &&
            !error.definiteRejection,
      );
    }
  } finally {
    await connected.close();
  }
  stdout.writeln('WINDOWS_DART_GO_PIPE_OWNER_DIGEST_FAILURE_DEADLINE_PASS');
}
