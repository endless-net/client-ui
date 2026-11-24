import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef Capacity = ({int free, int total});
typedef IoCount = ({int received, int sent});

class HostSample {
  const HostSample({
    required this.time,
    this.cpu,
    this.memory,
    this.disk,
    this.interfaces,
    this.keyboards,
    this.mice,
  });

  factory HostSample.fromMap(Map<Object?, Object?> values, Duration time) {
    Capacity? capacity(String freeKey, String totalKey) {
      final free = values[freeKey], total = values[totalKey];
      return free is int &&
              total is int &&
              total > 0 &&
              free >= 0 &&
              free <= total
          ? (free: free, total: total)
          : null;
    }

    final idle = values['idle'], total = values['cpu'];
    final network = values['interfaces'];
    final interfaces = network is Map
        ? <Object?, IoCount>{
            for (final MapEntry(:key, :value) in network.entries)
              if (value is List &&
                  value.length == 2 &&
                  value[0] is int &&
                  value[1] is int)
                key: (received: value[0] as int, sent: value[1] as int),
          }
        : null;
    return HostSample(
      time: time,
      cpu: idle is int && total is int ? (idle: idle, total: total) : null,
      memory: capacity('memoryFree', 'memoryTotal'),
      disk: capacity('diskFree', 'diskTotal'),
      interfaces: interfaces,
      keyboards: values['keyboards'] as int?,
      mice: values['mice'] as int?,
    );
  }

  final Duration time;
  final ({int idle, int total})? cpu;
  final Capacity? memory, disk;
  final Map<Object?, IoCount>? interfaces;
  final int? keyboards, mice;
}

typedef HostPoint = ({double? cpu, double? receive, double? send});

HostPoint measure(HostSample? before, HostSample after) {
  double? cpu, receive, send;
  if (before != null) {
    final micros = (after.time - before.time).inMicroseconds;
    if (micros >= 500000 && micros <= 8000000) {
      if (before.cpu case final previous?) {
        if (after.cpu case final current?) {
          final total = current.total - previous.total;
          final idle = current.idle - previous.idle;
          if (total > 0 && idle >= 0 && idle <= total) cpu = 1 - idle / total;
        }
      }
      final old = before.interfaces, next = after.interfaces;
      if (old != null &&
          next != null &&
          next.isNotEmpty &&
          setEquals(old.keys.toSet(), next.keys.toSet())) {
        var incoming = 0, outgoing = 0;
        var valid = true;
        for (final MapEntry(:key, :value) in next.entries) {
          final baseline = old[key]!;
          final rx = value.received - baseline.received;
          final tx = value.sent - baseline.sent;
          if (rx < 0 || tx < 0) {
            valid = false;
            break;
          }
          incoming += rx;
          outgoing += tx;
        }
        if (valid) {
          // Bytes per observation interval → megabits per second.
          receive = incoming * 8 / micros;
          send = outgoing * 8 / micros;
        }
      }
    }
  }
  return (cpu: cpu, receive: receive, send: send);
}

class HostMonitor extends ChangeNotifier {
  final _clock = Stopwatch()..start();
  static const _channel = MethodChannel('endlessnet/dashboard');
  HostSample? sample;
  final _history = <HostPoint>[];
  HostPoint get current =>
      _history.isEmpty ? (cpu: null, receive: null, send: null) : _history.last;
  List<HostPoint> get history => List.unmodifiable(_history);
  bool get available => Platform.isWindows && sample != null;
  bool get pending => Platform.isWindows && !_resolved;
  Timer? _timer;
  bool _running = false, _disposed = false, _resolved = false;

  void start() {
    if (!Platform.isWindows || _timer != null) return;
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_read()),
    );
    unawaited(_read());
  }

  Future<void> _read() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      final values = await _channel.invokeMapMethod<Object?, Object?>(
        'snapshot',
      );
      if (_disposed) return;
      if (values == null || values.isEmpty) {
        _clearMeasurement();
      } else {
        final next = HostSample.fromMap(values, _clock.elapsed);
        _append(measure(sample, next));
        sample = next;
      }
    } catch (_) {
      if (!_disposed) _clearMeasurement();
    } finally {
      _running = false;
      _resolved = true;
      if (!_disposed) notifyListeners();
    }
  }

  void _clearMeasurement() {
    sample = null;
    _append((cpu: null, receive: null, send: null));
  }

  void _append(HostPoint point) {
    _history.add(point);
    if (_history.length > 30) _history.removeAt(0);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
