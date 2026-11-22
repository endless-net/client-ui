import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'controller.dart';

class SessionLoginPanel extends StatelessWidget {
  const SessionLoginPanel({
    super.key,
    required this.controller,
    required this.openBrowser,
  });
  final SessionLoginController controller;
  final Future<bool> Function(Uri) openBrowser;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      if (!c.registered) return const SizedBox.shrink();
      final a = c.attempt;
      final url = c.browserAction;
      final sessionState = c.connectionLoginRequired
          ? 'Требуется повторный вход для подключения.'
          : c.sessionActive
          ? 'Сессия пользователя действует.'
          : c.sessionExpired
          ? 'Срок текущей сессии истёк. Нажмите «Подключить», чтобы проверить автоматическое продление.'
          : 'Текущая сессия пользователя не подтверждена.';
      final state = switch (a?.phase) {
        api.SessionLoginPhase.SESSION_LOGIN_PHASE_PREPARING =>
          'Подготовка входа…',
        api.SessionLoginPhase.SESSION_LOGIN_PHASE_AWAITING_CONFIRMATION =>
          'Подтвердите вход тем же пользователем в браузере.',
        api.SessionLoginPhase.SESSION_LOGIN_PHASE_DENIED => 'Вход отклонён. Используйте пользователя, зарегистрировавшего устройство.',
        api.SessionLoginPhase.SESSION_LOGIN_PHASE_EXPIRED =>
          'Время подтверждения входа истекло.',
        api.SessionLoginPhase.SESSION_LOGIN_PHASE_FAILED =>
          'Не удалось завершить вход. Регистрация устройства сохранена.',
        api.SessionLoginPhase.SESSION_LOGIN_PHASE_UNCERTAIN =>
          'Исход входа пока неизвестен. Сохранённый запрос не заменён.',
        _ => sessionState,
      };
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state),
            if (a?.restriction.reasonKey == 'client.session.foreign_user')
              const Text(
                'Выполнен вход другим пользователем. Сессия и регистрация устройства не заменены.',
              ),
            if (c.problem.isNotEmpty) Text(c.problem),
            Wrap(
              spacing: 12,
              children: [
                if (c.canStart)
                  FilledButton(
                    onPressed: c.start,
                    child: const Text('Войти снова'),
                  ),
                if (c.canRetryOriginal)
                  FilledButton(
                    onPressed: () => c.start(retryOriginal: true),
                    child: const Text('Повторить сохранённый запрос'),
                  ),
                if (url != null)
                  FilledButton(
                    onPressed: () => openBrowser(url),
                    child: const Text('Открыть подтверждение входа'),
                  ),
                TextButton(
                  onPressed: c.busy ? null : c.refresh,
                  child: const Text('Проверить сессию'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
