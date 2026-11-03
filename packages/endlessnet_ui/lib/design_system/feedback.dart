import 'package:flutter/material.dart';

import 'controls.dart';
import 'theme.dart';

enum EnStatusKind {
  neutral,
  success,
  warning,
  error,
  pending,
  unknown,
  unavailable,
}

enum EnMessageKind { inline, banner, snackbar }

enum EnRegionState { loading, empty, error, unknown, unavailable }

Color statusColor(BuildContext context, EnStatusKind kind) {
  final colors = BrandColors.of(context);
  return switch (kind) {
    EnStatusKind.success => colors.success,
    EnStatusKind.warning => colors.warning,
    EnStatusKind.error => colors.error,
    _ => colors.text,
  };
}

/// C10. Card/section/toolbar: slots contain no automatic domain actions.
class EnCard extends StatelessWidget {
  const EnCard({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.actions = const [],
  });
  final String title;
  final String? description;
  final Widget child;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(description!),
          ],
          const SizedBox(height: 16),
          child,
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    ),
  );
}

/// C11. Meaning is conveyed in text, not just a color dot.
class EnStatus extends StatelessWidget {
  const EnStatus({
    super.key,
    required this.label,
    this.kind = EnStatusKind.neutral,
    this.reason,
  });
  final String label;
  final EnStatusKind kind;
  final String? reason;
  @override
  Widget build(BuildContext context) => Semantics(
    label: reason == null ? label : '$label: $reason',
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: BrandColors.of(context).surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusColor(context, kind)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            reason == null ? label : '$label: $reason',
            style: TextStyle(color: statusColor(context, kind)),
          ),
        ),
      ),
    ),
  );
}

/// C12. Dismiss only dismisses this presentation; it does not cancel an operation.
class EnMessage extends StatelessWidget {
  const EnMessage({
    super.key,
    required this.message,
    this.severity = EnStatusKind.neutral,
    this.kind = EnMessageKind.inline,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });
  final String message;
  final EnStatusKind severity;
  final EnMessageKind kind;
  final String? actionLabel;
  final VoidCallback? onAction, onDismiss;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BrandColors.of(context).surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor(context, severity)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: TextStyle(color: statusColor(context, severity)),
          ),
          if (onAction != null || onDismiss != null)
            Wrap(
              spacing: 8,
              children: [
                if (onAction != null && actionLabel != null)
                  EnButton(
                    label: actionLabel!,
                    kind: EnButtonKind.text,
                    onPressed: onAction,
                  ),
                if (onDismiss != null)
                  EnButton(
                    label: 'Закрыть сообщение',
                    kind: EnButtonKind.text,
                    onPressed: onDismiss,
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}

void showEnSnackBar(
  BuildContext context, {
  required String message,
  EnStatusKind severity = EnStatusKind.neutral,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 6),
      backgroundColor: BrandColors.of(context).surface,
      content: EnMessage(
        message: message,
        severity: severity,
        kind: EnMessageKind.snackbar,
      ),
    ),
  );
}

/// C13. Unknown, empty and unavailable are deliberately distinct.
class EnRegion extends StatelessWidget {
  const EnRegion({super.key, required this.state, this.message, this.onRetry});
  final EnRegionState state;
  final String? message;
  final VoidCallback? onRetry;
  static String label(EnRegionState state) => switch (state) {
    EnRegionState.loading => 'Загрузка',
    EnRegionState.empty => 'Нет данных',
    EnRegionState.error => 'Ошибка',
    EnRegionState.unknown => 'Результат неизвестен',
    EnRegionState.unavailable => 'Недоступно',
  };
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (state == EnRegionState.loading)
        const LinearProgressIndicator(semanticsLabel: 'Загрузка'),
      Text(label(state)),
      if (message != null) Text(message!),
      if (onRetry != null && state != EnRegionState.loading)
        EnButton(
          label: 'Повторить',
          kind: EnButtonKind.secondary,
          onPressed: onRetry,
        ),
    ],
  );
}
