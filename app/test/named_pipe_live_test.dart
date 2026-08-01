import 'dart:io';

import 'package:endlessnet/named_pipe_http.dart';
import 'package:endlessnet/service_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final live = Platform.environment['ENDLESSNET_LIVE_PIPE_TEST'] == '1';

  test(
    'app talks directly to the installed EndlessNet named pipe',
    () async {
      final pipe = Platform.environment['ENDLESSNET_PIPE']?.trim();
      final client = NamedPipeHttpClient(
        pipePath: pipe == null || pipe.isEmpty
            ? r'\\.\pipe\endlessnet-service'
            : pipe,
        timeout: const Duration(seconds: 8),
      );

      final status = await client.request('GET', ServiceIPCPath.status);

      expect(status['ipc_protocol'], 'endlessnet-client-ipc');
      expect(status['ipc_version'], ServiceIPCMetadata.version);
      expect(status['state'], isNotEmpty);

      final diagnostics = await client.request(
        'GET',
        ServiceIPCPath.diagnostics,
      );
      expect(diagnostics['diagnostics'], isA<Map<String, dynamic>>());
    },
    skip: live ? false : 'set ENDLESSNET_LIVE_PIPE_TEST=1',
  );
}
