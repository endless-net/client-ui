import 'dart:async';

import 'package:endlessnet_ui/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => MaterialApp(
  theme: BrandTheme.dark(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('C17 synthetic slot keeps owner draft and drawer emits intent', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'Черновик');
    addTearDown(controller.dispose);
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark(),
        home: EnShell(
          items: const [EnNavigationItem('one', 'Раздел A')],
          selected: null,
          onSelect: (value) => selected = value,
          child: EnField(label: 'Название', controller: controller),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Новый черновик');
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Раздел A'));
    await tester.pumpAndSettle();
    expect(selected, 'one');
    expect(controller.text, 'Новый черновик');
  });
  testWidgets('C07 table emits sort/selection intents for stable IDs', (
    tester,
  ) async {
    String? selected;
    int? sorted;
    await tester.pumpWidget(
      app(
        EnTable(
          columns: const ['Название'],
          rows: const [
            EnTableRow(id: 'a', cells: ['Alpha']),
            EnTableRow(id: 'b', cells: ['Beta'], enabled: false),
          ],
          onSelect: (id, value) => selected = id,
          onSort: (index, ascending) => sorted = index,
        ),
      ),
    );
    await tester.tap(find.text('Alpha'));
    expect(selected, 'a');
    await tester.tap(find.text('Beta'));
    expect(selected, 'a');
    await tester.tap(find.text('Название'));
    expect(sorted, 0);
  });
  testWidgets('C08 list disabled row does not activate', (tester) async {
    String? selected;
    await tester.pumpWidget(
      app(
        EnList(
          items: const [
            EnListItem(id: 'a', label: 'Alpha'),
            EnListItem(id: 'b', label: 'Beta', enabled: false),
          ],
          onActivate: (value) => selected = value,
        ),
      ),
    );
    await tester.tap(find.text('Beta'));
    expect(selected, isNull);
    await tester.tap(find.text('Alpha'));
    expect(selected, 'a');
  });
  testWidgets('C09 unknown total and loading are explicit, no hidden fetch', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      app(
        EnPager(
          loadedCount: 0,
          hasNext: true,
          loading: true,
          onNext: () => calls++,
        ),
      ),
    );
    expect(find.text('Загружено: 0; всего: неизвестно'), findsOneWidget);
    await tester.tap(find.text('Далее'));
    expect(calls, 0);
    await tester.pumpWidget(app(const EnPager(loadedCount: 0, total: 0)));
    expect(find.text('Загружено: 0; всего: 0'), findsOneWidget);
  });
  testWidgets('C18 missing/empty are distinct and expansion belongs to owner', (
    tester,
  ) async {
    bool? expanded;
    await tester.pumpWidget(
      app(
        EnDetails(
          title: 'Сведения',
          values: const {'A': null, 'B': ''},
          onExpand: (value) => expanded = value,
        ),
      ),
    );
    expect(find.text('A: Нет значения'), findsOneWidget);
    expect(find.text('B: Пустое значение'), findsOneWidget);
    await tester.tap(find.text('− Сведения'));
    expect(expanded, false);
  });
  testWidgets('C19 invalid is unknown, indeterminate is not zero', (
    tester,
  ) async {
    await tester.pumpWidget(app(const EnProgress(label: 'Операция', value: 2)));
    expect(find.text('Прогресс неизвестен'), findsOneWidget);
    expect(find.text('100%'), findsNothing);
    await tester.pumpWidget(app(const EnProgress(label: 'Операция')));
    expect(find.text('Выполняется'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
  });
  testWidgets('C20 copy failures are visible; sensitive never copied', (
    tester,
  ) async {
    var copies = 0;
    Future<void> copy(String value) async {
      copies++;
      throw StateError('denied');
    }

    await tester.pumpWidget(app(EnMachineText(text: 'demo-id', onCopy: copy)));
    await tester.tap(find.text('Копировать'));
    await tester.pump();
    expect(find.text('Не удалось скопировать'), findsOneWidget);
    await tester.pumpWidget(
      app(EnMachineText(text: 'secret', sensitive: true, onCopy: copy)),
    );
    expect(find.text('secret'), findsNothing);
    expect(find.text('Копировать'), findsNothing);
    expect(copies, 1);
  });
  testWidgets('C20 obsolete copy result does not label a different value', (
    tester,
  ) async {
    final completion = Completer<void>();
    await tester.pumpWidget(
      app(EnMachineText(text: 'old', onCopy: (_) => completion.future)),
    );
    await tester.tap(find.text('Копировать'));
    await tester.pumpWidget(
      app(EnMachineText(text: 'new', onCopy: (_) async {})),
    );
    completion.completeError(StateError('old operation'));
    await tester.pump();
    expect(find.text('Не удалось скопировать'), findsNothing);
  });
}
