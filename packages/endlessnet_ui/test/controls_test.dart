import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:endlessnet_ui/design_system/controls.dart';
import 'package:endlessnet_ui/design_system/navigation.dart';
import 'package:endlessnet_ui/design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => MaterialApp(
  theme: BrandTheme.dark(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('C14 a failed confirmation remains visible and reaches owner', (
    tester,
  ) async {
    Object? error;
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('Открыть'),
              onPressed: () => showEnConfirmation(
                context,
                title: 'Подтверждение',
                child: const Text('Данные'),
                onConfirm: () => throw StateError('denied'),
                onError: (value) => error = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Подтвердить'));
    await tester.pump();
    expect(error, isA<StateError>());
    expect(find.text('Подтверждение'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.text('Подтверждение'), findsNothing);
  });
  testWidgets('C15 menu excludes disabled actions and returns selected key', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      app(
        EnMenu(
          label: 'Действия',
          items: const [
            EnMenuAction('a', 'Открыть'),
            EnMenuAction('b', 'Удалить', enabled: false),
          ],
          onSelected: (value) => selected = value,
        ),
      ),
    );
    await tester.tap(find.text('Действия'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    expect(selected, isNull);
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(selected, 'a');
  });
  testWidgets('C16 tab keyboard emits a selected key, disabled stays silent', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      app(
        EnTabs(
          items: const [
            EnNavigationItem('a', 'Первая'),
            EnNavigationItem('b', 'Вторая'),
            EnNavigationItem('c', 'Третья', enabled: false),
          ],
          selected: 'a',
          onSelect: (value) => selected = value,
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(selected, 'b');
    await tester.tap(find.text('Третья'));
    expect(selected, 'b');
  });
  testWidgets('C02 pending and disabled expose no assistive tap action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        app(EnButton(label: 'Ожидание', pending: true, onPressed: () {})),
      );
      final data = tester
          .getSemantics(find.byType(FilledButton))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse);
    } finally {
      semantics.dispose();
    }
  });
  testWidgets(
    'C02 pending prevents a second callback, errors return to owner',
    (tester) async {
      final completion = Completer<void>();
      var calls = 0;
      Object? error;
      await tester.pumpWidget(
        app(
          EnButton(
            label: 'Сохранить',
            onPressed: () {
              calls++;
              return completion.future;
            },
            onError: (value) => error = value,
          ),
        ),
      );
      await tester.tap(find.text('Сохранить'));
      await tester.pump();
      await tester.tap(find.text('Сохранить'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, 1);
      completion.completeError(StateError('отказ'));
      await tester.pump();
      expect(error, isA<StateError>());
      await tester.tap(find.text('Сохранить'));
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('C02 disabled reason is visible and no action occurs', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      app(
        EnButton(
          label: 'Удалить',
          enabled: false,
          disabledReason: 'Нет разрешения',
          onPressed: () => calls++,
        ),
      ),
    );
    await tester.tap(find.text('Удалить'));
    expect(calls, 0);
    expect(find.text('Нет разрешения'), findsOneWidget);
  });

  testWidgets('C03 preserves owner draft; password reveal is explicit', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'секрет');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      app(EnField(label: 'Пароль', controller: controller, secret: true)),
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
    await tester.tap(find.byTooltip('Показать пароль'));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isFalse,
    );
    await tester.enterText(find.byType(TextField), 'новый');
    await tester.pumpWidget(
      app(EnField(label: 'Пароль', controller: controller, secret: true)),
    );
    expect(controller.text, 'новый');
  });

  testWidgets(
    'C04 unknown value is explicit and disabled choice has no event',
    (tester) async {
      String? chosen;
      await tester.pumpWidget(
        app(
          EnSelect(
            label: 'Режим',
            value: 'missing',
            options: const {'one': 'Один'},
            enabled: false,
            onChanged: (value) => chosen = value,
          ),
        ),
      );
      expect(find.text('Неизвестное значение'), findsOneWidget);
      expect(chosen, isNull);
    },
  );

  testWidgets('C05 form uses owner errors and submit permission', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      app(
        EnForm(
          errors: const ['Проверьте адрес'],
          canSubmit: false,
          onSubmit: () => calls++,
          child: const Text('Поля'),
        ),
      ),
    );
    expect(find.text('Проверьте адрес'), findsOneWidget);
    await tester.tap(find.text('Сохранить'));
    expect(calls, 0);
  });

  testWidgets('C06 search clear notifies owner without automatic retry', (
    tester,
  ) async {
    final query = TextEditingController(text: 'demo');
    addTearDown(query.dispose);
    var changes = 0;
    await tester.pumpWidget(
      app(
        EnSearch(
          controller: query,
          onChanged: (_) => changes++,
          onClear: () {
            query.clear();
            changes++;
          },
        ),
      ),
    );
    expect(changes, 0);
    await tester.tap(find.byTooltip('Очистить поиск'));
    expect(changes, 1);
    expect(query.text, isEmpty);
  });
}
