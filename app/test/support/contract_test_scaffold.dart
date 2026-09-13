import 'package:flutter/material.dart';

/// Use real platform insets. Do not hide iOS hit-test failures by forcing a
/// zero-padding MediaQuery or invoking button callbacks directly.
class ContractTestScaffold extends StatelessWidget {
  const ContractTestScaffold({super.key, required this.body});
  final Widget body;

  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: body));
}
