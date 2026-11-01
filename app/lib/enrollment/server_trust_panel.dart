import 'package:flutter/material.dart';

import 'server_trust_controller.dart';

class ServerTrustPanel extends StatefulWidget {
  const ServerTrustPanel({
    super.key,
    required this.controller,
    this.onConfirmed,
  });
  final ServerTrustController controller;
  final Future<void> Function()? onConfirmed;

  @override
  State<ServerTrustPanel> createState() => _ServerTrustPanelState();
}

class _ServerTrustPanelState extends State<ServerTrustPanel> {
  bool _dialogOpen = false;
  ServerTrustController get controller => widget.controller;

  Future<void> _confirm(BuildContext context) async {
    if (_dialogOpen) return;
    final owner = controller;

    final displayed = controller.observation;
    if (displayed == null || !controller.canConfirm) return;
    final identity = displayed.identity;
    setState(() => _dialogOpen = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Подтвердить объявление сервера?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Сервер: ${identity.controlOrigin}'),
                Text('Профиль: ${identity.profileId}'),
                Text(
                  'Принятый ключ: ${identity.trustedKeyId.isEmpty ? "отсутствует" : identity.trustedKeyId}',
                ),
                SelectableText('Объявленный ключ: ${identity.announcedKeyId}'),
                SelectableText('Объявление: ${identity.announcementId}'),
                const Text(
                  'Сверьте сервер и идентификатор ключа с доверенным источником. Подтверждение изменит локальное доверие к этому серверу.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Подтвердить это объявление'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || !identical(owner, controller)) {
        return;
      }
      final accepted = await owner.confirm(displayed);
      if (accepted && mounted && identical(owner, controller)) {
        await widget.onConfirmed?.call();
      }
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  String _message(String reason) => switch (reason) {
    'ui.server_identity.trust_unknown' => 'Исход подтверждения пока неизвестен. Перечитайте текущее объявление; команда не повторяется автоматически.',
    'ui.server_identity.stale_confirmation' ||
    'client.server_identity.confirmation_mismatch' ||
    'ui.stale_state' => 'Объявление или состояние изменилось. Перечитайте и проверьте данные заново.',
    'ui.contract_mismatch' =>
      'Версии интерфейса и локального клиента не согласованы.',
    'ui.permission_required' || 'client.owner.required' =>
      'Локальный клиент не разрешил эту операцию для текущего пользователя.',
    '' => '',
    _ => 'Не удалось подтвердить текущее состояние доверия. Перечитайте объявление.',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final value = controller.observation?.identity;
      final message = _message(controller.reasonKey);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Доверие серверу'),
          if (controller.busy) const LinearProgressIndicator(),
          if (value != null) ...[
            Text('Сервер: ${value.controlOrigin}'),
            SelectableText('Объявленный ключ: ${value.announcedKeyId}'),
            SelectableText('Объявление: ${value.announcementId}'),
            if (controller.trusted)
              const Text('Текущее объявление принято локальным клиентом.'),
            if (value.changed)
              const Text(
                'Текущее объявление требует отдельного подтверждения.',
              ),
          ],
          if (message.isNotEmpty) Text(message),
          if (!controller.administratorAvailable)
            const Text(
              'Подтверждение доступно администратору устройства. Интерфейс не повышает права пользователя.',
            ),
          OutlinedButton(
            onPressed: controller.canRefresh ? controller.refresh : null,
            child: const Text('Перечитать объявление'),
          ),
          FilledButton(
            onPressed: !_dialogOpen && controller.canConfirm
                ? () => _confirm(context)
                : null,
            child: const Text('Проверить и подтвердить сервер'),
          ),
        ],
      );
    },
  );
}
