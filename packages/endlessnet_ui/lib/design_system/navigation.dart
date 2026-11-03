import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controls.dart';

/// C14. Returns confirmation intent; no server operation is created here.
class EnConfirmationDialog extends StatefulWidget {
  const EnConfirmationDialog({
    super.key,
    required this.title,
    required this.child,
    required this.onConfirm,
    this.onError,
    this.danger = false,
    this.pending = false,
    this.confirmLabel = 'Подтвердить',
  });
  final String title, confirmLabel;
  final Widget child;
  final FutureOr<void> Function() onConfirm;
  final ValueChanged<Object>? onError;
  final bool danger, pending;
  @override
  State<EnConfirmationDialog> createState() => _EnConfirmationDialogState();
}

class _EnConfirmationDialogState extends State<EnConfirmationDialog> {
  bool _busy = false;
  void _dismiss() {
    if (!_busy && !widget.pending) Navigator.of(context).maybePop(false);
  }

  Future<void> _confirm() async {
    if (_busy || widget.pending) return;
    setState(() => _busy = true);
    try {
      await widget.onConfirm();
      if (mounted) Navigator.of(context).pop(true);
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
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !widget.pending,
    child: CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _dismiss},
      child: AlertDialog(
        title: Text(widget.title),
        content: widget.child,
        actions: [
          TextButton(
            autofocus: true,
            onPressed: _busy || widget.pending ? null : _dismiss,
            child: const Text('Отмена'),
          ),
          EnButton(
            label: widget.confirmLabel,
            pending: _busy || widget.pending,
            kind: widget.danger ? EnButtonKind.danger : EnButtonKind.primary,
            onPressed: _confirm,
            onError: widget.onError,
          ),
        ],
      ),
    ),
  );
}

Future<bool?> showEnConfirmation(
  BuildContext context, {
  required String title,
  required Widget child,
  required FutureOr<void> Function() onConfirm,
  ValueChanged<Object>? onError,
  bool danger = false,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => EnConfirmationDialog(
    title: title,
    onConfirm: onConfirm,
    onError: onError,
    danger: danger,
    child: child,
  ),
);

@immutable
class EnMenuAction {
  const EnMenuAction(
    this.id,
    this.label, {
    this.enabled = true,
    this.disabledReason,
  });
  final String id, label;
  final bool enabled;
  final String? disabledReason;
}

/// C15. Popup uses native keyboard/focus behavior; caller supplies permissions.
class EnMenu extends StatelessWidget {
  const EnMenu({
    super.key,
    required this.label,
    required this.items,
    required this.onSelected,
    this.enabled = true,
  });
  final String label;
  final List<EnMenuAction> items;
  final ValueChanged<String> onSelected;
  final bool enabled;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: label,
    enabled: enabled && items.isNotEmpty,
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final item in items)
        PopupMenuItem(
          value: item.id,
          enabled: item.enabled,
          child: Text(
            item.disabledReason == null
                ? item.label
                : '${item.label}: ${item.disabledReason}',
          ),
        ),
    ],
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text(label), const Icon(Icons.expand_more)],
      ),
    ),
  );
}

/// C15. Native hover/long-press plus explicit keyboard focus presentation.
class EnTooltip extends StatefulWidget {
  const EnTooltip({super.key, required this.message, required this.child});
  final String message;
  final Widget child;
  @override
  State<EnTooltip> createState() => _EnTooltipState();
}

class _EnTooltipState extends State<EnTooltip> {
  final _tooltip = GlobalKey<TooltipState>();
  @override
  Widget build(BuildContext context) => Tooltip(
    key: _tooltip,
    message: widget.message,
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (focused) {
          _tooltip.currentState?.ensureTooltipVisible();
        } else {
          Tooltip.dismissAllToolTips();
        }
      },
      child: widget.child,
    ),
  );
}

@immutable
class EnNavigationItem {
  const EnNavigationItem(this.id, this.label, {this.enabled = true});
  final String id, label;
  final bool enabled;
}

/// C16. Controlled tabs; arrows move among enabled tabs, Tab retains traversal.
class EnTabs extends StatefulWidget {
  const EnTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });
  final List<EnNavigationItem> items;
  final String? selected;
  final ValueChanged<String> onSelect;
  @override
  State<EnTabs> createState() => _EnTabsState();
}

class _EnTabsState extends State<EnTabs> {
  final _nodes = <String, FocusNode>{};
  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.arrowLeft &&
            event.logicalKey != LogicalKeyboardKey.arrowRight)) {
      return KeyEventResult.ignored;
    }
    final enabled = widget.items.where((item) => item.enabled).toList();
    if (enabled.isEmpty) return KeyEventResult.ignored;
    var index = enabled.indexWhere(
      (item) => _nodes[item.id]?.hasFocus ?? false,
    );
    final direction = event.logicalKey == LogicalKeyboardKey.arrowRight
        ? 1
        : -1;
    index = (index + direction) % enabled.length;
    final target = enabled[index];
    _nodes[target.id]?.requestFocus();
    widget.onSelect(target.id);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: _key,
    canRequestFocus: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.selected != null &&
            !widget.items.any((item) => item.id == widget.selected))
          const Text('Неизвестное значение'),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final item in widget.items)
                Semantics(
                  selected: widget.selected == item.id,
                  child: TextButton(
                    focusNode: _nodes.putIfAbsent(
                      item.id,
                      () => FocusNode(debugLabel: item.id),
                    ),
                    onPressed: item.enabled
                        ? () => widget.onSelect(item.id)
                        : null,
                    child: Text(item.label),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// C17. A slot-only adaptive shell. Child identity survives the breakpoint.
class EnShell extends StatelessWidget {
  const EnShell({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.child,
    this.header = const Text('EndlessNet'),
  });
  final List<EnNavigationItem> items;
  final String? selected;
  final ValueChanged<String> onSelect;
  final Widget child, header;
  Widget _navigation(BuildContext context, bool drawer) => ListView(
    children: [
      for (final item in items)
        ListTile(
          title: Text(item.label),
          selected: item.id == selected,
          enabled: item.enabled,
          onTap: !item.enabled
              ? null
              : () {
                  onSelect(item.id);
                  if (drawer) Navigator.of(context).pop();
                },
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final narrow = box.maxWidth < 840;
      return Scaffold(
        appBar: AppBar(title: header),
        drawer: narrow
            ? Drawer(
                child: Builder(
                  builder: (context) => _navigation(context, true),
                ),
              )
            : null,
        body: Row(
          children: [
            if (!narrow)
              SizedBox(
                key: const ValueKey('sidebar'),
                width: 240,
                child: _navigation(context, false),
              ),
            Expanded(key: const ValueKey('content-slot'), child: child),
          ],
        ),
      );
    },
  );
}
