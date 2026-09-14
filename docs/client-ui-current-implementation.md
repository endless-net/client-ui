# Текущая реализация Client UI — 2026-09-14

Проверенный UI commit: `97fec77` (main), чистое рабочее дерево до аудита.
Это проверка source gate первой стадии цели, не platform acceptance.
Все 104 требования остаются в [матрице](../tests/client-coverage.json);
полностью принятых US: 0 из 14.

## Producer и принятые решения

`git ls-remote` для client/main и локальный client/origin/main совпали:
`60ff0eec554df0b77fdcd9a8fed7d6db933da65e`. Сравнение `proto` и
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
| 02 | Window/tray, Windows opt-in HKCU, Linux desktop entry, macOS SMAppService | Реальная доступность tray, quick surfaces mobile, login и cleanup при distribution lifecycle |
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
| 15 | Persisted opt-in, dispatcher, retry, deadline/blocked planner, Linux/macOS native delivery | Windows/Android/iOS native notifications; полнота значимых событий, OS permission/click и ограничения dedup |
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
- `client_native_notifications.dart` подключён к dispatcher. Linux и macOS
  имеют native delivery, Windows runner пока содержит только autostart и
  diagnostics channels. Настройки уведомлений существуют, но UF-15 не закрыт.
- `client_windows_autostart.dart`, native `ui_autostart.h` и общий panel дают
  explicit opt-in. MSI больше не регистрирует Run автоматически. Native unit
  проверяет fake Win32 boundary, а не фактический login/permission.
- `client_desktop_app.dart` при plugin error не оставляет скрытое окно за
  неинициализированным треем. Потеря OS tray host без ошибки плагина не обнаруживается;
  это отдельный source-пробел, а не только недостающий acceptance run.
- Android/iOS product folders в `app` отсутствуют; mobile test harness нельзя
  считать продуктом. Сначала нужен реальный разрешённый transport/ABI контракт.

## Следующий порядок реализации

1. Windows native notifications: permission/status, fixed RU/EN content, click
   foreground, lifetime/dedup и unit boundary; готовый AppUserModelID — только основа.
2. OS tray availability/loss detection и оставшиеся UI-owned desktop adapters;
   distribution cleanup текущих autostart registrations.
3. Mobile hosts/bridge, callback и privileged/export flows после получения
   конкретного внешнего контракта. Не создавать runtime или TCP fallback в UI.
4. Завершить accessibility/localization source audit и остальные source gaps,
   затем повторить full implementation gate по BA/SA и всей матрице.
5. Только после закрытия source gate переходить к новым пяти-платформенным
   testserver integration runs и отдельно к реальной platform acceptance.

Доступной работы в client-ui ещё достаточно; состояние цели не blocked.
Внешние зависимости остаются конкретными ограничениями отдельных flows, а не
основанием считать остальные UI-owned части готовыми.
