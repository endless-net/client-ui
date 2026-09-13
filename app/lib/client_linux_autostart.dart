import 'dart:convert';
import 'dart:io';

enum ClientAutostartSetting { notConfigured, enabled, disabled }

String clientAutostartExec(String executable) {
  if (!executable.startsWith('/') ||
      executable.contains('=') ||
      executable.runes.any((c) => c < 32 || c == 127)) {
    throw const FormatException('Invalid autostart executable');
  }
  final quoted = executable
      .replaceAllMapped(RegExp(r'["`$\\]'), (match) => '\\${match[0]}')
      .replaceAll('%', '%%')
      .replaceAll('\\', '\\\\');
  return '"$quoted"';
}

Directory clientLinuxAutostartDirectory(Map<String, String> environment) {
  final configured = environment['XDG_CONFIG_HOME'];
  if (configured != null && configured.isNotEmpty) {
    if (!configured.startsWith('/')) {
      throw const FormatException('Absolute XDG config required');
    }
    return Directory('$configured/autostart');
  }
  final home = environment['HOME'];
  if (home == null || !home.startsWith('/')) {
    throw const FormatException('Absolute home required');
  }
  return Directory('$home/.config/autostart');
}

/// Own user entry only, never a claim about system-wide autostart policy.
final class ClientLinuxAutostart {
  ClientLinuxAutostart(this.directory, String executable)
    : _exec = clientAutostartExec(executable) {
    if (!directory.isAbsolute) {
      throw ArgumentError('Absolute autostart directory required');
    }
  }
  final Directory directory;
  final String _exec;
  Future<void> _tail = Future<void>.value();
  File get _file =>
      File.fromUri(directory.uri.resolve('endlessnet.app.desktop'));
  String _entry(bool enabled) =>
      '[Desktop Entry]\nType=Application\nName=EndlessNet\n'
      'Exec=$_exec\nTerminal=false\nHidden=${!enabled}\n';

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<ClientAutostartSetting> read() => _serial(_read);
  Future<ClientAutostartSetting> _read() async {
    final type = await FileSystemEntity.type(_file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return ClientAutostartSetting.notConfigured;
    }
    if (type != FileSystemEntityType.file) {
      throw const FormatException('Unrecognized autostart entry');
    }
    final handle = await _file.open();
    late String content;
    try {
      content = utf8.decode(await handle.read(65537));
    } finally {
      await handle.close();
    }
    if (content == _entry(true)) return ClientAutostartSetting.enabled;
    if (content == _entry(false)) return ClientAutostartSetting.disabled;
    throw const FormatException('Unrecognized autostart entry');
  }

  Future<ClientAutostartSetting> setEnabled(bool enabled) => _serial(() async {
    await _read(); // Do not overwrite foreign/modified entries or symlinks.
    await directory.create(recursive: true);
    final temporary = await directory.createTemp('endlessnet-autostart-');
    try {
      final file = File.fromUri(temporary.uri.resolve('entry.desktop'));
      await file.writeAsString(_entry(enabled), flush: true);
      await file.rename(_file.path);
    } finally {
      await temporary.delete(recursive: true);
    }
    return _read();
  });
}
