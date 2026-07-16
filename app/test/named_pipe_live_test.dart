import 'dart:io';

import 'package:endlessnet_tray/named_pipe_http.dart';
import 'package:endlessnet_tray/service_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final live = Platform.environment['ENDLESSNET_TRAY_LIVE_PIPE_TEST'] == '1';

  test(
    'tray talks directly to the installed EndlessNet named pipe',
    () async {
      final pipe = Platform.environment['ENDLESSNET_TRAY_PIPE']?.trim();
      final client = NamedPipeHttpClient(
        pipePath: pipe == null || pipe.isEmpty
            ? r'\\.\pipe\endlessnet-service'
            : pipe,
        timeout: const Duration(seconds: 8),
      );

      final status = await client.request('GET', ServiceIPCPath.status);

      expect(status['ipc_protocol'], 'endlessnet-client-ipc');
      expect(status['ipc_version'], 1);
      expect(status['state'], isNotEmpty);
    },
    skip: live ? false : 'set ENDLESSNET_TRAY_LIVE_PIPE_TEST=1',
  );
}
