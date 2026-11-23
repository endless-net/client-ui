import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'board.dart';
import 'telemetry.dart';

IconData tileIcon(TileKind kind) => switch (kind) {
  TileKind.hardware => Icons.memory_outlined,
  TileKind.network => Icons.speed,
  TileKind.disk => Icons.storage_outlined,
  TileKind.peripherals => Icons.keyboard_alt_outlined,
  TileKind.computer => Icons.desktop_windows_outlined,
  TileKind.tunnel => Icons.shield_outlined,
};

class TileData {
  const TileData({
    required this.host,
    required this.system,
    required this.processors,
    required this.monitor,
    required this.tunnelStatus,
  });
  final String host, system, tunnelStatus;
  final int processors;
  final HostMonitor monitor;
}

class TileContents extends StatelessWidget {
  const TileContents({
    super.key,
    required this.kind,
    required this.size,
    required this.data,
  });
  final TileKind kind;
  final TileSize size;
  final TileData data;

  @override
  Widget build(BuildContext context) {
    final monitor = data.monitor;
    final scheme = Theme.of(context).colorScheme;
    final sample = monitor.sample;
    final cpu = monitor.current.cpu;
    final history = monitor.history;
    final waiting = monitor.pending ? 'Первый замер…' : 'Нет данных';
    final interval = monitor.available ? 'Ожидаем следующий замер…' : waiting;
    final large = size == TileSize.large;
    final expanded = size != TileSize.square;
    return switch (kind) {
      TileKind.hardware => _Hardware(
        cpu: cpu,
        memory: sample?.memory,
        history: history,
        interval: interval,
        size: size,
        processors: data.processors,
      ),
      TileKind.network => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (expanded)
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    'Приём, Мбит/с',
                    _number(monitor.current.receive),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    'Отправка, Мбит/с',
                    _number(monitor.current.send),
                  ),
                ),
              ],
            )
          else ...[
            _Metric('Приём, Мбит/с', _number(monitor.current.receive)),
            const SizedBox(height: 8),
            _Metric('Отправка, Мбит/с', _number(monitor.current.send)),
          ],
          const SizedBox(height: 10),
          if (monitor.current.receive == null && monitor.current.send == null)
            _Caption(
              sample?.interfaces?.isEmpty == true
                  ? 'Нет активных физических адаптеров'
                  : interval,
            ),
          if (expanded) ...[
            _Chart(
              primary: history.map((point) => point.receive).toList(),
              secondary: history.map((point) => point.send).toList(),
              height: large ? 156 : 58,
            ),
            if (large)
              const _Caption('Общий трафик активных физических адаптеров'),
          ],
        ],
      ),
      TileKind.disk => switch (sample?.disk) {
        final capacity? => _CapacityTile(
          capacity: capacity,
          expanded: expanded,
        ),
        null => _Caption(waiting),
      },
      TileKind.peripherals =>
        sample?.keyboards == null || sample?.mice == null
            ? _Caption(waiting)
            : Column(
                children: [
                  _DeviceCount(
                    Icons.keyboard_alt_outlined,
                    'Клавиатуры',
                    sample!.keyboards!,
                  ),
                  const SizedBox(height: 8),
                  _DeviceCount(Icons.mouse_outlined, 'Мыши', sample.mice!),
                  if (expanded) ...[
                    const SizedBox(height: 12),
                    const _Caption('Устройства ввода, обнаруженные Windows'),
                  ],
                ],
              ),
      TileKind.computer => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Metric('Текущий ПК', data.host),
          if (expanded) ...[
            const SizedBox(height: 8),
            Text(data.system, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 8),
          _Caption('Логических процессоров: ${data.processors}'),
        ],
      ),
      TileKind.tunnel => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 28, color: scheme.primary),
          const SizedBox(height: 8),
          Text(
            data.tunnelStatus,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (expanded) ...[
            const SizedBox(height: 8),
            const _Caption(
              'Подробности открываются по статусу в верхней панели.',
            ),
          ],
        ],
      ),
    };
  }
}

String _number(double? value) {
  if (value == null) return '—';
  final precision = value == 0 || value >= 100
      ? 0
      : value < 1
      ? 2
      : 1;
  return value.toStringAsFixed(precision).replaceFirst('.', ',');
}

String _gigabytes(int bytes) {
  final amount = bytes / (1024 * 1024 * 1024);
  return '${amount.toStringAsFixed(amount < 100 ? 1 : 0).replaceFirst('.', ',')} ГиБ';
}

class _Hardware extends StatelessWidget {
  const _Hardware({
    required this.cpu,
    required this.memory,
    required this.history,
    required this.interval,
    required this.size,
    required this.processors,
  });
  final double? cpu;
  final Capacity? memory;
  final List<HostPoint> history;
  final String interval;
  final TileSize size;
  final int processors;

  @override
  Widget build(BuildContext context) {
    final ram = memory;
    final cpuValue = cpu == null ? '—' : '${(cpu! * 100).round()}%';
    final memoryValue = ram == null ? '—' : _gigabytes(ram.total - ram.free);
    final theme = Theme.of(context);
    return switch (size) {
      TileSize.square => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Metric('Загрузка CPU', cpuValue),
          const SizedBox(height: 8),
          _Caption(
            cpu == null ? interval : 'Логических процессоров: $processors',
          ),
        ],
      ),
      TileSize.wide => Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          _Metric('Загрузка CPU', cpuValue),
          _Metric('Оперативная память', memoryValue),
          if (cpu == null) _Caption(interval),
        ],
      ),
      TileSize.large => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Metric('Загрузка CPU', cpuValue),
                  if (cpu == null) _Caption(interval),
                  const SizedBox(height: 10),
                  _Chart(
                    primary: history.map((point) => point.cpu).toList(),
                    maximum: 1,
                    height: 112,
                  ),
                  const SizedBox(height: 6),
                  _Caption('Логических процессоров: $processors'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _Metric('Оперативная память', memoryValue),
          if (ram != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: 1 - ram.free / ram.total,
              semanticsLabel: 'Доля занятой оперативной памяти',
            ),
            const SizedBox(height: 8),
            _Caption('Всего ${_gigabytes(ram.total)}'),
          ] else
            _Caption(interval),
        ],
      ),
    };
  }
}

class _CapacityTile extends StatelessWidget {
  const _CapacityTile({required this.capacity, required this.expanded});
  final Capacity capacity;
  final bool expanded;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Metric('Свободно на системном томе', _gigabytes(capacity.free)),
      const SizedBox(height: 12),
      LinearProgressIndicator(
        value: 1 - capacity.free / capacity.total,
        semanticsLabel: 'Доля занятого места на диске',
      ),
      const SizedBox(height: 8),
      _Caption(
        expanded
            ? 'Занято ${_gigabytes(capacity.total - capacity.free)} из ${_gigabytes(capacity.total)}'
            : 'Всего ${_gigabytes(capacity.total)}',
      ),
    ],
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Caption(label),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
    ],
  );
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontSize: 12,
    ),
  );
}

class _DeviceCount extends StatelessWidget {
  const _DeviceCount(this.icon, this.name, this.count);
  final IconData icon;
  final String name;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(name)),
      Text('$count', style: Theme.of(context).textTheme.titleMedium),
    ],
  );
}

class _Chart extends StatelessWidget {
  const _Chart({
    required this.primary,
    this.secondary,
    this.maximum,
    required this.height,
  });
  final List<double?> primary;
  final List<double?>? secondary;
  final double? maximum;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(double.infinity, height),
        painter: _ChartPainter(
          primary,
          secondary,
          maximum,
          colors.primary,
          colors.secondary,
          colors.outlineVariant,
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  const _ChartPainter(
    this.primary,
    this.secondary,
    this.maximum,
    this.accent,
    this.alternate,
    this.grid,
  );
  final List<double?> primary;
  final List<double?>? secondary;
  final double? maximum;
  final Color accent, alternate, grid;

  @override
  void paint(Canvas canvas, Size size) {
    final scale =
        maximum ??
        [
          ...primary.whereType<double>(),
          ...?secondary?.whereType<double>(),
          0.1,
        ].reduce(math.max);
    for (final ratio in [0.0, .5, 1.0]) {
      final y = ratio * size.height;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()..color = grid,
      );
    }

    void draw(List<double?> values, Color color) {
      final path = Path();
      var connected = false;
      for (var i = 0; i < values.length; i++) {
        final value = values[i];
        if (value == null) {
          connected = false;
          continue;
        }
        final x = (30 - values.length + i) * size.width / 29;
        final y = size.height * (1 - (value / scale).clamp(0, 1));
        if (connected) {
          path.lineTo(x, y);
        } else {
          path.moveTo(x, y);
          canvas.drawCircle(Offset(x, y), 1.5, Paint()..color = color);
        }
        connected = true;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 1.7
          ..style = PaintingStyle.stroke,
      );
    }

    draw(primary, accent);
    if (secondary case final series?) draw(series, alternate);
  }

  @override
  bool shouldRepaint(_ChartPainter oldDelegate) =>
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.maximum != maximum ||
      oldDelegate.accent != accent ||
      oldDelegate.alternate != alternate ||
      oldDelegate.grid != grid;
}
