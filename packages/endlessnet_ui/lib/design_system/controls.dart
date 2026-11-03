import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';
import 'tokens.dart';

enum EnButtonKind { primary, secondary, text, danger, icon }

/// C02. An action only; it does not infer domain permission or server success.
class EnButton extends StatefulWidget {
  const EnButton({
    super.key,
    required this.label,
    this.onPressed,
    this.onError,
    this.kind = EnButtonKind.primary,
    this.icon,
    this.enabled = true,
    this.pending = false,
    this.disabledReason,
    this.autofocus = false,
  });
  final String label;
  final FutureOr<void> Function()? onPressed;
  final ValueChanged<Object>? onError;
  final EnButtonKind kind;
  final IconData? icon;
  final bool enabled, pending, autofocus;
  final String? disabledReason;
  @override
  State<EnButton> createState() => _EnButtonState();
}

class _EnButtonState extends State<EnButton> {
  bool _busy = false;
  bool _focused = false;
  Future<void> _activate() async {
    if (_busy ||
        widget.pending ||
        !widget.enabled ||
        widget.onPressed == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } catch (error, stack) {
      if (widget.onError != null) {
        widget.onError!(error);
      } else {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stack),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _busy || widget.pending;
    final action = widget.enabled && !pending && widget.onPressed != null
        ? _activate
        : null;
    final colors = BrandColors.of(context);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pending) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              semanticsLabel: 'Выполняется',
            ),
          ),
          const SizedBox(width: 8),
        ] else if (widget.icon != null && widget.kind != EnButtonKind.icon) ...[
          Icon(widget.icon, size: 20),
          const SizedBox(width: 8),
        ],
        Flexible(child: Text(widget.label)),
      ],
    );
    final button = switch (widget.kind) {
      EnButtonKind.primary => FilledButton(
        onPressed: action,
        autofocus: widget.autofocus,
        child: content,
      ),
      EnButtonKind.danger => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: colors.error,
          foregroundColor: colors.surface,
        ),
        onPressed: action,
        autofocus: false,
        child: content,
      ),
      EnButtonKind.secondary => OutlinedButton(
        onPressed: action,
        autofocus: widget.autofocus,
        child: content,
      ),
      EnButtonKind.text => TextButton(
        onPressed: action,
        autofocus: widget.autofocus,
        child: content,
      ),
      EnButtonKind.icon => IconButton(
        tooltip: pending ? '${widget.label}: выполняется' : widget.label,
        autofocus: widget.autofocus,
        onPressed: action,
        icon: pending
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(widget.icon ?? Icons.more_horiz),
      ),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (value) => setState(() => _focused = value),
          child: Container(
            padding: const EdgeInsets.all(BrandTokens.focusOffset),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                width: BrandTokens.focusWidth,
                color: _focused ? colors.primary : Colors.transparent,
              ),
            ),
            child: button,
          ),
        ),
        if ((!widget.enabled || widget.onPressed == null) &&
            widget.disabledReason != null)
          Text(
            widget.disabledReason!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
      ],
    );
  }
}

/// C03. The controller, validation result and draft belong to the caller.
class EnField extends StatefulWidget {
  const EnField({
    super.key,
    required this.label,
    required this.controller,
    this.helper,
    this.error,
    this.secret = false,
    this.enabled = true,
    this.readOnly = false,
    this.maxLines = 1,
    this.keyboardType,
    this.prefix,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
  });
  final String label;
  final TextEditingController controller;
  final String? helper, error;
  final bool secret, enabled, readOnly;
  final int maxLines;
  final TextInputType? keyboardType;
  final Widget? prefix, suffix;
  final ValueChanged<String>? onChanged, onSubmitted;
  @override
  State<EnField> createState() => _EnFieldState();
}

class _EnFieldState extends State<EnField> {
  bool _reveal = false;
  @override
  void didUpdateWidget(EnField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.secret != widget.secret ||
        oldWidget.controller != widget.controller) {
      _reveal = false;
    }
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    enabled: widget.enabled,
    readOnly: widget.readOnly,
    obscureText: widget.secret && !_reveal,
    maxLines: widget.secret ? 1 : widget.maxLines,
    keyboardType: widget.keyboardType,
    enableSuggestions: !widget.secret,
    autocorrect: !widget.secret,
    onChanged: widget.onChanged,
    onSubmitted: widget.onSubmitted,
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helper,
      errorText: widget.error,
      prefixIcon: widget.prefix,
      suffixIcon: widget.secret
          ? IconButton(
              tooltip: _reveal ? 'Скрыть пароль' : 'Показать пароль',
              onPressed: widget.enabled
                  ? () => setState(() => _reveal = !_reveal)
                  : null,
              icon: Icon(_reveal ? Icons.visibility_off : Icons.visibility),
            )
          : widget.suffix,
    ),
  );
}

/// C04. Native Material selection under the shared theme.
class EnSelect extends StatelessWidget {
  const EnSelect({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final String label;
  final Map<String, String> options;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final unknown = value != null && !options.containsKey(value);
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        helperText: unknown
            ? 'Неизвестное значение'
            : options.isEmpty
            ? 'Нет вариантов'
            : null,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: options.containsKey(value) ? value : null,
          hint: const Text('Выберите значение'),
          items: [
            for (final entry in options.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: enabled && options.isNotEmpty ? onChanged : null,
        ),
      ),
    );
  }
}

/// C05. This group renders owner validation; it never invents business rules.
class EnForm extends StatelessWidget {
  const EnForm({
    super.key,
    required this.child,
    required this.onSubmit,
    this.onError,
    this.errors = const [],
    this.canSubmit = true,
    this.pending = false,
    this.submitLabel = 'Сохранить',
  });
  final Widget child;
  final FutureOr<void> Function() onSubmit;
  final ValueChanged<Object>? onError;
  final List<String> errors;
  final bool canSubmit, pending;
  final String submitLabel;
  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        for (final error in errors)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: TextStyle(color: BrandColors.of(context).error),
              ),
            ),
          ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: EnButton(
            label: submitLabel,
            enabled: canSubmit,
            pending: pending,
            onPressed: onSubmit,
            onError: onError,
          ),
        ),
      ],
    ),
  );
}

/// C06. No debounce, data loading or implicit query reset.
class EnSearch extends StatelessWidget {
  const EnSearch({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.filters = const [],
    this.activeCount = 0,
    this.enabled = true,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final List<Widget> filters;
  final int activeCount;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      EnField(
        label: 'Поиск',
        controller: controller,
        enabled: enabled,
        onChanged: onChanged,
        prefix: const Icon(Icons.search),
        suffix: IconButton(
          tooltip: 'Очистить поиск',
          onPressed: enabled ? onClear : null,
          icon: const Icon(Icons.close),
        ),
      ),
      if (filters.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Активных фильтров: $activeCount'),
        Wrap(spacing: 8, runSpacing: 8, children: filters),
      ],
    ],
  );
}
