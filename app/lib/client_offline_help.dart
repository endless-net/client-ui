import 'package:flutter/material.dart';
import 'client_locale.dart';

/// UI-owned content, not producer offline_help_key values or filesystem paths.
const clientHelpArticles = <({String id, String enTitle, String ruTitle, String en, String ru})>[
  (
    id: 'service',
    enTitle: 'Service and permissions',
    ruTitle: 'Служба и разрешения',
    en: 'Opening the UI does not mean the tunnel is connected. Reconnect runtime if the local service is unavailable, then wait for a fresh status. An incompatible contract requires a compatible UI/core pair. Observer access is read-only; use the installation owner for changes. Administrator actions require a separate explicit permission prompt.',
    ru: 'Открытое окно не означает, что туннель подключён. Если локальная служба недоступна, переподключитесь к ней и дождитесь нового состояния. При несовместимом контракте нужна совместимая пара UI/core. Наблюдатель имеет доступ только для чтения; изменения выполняет владелец установки. Действия администратора требуют отдельного явного запроса разрешения.',
  ),
  (
    id: 'enrollment',
    enTitle: 'Enrollment and login',
    ruTitle: 'Регистрация и вход',
    en: 'Create a profile with the intended control origin, then explicitly enroll using the offered browser or token method. Never share an enrollment token. A browser opening is not proof of login or approval: recover the operation and check the service status. Session renewal and device credential renewal are different operations; inspect the displayed deadline and required action.',
    ru: 'Создайте профиль с нужным адресом управляющего сервиса, затем явно запустите регистрацию предложенным способом через браузер или токен. Никому не передавайте токен регистрации. Открытие браузера не подтверждает вход или одобрение: восстановите операцию и проверьте состояние службы. Продление сеанса и учётных данных устройства — разные операции; смотрите показанный срок и требуемое действие.',
  ),
  (
    id: 'connection',
    enTitle: 'Connection and networks',
    ruTitle: 'Подключение и сети',
    en: 'Choose the intended profile and network before connecting. Selected and active profiles can differ. Follow the reported connection phase; an accepted Connect command is not yet Connected. Disconnect remains a separate explicit action. Switching networks or profiles invalidates old views: refresh them before acting.',
    ru: 'Перед подключением выберите нужные профиль и сеть. Выбранный и активный профили могут различаться. Следите за сообщённой фазой подключения: принятая команда ещё не означает подключение. Отключение — отдельное явное действие. При смене сети или профиля старые данные теряют актуальность: обновите их перед действием.',
  ),
  (
    id: 'recovery',
    enTitle: 'Unknown operation result',
    ruTitle: 'Неизвестный результат операции',
    en: 'If a command times out or the service connection is lost, recover the original pending intention before sending another command. Pending, waiting for user and completed outcomes are different states. Recovery checks the original operation; it does not resend it. Read the result before acknowledging it. Follow any required action explicitly; do not repeat browser or privileged actions automatically.',
    ru: 'Если команда не ответила вовремя или связь со службой потеряна, восстановите исходное незавершённое намерение до отправки новой команды. Ожидание, ожидание пользователя и завершение — разные состояния. Восстановление проверяет исходную операцию, а не отправляет её заново. Прочитайте результат перед подтверждением ознакомления. Выполняйте требуемые действия явно; не повторяйте автоматически действия браузера или администратора.',
  ),
  (
    id: 'trust',
    enTitle: 'Changed server identity',
    ruTitle: 'Изменение идентичности сервера',
    en: 'Do not approve an unexpected identity change just to restore connectivity. Inspect the control origin, trusted key and announced key. Confirm the change through a trusted administrator or support channel. Reload the identity before confirming; a changed announcement requires a new decision. The UI does not silently replace trust.',
    ru: 'Не одобряйте неожиданную смену идентичности только ради восстановления связи. Проверьте адрес управляющего сервиса, доверенный и объявленный ключи. Подтвердите смену через доверенный канал администратора или поддержки. Перед согласием обновите идентичность; новое объявление требует нового решения. UI не заменяет доверие незаметно.',
  ),
  (
    id: 'exit',
    enTitle: 'Exit node and LAN access',
    ruTitle: 'Выходной узел и локальная сеть',
    en: 'Select the exit node, address families and LAN policy explicitly. IPv4-only does not protect IPv6, and IPv6-only does not protect IPv4. Requested and effective routes can differ; inspect each family and its failures. Reported fail-closed is service data, not an independent traffic test. Clearing the exit requires confirmation and restores ordinary routing policy.',
    ru: 'Явно выберите выходной узел, семейства адресов и политику локальной сети. Режим только IPv4 не защищает IPv6, а только IPv6 — IPv4. Запрошенные и фактические маршруты могут различаться; проверьте каждое семейство и его ошибки. Сообщённая блокировка при отказе — данные службы, не независимая проверка трафика. Сброс выходного узла требует подтверждения и возвращает обычную политику маршрутизации.',
  ),
  (
    id: 'resources',
    enTitle: 'Resources and route conflicts',
    ruTitle: 'Ресурсы и конфликты маршрутов',
    en: 'Search the current resource catalog and inspect availability, effective state and route overlap. A hidden or policy-blocked resource is not made available by enabling it locally. Refresh after a change; accepted does not mean applied. Open a resource only through an offered explicit action. Use diagnostics to inspect conflicting local and overlay prefixes.',
    ru: 'Ищите ресурс в актуальном каталоге и проверяйте доступность, фактическое состояние и пересечения маршрутов. Локальное включение не делает доступным скрытый или заблокированный политикой ресурс. После изменения обновите данные: принятие не означает применение. Открывайте ресурс только предложенным явным действием. В диагностике можно посмотреть конфликтующие локальные и оверлейные префиксы.',
  ),
  (
    id: 'preferences',
    enTitle: 'Preferences and policy',
    ruTitle: 'Настройки и политика',
    en: 'Edit the draft, then Apply or Discard it explicitly. Requested values are not necessarily effective values. No override differs from false: Reset removes an override rather than forcing a default. Locked settings require the indicated policy owner. Inspect lifecycle settings before assuming that closing the UI, logging off, suspending or resuming changes the connection.',
    ru: 'Измените черновик, затем явно примените или отмените правки. Запрошенные значения не обязательно совпадают с фактическими. Отсутствие переопределения отличается от false: сброс удаляет переопределение, а не задаёт значение по умолчанию. Заблокированные настройки требуют участия указанного владельца политики. Проверьте настройки жизненного цикла, прежде чем считать, что закрытие UI, выход из системы, сон или пробуждение меняют подключение.',
  ),
  (
    id: 'cleanup',
    enTitle: 'Logout and local removal',
    ruTitle: 'Выход и локальное удаление',
    en: 'Logout and Forget local enrollment are different actions. Local removal does not prove remote cleanup. Read the returned cleanup outcome and any remaining action before retrying. Removing a profile is available only when the current state permits it and does not substitute for logout. Confirm the exact profile and action before proceeding.',
    ru: 'Выход и удаление локальной регистрации — разные действия. Локальное удаление не подтверждает очистку на сервере. Перед повтором прочитайте результат очистки и оставшиеся действия. Удаление профиля доступно только при разрешающем текущем состоянии и не заменяет выход. Перед продолжением проверьте конкретный профиль и действие.',
  ),
  (
    id: 'diagnostics',
    enTitle: 'Diagnostics and privacy',
    ruTitle: 'Диагностика и конфиденциальность',
    en: 'Inspect the local snapshot, interfaces, routes, tunnel, DNS and reported failures. A truncated snapshot or recent log window is not a complete history. Creating an archive neither exports nor uploads it. Recover the archive operation for verified download, then explicitly choose export where supported. Inspect the exported file before sharing. Never send tokens, private keys or browser action URLs to support.',
    ru: 'Просмотрите локальный снимок, интерфейсы, маршруты, туннель, DNS и сообщённые ошибки. Сокращённый снимок или последние записи журнала — не полная история. Создание архива не экспортирует и не отправляет его. Восстановите операцию архива для проверенной загрузки, затем явно выберите экспорт, если он поддерживается. Проверьте файл перед передачей. Не отправляйте поддержке токены, закрытые ключи или URL действий браузера.',
  ),
  (
    id: 'updates',
    enTitle: 'Updates and compatibility',
    ruTitle: 'Обновления и совместимость',
    en: 'Compare the installed UI and core versions and the reported compatibility. Unavailable or unverified update metadata does not mean the installation is up to date. Follow the trusted distribution channel or external manager indicated by the service. An update notice does not install anything. Refresh the installed pair after the external update completes.',
    ru: 'Сравните установленные версии UI и core и сообщённую совместимость. Недоступные или непроверенные сведения об обновлении не означают, что установлена актуальная версия. Используйте доверенный канал распространения или внешний менеджер, указанный службой. Уведомление ничего не устанавливает. После внешнего обновления заново получите сведения об установленной паре.',
  ),
  (
    id: 'help',
    enTitle: 'Language and contacting support',
    ruTitle: 'Язык и обращение в поддержку',
    en: 'Choose English or Russian in the UI. A storage warning means the current language may not survive restart. This help works without the service or internet. Refresh support information before opening an offered link; an unavailable link is not replaced with a guessed address. Include the displayed UI/core versions and a reviewed redacted diagnostic file when contacting support.',
    ru: 'Выберите English или Русский в UI. Предупреждение хранилища означает, что язык может не сохраниться после перезапуска. Эта справка работает без службы и интернета. Перед открытием предложенной ссылки обновите сведения о поддержке; недоступная ссылка не заменяется угаданным адресом. При обращении укажите показанные версии UI/core и приложите проверенный диагностический файл с удалёнными конфиденциальными данными.',
  ),
];

class ClientOfflineHelp extends StatelessWidget {
  const ClientOfflineHelp({super.key, required this.locale});
  final ClientLocale locale;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final article in clientHelpArticles)
        ExpansionTile(
          key: Key('client-help-${article.id}'),
          title: Text(locale.text(en: article.enTitle, ru: article.ruTitle)),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(locale.text(en: article.en, ru: article.ru)),
            ),
          ],
        ),
    ],
  );
}
