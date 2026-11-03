import 'package:flutter/material.dart';

/// C01. Outlined source wordmark in a PNG; no font or recoloring dependency.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.width = 160});
  final double width;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final effectiveWidth = width < 160 ? 160.0 : width;
    return Semantics(
      label: 'EndlessNet',
      image: true,
      child: Padding(
        // Conservative clear space exceeds half the source E height.
        padding: EdgeInsets.all(effectiveWidth / 10),
        child: Image.asset(
          'assets/brand/logo-${dark ? 'dark' : 'light'}.png',
          package: 'endlessnet_ui',
          width: effectiveWidth,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    size <= 32 ? 'assets/brand/mark-small.png' : 'assets/brand/mark.png',
    package: 'endlessnet_ui',
    width: size <= 32 ? size.clamp(16, 32) : size.clamp(48, double.infinity),
    semanticLabel: 'EndlessNet',
    fit: BoxFit.contain,
  );
}
