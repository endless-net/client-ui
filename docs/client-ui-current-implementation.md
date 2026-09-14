# Текущая реализация Client UI — 2026-09-14

Проверенный UI commit: `853c42d` (main),
чистое рабочее дерево до аудита.
Это проверка source gate первой стадии цели, не platform acceptance.
Все 104 требования остаются в [матрице](../tests/client-coverage.json);
полностью принятых US: 0 из 14.

Повторная проверка producer на UI `853c42d`: `ls-remote` и локальный
`client/origin/main` совпадают на `09a7dd4f12f929ed3b175060f0a3afc7bf015b90`.
`proto/client/v0` и `packages/client_api` не отличаются от UI pin; новые runtime
commits не требуют смены SDK или версии UI. Текущая Windows privileged wiring и
конкретные зависимости Linux/macOS/mobile перепроверены в
[аудите privileged adapter](native-privileged-recovery.md).

Windows native permission, toast delivery, COM activation, обнаружение потери
трея и явное восстановление регистрации уже входят в этот snapshot. Их наличие
в source не закрывает installed/native acceptance. Последняя проверка кода:
926 Flutter tests passed, 30 skipped; analyze, Go и 13 Node checks прошли.
Native tray state unit и Windows release build прошли на `622466e`; они
не являются повторной native проверкой текущего commit. Исторические integration runs в
[ledger](client-ui-test-coverage.md) относятся к указанным там старым commits.

## Producer и принятые решения

`git ls-remote` для client/main и локальный client/origin/main совпали:
`09a7dd4f12f929ed3b175060f0a3afc7bf015b90`. Сравнение `proto/client/v0` и
`packages/client_api` с UI pin `cd05fcddb858877b10ecefe7b0b4a3819d2c6f3b`
не показало изменений. Текущие контракт/SDK поэтому актуальны без смены pin,
версии приложения, протокола или manifest generation.

Повторно прочитаны разрешённый BA и producer SDK README/service.proto.
SDK явно не предоставляет mobile bridge. Enroll принимает `browser_login`
или `enrollment_token`; это не контракт верифицируемого одноразового callback
в UI. Нельзя вводить собственные credentials/deep-link поля вместо него.
NotifyLifecycle предоставляет только UI_QUIT; runtime preferences определяют
его effective поведение, а logoff/suspend/resume не отправляются из UI.

Шесть решений пользователя приняты и записаны в [SA](client-ui-system-analysis.md):
Windows AppUserModelID, OS matrix, граница mobile bridge, browser/callback approach,
desktop close и opt-in, accessibility. Их больше не следует запрашивать повторно.
Минимальные версии Android/iOS и конкретный callback/bridge контракт этим не заданы.

## Сверка функционального scope

Каждая строка описывает существующий source и оставшуюся работу; наличие панели
не означает завершённый бизнес-сценарий или доказанную OS/runtime семантику.

| UF | Текущая реализация | Оставшийся результат |
|---|---|---|
| 01 | Desktop hosts Windows/Linux/macOS, metadata target и protected local transport | Продуктовые Android/iOS hosts и bridge; distribution/совместимая установка пяти платформ |
| 02 | Window/tray, Windows Shell/icon bounds, Linux watcher и macOS status-item bounds, явное восстановление, desktop autostart opt-in | Реальная доступность tray, quick surfaces mobile, login и cleanup при distribution lifecycle |
| 03 | Typed enrollment, browser action, journal/recovery | Одноразовый проверяемый callback по producer contract; native permission и реальные enrollment/approval |
| 04 | Snapshot/revision, отдельные link/phase/reason, next action | Полный набор состояний на реальных hosts без ложного вывода об установке службы |
| 05 | Connect/Disconnect, tray, durable request ID | Реальные tunnel outcomes, restart/resume и согласованность quick surfaces |
| 06 | Peers, search, paths/health | Реальные direct/relay переходы и accessibility больших списков |
| 07 | Network catalog/select и stale-context guards | Открытие реального разрешённого ресурса после смены сети |
| 08 | Exit choices, LAN и независимые IPv4/IPv6 requested/effective | Runtime traffic enforcement и отказ выхода на каждой платформе |
| 09 | Recovery lookup, outbox, deadline/continuity projections | Полные interruption/restart/resume flows и platform authorization |
| 10 | Identity и scoped Windows privileged helper | Не-Windows privileged adapters; реальные owner/admin denial и cancellation |
| 11 | Archive preview, bounded verified export, Windows/Linux chooser и macOS lease | Mobile export; реальное permission/privacy поведение и соответствие archive preview |
| 12 | Logout/local forget, confirmations и typed outcomes | Реальные remote cleanup/local removal и authorization failures |
| 13 | Windows MSI/WinGet/signing/pairing scripts | Полный install/repair/upgrade/uninstall, outcome и state preservation; новые платформенные каналы |
| 14 | RU/EN panels/shell/tray, persisted locale, semantics и large-text tests | Полный keyboard/focus/200% аудит и ручные NVDA/VoiceOver/TalkBack/Orca проверки |
| 15 | Persisted opt-in, dispatcher, retry, deadline/blocked/update planner, Windows/Linux/macOS native delivery и activation | Android/iOS native notifications; полнота значимых событий, реальный OS permission/click и ограничения dedup |
| 16 | Profile create/select/rename/remove, authoritative context guards | Реальные multi-profile flows и отказы переключения на пяти hosts |
| 17 | Session renewal, независимые credential сроки | Реальная continuity и независимые истечения, включая mobile |
| 18 | Preferences draft/apply/reset, presence vs false | Реальные apply failures, enforced policy и свежий effective результат |
| 19 | Peers/resources search, pagination, stale guards | Реальная фильтрация caller доступа и доступ к разрешённым ресурсам |
| 20 | Managed source/lock/reason и requested/effective | Изменение policy на живой установке, default/denial behavior |
| 21 | UI_QUIT и lifecycle settings, UI resume/refetch; desktop autostart отдельно | Реальные crash/quit/logoff/suspend/resume/runtime restart; последние OS события принадлежат core |
| 22 | Update source/compatibility/installed pair projections | Trusted distribution execution/outcome и новый bootstrap после установки |
| 23 | About/build, checked support links, RU/EN offline topics | Producer help-key mapping и реальное browser/support acceptance |

## Конкретные исправления прежнего аудита

- `client_bundle_destination.dart` поддерживает три desktop платформы. macOS
  host содержит `DiagnosticsDestination` и выдаёт ограниченную по времени lease;
  утверждение «export только Windows» больше не актуально.
- `client_native_notifications.dart` подключён к dispatcher. Все три desktop
  runner имеют notification channel; Windows `ui_notifications.h` и
  `ui_notification_activation.h` подключены в `flutter_window.cpp`. Primary UI
  lifetime управляет COM activation. Это source и local unit/build evidence,
  а не доказательство installed toast, OS permission или foreground activation.
- `client_windows_autostart.dart`, native `ui_autostart.h` и общий panel дают
  explicit opt-in. MSI больше не регистрирует Run автоматически. Native unit
  проверяет fake Win32 boundary, а не фактический login/permission.
- `client_desktop_app.dart` проверяет native tray availability периодически и
  перед скрытием. Windows отслеживает Shell/TaskbarCreated, Linux — watcher;
  ошибка/потеря показывает окно. Явное восстановление удаляет старую регистрацию
  перед созданием и повторной проверкой, не скрывая окно автоматически. Повторная
  потеря во время восстановления сохраняет неготовность. Windows дополнительно
  проверяет Shell_NotifyIconGetRect, macOS — непустые конечные bounds окна
  status item через pinned plugin. Геометрия не доказывает видимость и
  доступность пользователю в реальной конфигурации панели/overflow.
- После исходного аудита исправлены lifetime guards recovery, connection,
  cleanup, каталогов, diagnostics, preferences, exit, resources, update и support.
  A-B-A замена контроллера не возвращает старым callbacks право менять новую
  панель. Регрессии keyed-форм подтверждают сброс черновиков и token input.
- Desktop actions и Quit dialog доступны при 200% в локальных layout-тестах;
  добавлены проверки клавиатуры для peers и identity confirmation, а offline
  help раскрывает expanded semantics. Это не полный accessibility acceptance.
- Android/iOS product folders в `app` отсутствуют; mobile test harness нельзя
  считать продуктом. Сначала нужен реальный разрешённый transport/ABI контракт.

## Следующий порядок реализации

1. Завершить accessibility/localization source audit: для loaded panels проверить
   keyboard traversal/activation, focus, читаемость при 200% и точные RU/EN labels.
   Уже есть отдельные проверки exit choices, recovery, профилей, сетей и ресурсов;
   это не доказательство полного набора состояний всех 16 session panels.
2. Distribution lifecycle новых платформ:
   package identity, install/repair/upgrade/uninstall, cleanup autostart. Существующие
   `app/linux`/`app/macos` hosts и compile jobs не заменяют distribution artifacts.
3. Mobile hosts/bridge, callback и non-Windows privileged/export flows после получения
   конкретного внешнего контракта. Не создавать runtime или TCP fallback в UI.
4. Повторить full implementation gate по BA/SA и всей матрице, включая источники
   update/support и точные distribution outcomes. Отсутствие TODO и зелёный
   coverage checker не подтверждают полноту: checker проверяет трассировку 104 ID,
   а не runtime/OS результаты. Все 14 US пока имеют implementation=partial.
5. Только после закрытия source gate переходить к новым пяти-платформенным
   testserver integration runs и отдельно к реальной platform acceptance.

Доступной работы в client-ui ещё достаточно; состояние цели не blocked.
Внешние зависимости остаются конкретными ограничениями отдельных flows, а не
основанием считать остальные UI-owned части готовыми.
