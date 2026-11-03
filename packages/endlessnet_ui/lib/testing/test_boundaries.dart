import 'dart:convert';
import 'dart:io';

class BoundaryIssue {
  const BoundaryIssue(this.file, this.line, this.rule);
  final String file, rule;
  final int line;
  @override
  String toString() => '$file:$line: $rule';
}

final _rules = <String, RegExp>{
  'geometry': RegExp(
    r'\b(getRect|getSize|getTopLeft|getTopRight|getBottomLeft|getBottomRight)\s*\(',
  ),
  'capture': RegExp(
    r'\b(matchesGoldenFile|matchesReferenceImage|compareWithGolden|toImage|takeScreenshot|screenshot)\s*\(',
  ),
  'viewport': RegExp(
    r'\b(physicalSize|devicePixelRatio|textScaleFactor)\s*=|\b(setSurfaceSize|TextScaler\.linear)\s*\(',
  ),
  'design dependency': RegExp(
    r'test_design[/\\]|componentFrames|DESIGN_\w*CAPTURE|COMPONENT_CAPTURE',
  ),
  'design assertions': RegExp(
    r'\bexpect\s*\([^;]*(\.(color|fontSize|fontFamily|fontWeight|padding|size|width|height|position|left|right|top|bottom|overflow)\b|takeException\s*\()',
    dotAll: true,
  ),
  'theme matrix': RegExp(
    r'for\s*\([^\n]*(theme|Theme|brightness|Brightness|viewport|textScale)',
  ),
  'external suite/process': RegExp(
    r'\bProcess\.(run|start|runSync|startSync)\s*\(|package:integration_test/',
  ),
};

/// Source-only rules; fixtures remain outside the ordinary test directory.
List<BoundaryIssue> inspectSource(String source, String file) {
  // Preserve line offsets; comments do not execute and are not assertions.
  final code = _maskComments(source);
  return [
    for (final rule in _rules.entries)
      for (final match in rule.value.allMatches(code))
        BoundaryIssue(
          file,
          '\n'.allMatches(code.substring(0, match.start)).length + 1,
          rule.key,
        ),
  ];
}

// Preserve quoted strings and line numbers, including // in URL/string values.
String _maskComments(String source) {
  final result = StringBuffer();
  var index = 0;
  while (index < source.length) {
    final char = source[index];
    if (char == "'" || char == '"') {
      final triple = source.startsWith(char * 3, index);
      final delimiter = triple ? char * 3 : char;
      final raw = index > 0 && source[index - 1] == 'r';
      result.write(delimiter);
      index += delimiter.length;
      while (index < source.length) {
        if (source.startsWith(delimiter, index)) {
          result.write(delimiter);
          index += delimiter.length;
          break;
        }
        if (!raw && source[index] == r'\' && index + 1 < source.length) {
          result.write(source.substring(index, index + 2));
          index += 2;
        } else {
          result.write(source[index++]);
        }
      }
    } else if (source.startsWith('//', index)) {
      while (index < source.length && source[index] != '\n') {
        result.write(' ');
        index++;
      }
    } else if (source.startsWith('/*', index)) {
      var depth = 1;
      result.write('  ');
      index += 2;
      while (index < source.length && depth > 0) {
        if (source.startsWith('/*', index)) {
          depth++;
          result.write('  ');
          index += 2;
        } else if (source.startsWith('*/', index)) {
          depth--;
          result.write('  ');
          index += 2;
        } else {
          result.write(source[index] == '\n' ? '\n' : ' ');
          index++;
        }
      }
    } else {
      result.write(char);
      index++;
    }
  }
  return result.toString();
}

/// No subprocesses, test execution or network: scan only unit sources/helpers.
List<BoundaryIssue> inspectProject(Directory app) {
  final root = app.absolute.uri.normalizePath();
  final testRoot = Directory.fromUri(root.resolve('test/'));
  if (!testRoot.existsSync()) {
    return [BoundaryIssue(testRoot.path, 1, 'ordinary test directory missing')];
  }
  final issues = <BoundaryIssue>[];
  final visited = <String>{};
  final scannerFiles = {
    for (final name in [
      'test_boundaries',
      'check_test_boundaries',
      'test_boundary_fixtures',
    ])
      root.resolve('tool/$name.dart').toFilePath(),
  };
  String relative(File file) =>
      file.absolute.uri.toString().substring(root.toString().length);
  void visit(File file) {
    final normalized = File.fromUri(file.absolute.uri.normalizePath());
    if (!visited.add(normalized.path) ||
        scannerFiles.contains(normalized.path)) {
      return;
    }
    if (!normalized.existsSync()) {
      issues.add(
        BoundaryIssue(normalized.path, 1, 'missing local test helper'),
      );
      return;
    }
    final content = _maskComments(normalized.readAsStringSync());
    issues.addAll(inspectSource(content, normalized.path));
    for (final directive in RegExp(
      r'\b(?:import|export|part)\s+([^;]+);',
    ).allMatches(content)) {
      for (final quoted in RegExp(
        "['\"]([^'\"]+)['\"]",
      ).allMatches(directive[1]!)) {
        final path = quoted[1]!;
        if (path.contains(':')) continue;
        final uri = normalized.uri.resolve(path).normalizePath();
        if (!uri.toString().startsWith(root.toString())) {
          issues.add(
            BoundaryIssue(normalized.path, 1, 'helper outside package'),
          );
        } else if (uri.toString().startsWith(root.resolve('lib/').toString())) {
          continue;
        } else if (uri.path.contains('/test_design/')) {
          issues.add(BoundaryIssue(normalized.path, 1, 'design helper import'));
        } else {
          visit(File.fromUri(uri));
        }
      }
    }
  }

  final tests = testRoot
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
  for (final file in tests) {
    visit(file);
  }
  final expected = tests
      .where((file) => file.path.endsWith('_test.dart'))
      .map(relative)
      .toSet();
  final ownProfile = File.fromUri(root.resolve('.ci/profile.json'));
  final profileFile = ownProfile.existsSync()
      ? ownProfile
      : File.fromUri(root.resolve('../.ci/profile.json'));
  final profile =
      jsonDecode(profileFile.readAsStringSync()) as Map<String, dynamic>;
  final modules = (profile['modules'] as List).cast<Map<String, dynamic>>();
  final module = modules.singleWhere(
    (module) => module['path'] == (ownProfile.existsSync() ? '.' : 'app'),
  );
  final entries = (module['unit'] as List).cast<String>();
  if (entries.toSet().length != entries.length ||
      entries.toSet().difference(expected).isNotEmpty ||
      expected.difference(entries.toSet()).isNotEmpty) {
    issues.add(
      BoundaryIssue(
        profileFile.path,
        1,
        'unit profile must list every ordinary test once, without design tests',
      ),
    );
  }
  return issues;
}
