import 'package:endlessnet/client_adaptive_shell.dart';
import 'package:endlessnet/client_locale.dart';
import 'package:endlessnet/client_session_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in ClientLocale.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('adaptive navigation preserves form $locale scale=$scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var page = ClientPage.connection;
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: StatefulBuilder(
              builder: (context, update) => ClientAdaptiveShell(
                locale: locale,
                page: page,
                onPageChanged: (value) => update(() => page = value),
                languageSelector: const SizedBox(
                  width: 80,
                  child: Text('English'),
                ),
                notices: const SizedBox.shrink(),
                body: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      key: const Key('profile-draft'),
                      controller: controller,
                    ),
                    FilledButton(
                      onPressed: () {},
                      child: const Text('Connect'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.enterText(
          find.byKey(const Key('profile-draft')),
          'My network',
        );
        final original = tester.state(find.byKey(const Key('profile-draft')));
        for (final size in [
          const Size(320, 568),
          const Size(390, 844),
          const Size(844, 390),
          const Size(800, 900),
          const Size(1280, 800),
          const Size(390, 844),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          final rail = size.width >= 720 && size.height >= 400;
          expect(
            find.byType(NavigationRail),
            rail ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(NavigationBar),
            rail ? findsNothing : findsOneWidget,
          );
          expect(tester.takeException(), isNull, reason: '$size');
          expect(
            tester.state(find.byKey(const Key('profile-draft'))),
            same(original),
          );
          expect(controller.text, 'My network');
          await tester.tap(find.byKey(const ValueKey('page-settings')));
          await tester.pumpAndSettle();
          expect(page, ClientPage.settings);
          expect(
            tester.takeException(),
            isNull,
            reason: '$size after navigation',
          );
        }
      });
    }
  }
}
