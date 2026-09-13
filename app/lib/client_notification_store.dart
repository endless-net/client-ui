import 'dart:io';

/// UI preference only; never stores notification content or runtime identity.
final class ClientNotificationStore {
  ClientNotificationStore(this.directory) {
    if (!directory.isAbsolute) {
      throw ArgumentError('Absolute settings directory required');
    }
  }
  final Directory directory;
  File get _file => File.fromUri(directory.uri.resolve('notifications'));
  Future<void> _tail = Future<void>.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<bool?> read() => _serial(() async {
    final type = await FileSystemEntity.type(_file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw const FormatException('Invalid notification setting');
    }
    final handle = await _file.open();
    try {
      return switch (String.fromCharCodes(await handle.read(2))) {
        '0' => false,
        '1' => true,
        _ => throw const FormatException('Invalid notification setting'),
      };
    } finally {
      await handle.close();
    }
  });

  Future<void> write(bool enabled) => _serial(() async {
    await directory.create(recursive: true);
    final type = await FileSystemEntity.type(_file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const FormatException('Invalid notification setting');
    }
    final temporary = await directory.createTemp('notifications-');
    try {
      final file = File.fromUri(temporary.uri.resolve('notifications'));
      await file.writeAsString(enabled ? '1' : '0', flush: true);
      await file.rename(_file.path);
    } finally {
      await temporary.delete(recursive: true);
    }
  });
}
