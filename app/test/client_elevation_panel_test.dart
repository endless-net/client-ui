@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_cleanup_panel.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_identity_panel.dart';
import 'package:endlessnet/client_operation.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in ClientLocale.values) {
    testWidgets('owner identity keyboard confirmation at 200% in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      var loads = 0;
      var trusts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ClientIdentityPanel(
                locale: locale,
                state: state,
                canElevate: true,
                load: () async {
                  loads++;
                  return api.GetServerIdentityResponse()..mergeFromProto3Json({
                    'metadata': {'instanceId': 'runtime', 'revision': '1'},
                    'identity': {
                      'profileId': 'profile',
                      'controlOrigin': 'https://control.test',
                      'trustedKeyId': 'old',
                      'announcedKeyId': 'new',
                      'announcementId': 'a' * 64,
                      'changed': true,
                    },
                  });
                },
                trust: (identity) async {
                  trusts++;
                  expect(identity.announcementId, 'a' * 64);
                  return ClientOperation.fromProto(
                    api.Operation(
                      id: 'operation',
                      kind: api
                          .OperationKind
                          .OPERATION_KIND_TRUST_SERVER_IDENTITY,
                      state: api.OperationState.OPERATION_STATE_PENDING,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'runtime', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'runtime',
              'callerAccess': 'ACCESS_OWNER',
              'capabilities': [
                {
                  'capability': 'CAPABILITY_IDENTITY_RECOVERY',
                  'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                },
              ],
            },
            'status': {
              'activeProfileId': 'profile',
              'metadata': {'instanceId': 'runtime', 'revision': '1'},
            },
          },
        }),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('trust-client-identity')))
            .onPressed,
        isNull,
      );
      for (final value in ['https://control.test', 'a' * 64]) {
        final text = find.textContaining(value);
        await tester.ensureVisible(text);
        await tester.pumpAndSettle();
        final paragraph = tester.renderObject<RenderParagraph>(text);
        final painter = TextPainter(
          text: paragraph.text,
          textDirection: paragraph.textDirection,
          textScaler: paragraph.textScaler,
        )..layout(maxWidth: paragraph.size.width);
        expect(
          paragraph.size.height + 0.01,
          greaterThanOrEqualTo(painter.height),
        );
        painter.dispose();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('compare-client-identity')),
            )
            .value,
        isTrue,
      );
      expect(trusts, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(trusts, 1);
      expect(tester.takeException(), isNull);
      await events.close();
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });
  }
  for (final access in ['OWNER', 'OBSERVER']) {
    testWidgets('cleanup elevation requires explicit $access confirmation', (
      tester,
    ) async {
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClientCleanupPanel(
              state: state,
              canElevate: true,
              logout: (_) async => throw StateError('No fallback'),
              forget: (id) async {
                calls++;
                return ClientOperation.fromProto(
                  api.Operation(
                    id: 'operation',
                    kind: api
                        .OperationKind
                        .OPERATION_KIND_FORGET_LOCAL_ENROLLMENT,
                    state: api.OperationState.OPERATION_STATE_PENDING,
                  ),
                );
              },
            ),
          ),
        ),
      );
      events.add(
        api.WatchEventsResponse()..mergeFromProto3Json({
          'sequence': '1',
          'metadata': {'instanceId': 'runtime', 'revision': '1'},
          'snapshot': {
            'runtime': {
              'protocol': api.ClientContract.protocol,
              'contractSha256': api.ClientContract.sha256,
              'instanceId': 'runtime',
              'callerAccess': 'ACCESS_$access',
              'capabilities': [
                {
                  'capability': 'CAPABILITY_LOCAL_FORGET',
                  'restriction': {'availability': 'AVAILABILITY_AVAILABLE'},
                },
              ],
            },
            'status': {
              'activeProfileId': 'profile',
              'metadata': {'instanceId': 'runtime', 'revision': '1'},
            },
          },
        }),
      );
      await tester.pump();
      final button = tester.widget<OutlinedButton>(
        find.byKey(const Key('client-local-forget')),
      );
      if (access == 'OBSERVER') {
        expect(button.onPressed, isNull);
      } else {
        await tester.tap(find.byKey(const Key('client-local-forget')));
        await tester.pump();
        expect(calls, 0);
        expect(
          find.text(
            'Confirmation will open the system administrator approval prompt.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('confirm-client-cleanup')));
        await tester.pump();
        expect(calls, 1);
      }
      await events.close();
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    });
  }
}
