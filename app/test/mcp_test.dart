import 'dart:io';

import 'package:endlessnet_client_ui/mcp/protocol.dart';
import 'package:endlessnet_client_ui/mcp/recovery_log.dart';
import 'package:flutter_test/flutter_test.dart';

Json request(String method, {Object? id, Json? params}) => {
  'jsonrpc': '2.0',
  'method': method,
  'id': ?id,
  'params': ?params,
};

void main() {
  test('saved recovery is independent of ordinary logs and survives rotation and reopening', () async {
    final directory = await Directory.systemTemp.createTemp(
      'endlessnet-recovery-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = File('${directory.path}${Platform.pathSeparator}recovery.bin');
    Future<(File, void Function())> acquire() async => (path, () {});
    final first = UiDiagnostics();
    await first.recovery.open(acquire);
    for (var i = 0; i < 258; i++) {
      first.recovery.record(
        RecoveryEvent.readFailed,
        stage: RecoveryStage.status,
        cause: RecoveryCause.timeout,
      );
      first.record('updates', 'checking');
    }
    first.recovery.record(RecoveryEvent.recovered);
    for (var i = 0; i < 260; i++) {
      first.record('updates', 'checking');
    }
    await first.recovery.close();
    expect(await path.length(), 256 * 512);

    final reopened = UiDiagnostics();
    await reopened.recovery.open(acquire);
    final page = reopened.read({'source': 'recovery', 'limit': 1});
    expect(page['historyGap'], true);
    expect(page['nextCursor'], 4);
    expect(page['storageUnavailable'], false);
    expect((page['entries'] as List<Json>).single['state'], {
      'stage': 'status',
      'cause': 'timeout',
    });
    final tail = reopened.read({'source': 'recovery', 'after': 258});
    expect(tail['hasMore'], false);
    expect((tail['entries'] as List<Json>).single['event'], 'recovered');
    expect(reopened.read({})['entries'], isEmpty);
    await reopened.recovery.close();
  });

  test('storage failure leaves safe recovery events readable', () async {
    final diagnostics = UiDiagnostics();
    await diagnostics.recovery.open(
      () async => throw const FileSystemException('raw path'),
    );
    diagnostics.recovery.record(RecoveryEvent.recovered);
    final page = diagnostics.read({'source': 'recovery'});
    expect(page['storageUnavailable'], true);
    expect((page['entries'] as List<Json>).single['event'], 'recovered');
    expect(page.toString(), isNot(contains('raw path')));
    await diagnostics.recovery.close();
  });

  test(
    'binds initialization and the closed tool set to each session',
    () async {
      final invoked = <String>[];
      final session = UiMcpSession((name, _) async {
        invoked.add(name);
        return {'fresh': true};
      });
      final list = request('tools/list', id: 3);
      expect((await session.handle(list))?['error'], isNotNull);
      expect(
        await session.handle(request('notifications/initialized')),
        isNull,
      );
      final init = await session.handle(
        request(
          'initialize',
          id: 1,
          params: {
            'protocolVersion': '2025-11-25',
            'capabilities': <String, Object?>{},
            'clientInfo': <String, Object?>{'name': 'test', 'version': '1'},
          },
        ),
      );
      expect((init?['result'] as Json)['protocolVersion'], '2025-11-25');
      expect((await session.handle(list))?['error'], isNotNull);
      await session.handle(request('notifications/initialized'));
      final tools =
          ((await session.handle(list))?['result'] as Json)['tools']
              as List<Json>;
      expect(tools.map((tool) => tool['name']), [
        'app_status',
        'logs_read',
        'client_logs_read',
        'connectivity_refresh',
        'connectivity_connect',
        'connectivity_disconnect',
      ]);

      for (final (name, args) in [
        ('rpc_call', <String, Object?>{}),
        ('connectivity_connect', <String, Object?>{'profile': 'other'}),
        ('logs_read', <String, Object?>{'limit': 101}),
        ('logs_read', <String, Object?>{'source': 'other'}),
        ('client_logs_read', <String, Object?>{'after': 1}),
        ('client_logs_read', <String, Object?>{'pageToken': 1}),
      ]) {
        final response = await session.handle(
          request(
            'tools/call',
            id: 4,
            params: {'name': name, 'arguments': args},
          ),
        );
        expect(response?['error'], isNotNull);
      }
      expect(invoked, isEmpty);
      final refresh = await session.handle(
        request('tools/call', id: 5, params: {'name': 'connectivity_refresh'}),
      );
      expect((refresh?['result'] as Json)['structuredContent'], {
        'fresh': true,
      });
      final logs = await session.handle(
        request(
          'tools/call',
          id: 6,
          params: {
            'name': 'client_logs_read',
            'arguments': {'pageToken': 'cursor', 'limit': 20},
          },
        ),
      );
      expect((logs?['result'] as Json)['structuredContent'], {'fresh': true});
      final recovery = await session.handle(
        request(
          'tools/call',
          id: 7,
          params: {
            'name': 'logs_read',
            'arguments': {'source': 'recovery', 'after': 1},
          },
        ),
      );
      expect((recovery?['result'] as Json)['structuredContent'], {
        'fresh': true,
      });
      expect(invoked, [
        'connectivity_refresh',
        'client_logs_read',
        'logs_read',
      ]);
    },
  );

  test(
    'reports evicted events and continues from the last returned cursor',
    () {
      final log = UiDiagnostics();
      for (var i = 0; i < 260; i++) {
        log.record('test', 'change');
      }
      final first = log.read({'limit': 2});
      expect(first['historyGap'], true);
      expect(first['hasMore'], true);
      expect(first['nextCursor'], 6);
      final second = log.read({'after': first['nextCursor'], 'limit': 1});
      expect((second['entries'] as List<Json>).single['sequence'], 7);
      expect(second['historyGap'], false);
      final end = log.read({'after': 260});
      expect(end['entries'], isEmpty);
      expect(end['hasMore'], false);
      expect(log.read({'after': 300})['cursorAhead'], true);
    },
  );
}
