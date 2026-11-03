import 'dart:io';

import 'package:endlessnet_ui/testing/test_boundaries.dart';

void main() {
  final issues = inspectProject(Directory.current);
  for (final issue in issues) {
    stderr.writeln(issue);
  }
  if (issues.isNotEmpty) {
    exitCode = 1;
  } else {
    stdout.writeln(
      'Functional test boundaries: PASS; design suite is separate.',
    );
  }
}
