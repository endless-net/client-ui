@Tags(['short'])
library;

import 'dart:ffi';
import 'package:endlessnet/client_build_target.dart';
import 'package:endlessnet/main.dart';
import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = <Abi, (String, api.Platform)>{
    Abi.windowsX64: ('windows/amd64', api.Platform.PLATFORM_WINDOWS),
    Abi.windowsArm64: ('windows/arm64', api.Platform.PLATFORM_WINDOWS),
    Abi.windowsIA32: ('windows/386', api.Platform.PLATFORM_WINDOWS),
    Abi.linuxX64: ('linux/amd64', api.Platform.PLATFORM_LINUX),
    Abi.linuxArm64: ('linux/arm64', api.Platform.PLATFORM_LINUX),
    Abi.linuxArm: ('linux/arm', api.Platform.PLATFORM_LINUX),
    Abi.linuxIA32: ('linux/386', api.Platform.PLATFORM_LINUX),
    Abi.linuxRiscv64: ('linux/riscv64', api.Platform.PLATFORM_LINUX),
    Abi.macosX64: ('macos/amd64', api.Platform.PLATFORM_MACOS),
    Abi.macosArm64: ('macos/arm64', api.Platform.PLATFORM_MACOS),
    Abi.androidX64: ('android/amd64', api.Platform.PLATFORM_ANDROID),
    Abi.androidArm64: ('android/arm64', api.Platform.PLATFORM_ANDROID),
    Abi.androidArm: ('android/arm', api.Platform.PLATFORM_ANDROID),
    Abi.androidIA32: ('android/386', api.Platform.PLATFORM_ANDROID),
    Abi.iosArm64: ('ios/arm64', api.Platform.PLATFORM_IOS),
    Abi.iosX64: ('ios/amd64', api.Platform.PLATFORM_IOS),
  };
  for (final entry in cases.entries) {
    test('UI build identity follows ${entry.key} without target override', () {
      expect(nativeClientBuildTarget(entry.key), entry.value.$1);
      final identity = desktopBuildIdentity(
        buildTarget: '',
        processAbi: entry.key,
      );
      expect(identity.platform, entry.value.$2);
      expect(identity.architecture, entry.value.$1.split('/').last);
      expect(identity.isFrozen, isTrue);
      expect(
        versionText(buildTarget: '', processAbi: entry.key),
        contains('target: ${entry.value.$1}\n'),
      );
    });
  }
  test('explicit build target still overrides local ABI', () {
    final identity = desktopBuildIdentity(
      buildTarget: 'darwin/arm64',
      processAbi: Abi.windowsX64,
    );
    expect(identity.platform, api.Platform.PLATFORM_MACOS);
    expect(identity.architecture, 'arm64');
    expect(
      versionText(buildTarget: 'darwin/arm64', processAbi: Abi.windowsX64),
      contains('target: darwin/arm64\n'),
    );
  });
  test('unmapped ABI fails rather than advertising a different platform', () {
    expect(
      () => nativeClientBuildTarget(Abi.fuchsiaX64),
      throwsUnsupportedError,
    );
  });
}
