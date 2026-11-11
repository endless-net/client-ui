import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'releases.dart';

enum UpdateStatus {
  checking,
  current,
  available,
  installing,
  completed,
  restart,
  failed,
}

final class UpdateController extends ChangeNotifier {
  UpdateController(this.current, this.source, this.install);
  final ReleaseVersion current;
  final ReleaseSource source;
  final Future<int> Function(File, WindowsRelease) install;
  UpdateStatus status = UpdateStatus.checking;
  WindowsRelease? release;
  Timer? _timer;
  bool _busy = false, _disposed = false;

  void start() {
    if (_disposed || _timer != null) return;
    unawaited(check());
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(check()),
    );
  }

  void _show(UpdateStatus value) {
    if (_disposed) return;
    status = value;
    notifyListeners();
  }

  Future<void> check() async {
    if (_disposed ||
        _busy ||
        status == UpdateStatus.completed ||
        status == UpdateStatus.restart) {
      return;
    }
    _busy = true;
    _show(UpdateStatus.checking);
    try {
      final latest = await source.latest();
      if (_disposed) return;
      release = latest.version.compareTo(current) > 0 ? latest : null;
      _show(release == null ? UpdateStatus.current : UpdateStatus.available);
    } catch (_) {
      release = null;
      _show(UpdateStatus.failed);
    } finally {
      _busy = false;
    }
  }

  Future<void> update() async {
    if (_disposed ||
        _busy ||
        status != UpdateStatus.available ||
        release == null) {
      return;
    }
    _busy = true;
    final selected = release!;
    _show(UpdateStatus.installing);
    File? file;
    try {
      file = await source.download(selected);
      if (_disposed) return;
      final code = await install(file, selected);
      _show(switch (code) {
        0 => UpdateStatus.completed,
        3010 || 1641 => UpdateStatus.restart,
        _ => UpdateStatus.failed,
      });
    } catch (_) {
      _show(UpdateStatus.failed);
    } finally {
      if (file != null) {
        try {
          await file.parent.delete(recursive: true);
        } catch (_) {
          /* Temp cleanup is best effort after MSI exits. */
        }
      }
      _busy = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    source.close();
    // Never terminate a Windows Installer operation when the UI closes.
    super.dispose();
  }
}
