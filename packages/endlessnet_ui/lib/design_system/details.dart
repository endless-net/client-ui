import 'package:flutter/material.dart';

import 'controls.dart';
import 'theme.dart';

/// C18. Missing and empty values remain distinct; caller owns expansion.
class EnDetails extends StatelessWidget {
  const EnDetails({
    super.key,
    required this.values,
    this.title,
    this.expanded = true,
    this.onExpand,
  });
  final Map<String, String?> values;
  final String? title;
  final bool expanded;
  final ValueChanged<bool>? onExpand;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (title != null)
        Semantics(
          expanded: expanded,
          child: TextButton(
            onPressed: onExpand == null ? null : () => onExpand!(!expanded),
            child: Text('${expanded ? '−' : '+'} $title'),
          ),
        ),
      if (expanded)
        for (final entry in values.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '${entry.key}: ${entry.value == null
                  ? 'Нет значения'
                  : entry.value!.isEmpty
                  ? 'Пустое значение'
                  : entry.value}',
            ),
          ),
    ],
  );
}

/// C19. null = indeterminate, invalid fraction = unknown; never clamp to success.
class EnProgress extends StatelessWidget {
  const EnProgress({super.key, required this.label, this.value, this.action});
  final String label;
  final double? value;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final invalid =
        value != null && (!value!.isFinite || value! < 0 || value! > 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        if (invalid)
          const Text('Прогресс неизвестен')
        else ...[
          LinearProgressIndicator(value: value, semanticsLabel: label),
          Text(value == null ? 'Выполняется' : '${(value! * 100).round()}%'),
        ],
        if (action != null)
          Align(alignment: Alignment.centerLeft, child: action!),
      ],
    );
  }
}

/// C20. Copy result is explicit. Sensitive values cannot reach copy callbacks.
class EnMachineText extends StatefulWidget {
  const EnMachineText({
    super.key,
    required this.text,
    this.sensitive = false,
    this.selectable = true,
    this.copyable = true,
    this.onCopy,
  });
  final String text;
  final bool sensitive, selectable, copyable;
  final Future<void> Function(String)? onCopy;
  @override
  State<EnMachineText> createState() => _EnMachineTextState();
}

class _EnMachineTextState extends State<EnMachineText> {
  String? _result;
  int _generation = 0;
  @override
  void didUpdateWidget(EnMachineText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.sensitive != widget.sensitive) {
      _generation++;
      _result = null;
    }
  }

  Future<void> _copy() async {
    final generation = _generation;
    String result;
    try {
      await widget.onCopy!(widget.text);
      result = 'Скопировано';
    } catch (_) {
      result = 'Не удалось скопировать';
    }
    if (mounted && generation == _generation && !widget.sensitive) {
      setState(() => _result = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.sensitive ? 'Скрыто' : widget.text;
    final style = TextStyle(
      fontFamily: 'NotoSansMono',
      package: 'endlessnet_ui',
      color: BrandColors.of(context).text,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.selectable && !widget.sensitive)
          SelectableText(value, style: style)
        else
          Text(value, style: style),
        if (!widget.sensitive && widget.copyable && widget.onCopy != null)
          Align(
            alignment: Alignment.centerLeft,
            child: EnButton(
              label: 'Копировать',
              kind: EnButtonKind.secondary,
              onPressed: _copy,
            ),
          ),
        if (_result != null && !widget.sensitive)
          Semantics(liveRegion: true, child: Text(_result!)),
      ],
    );
  }
}
