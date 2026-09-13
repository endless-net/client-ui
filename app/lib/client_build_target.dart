import 'dart:ffi';

/// Dart ABI describes this UI process, not the host OS's possible architectures.
/// Never advertise Windows/amd64 for an unconfigured ARM or POSIX build.
String nativeClientBuildTarget(Abi abi) => switch (abi) {
  Abi.windowsX64 => 'windows/amd64',
  Abi.windowsArm64 => 'windows/arm64',
  Abi.windowsIA32 => 'windows/386',
  Abi.linuxX64 => 'linux/amd64',
  Abi.linuxArm64 => 'linux/arm64',
  Abi.linuxArm => 'linux/arm',
  Abi.linuxIA32 => 'linux/386',
  Abi.linuxRiscv64 => 'linux/riscv64',
  Abi.macosX64 => 'macos/amd64',
  Abi.macosArm64 => 'macos/arm64',
  Abi.androidX64 => 'android/amd64',
  Abi.androidArm64 => 'android/arm64',
  Abi.androidArm => 'android/arm',
  Abi.androidIA32 => 'android/386',
  Abi.iosArm64 => 'ios/arm64',
  Abi.iosX64 => 'ios/amd64',
  _ => throw UnsupportedError('Unsupported client UI process ABI'),
};
