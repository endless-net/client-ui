import 'dart:async';

import 'package:endlessnet_ui/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import '../../tool/component_catalog/cases.dart';

void main() {
  testWidgets('C15 tooltip is presented on keyboard focus', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpComponent(
      tester,
      const ComponentExample(id: 'C15', variant: 'tooltip', state: 'focus'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Подсказка по фокусу'), findsOneWidget);
  });
  testWidgets('C12 snackbar variant really presents a shared message', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpComponent(
      tester,
      const ComponentExample(id: 'C12', variant: 'snackbar', state: 'error'),
    );
    await tester.tap(find.text('Показать сообщение'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(EnMessage), findsOneWidget);
  });
  registerComponentChecks(['C10', 'C11', 'C12', 'C13', 'C14', 'C15', 'C16']);
  testWidgets('C14 danger starts at Cancel and pending blocks Escape/repeat', (
    tester,
  ) async {
    final completion = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Открыть'),
              onPressed: () => showEnConfirmation(
                context,
                title: 'Подтвердите',
                child: const Text('Синтетические данные'),
                danger: true,
                onConfirm: () {
                  calls++;
                  return completion.future;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Отмена'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final cancelFocus = Focus.of(tester.element(find.text('Отмена')))
          .hasFocus;
      final confirmFocus = Focus.of(tester.element(find.text('Подтвердить')))
          .hasFocus;
      expect(cancelFocus || confirmFocus, isTrue);
    }
    await tester.tap(find.text('Подтвердить'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Подтвердить'));
    expect(calls, 1);
    completion.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
