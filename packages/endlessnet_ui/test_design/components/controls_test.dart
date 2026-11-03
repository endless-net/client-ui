import 'package:endlessnet_ui/design_system/design_system.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import '../../tool/component_catalog/cases.dart';

void main() {
  testWidgets('C03 synthetic owner draft survives theme and viewport changes', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const example = ComponentExample(
      id: 'C03',
      variant: 'text',
      state: 'default',
    );
    await pumpComponent(tester, example);
    await tester.enterText(find.byType(TextField), 'Сохранённый черновик');
    await pumpComponent(tester, example, dark: false, width: 360, scale: 2);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Сохранённый черновик',
    );
    expect(tester.takeException(), isNull);
  });
  registerComponentChecks(['C02', 'C03', 'C04', 'C05', 'C06']);
  testWidgets(
    'C04 variants show actual unknown and reversible selected state; C06 empty',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpComponent(
        tester,
        const ComponentExample(
          key: ValueKey('selected'),
          id: 'C04',
          variant: 'checkbox',
          state: 'selected',
        ),
      );
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      for (final variant in ['select', 'radio', 'segmented']) {
        await pumpComponent(
          tester,
          ComponentExample(
            key: ValueKey(variant),
            id: 'C04',
            variant: variant,
            state: 'unknown',
          ),
        );
        expect(find.text('Неизвестное значение'), findsOneWidget);
      }
      await pumpComponent(
        tester,
        const ComponentExample(
          key: ValueKey('empty'),
          id: 'C06',
          variant: 'search',
          state: 'empty',
        ),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    },
  );
  testWidgets('C02 actual hover/focus/pressed and minimum target', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpComponent(tester, EnButton(label: 'Действие', onPressed: () {}));
    final button = find.byType(FilledButton);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(Focus.of(tester.element(find.text('Действие'))).hasFocus, isTrue);
    await pointer.down(tester.getCenter(button));
    await tester.pump();
    await pointer.up();
    await pointer.removePointer();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
