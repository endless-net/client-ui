@Tags(['short'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Source guards only: these do not compile or qualify a native application.
void main() {
  test('Linux host uses the selected application identity', () {
    final cmake = File('linux/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('set(APPLICATION_ID "endlessnet.app")'));
    final runner = File('linux/runner/my_application.cc').readAsStringSync();
    expect(runner, contains('gtk_window_set_title(window, "EndlessNet")'));
    expect(
      runner,
      contains('gtk_header_bar_set_title(header_bar, "EndlessNet")'),
    );
  });

  test('macOS bundle identifier is distinct from its build product name', () {
    final config = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    expect(config, contains('PRODUCT_BUNDLE_IDENTIFIER = endlessnet.app'));
    expect(config, contains('PRODUCT_NAME = EndlessNet'));
    final project = File(
      'macos/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    expect(project, contains('path = "EndlessNet.app"'));
    expect(
      project,
      contains('PRODUCT_BUNDLE_IDENTIFIER = endlessnet.app.RunnerTests'),
    );
    expect(
      project,
      contains(
        r'$(BUILT_PRODUCTS_DIR)/EndlessNet.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/EndlessNet',
      ),
    );
    final scheme = File(
      'macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
    ).readAsStringSync();
    expect('BuildableName = "EndlessNet.app"'.allMatches(scheme), hasLength(5));
    expect(project, isNot(contains('endlessnet.endlessnet')));
  });

  test('macOS version comes from the existing Flutter build settings', () {
    final plist = File('macos/Runner/Info.plist').readAsStringSync();
    expect(plist, contains(r'<string>$(FLUTTER_BUILD_NAME)</string>'));
    expect(plist, contains(r'<string>$(FLUTTER_BUILD_NUMBER)</string>'));
  });
}
