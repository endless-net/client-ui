@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_networks.dart';
import 'package:endlessnet/client_networks_panel.dart';
import 'package:endlessnet/client_profiles.dart';
import 'package:endlessnet/client_profiles_panel.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_networks_activation_test.dart' as networks;
import 'client_profile_context_test.dart' as profiles;

void main() {
  for (final profile in [true, false]) {
    for (final select in [true, false]) {
      testWidgets('catalog replacement profile=$profile selection=$select', (
        tester,
      ) async {
        final states = [ClientStateController(), ClientStateController()];
        final streams = [
          StreamController<api.WatchEventsResponse>(),
          StreamController<api.WatchEventsResponse>(),
        ];
        for (var i = 0; i < 2; i++) {
          await states[i].attach(streams[i].stream);
          streams[i].add(networks.snapshot(1));
        }
        await tester.pump();
        final Object catalog = profile
            ? await profiles.catalog(false, false)
            : await networks.catalog();
        final old = Completer<Object>();
        final fresh = Completer<Object>();
        var replacing = false;
        var commands = 0;
        Future<Object> load() => replacing
            ? fresh.future
            : select
            ? Future.value(catalog)
            : old.future;
        Future<ClientOperation> command() async {
          commands++;
          return await old.future as ClientOperation;
        }

        Future<void> render(int index) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: profile
                    ? ClientProfilesPanel(
                        state: states[index],
                        load: () async => await load() as ClientProfileCatalog,
                        select: (_) => command(),
                        rename: (_, _) async =>
                            throw StateError('No rename requested'),
                        remove: (_) async =>
                            throw StateError('No removal requested'),
                      )
                    : ClientNetworksPanel(
                        state: states[index],
                        load: () async => await load() as ClientNetworkCatalog,
                        select: (_, _) => command(),
                      ),
              ),
            ),
          ),
        );
        final refresh = find.byKey(
          Key(profile ? 'client-load-profiles' : 'client-load-networks'),
        );
        final selection = find.byKey(
          ValueKey(profile ? 'select-profile-b' : 'select-network-b'),
        );
        VoidCallback? queued;
        await render(0);
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        if (select) {
          await tester.ensureVisible(selection);
          queued = tester.widget<TextButton>(selection).onPressed!;
          await tester.tap(selection);
          await tester.pump();
        }
        replacing = true;
        await render(1);
        await render(0);
        expect(selection, findsNothing);
        expect(tester.widget<OutlinedButton>(refresh).onPressed, isNotNull);
        await tester.ensureVisible(refresh);
        await tester.tap(refresh);
        await tester.pump();
        old.complete(
          select
              ? ClientOperation.fromProto(
                  api.Operation(
                    id: 'old-operation',
                    state: api.OperationState.OPERATION_STATE_PENDING,
                    kind: profile
                        ? api.OperationKind.OPERATION_KIND_SELECT_PROFILE
                        : api.OperationKind.OPERATION_KIND_SELECT_NETWORK,
                  ),
                )
              : catalog,
        );
        await tester.pumpAndSettle();
        expect(selection, findsNothing);
        expect(tester.widget<OutlinedButton>(refresh).onPressed, isNull);
        fresh.complete(catalog);
        await tester.pumpAndSettle();
        expect(selection, findsOneWidget);
        queued?.call();
        expect(
          commands,
          select ? 1 : 0,
          reason:
              'A-B-A must revoke queued selection even when the same catalog object is reused',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          for (var i = 0; i < 2; i++) {
            await states[i].detach();
            await streams[i].close();
            states[i].dispose();
          }
        });
      });
    }
  }
}
