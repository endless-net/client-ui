import 'package:flutter/material.dart';

/// C01. Literal brand values from EndlessNet front/logo-pack, not page CSS.
abstract final class BrandTokens {
  static const dark = Color(0xFF07111D);
  static const darkAlt = Color(0xFF0B1726);
  static const light = Color(0xFFF7F9FC);
  static const ink = Color(0xFF081321);
  static const white = Color(0xFFF5F8FC);
  static const cyan = Color(0xFF19D8F2);
  static const blue = Color(0xFF128CFF);
  static const indigo = Color(0xFF244BFF);
  static const muted = Color(0xFF8DA0B6);
  static const spacing = <double>[4, 8, 12, 16, 24, 32, 48];
  static const controlRadius = 8.0;
  static const cardRadius = 12.0;
  static const dialogRadius = 16.0;
  static const target = 44.0;
  static const focusWidth = 2.0;
  static const focusOffset = 2.0;
  static const duration = Duration(milliseconds: 150);
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyan, blue, indigo],
    stops: [0, .52, 1],
  );
}
