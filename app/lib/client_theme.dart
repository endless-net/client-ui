import 'package:flutter/material.dart';

ThemeData clientTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xFF0B1422) : const Color(0xFFF4F7FB);
  final surface = dark ? const Color(0xFF142236) : Colors.white;
  final border = dark ? const Color(0xFF293B52) : const Color(0xFFE1E7F0);
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xFF387BFF),
    brightness: brightness,
    primary: dark ? const Color(0xFF78A8FF) : const Color(0xFF1864F2),
    surface: surface,
    onSurface: dark ? const Color(0xFFF1F5FC) : const Color(0xFF17253C),
    onSurfaceVariant: dark ? const Color(0xFFB2C5DF) : const Color(0xFF526581),
    secondaryContainer: dark
        ? const Color(0xFF19365A)
        : const Color(0xFFE3EDFF),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colors,
    scaffoldBackgroundColor: background,
    dividerColor: border,
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF1864F2),
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: background,
      indicatorColor: colors.secondaryContainer,
      surfaceTintColor: Colors.transparent,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: background,
      indicatorColor: colors.secondaryContainer,
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
    ),
  );
}
