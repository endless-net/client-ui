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
      background: dark ? BrandTokens.dark : const Color(0xFFE6F3FD),
      surface: Color(dark ? 0xFF142A41 : 0xFFF9FCFE),
      text: Color(dark ? 0xFFF8FAFF : 0xFF0F1720),
      secondary: Color(dark ? 0xFFC6D2E0 : 0xFF3B4856),
      primary: dark ? BrandTokens.cyan : const Color(0xFF007783),
      onPrimary: dark ? const Color(0xFF111923) : Colors.white,
      success: Color(dark ? 0xFFB1F1D0 : 0xFF216A42),
      error: Color(dark ? 0xFFFF8A80 : 0xFFB42318),
      warning: Color(dark ? 0xFFFCD34D : 0xFF854D0E),
      motion: reduced ? Duration.zero : BrandTokens.duration,
    );
    final panel = Color(dark ? 0xFF0E1F32 : 0xFFF4FAFE);
    final inset = Color(dark ? 0xFF0F2134 : 0xFFF1F8FE);
    final raised = Color(dark ? 0xFF283D54 : 0xFFE8F4FD);
    final selected = Color(dark ? 0xFF154D64 : 0xFFE3F2FD);
    final accent = Color(dark ? 0xFFA8B2FF : 0xFF434DB0);
    final divider = Color(dark ? 0xFF3D5065 : 0xFFA5B8C8);
    final outline = Color(dark ? 0xFF829BB2 : 0xFF718597);
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
          primaryContainer: selected,
          onPrimaryContainer: colors.text,
          secondary: accent,
          onSecondary: colors.onPrimary,
          secondaryContainer: selected,
          onSecondaryContainer: colors.text,
          surface: colors.surface,
          onSurface: colors.text,
          onSurfaceVariant: colors.secondary,
          surfaceDim: colors.background,
          surfaceBright: raised,
          surfaceContainerLowest: colors.background,
          surfaceContainerLow: panel,
          surfaceContainer: inset,
          surfaceContainerHigh: raised,
          surfaceContainerHighest: raised,
          surfaceTint: Colors.transparent,
          error: colors.error,
          onError: colors.onPrimary,
          outline: outline,
          outlineVariant: divider,
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
      dividerColor: divider,
      focusColor: colors.primary.withValues(alpha: .16),
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
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: button.copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return null;
            return BorderSide(color: outline);
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: button),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(44, 44))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inset,
        border: border(outline),
        enabledBorder: border(outline),
        focusedBorder: border(colors.primary, 2),
        errorBorder: border(colors.error),
        focusedErrorBorder: border(colors.error, 2),
        contentPadding: const EdgeInsets.all(12),
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: panel,
        foregroundColor: colors.text,
        scrolledUnderElevation: 0,
      ),
      drawerTheme: DrawerThemeData(backgroundColor: panel),
      listTileTheme: ListTileThemeData(
        selectedColor: colors.text,
        selectedTileColor: selected,
      ),
      popupMenuTheme: PopupMenuThemeData(color: raised),
      tooltipTheme: const TooltipThemeData(preferBelow: false),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
          side: BorderSide(color: divider),
        ),
      ),
    );
  }
}
