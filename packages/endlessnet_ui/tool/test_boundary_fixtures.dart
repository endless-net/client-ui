import 'dart:convert';
import 'dart:io';

const forbiddenSources = <String>[
  'tester.getSize(find.byType(Button));',
  'expect(value, matchesGoldenFile("x.png"));',
  'tester.view.physicalSize = Size(360, 640);',
  'import "../test_design/components/helper.dart";',
  'import "../test_design/../test_design/components/helper.dart";',
  'expect(style.color, Colors.red);',
  'expect(style.fontSize, 14);',
  'expect(tester.takeException(), isNull);',
  'for (final theme in themes) { run(theme); }',
  'Process.run("flutter", ["test"]);',
  'final s = "http://example"; tester.getRect(widget);',
  'final s = r"/* quoted */"; expect(box.width, 10);',
  'expect(style.fontFamily, "Inter");',
];
const allowedSource = '''
// tester.getRect is only a comment, not executable acceptance.
/* import '../test_design/ignored.dart'; */
expect(find.text('Ошибка'), findsOneWidget);
expect(calls, 1);
expect(node.hasFlag(SemanticsFlag.isEnabled), isFalse);
await tester.enterText(find.byType(TextField), 'Новый текст');
''';

class BoundaryProjectFixture {
  BoundaryProjectFixture() {
    app.createSync(recursive: true);
    Directory('${app.path}/test').createSync();
    Directory('${root.path}/.ci').createSync();
    File('${app.path}/test/sample_test.dart').writeAsStringSync(allowedSource);
    setProfile(['test/sample_test.dart']);
  }
  final root = Directory.systemTemp.createTempSync('endlessnet-boundary-unit-');
  late final app = Directory('${root.path}/app');
  void setProfile(List<String> entries) => File('${root.path}/.ci/profile.json')
      .writeAsStringSync(
        jsonEncode({
          'modules': [
            {'path': 'app', 'unit': entries},
          ],
        }),
      );
  void setTest(String source) =>
      File('${app.path}/test/sample_test.dart').writeAsStringSync(source);
  void addHelper(String source) {
    Directory('${app.path}/helpers').createSync();
    File('${app.path}/helpers/helper.dart').writeAsStringSync(source);
    setTest("import '../helpers/helper.dart';");
  }

  void dispose() => root.deleteSync(recursive: true);
}

const escapedDesignImport =
    "import '../helpers/../test_design/components/hidden.dart';";
