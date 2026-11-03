import 'package:endlessnet_ui/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => MaterialApp(
  theme: BrandTheme.dark(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('C10 card presents owner content and actions', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      app(
        EnCard(
          title: 'Пример',
          description: 'Описание',
          actions: [EnButton(label: 'Действие', onPressed: () => calls++)],
          child: const Text('Данные'),
        ),
      ),
    );
    expect(find.text('Данные'), findsOneWidget);
    expect(calls, 0);
    await tester.tap(find.text('Действие'));
    expect(calls, 1);
  });
  testWidgets('C11 status carries text and reason', (tester) async {
    await tester.pumpWidget(
      app(
        const EnStatus(
          label: 'Неизвестно',
          kind: EnStatusKind.unknown,
          reason: 'Нет подтверждения',
        ),
      ),
    );
    expect(find.text('Неизвестно: Нет подтверждения'), findsOneWidget);
  });
  testWidgets('C12 dismiss and action are different owner callbacks', (
    tester,
  ) async {
    var actions = 0;
    var dismisses = 0;
    await tester.pumpWidget(
      app(
        EnMessage(
          message: 'Не удалось выполнить',
          severity: EnStatusKind.error,
          actionLabel: 'Проверить',
          onAction: () => actions++,
          onDismiss: () => dismisses++,
        ),
      ),
    );
    expect(actions, 0);
    await tester.tap(find.text('Закрыть сообщение'));
    expect(dismisses, 1);
    expect(actions, 0);
    await tester.tap(find.text('Проверить'));
    expect(actions, 1);
  });
  for (final state in EnRegionState.values) {
    testWidgets('C13 ${state.name} is distinguishable, retry is explicit', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        app(EnRegion(state: state, onRetry: () => calls++)),
      );
      expect(find.text(EnRegion.label(state)), findsOneWidget);
      expect(calls, 0);
      if (state != EnRegionState.loading) {
        await tester.tap(find.text('Повторить'));
        expect(calls, 1);
      } else {
        expect(find.text('Повторить'), findsNothing);
      }
    });
  }
}
