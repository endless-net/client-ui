import 'dart:io';
import 'client_locale.dart';

/// UI-only preference, independent of endpoints, profiles and intention journals.
final class ClientLocaleStore {
  ClientLocaleStore(this.directory) {
    if (!directory.isAbsolute) {
      throw ArgumentError('UI settings require an absolute directory');
    }
  }
  final Directory directory;
  Future<void> _tail = Future<void>.value();
  File get _file => File.fromUri(directory.uri.resolve('language'));

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<ClientLocale?> read() => _serial(() async {
    final type = await FileSystemEntity.type(_file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw const FormatException('Invalid UI language file');
    }
    final handle = await _file.open();
    try {
      // Bounded even if another process changes the file during this read.
      final bytes = await handle.read(3);
      return switch (String.fromCharCodes(bytes)) {
        'en' => ClientLocale.en,
        'ru' => ClientLocale.ru,
        _ => throw const FormatException('Invalid UI language'),
      };
    } finally {
      await handle.close();
    }
  });

  Future<void> write(ClientLocale locale) => _serial(() async {
    await directory.create(recursive: true);
    final type = await FileSystemEntity.type(_file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const FormatException('Invalid UI language file');
    }
    final temporary = await directory.createTemp('language-');
    try {
      final file = File.fromUri(temporary.uri.resolve('language'));
      await file.writeAsString(locale.name, flush: true);
      await file.rename(_file.path);
    } finally {
      // Only the uniquely created temporary directory belongs to this write.
      await temporary.delete(recursive: true);
    }
  });
}

Directory clientLocaleDirectory() {
  final home =
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  if (home == null || home.isEmpty || !Directory(home).isAbsolute) {
    throw StateError('Caller home is required for UI settings');
  }
  return Directory('$home/.endlessnet/ui-settings');
}
