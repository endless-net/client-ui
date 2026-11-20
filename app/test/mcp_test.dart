import 'package:endlessnet_client_ui/mcp/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Json request(String method, {Object? id, Json? params}) => {
  'jsonrpc': '2.0',
  'method': method,
  'id': ?id,
  'params': ?params,
};

void main() {
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
        'connectivity_refresh',
        'connectivity_connect',
        'connectivity_disconnect',
      ]);

      for (final (name, args) in [
        ('rpc_call', <String, Object?>{}),
        ('connectivity_connect', <String, Object?>{'profile': 'other'}),
        ('logs_read', <String, Object?>{'limit': 101}),
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
      expect(invoked, ['connectivity_refresh']);
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
