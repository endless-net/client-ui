import 'dart:async';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:endlessnet_client_ui/client/connectivity_client.dart';
import 'package:endlessnet_client_ui/dashboard/resource_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Reader implements ResourceClient {
  final meta = api.SnapshotMetadata(instanceId: 'agent');
  bool down = false;
  String network = 'network';
  Completer<void>? pending;
  final tokens = <String>[];
  @override
  Future<api.ListResourcesResponse> listResources(
    api.ListResourcesRequest request,
    Duration timeout,
  ) async {
    expect(request.profile.profileId, 'profile');
    tokens.add(request.page.pageToken);
    final second = request.page.pageToken.isNotEmpty;
    final result = api.ListResourcesResponse(
      resources: [
        api.Resource(
          id: second ? 'second' : 'first',
          displayName: second ? 'Office' : 'Database',
          networkId: network,
          subnet: api.SubnetTarget(cidr: '10.7.0.0/24'),
          availability: api.Restriction(
            availability: down
                ? api.Availability.AVAILABILITY_TEMPORARILY_UNAVAILABLE
                : api.Availability.AVAILABILITY_AVAILABLE,
          ),
        ),
      ],
      page: api.PageResponse(
        nextPageToken: second ? '' : 'next',
        metadata: meta,
      ),
    );
    await pending?.future;
    return result;
  }
}

void main() {
  testWidgets('refreshes an open list across a newer node observation', (
    tester,
  ) async {
    final reader = _Reader();
    Future<void> show(int observation) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkResourceList(
            client: reader,
            timeout: const Duration(seconds: 1),
            status: api.Status(
              activeProfileId: 'profile',
              network: api.Network(id: 'network'),
              metadata: reader.meta,
              agent: api.AgentStatus()..ensureGeneratedAt().nanos = observation,
            ),
          ),
        ),
      ),
    );
    await show(1);
    await show(2);
    expect(reader.tokens, isEmpty);
    await tester.tap(find.text('Показать ресурсы сети'));
    await tester.pumpAndSettle();
    final delayed = reader.pending = Completer<void>();
    await tester.tap(find.text('Ещё ресурсы'));
    await tester.pump();
    reader.down = true;
    await show(3);
    expect(find.text('Database'), findsNothing);
    reader.pending = null;
    delayed.complete();
    await tester.pumpAndSettle();
    expect(reader.tokens, ['', 'next', '']);
    expect(find.text('Office'), findsNothing);
    expect(find.text('10.7.0.0/24 · Путь недоступен'), findsOneWidget);
  });

  testWidgets(
    'reads installed and withdrawn resources and discards foreign rows',
    (tester) async {
      final reader = _Reader();
      final status = api.Status(
        activeProfileId: 'profile',
        network: api.Network(id: 'network'),
        metadata: reader.meta,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkResourceList(
              client: reader,
              timeout: const Duration(seconds: 1),
              status: status,
            ),
          ),
        ),
      );
      Future<void> click(String text) async {
        await tester.tap(find.text(text));
        await tester.pumpAndSettle();
      }

      await click('Показать ресурсы сети');
      expect(find.text('10.7.0.0/24 · Путь установлен'), findsOneWidget);
      await click('Ещё ресурсы');
      expect(find.text('Office'), findsOneWidget);
      reader.down = true;
      await click('Обновить ресурсы сети');
      expect(find.text('10.7.0.0/24 · Путь недоступен'), findsOneWidget);
      expect(find.text('Office'), findsNothing);
      reader.network = 'other';
      await click('Обновить ресурсы сети');
      expect(find.text('Database'), findsNothing);
      expect(
        find.text('Не удалось получить актуальный список ресурсов.'),
        findsOneWidget,
      );
    },
  );
}
