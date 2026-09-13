import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// Process-level outcome only, never proof that a runtime operation completed.
enum PrivilegedHelperResult { completed, canceled, failed }

bool launchWindowsProcessElevated(String executable, List<String> arguments) {
  final verbPtr = 'runas'.toNativeUtf16();
  final executablePtr = executable.toNativeUtf16();
  final parametersPtr = arguments
      .map(quoteWindowsCommandLineArgument)
      .join(' ')
      .toNativeUtf16();
  try {
    final result = ShellExecute(
      null,
      PCWSTR(verbPtr),
      PCWSTR(executablePtr),
      PCWSTR(parametersPtr),
      null,
      SW_SHOWNORMAL,
    );
    return result.address > 32;
  } finally {
    calloc.free(verbPtr);
    calloc.free(executablePtr);
    calloc.free(parametersPtr);
  }
}

PrivilegedHelperResult launchWindowsProcessElevatedAndWait(
  String executable,
  List<String> arguments,
) {
  const seeMaskNoCloseProcess = 0x00000040;
  const workerTimeoutMilliseconds = 120000;
  final verbPtr = 'runas'.toNativeUtf16();
  final executablePtr = executable.toNativeUtf16();
  final parametersPtr = arguments
      .map(quoteWindowsCommandLineArgument)
      .join(' ')
      .toNativeUtf16();
  final executeInfo = calloc<SHELLEXECUTEINFO>();
  try {
    executeInfo.ref
      ..cbSize = ffi.sizeOf<SHELLEXECUTEINFO>()
      ..fMask = seeMaskNoCloseProcess
      ..lpVerb = PWSTR(verbPtr)
      ..lpFile = PWSTR(executablePtr)
      ..lpParameters = PWSTR(parametersPtr)
      ..nShow = SW_HIDE;
    final launched = ShellExecuteEx(executeInfo);
    if (!launched.value || !executeInfo.ref.hProcess.isValid) {
      return launched.error == ERROR_CANCELLED
          ? PrivilegedHelperResult.canceled
          : PrivilegedHelperResult.failed;
    }

    final process = executeInfo.ref.hProcess;
    try {
      final waitResult = WaitForSingleObject(
        process,
        workerTimeoutMilliseconds,
      );
      if (waitResult.value != WAIT_OBJECT_0) {
        return PrivilegedHelperResult.failed;
      }
      final exitCodePtr = calloc<ffi.Uint32>();
      try {
        final readExitCode = GetExitCodeProcess(process, exitCodePtr);
        return readExitCode.value && exitCodePtr.value == 0
            ? PrivilegedHelperResult.completed
            : PrivilegedHelperResult.failed;
      } finally {
        calloc.free(exitCodePtr);
      }
    } finally {
      process.close();
    }
  } finally {
    calloc.free(executeInfo);
    calloc.free(verbPtr);
    calloc.free(executablePtr);
    calloc.free(parametersPtr);
  }
}

String quoteWindowsCommandLineArgument(String value) {
  if (value.isEmpty) {
    return '""';
  }
  if (!RegExp(r'[\s"]').hasMatch(value)) {
    return value;
  }
  final quoted = StringBuffer('"');
  var backslashes = 0;
  void writeBackslashes(int count) {
    for (var i = 0; i < count; i++) {
      quoted.write(r'\');
    }
  }

  for (final codeUnit in value.codeUnits) {
    if (codeUnit == 0x5c) {
      backslashes++;
      continue;
    }
    if (codeUnit == 0x22) {
      writeBackslashes(backslashes * 2 + 1);
      quoted.write('"');
      backslashes = 0;
      continue;
    }
    writeBackslashes(backslashes);
    backslashes = 0;
    quoted.writeCharCode(codeUnit);
  }
  writeBackslashes(backslashes * 2);
  quoted.write('"');
  return quoted.toString();
}
