import 'package:flutter/material.dart';

import 'controller.dart';

class UpdatePanel extends StatelessWidget {
  const UpdatePanel({super.key, required this.controller});
  final UpdateController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ListTile(
      title: Text(switch (controller.status) {
        UpdateStatus.checking => 'Проверка обновлений…',
        UpdateStatus.current => 'Обновлений нет',
        UpdateStatus.available =>
          'Доступна версия ${controller.release!.version.text}',
        UpdateStatus.installing => 'Загрузка и установка обновления…',
        UpdateStatus.completed =>
          'Обновление завершено. Откройте интерфейс заново.',
        UpdateStatus.restart =>
          'Обновление установлено. Требуется перезагрузка Windows.',
        UpdateStatus.failed =>
          'Не удалось проверить или установить обновление.',
      }),
      trailing: switch (controller.status) {
        UpdateStatus.available => FilledButton(
          onPressed: controller.update,
          child: const Text('Скачать и обновить'),
        ),
        UpdateStatus.failed || UpdateStatus.current => TextButton(
          onPressed: controller.check,
          child: const Text('Проверить обновления'),
        ),
        _ => null,
      },
    ),
  );
}
