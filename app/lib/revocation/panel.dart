import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'controller.dart';

class RevocationPanel extends StatelessWidget {
  const RevocationPanel({super.key, required this.controller});
  final RevocationController controller;
  Future<void> _confirm(
    BuildContext context,
    api.NodeRevocationTarget target,
  ) async {
    final selected = api.NodeRevocationTarget.fromBuffer(
      target.writeToBuffer(),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отозвать доступ устройства?'),
        content: Text(
          '${selected.hostname}\nAccount: ${selected.accountId}\nNetwork: ${selected.networkId}\nNode: ${selected.nodeId}\n\nОтзывается только эта регистрация. Файлы и ключи на потерянном устройстве не удаляются.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отозвать доступ'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.revoke(selected);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final result = controller.result;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Доступ устройств',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (controller.busy) const LinearProgressIndicator(),
              TextButton(
                onPressed: controller.busy ? null : controller.refresh,
                child: const Text('Обновить список устройств'),
              ),
              for (final target in controller.targets)
                ListTile(
                  title: Text(
                    target.hostname.isEmpty ? target.nodeId : target.hostname,
                  ),
                  subtitle: Text(
                    'Account: ${target.accountId}\nNetwork: ${target.networkId}\nNode: ${target.nodeId} · ${target.assignedIp}\n${target.status}',
                  ),
                  trailing: OutlinedButton(
                    onPressed:
                        controller.canChoose && target.status != 'revoked'
                        ? () => _confirm(context, target)
                        : null,
                    child: const Text('Отозвать'),
                  ),
                ),
              if (result?.phase ==
                  api.NodeRevocationPhase.NODE_REVOCATION_PHASE_ACCEPTED) ...[
                const Text('Отзыв принят'),
                Text('Регистрация: ${result!.target.nodeId}'),
                Text('Принят: ${result.acceptedAt.toDateTime().toLocal()}'),
                Text(
                  'Предельный срок применения: ${result.enforceBy.toDateTime().toLocal()}',
                ),
              ],
              if (controller.problem.isNotEmpty) Text(controller.problem),
              if (controller.hasOriginal)
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: controller.busy
                          ? null
                          : controller.queryOriginal,
                      child: const Text('Проверить исходную команду'),
                    ),
                    TextButton(
                      onPressed: controller.busy
                          ? null
                          : controller.retryOriginal,
                      child: const Text('Повторить исходную команду'),
                    ),
                  ],
                ),
              const Text(
                'Прекращение трафика отдельно не подтверждено. Локальная очистка потерянного устройства неизвестна.',
              ),
            ],
          ),
        ),
      );
    },
  );
}
