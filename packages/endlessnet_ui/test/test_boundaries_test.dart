import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:endlessnet_ui/testing/test_boundaries.dart';

import '../tool/test_boundary_fixtures.dart';

void main() {
  test(
    'guard checks transitive helpers, normalized imports and profile failures',
    () {
      final fixture = BoundaryProjectFixture();
      try {
        expect(inspectProject(fixture.app), isEmpty);
        fixture.addStandaloneIntegrationDriver();
        expect(inspectProject(fixture.app), isEmpty);
        fixture.importIntegrationDriver();
        expect(inspectProject(fixture.app), isNotEmpty);
        fixture.addHelper(forbiddenSources.first);
        expect(inspectProject(fixture.app), isNotEmpty);
        fixture.setTest(escapedDesignImport);
        expect(inspectProject(fixture.app), isNotEmpty);
        fixture.setTest(allowedSource);
        fixture.setProfile([]);
        expect(inspectProject(fixture.app), isNotEmpty);
        fixture.setProfile(['test/sample_test.dart', 'test/sample_test.dart']);
        expect(inspectProject(fixture.app), isNotEmpty);
      } finally {
        fixture.dispose();
      }
    },
  );
  test(
    'C01–C20 ordinary test sources and declared entrypoints stay independent',
    () {
      expect(inspectProject(Directory.current), isEmpty);
    },
  );
  test('boundary scanner rejects forbidden fixtures with file and line', () {
    for (final source in forbiddenSources) {
      final findings = inspectSource('\n$source', 'fixture.dart');
      expect(findings, isNotEmpty, reason: source);
      expect(findings.first.file, 'fixture.dart');
      expect(findings.first.line, 2);
    }
    expect(inspectSource(allowedSource, 'allowed.dart'), isEmpty);
  });
}
