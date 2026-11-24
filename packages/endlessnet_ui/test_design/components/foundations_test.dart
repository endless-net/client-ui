import 'package:endlessnet_ui/design_system/brand_assets.dart';
import 'package:endlessnet_ui/design_system/theme.dart';
import 'package:endlessnet_ui/design_system/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerComponentChecks(['C01']);

  test(
    'C01 canonical palette, geometry and independent contrast expectations',
    () {
      expect(BrandTokens.cyan, const Color(0xFF19D8F2));
      expect(BrandTokens.blue, const Color(0xFF128CFF));
      expect(BrandTokens.indigo, const Color(0xFF244BFF));
      expect(BrandTokens.dark, const Color(0xFF07111D));
      expect(BrandTokens.darkAlt, const Color(0xFF0B1726));
      expect(BrandTokens.light, const Color(0xFFF7F9FC));
      expect(BrandTokens.ink, const Color(0xFF081321));
      expect(BrandTokens.white, const Color(0xFFF5F8FC));
      expect(BrandTokens.muted, const Color(0xFF8DA0B6));
      expect(BrandTokens.spacing, [4, 8, 12, 16, 24, 32, 48]);
      expect(BrandTokens.controlRadius, 8);
      expect(BrandTokens.target, 44);
      for (final theme in [BrandTheme.dark(), BrandTheme.light()]) {
        final colors = theme.extension<BrandColors>()!;
        final scheme = theme.colorScheme;
        final dark = theme.brightness == Brightness.dark;
        expect(
          [
            colors.background,
            scheme.surfaceContainerLow,
            colors.surface,
            scheme.surfaceContainer,
            scheme.surfaceContainerHigh,
            scheme.primaryContainer,
            colors.text,
            colors.secondary,
            colors.primary,
            colors.onPrimary,
            scheme.secondary,
            scheme.outlineVariant,
            scheme.outline,
            colors.success,
            colors.error,
            colors.warning,
          ],
          (dark
                  ? [
                      0xFF07111D,
                      0xFF0E1F32,
                      0xFF142A41,
                      0xFF0F2134,
                      0xFF283D54,
                      0xFF154D64,
                      0xFFF8FAFF,
                      0xFFC6D2E0,
                      0xFF19D8F2,
                      0xFF111923,
                      0xFFA8B2FF,
                      0xFF3D5065,
                      0xFF829BB2,
                      0xFFB1F1D0,
                      0xFFFF8A80,
                      0xFFFCD34D,
                    ]
                  : [
                      0xFFE6F3FD,
                      0xFFF4FAFE,
                      0xFFF9FCFE,
                      0xFFF1F8FE,
                      0xFFE8F4FD,
                      0xFFE3F2FD,
                      0xFF0F1720,
                      0xFF3B4856,
                      0xFF007783,
                      0xFFFFFFFF,
                      0xFF434DB0,
                      0xFFA5B8C8,
                      0xFF718597,
                      0xFF216A42,
                      0xFFB42318,
                      0xFF854D0E,
                    ])
              .map(Color.new),
        );
        final roles = [
          theme.textTheme.labelSmall!,
          theme.textTheme.bodyMedium!,
          theme.textTheme.bodyLarge!,
          theme.textTheme.titleMedium!,
          theme.textTheme.headlineSmall!,
          theme.textTheme.headlineLarge!,
        ];
        final sizes = [12, 14, 16, 18, 24, 32];
        final heights = [16, 20, 24, 26, 32, 40];
        for (var i = 0; i < roles.length; i++) {
          expect(roles[i].fontFamily, 'packages/endlessnet_ui/Inter');
          expect(roles[i].fontSize, sizes[i]);
          expect(
            roles[i].height! * roles[i].fontSize!,
            closeTo(heights[i], .001),
          );
        }
        double contrast(Color first, Color second) {
          final a = first.computeLuminance(), b = second.computeLuminance();
          return (a > b) ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
        }

        expect(
          contrast(colors.onPrimary, colors.primary),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(scheme.onSecondary, scheme.secondary),
          greaterThanOrEqualTo(4.5),
        );
        for (final surface in [
          colors.background,
          colors.surface,
          scheme.surfaceContainerLow,
          scheme.surfaceContainer,
          scheme.surfaceContainerHigh,
          scheme.primaryContainer,
        ]) {
          expect(contrast(colors.text, surface), greaterThanOrEqualTo(4.5));
          expect(
            contrast(colors.secondary, surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(contrast(colors.primary, surface), greaterThanOrEqualTo(3));
          expect(contrast(scheme.outline, surface), greaterThanOrEqualTo(3));
        }
        expect(
          contrast(colors.primary, colors.surface),
          greaterThanOrEqualTo(3),
        );
        expect(
          contrast(colors.primary, colors.background),
          greaterThanOrEqualTo(3),
        );
        for (final foreground in [
          colors.text,
          colors.secondary,
          colors.success,
          colors.error,
          colors.warning,
        ]) {
          final light = foreground.computeLuminance();
          final dark = colors.surface.computeLuminance();
          final ratio = (light > dark)
              ? (light + .05) / (dark + .05)
              : (dark + .05) / (light + .05);
          expect(ratio, greaterThanOrEqualTo(4.5));
        }
      }
      expect(
        BrandTheme.dark(reducedMotion: true).extension<BrandColors>()!.motion,
        Duration.zero,
      );
    },
  );

  testWidgets('C01 fonts and logo assets are bundled', (tester) async {
    for (final path in [
      'assets/fonts/Inter-Regular.ttf',
      'assets/fonts/Inter-Medium.ttf',
      'assets/fonts/Inter-SemiBold.ttf',
      'assets/fonts/NotoSansMono-Regular.ttf',
      'assets/brand/logo-dark.png',
      'assets/brand/logo-light.png',
      'assets/brand/mark-small.png',
    ]) {
      expect((await rootBundle.load(path)).lengthInBytes, greaterThan(100));
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: BrandTheme.dark(),
        home: const Scaffold(body: BrandLogo()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(Image)).width, 160);
  });
}
