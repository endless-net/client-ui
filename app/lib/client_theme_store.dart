import 'dart:io';
import 'package:flutter/material.dart';

/// UI-only preference, independent of endpoints, profiles and intention journals.
final class ClientThemeStore {
  ClientThemeStore(this.directory) {
    if (!directory.isAbsolute) {
      throw ArgumentError('UI settings require an absolute directory');
    }
  }
  final Directory directory;
  Future<void> _tail = Future<void>.value();
  File get _file => File.fromUri(directory.uri.resolve('theme'));

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<ThemeMode?> read() => _serial(() async {
    final type = await FileSystemEntity.type(_file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw const FormatException('Invalid UI theme file');
    }
    final handle = await _file.open();
    try {
      // Bounded even if another process changes the file during this read.
      final bytes = await handle.read(7);
      return switch (String.fromCharCodes(bytes)) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => throw const FormatException('Invalid UI theme'),
      };
    } finally {
      await handle.close();
    }
  });

  Future<void> write(ThemeMode mode) => _serial(() async {
    await directory.create(recursive: true);
    final type = await FileSystemEntity.type(_file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const FormatException('Invalid UI theme file');
    }
    final temporary = await directory.createTemp('theme-');
    try {
      final file = File.fromUri(temporary.uri.resolve('theme'));
      await file.writeAsString(mode.name, flush: true);
      await file.rename(_file.path);
    } finally {
      // Only the uniquely created temporary directory belongs to this write.
      await temporary.delete(recursive: true);
    }
  });
}
