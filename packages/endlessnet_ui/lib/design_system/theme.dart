import 'package:flutter/material.dart';

import 'tokens.dart';

@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({
    required this.background,
    required this.surface,
    required this.text,
    required this.secondary,
    required this.primary,
    required this.onPrimary,
    required this.success,
    required this.error,
    required this.warning,
    required this.motion,
  });

  final Color background, surface, text, secondary, primary, onPrimary;
  final Color success, error, warning;
  final Duration motion;

  static BrandColors of(BuildContext context) =>
      Theme.of(context).extension<BrandColors>()!;

  @override
  BrandColors copyWith({Duration? motion}) => BrandColors(
    background: background,
    surface: surface,
    text: text,
    secondary: secondary,
    primary: primary,
    onPrimary: onPrimary,
    success: success,
    error: error,
    warning: warning,
    motion: motion ?? this.motion,
  );

  @override
  BrandColors lerp(covariant BrandColors? other, double t) {
    if (other == null) return this;
    return BrandColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      text: Color.lerp(text, other.text, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      motion: t < .5 ? motion : other.motion,
    );
  }
}

abstract final class BrandTheme {
  static ThemeData dark({bool reducedMotion = false}) =>
      _build(true, reducedMotion);
  static ThemeData light({bool reducedMotion = false}) =>
      _build(false, reducedMotion);

  static ThemeData _build(bool dark, bool reduced) {
    final colors = BrandColors(
      background: dark ? BrandTokens.dark : BrandTokens.light,
      surface: dark ? BrandTokens.darkAlt : Colors.white,
      text: dark ? BrandTokens.white : BrandTokens.ink,
      secondary: dark ? BrandTokens.muted : const Color(0xFF526176),
      primary: dark ? BrandTokens.cyan : BrandTokens.indigo,
      onPrimary: dark ? BrandTokens.ink : BrandTokens.white,
      success: Color(dark ? 0xFF6EE7B7 : 0xFF166534),
      error: Color(dark ? 0xFFFF8A80 : 0xFFB42318),
      warning: Color(dark ? 0xFFFCD34D : 0xFF854D0E),
      motion: reduced ? Duration.zero : BrandTokens.duration,
    );
    TextStyle text(double size, double height, FontWeight weight) => TextStyle(
      fontFamily: 'Inter',
      package: 'endlessnet_ui',
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      color: colors.text,
    );
    final scheme =
        ColorScheme.fromSeed(
          seedColor: colors.primary,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: colors.primary,
          onPrimary: colors.onPrimary,
          surface: colors.surface,
          onSurface: colors.text,
          onSurfaceVariant: colors.secondary,
          error: colors.error,
          outline: colors.secondary,
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(BrandTokens.controlRadius),
    );
    final button = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      shape: WidgetStatePropertyAll(shape),
      animationDuration: colors.motion,
    );
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color, width: width),
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'packages/endlessnet_ui/Inter',
      extensions: [colors],
      scaffoldBackgroundColor: colors.background,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: TextTheme(
        labelSmall: text(12, 16, FontWeight.w400),
        bodyMedium: text(14, 20, FontWeight.w400),
        bodyLarge: text(16, 24, FontWeight.w400),
        titleMedium: text(18, 26, FontWeight.w500),
        headlineSmall: text(24, 32, FontWeight.w600),
        headlineLarge: text(32, 40, FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(style: button),
      outlinedButtonTheme: OutlinedButtonThemeData(style: button),
      textButtonTheme: TextButtonThemeData(style: button),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(44, 44))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: border(colors.secondary),
        enabledBorder: border(colors.secondary),
        focusedBorder: border(colors.primary, 2),
        errorBorder: border(colors.error),
        focusedErrorBorder: border(colors.error, 2),
        contentPadding: const EdgeInsets.all(12),
      ),
      tooltipTheme: const TooltipThemeData(preferBelow: false),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
