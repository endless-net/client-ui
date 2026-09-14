@Tags(['short'])
library;

import 'dart:async';
import 'package:endlessnet/client_exit_panel.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_state_controller.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'client_exit_activation_test.dart' as fixtures;

void main() {
  for (final locale in ClientLocale.values) {
    testWidgets('US-14 exit choices at 200% with keyboard in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = ClientStateController();
      final events = StreamController<api.WatchEventsResponse>();
      await state.attach(events.stream);
      events.add(fixtures.snapshot(1));
      await tester.pump();
      var commands = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ClientExitPanel(
                state: state,
                locale: locale,
                load: () => fixtures.catalog(
                  displayName: 'Regional office secure network gateway',
                ),
                select: (_, _, _, _, _) async {
                  commands++;
                  return fixtures.pending(
                    api.OperationKind.OPERATION_KIND_SELECT_EXIT_NODE,
                  );
                },
                clear: (_, _) async {
                  commands++;
                  return fixtures.pending(
                    api.OperationKind.OPERATION_KIND_CLEAR_EXIT_NODE,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('client-load-exits')));
      await tester.pumpAndSettle();
      final choice = find.byKey(const Key('client-exit-node'));
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Measure the complete text against its rendered bounds: absence of a
      // RenderFlex exception alone does not detect fixed-height text clipping.
      void checkLabels() {
        final labels = find.textContaining(
          'Regional office',
          skipOffstage: true,
        );
        expect(labels, findsWidgets);
        for (final element in labels.evaluate()) {
          final paragraph = element.findRenderObject()! as RenderParagraph;
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
      }

      checkLabels();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(tester.widget<DropdownButton<String>>(choice).value, isNull);
      // Dismissing the menu returns focus to its trigger. Reopen and select
      // through keyboard events, without calling the widget callback directly.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tester.widget<DropdownButton<String>>(choice).value, isNotNull);
      checkLabels();
      expect(commands, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await state.detach();
        await events.close();
        state.dispose();
      });
    });
  }
}
