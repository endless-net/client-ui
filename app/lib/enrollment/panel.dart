import 'dart:async';

import 'package:endlessnet_client_api/client_api.dart' as api;
import 'package:flutter/material.dart';

import 'controller.dart';
import 'server_trust_controller.dart';
import 'server_trust_panel.dart';

// View uses Client public snapshots. It neither opens a browser automatically
// nor creates the transport/store or claims OS/backend authority.
class EnrollmentPanel extends StatefulWidget {
  const EnrollmentPanel({
    super.key,
    required this.controller,
    required this.now,
    this.openBrowser,
    this.serverTrust,
    this.reconnect,
    this.connectivityPanel,
    this.simple = false,
    this.hostname = "",
    this.onStart,
  });

  final EnrollmentController controller;
  final ServerTrustController? serverTrust;
  final DateTime Function() now;
  final Future<bool> Function(Uri)? openBrowser;
  final Future<void> Function()? reconnect;
  final Widget? connectivityPanel;
  final bool simple;
  final String hostname;
  final Future<void> Function(String, api.EnrollmentMode)? onStart;

  @override
  State<EnrollmentPanel> createState() => _EnrollmentPanelState();
}

class _EnrollmentPanelState extends State<EnrollmentPanel> {
  final _hostname = TextEditingController();
  api.EnrollmentMode _mode = api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION;
  Timer? _timer;
  String? _trustProfile;
  bool _opening = false;
  bool _browserFailed = false;
  String? _browserFailureProfile;
  Uri? _browserFailureUrl;

  @override
  void initState() {
    super.initState();
    _hostname.text = widget.hostname;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hostname.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final c = widget.controller;
    final url = c.browserAction;
    final launch = widget.openBrowser;
    final profile = c.profile?.id;
    if (_opening || url == null || launch == null) return;
    setState(() {
      _opening = true;
      _browserFailed = false;
    });
    var opened = false;
    try {
      opened = await launch(url);
    } catch (_) {
      // Launcher diagnostics never enter the UI or logs.
    } finally {
      if (mounted) {
        setState(() {
          _opening = false;
          _browserFailureProfile = profile;
          _browserFailureUrl = url;
          _browserFailed =
              !opened &&
              identical(c, widget.controller) &&
              profile == c.profile?.id &&
              url == c.browserAction;
        });
      }
    }
  }

  String _title(EnrollmentController c) {
    if (c.link == EnrollmentLinkState.mismatch) {
      return 'Несовместимая версия клиента';
    }
    if (c.callRejected) return 'Команда отклонена';
    if (c.uncertain) return 'Исход регистрации пока неизвестен';
    if (c.link == EnrollmentLinkState.loading) return 'Подключение к клиенту';
    if (c.link != EnrollmentLinkState.available) {
      return 'Локальный клиент недоступен';
    }
    if (c.registeredConfirmed) return 'Устройство зарегистрировано';
    return switch (c.currentAttempt?.phase) {
      api.EnrollmentPhase.ENROLLMENT_PHASE_AWAITING_LOGIN => 'Ожидание входа',
      api.EnrollmentPhase.ENROLLMENT_PHASE_CHOOSING_CONTEXT =>
        'Ожидание назначения сети сервером',
      api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERING =>
        'Регистрация устройства',
      api.EnrollmentPhase.ENROLLMENT_PHASE_PENDING_APPROVAL =>
        'Ожидание одобрения',
      api.EnrollmentPhase.ENROLLMENT_PHASE_COMPLETING =>
        'Завершение регистрации',
      api.EnrollmentPhase.ENROLLMENT_PHASE_DENIED => 'Регистрация отклонена',
      api.EnrollmentPhase.ENROLLMENT_PHASE_CANCELLED => 'Ожидание отменено',
      api.EnrollmentPhase.ENROLLMENT_PHASE_EXPIRED => 'Время попытки истекло',
      api.EnrollmentPhase.ENROLLMENT_PHASE_REGISTERED =>
        'Регистрация требует подтверждения',
      null => 'Подключите этот компьютер',
      _ => 'Состояние требует проверки',
    };
  }

  String _reason(String key) => switch (key) {
    'client.owner.required' || 'ui.permission_required' =>
      'Действие доступно владельцу локального клиента.',
    'ui.stale_state' => 'Состояние изменилось. Проверьте текущую попытку.',
    'ui.contract_mismatch' =>
      'Установите согласованные версии клиента и интерфейса.',
    'ui.correlation_save_failed' || 'ui.correlation_store_failed' => 'Не удалось сохранить данные восстановления. Проверьте локальное хранилище.',
    'ui.enrollment_uncertain' || 'ui.client_unavailable' =>
      'Проверьте исходную попытку после восстановления связи.',
    'ui.registration_snapshot_mismatch' =>
      'Подтверждение устройства ещё не совпадает с текущим состоянием клиента.',
    'client.server_identity.confirmation_required' ||
    'client.server_identity.changed' => 'Требуется проверка и подтверждение текущего объявления сервера администратором устройства.',
    'client.server_identity.unavailable' =>
      'Не удалось получить текущее объявление сервера.',
    'client.registration.control_unavailable' ||
    'client.default_target.control_unavailable' ||
    'client.approval.control_unavailable' =>
      'Сервер управления временно недоступен. Служба повторит запрос.',
    'client.registration.trust_required' ||
    'client.default_target.trust_required' ||
    'client.approval.trust_required' =>
      'Не удалось проверить доверие к серверу.',
    'client.registration.checkpoint_unavailable' ||
    'client.default_target.checkpoint_unavailable' ||
    'client.approval.checkpoint_unavailable' => 'Не удалось прочитать или сохранить доверенную версию bootstrap на устройстве.',
    'client.registration.bootstrap_protocol' ||
    'client.default_target.bootstrap_protocol' ||
    'client.approval.bootstrap_protocol' =>
      'Сервер управления сообщил об ошибке протокола или конфигурации.',
    'client.registration.access_denied' ||
    'client.default_target.access_denied' ||
    'client.approval.access_denied' =>
      'Сервер отклонил запрос из-за отсутствия доступа.',
    'client.registration.quota_exhausted' => 'Квота устройств исчерпана. После освобождения места начните новую регистрацию.',
    'client.registration.request_rejected' ||
    'client.default_target.request_rejected' ||
    'client.approval.request_rejected' => 'Сервер отклонил параметры запроса.',
    'ui.invalid_argument' => 'Проверьте введённые данные.',
    'ui.unsupported' => 'Установленный клиент не поддерживает эту команду.',
    '' => '',
    _ => 'Клиент сообщил об ограничении. Проверьте состояние и доступные действия.',
  };

  String _owner(api.ActionOwner owner) => switch (owner) {
    api.ActionOwner.ACTION_OWNER_USER => 'Следующий шаг: пользователь.',
    api.ActionOwner.ACTION_OWNER_DEVICE_ADMINISTRATOR =>
      'Обратитесь к администратору устройства.',
    api.ActionOwner.ACTION_OWNER_ACCESS_ADMINISTRATOR =>
      'Обратитесь к администратору доступа.',
    api.ActionOwner.ACTION_OWNER_SUPPORT => 'Обратитесь в поддержку.',
    _ => '',
  };

  Widget _deadline(String label, DateTime deadline) {
    var seconds = deadline.difference(widget.now()).inSeconds;
    if (seconds < 0) seconds = 0;
    return Text(
      '$label: ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final profile = c.profile;
      final attempt = c.currentAttempt;
      final browserAction = c.browserAction;
      final owner =
          c.failure?.actionOwner ??
          attempt?.restriction.actionOwner ??
          c.enrollmentRestriction?.actionOwner ??
          api.ActionOwner.ACTION_OWNER_UNSPECIFIED;
      final reason =
          widget.simple && c.reasonKey.startsWith('client.server_identity.')
          ? 'Не удалось проверить сервер EndlessNet. Проверьте соединение и установленную версию; вход не начат.'
          : _reason(c.reasonKey);
      final action = _owner(owner);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title(c), style: Theme.of(context).textTheme.headlineSmall),
            if (profile != null) ...[
              if (!widget.simple)
                Text(
                  'Профиль: ${profile.displayName.isEmpty ? profile.id : profile.displayName}',
                ),
              Text(
                'Сервер: ${profile.controlOrigin == 'https://api.endlessnet.ru' ? 'https://endlessnet.ru' : profile.controlOrigin}',
              ),
            ],
            if (c.busy) const LinearProgressIndicator(),
            if (widget.connectivityPanel != null) widget.connectivityPanel!,
            if (reason.isNotEmpty) Text(reason),
            if (action.isNotEmpty) Text(action),
            if (attempt == null &&
                c.correlation == null &&
                !c.registeredConfirmed) ...[
              if (!widget.simple)
                TextField(
                  controller: _hostname,
                  enabled: c.canEnroll,
                  decoration: const InputDecoration(
                    labelText: 'Имя компьютера',
                  ),
                ),
              if (!widget.simple)
                DropdownButton<api.EnrollmentMode>(
                  value: _mode,
                  items: const [
                    DropdownMenuItem(
                      value: api.EnrollmentMode.ENROLLMENT_MODE_WORKSTATION,
                      child: Text('Рабочая станция'),
                    ),
                    DropdownMenuItem(
                      value: api.EnrollmentMode.ENROLLMENT_MODE_SERVER,
                      child: Text('Сервер'),
                    ),
                  ],
                  onChanged: c.canEnroll
                      ? (value) {
                          if (value != null) setState(() => _mode = value);
                        }
                      : null,
                ),
              FilledButton(
                onPressed: c.canEnroll
                    ? () => (widget.onStart ?? c.start)(_hostname.text, _mode)
                    : null,
                child: Text(
                  widget.simple
                      ? 'Войти и подключить компьютер'
                      : 'Начать вход',
                ),
              ),
            ],
            if (attempt != null) ...[
              if (!widget.simple) Text('Попытка: ${attempt.attemptId}'),
              if (!widget.simple && attempt.accountId.isNotEmpty)
                Text('Аккаунт: ${attempt.accountId}'),
              if (!widget.simple && attempt.networkId.isNotEmpty)
                Text('Сеть: ${attempt.networkId}'),
              if (c.registeredConfirmed) ...[
                if (!widget.simple) Text('Устройство: ${attempt.nodeId}'),
                const Text(
                  'Регистрация подтверждена. Доступность сетевых ресурсов проверяется отдельно.',
                ),
              ],
              if (!c.registeredConfirmed)
                _deadline('Срок попытки', attempt.deadline.toDateTime()),
              if (attempt.phase ==
                      api.EnrollmentPhase.ENROLLMENT_PHASE_AWAITING_LOGIN &&
                  attempt.hasLoginExpiresAt())
                _deadline('Время входа', attempt.loginExpiresAt.toDateTime()),
              if (attempt.phase ==
                      api.EnrollmentPhase.ENROLLMENT_PHASE_PENDING_APPROVAL &&
                  attempt.hasApprovalExpiresAt())
                _deadline(
                  'Время ожидания одобрения',
                  attempt.approvalExpiresAt.toDateTime(),
                ),
            ],
            if (c.uncertain && c.correlation?.recoveryDeadline != null)
              _deadline(
                'Автоматическая проверка',
                c.correlation!.recoveryDeadline!,
              ),
            if (!widget.simple &&
                widget.serverTrust != null &&
                profile != null &&
                (c.reasonKey.startsWith('client.server_identity.') ||
                    _trustProfile == profile.id)) ...[
              OutlinedButton(
                onPressed: c.busy || widget.serverTrust!.busy
                    ? null
                    : () async {
                        setState(() => _trustProfile = profile.id);
                        await widget.serverTrust!.bind(profile);
                      },
                child: const Text('Просмотреть объявление сервера'),
              ),
              if (_trustProfile == profile.id)
                ServerTrustPanel(
                  controller: widget.serverTrust!,
                  onConfirmed: c.refresh,
                ),
            ],
            if (browserAction != null) ...[
              SelectableText(browserAction.toString()),
              OutlinedButton(
                onPressed: !_opening && widget.openBrowser != null
                    ? _open
                    : null,
                child: const Text('Открыть вход в браузере'),
              ),
            ],
            if (_browserFailed &&
                _browserFailureProfile == profile?.id &&
                _browserFailureUrl == browserAction)
              const Text(
                'Не удалось открыть браузер. Повторите открытие страницы входа.',
              ),
            if (!widget.simple && c.canLoadTargets) ...[
              OutlinedButton(
                onPressed: () => c.loadTargets(),
                child: const Text('Загрузить доступные аккаунты и сети'),
              ),
              for (final target in c.targets)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${target.accountName} / ${target.networkName}'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${target.accountId} / ${target.networkId}'),
                      if (!c.canSelect(target.accountId, target.networkId))
                        Text(
                          target.restriction.reasonKey.isEmpty
                              ? 'Выбор недоступен.'
                              : _reason(target.restriction.reasonKey),
                        ),
                      if (_owner(target.restriction.actionOwner).isNotEmpty)
                        Text(_owner(target.restriction.actionOwner)),
                    ],
                  ),
                  trailing: TextButton(
                    onPressed: c.canSelect(target.accountId, target.networkId)
                        ? () =>
                              c.selectTarget(target.accountId, target.networkId)
                        : null,
                    child: const Text('Выбрать'),
                  ),
                ),
              if (c.hasNextTargetPage)
                OutlinedButton(
                  onPressed: () => c.loadTargets(next: true),
                  child: const Text('Следующая страница'),
                ),
            ],
            if (c.correlation != null)
              OutlinedButton(
                onPressed: c.busy ? null : c.refresh,
                child: const Text('Проверить исходную попытку'),
              ),
            if (c.correlation == null)
              OutlinedButton(
                onPressed: c.busy ? null : c.refresh,
                child: const Text('Перечитать состояние клиента'),
              ),
            if (widget.reconnect != null &&
                (c.link == EnrollmentLinkState.unavailable ||
                    c.link == EnrollmentLinkState.mismatch ||
                    c.callRejected))
              OutlinedButton(
                onPressed: c.busy ? null : widget.reconnect,
                child: const Text('Переподключиться к локальному клиенту'),
              ),
            if (c.canCancel)
              OutlinedButton(
                onPressed: c.cancelAttempt,
                child: const Text('Отменить ожидание'),
              ),
            if (attempt?.phase ==
                    api.EnrollmentPhase.ENROLLMENT_PHASE_CANCELLED ||
                c.canCancel)
              const Text(
                'Отмена ожидания не подтверждает удаление или отзыв уже зарегистрированного устройства.',
              ),
          ],
        ),
      );
    },
  );
}
