import 'package:endlessnet_ui/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/component_catalog/cases.dart';
import 'support.dart';

void main() {
  testWidgets('C18 collapsed variant expands; N/A is variant-specific', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final definition = componentDefinitions.singleWhere(
      (value) => value.id == 'C04',
    );
    expect(
      definition.notApplicable('unknown', variant: 'checkbox'),
      contains('N/A'),
    );
    expect(definition.notApplicable('unknown', variant: 'radio'), isNull);
    await pumpComponent(
      tester,
      const ComponentExample(
        id: 'C18',
        variant: 'disclosure',
        state: 'collapsed',
      ),
    );
    await tester.tap(find.text('+ Подробности'));
    await tester.pump();
    expect(find.text('− Подробности'), findsOneWidget);
  });
  registerComponentChecks(['C17', 'C18', 'C19', 'C20']);
  test('catalog inventory contains exactly C01–C20 with explicit N/A', () {
    expect(componentDefinitions.map((value) => value.id).toSet(), {
      for (var i = 1; i <= 20; i++) 'C${i.toString().padLeft(2, '0')}',
    });
    expect(componentDefinitions.length, 20);
    for (final value in componentDefinitions) {
      expect(value.variants, isNotEmpty);
      expect(value.states, isNotEmpty);
      expect(value.notApplicable('domain-operation'), contains('N/A'));
    }
  });
  testWidgets('C17 breakpoint839/840 retains the owner draft', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController(text: 'Черновик');
    addTearDown(controller.dispose);
    Widget shell() => SizedBox(
      height: 600,
      child: EnShell(
        items: const [EnNavigationItem('one', 'Раздел')],
        selected: 'one',
        onSelect: (_) {},
        child: EnField(label: 'Поле', controller: controller),
      ),
    );
    await pumpComponent(tester, shell(), width: 839, padding: 0);
    expect(find.byKey(const ValueKey('sidebar')), findsNothing);
    await tester.enterText(find.byType(TextField), 'Сохранённый черновик');
    await pumpComponent(tester, shell(), width: 840, padding: 0);
    expect(find.byKey(const ValueKey('sidebar')), findsOneWidget);
    expect(controller.text, 'Сохранённый черновик');
    expect(tester.takeException(), isNull);
  });
}
