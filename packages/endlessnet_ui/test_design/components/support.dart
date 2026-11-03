import 'package:endlessnet_ui/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/component_catalog/cases.dart';

Future<void> loadBrandFonts() async {
  for (final entry in {
    'Inter': ['Inter-Regular.ttf', 'Inter-Medium.ttf', 'Inter-SemiBold.ttf'],
    'NotoSansMono': ['NotoSansMono-Regular.ttf'],
  }.entries) {
    final loader = FontLoader('packages/endlessnet_ui/${entry.key}');
    for (final path in entry.value) {
      loader.addFont(rootBundle.load('assets/fonts/$path'));
    }
    await loader.load();
  }
}

Future<void> pumpComponent(
  WidgetTester tester,
  Widget child, {
  double width = 840,
  double scale = 1,
  bool dark = true,
  bool reduced = false,
  double padding = 16,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 1200);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark
          ? BrandTheme.dark(reducedMotion: reduced)
          : BrandTheme.light(reducedMotion: reduced),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
}

void registerComponentChecks(List<String> ids) {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadBrandFonts);
  for (final id in ids) {
    final definition = componentDefinitions.singleWhere(
      (value) => value.id == id,
    );
    testWidgets('$id all declared variants and states on synthetic inputs', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final variant in definition.variants) {
        for (final state in definition.statesFor(variant)) {
          await pumpComponent(
            tester,
            ComponentExample(
              key: ValueKey('$id/$variant/$state'),
              id: id,
              variant: variant,
              state: state,
            ),
          );
          expect(tester.takeException(), isNull, reason: '$id/$variant/$state');
        }
      }
    });
    testWidgets(
      '$id boundary matrix: widths, themes, text scale, reduced motion',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final width in [360.0, 840.0, 1440.0]) {
          for (final dark in [true, false]) {
            for (final scale in [1.0, 2.0]) {
              await pumpComponent(
                tester,
                ComponentExample(
                  id: id,
                  variant: definition.variants.first,
                  state: definition.states.first,
                  longText: true,
                ),
                width: width,
                dark: dark,
                scale: scale,
                reduced: true,
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '$id/$width/$dark/$scale',
              );
            }
          }
        }
      },
    );
  }
}
