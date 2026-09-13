# Проверка полноты реализации Client UI — 2026-09-14

Проверяемый commit: `ce98fa4` (main). Это source/unit audit, не повторная
platform acceptance и не закрытие цели. Источники: [SA](client-ui-system-analysis.md),
[матрица 104 требований](../tests/client-coverage.json) и
[BA, architecture/main](https://github.com/endless-net/architecture/blob/main/docs/ru/client-ui-business-analysis.md).
BA прочитан из разрешённого пользователем файла; другие owning repositories
не изменялись. Ни один из 14 US пока не имеет полного acceptance evidence.

Короткий набор последнего изменения: Flutter 3.38.1/Dart 3.10.0,
606 passed / 1 skipped. Число тестов не является мерой полноты функциональности.
Имена файлов ниже относятся к `app/lib`, если явно не указан другой каталог.

## UF: текущая реализация и недостающий результат

Последующее дополнение, не изменение исторического snapshot `ce98fa4`:
реализован [deadline notification planner](../app/lib/client_deadline_notifications.dart)
с [11 unit-тестами](../app/test/client_deadline_notifications_test.dart):
typed session/credential события, RU/EN fixed payload, acknowledge/dedup после
reconnect и инвалидирование receipts при смене контекста. Planner пока не
подключён к UI/native delivery; настройки, permissions, click handling и
прочие значимые события остаются пробелами UF-15. История только in-memory
в текущем runtime/caller/profile; restart UI и возврат к прежнему profile
не обещают сохранения dedup. Общий implementation gate остаётся открытым.

Дополнен [асинхронный диспетчер](../app/lib/client_notification_delivery.dart),
подписанный на state controller: одна отправка одновременно, отдельные delivery
outcomes, явный retry после ошибки, stale completion guards, account isolation.
[11 unit-тестов](../app/test/client_notification_delivery_test.dart) используют
управляемый adapter; shell/settings/native delivery по-прежнему отсутствуют.

Последующее shell дополнение: dispatcher подключён к `ClientDesktopApp`, а
scrollable RU/EN panel содержит toggle текущего запуска, пять delivery outcomes
и явный retry. Без adapter отображается unsupported; production native adapter
пока отсутствует. [Panel tests](../app/test/client_notifications_panel_test.dart)
и [shell test](../app/test/client_app_notifications_test.dart) — widget evidence,
не OS delivery. Persisted preference, permissions и native adapters остаются
незавершёнными; первое включение off пока не окончательная policy.

Persistence дополнение: [UI notification store](../app/lib/client_notification_store.dart)
подключён к entrypoint/shell, восстанавливает boolean, сериализует explicit
choices, сохраняет ошибки как безопасный UI notice и дожидается записи на quit.
[4 storage tests](../app/test/client_notification_store_test.dart) и
[5 shell tests](../app/test/client_app_notifications_test.dart) дают local/unit
evidence. Native delivery/permissions, мобильный settings container и итоговая
default policy остаются незавершёнными; это не полное закрытие UF-15.

Linux delivery source дополнена native Flutter channel → session D-Bus Notify.
Локально пройдены C++ syntax check с реальными GTK/Flutter headers и две GLib
unit-проверки (без desktop bus). Dart channel проверен 11 short tests.
Полная native app build, фактический показ/нажатие, desktop packaging/portal
и адаптеры Windows/macOS/Android/iOS не квалифицированы. См. актуальное
дополнение в [SA](client-ui-system-analysis.md), не считать UF-15 закрытым.

Linux click source дополнена: известный одноразовый notification ID/default
показывает текущее окно, без runtime command/URL/profile restoration. Receipt
set ограничен 64 ID, удаляется при close/service owner change; уничтоженный
host не удерживается живым callback. Четыре GLib unit tests и C++ syntax check
пройдены локально. Реальный ActionInvoked/Wayland focus остаётся acceptance gap.

Linux export source дополнена: `GtkFileChooserNative` через UI-only channel,
local single-folder selection, null на отмену/parent close, fixed error на
непригодный путь/конкурирующий запрос. Shell экспорт теперь доступен для
Windows/Linux и использует прежние checksum/context/unique-directory guards.
14 shared short tests и native syntax check прошли; реальный диалог, portal
permissions и OS captions не квалифицированы. macOS/mobile export ещё отсутствует.

macOS export source дополнена: NSOpenPanel + одноразовый lease, user-selected
read/write entitlement при сохранённом sandbox, release в finally после записи
или stale/error. Семь short channel tests проверяют Dart lifetime; AppKit
compilation, effective sandbox rights и реальный диалог пока не проверены.
Mobile export и macOS protected-IPC acceptance остаются отдельными пробелами.

macOS notification source дополнена: UNUserNotificationCenter delivery с
permission precheck, отдельный explicit permission button в UI и known-ID
default click только для текущего окна. 10 short permission tests проверяют
общую UI/channel-логику; AppKit/UserNotifications build и фактическая работа ОС
не проверены. Windows/Android/iOS adapters остаются незавершёнными.

Linux UI-autostart source дополнена: XDG user entry текущего UI executable,
explicit enable/Hidden=true disable, no runtime connection flags, строгий отказ
от перезаписи чужой записи. RU/EN panel различает отсутствие user entry и off,
показывает ошибку и explicit refresh; shell write блокирует quit. 6 storage и
5 widget tests — local component evidence. Реальный login, system policy,
перенос executable/upgrade и остальные платформы остаются открытыми.

| UF | Наблюдаемая реализация | Что ещё нужно для исходного scope |
| --- | --- | --- |
| UF-01 | `main.dart`, Windows runner/package pipeline; Linux/macOS scaffold | Product hosts Android/iOS отсутствуют; дистрибуция и compatible pairing всех платформ не квалифицированы |
| UF-02 | `client_desktop_app.dart`, `client_tray.dart`: окно, tray, явные действия | UI-autostart и его настройка отсутствуют; native quick surfaces/navigation всех платформ не завершены |
| UF-03 | `client_create_profile_panel.dart`, `client_enrollment_panel.dart`, typed submit/recovery | Mobile native authorization/browser return и реальные enrollment/approval не проверены |
| UF-04 | `client_state_controller.dart`, `client_connection_panel.dart`: snapshot, phase, unavailable/incompatible | Проверить весь набор состояний и понятность next step на реальных hosts; отсутствие службы нельзя выдавать за доказанное отсутствие установки |
| UF-05 | Connection panel и tray, durable journal, recovery без повторной команды | Реальное соединение/разрыв и совпадение primary/quick surface результата после restart/resume |
| UF-06 | `client_peers_panel.dart`: search, список, paths/health, revision | Реальные direct/relay переходы; доступность длинных списков и native accessibility |
| UF-07 | `client_networks_panel.dart`: разрешённый каталог, явный выбор, stale-context guards | Реальный ресурс после смены сети и отсутствие использования прежнего контекста |
| UF-08 | `client_exit_panel.dart`: разрешённый режим, LAN, requested/effective по семействам | Реальная защита трафика при потере exit; platform-specific ограничения нельзя доказать mock-состояниями |
| UF-09 | `client_recovery_panel.dart`, journal, lookup, browser action, session/credential warnings | Полные interruption/restart/resume flows на hosts; нерешённые producer/outbox outcomes сверять по контракту, не придумывать replay |
| UF-10 | `client_identity_panel.dart`, scoped privileged recovery; Windows helper | Не-Windows authorization adapters и реальные owner/admin denial/cancellation |
| UF-11 | `client_diagnostics_panel.dart`, details, recent logs, bounded verified chunks/export | До создания описать фиксированный состав/ограничения архива; export adapter пока только Windows; native privacy/export acceptance отсутствует |
| UF-12 | `client_cleanup_panel.dart`, typed outcomes, distinct logout/local forget | Реальное remote cleanup, отказ authorization и platform-local removal |
| UF-13 | Windows distribution scripts; UI не выполняет installer через RPC | Установка/repair/upgrade/uninstall по утверждённому каналу каждой платформы, сохранение state и outcome от distribution owner |
| UF-14 | RU/EN всех 16 панелей, shell/tray, Material/Cupertino; persisted locale | Полный accessibility/keyboard audit и usability/security review текстов; OS dialogs отдельно |
| UF-15 | Встроенные notices/live regions и deadline projections | Нет законченного слоя управляемых уведомлений: настройки, значимые переходы, dedup после reconnect, platform notification permission/delivery |
| UF-16 | `client_profiles_panel.dart`: create/select/rename/remove и cleanup guards | Реальные multi-profile flows, отдельная Account/Network identity, restart и отказ переключения на каждой платформе |
| UF-17 | Session renewal, независимый credential deadline, typed continuity | Runtime-confirmed continuity и независимые истечения на реальных данных |
| UF-18 | `client_preferences_panel.dart`: draft/apply/reset, presence vs false | Реальные apply failures и policy enforcement без оптимистического effective состояния |
| UF-19 | `client_peers_panel.dart`, `client_resources_panel.dart`: search/catalog/pagination | Невидимость неавторизованных данных и фактическое открытие разрешённого ресурса на hosts |
| UF-20 | Source/lock/owner/reason, requested/effective, managed setting guards | Policy changes/denials на реальной установке; product-approved defaults не заменять догадкой |
| UF-21 | NotifyLifecycle wrapper; shell отправляет UI_QUIT, preference controls существуют | OS logoff/suspend/resume adapters и отдельный UI-autostart отсутствуют. UI launch не должен становиться runtime-start командой |
| UF-22 | `client_update_panel.dart`: verified/expired/unavailable/compatibility, installed pair | Полный trusted source + distribution execution/outcome + fresh bootstrap после установки |
| UF-23 | About/build projection, revalidated support links, 12 RU/EN offline topics | Согласовать producer offline-help key mapping; native browser/support acceptance. Непрозрачный ключ не является URL или путём |

## Требования, которые нельзя закрыть только наличием панели

| Требования BA | Текущий предел доказательства и оставшийся gate |
| --- | --- |
| UBR-01/16/17/32; UI-AC-01/10/11/25 | Source Windows packaging + update/support projection не доказывают signatures, provenance, compatible artifacts, repair/state retention или live resource smoke всех платформ |
| UBR-02/03/07/08/10/11/12/14/15/21/22/36/37/38; UI-AC-03/04/06/07/09/14/16/22/23/24 | Typed consumer, guards, journal и mock outcomes реализованы; protected transport/OS identity/remote cleanup/native restart требуют отдельного исполнения |
| UBR-04/05/09/18/19/23; UI-AC-02/12/13 | Требуются проверка полного контекста Account/Network/device, объяснений каждой ошибки, клавиатуры и принятых assistive technologies; переводы и narrow-layout тесты недостаточны |
| UBR-06/13/31; UI-AC-05/08/27 | Есть bounded redacted reader, checksum и отдельный export. Preview состава/лимитов до Create неполон; native clipboard/log/export privacy требует собственного evidence |
| UBR-20/24/25/40; UI-AC-18/26 | Deadline projections и typed renewal есть; управляемые уведомления/dedup и реальная continuity не завершены |
| UBR-26; UI-AC-21 | UI_QUIT не заменяет crash/logoff/suspend/resume/runtime restart; autostart и OS event adapters нужны отдельно |
| UBR-27/28/29/39; UI-AC-17/19/20 | Mock requested/effective, policy, search и exit tests не подтверждают реальный dataplane/denial/fail-closed |
| UBR-30 | Классификация/security/mandatory и compatibility отображаются; execution/outcome принадлежат distribution, не UI notice |
| UBR-33/34/35; UI-AC-15 | Нужны принятые версии ОС, архитектуры и варианты поддержки с владельцами. Неутверждённые различия нельзя пометить accepted deferred/not applicable |

Все UF-01–23, UBR-01–40 и UI-AC-01–27 остаются в исходной матрице;
объединение строк здесь не удаляет ни один критерий. US-01–14 сохраняют
`implementation: partial`, пока необходимое source work и его проверки не
выполнены. Historical CI entries в ledger относятся только к указанным commits.

## Последовательность оставшейся работы

Дополнение после audit commit: pre-create preview в ClientDiagnosticsPanel
теперь содержит RU/EN описание snapshot/recent logs, ограничений 5 MiB /
15 минут / 256 KiB, отсутствие timed capture/upload и негарантированную
длительность создания. `client_diagnostics_locale_test.dart` проверяет текст
до submit и сохранение explicit consent. Source-пробел описания устранён;
соответствие фактического producer archive и native export ещё не принято.
Исходная таблица выше сохраняет состояние проверенного `ce98fa4`.

1. Закрыть конкретные UI-пробелы: archive preview; управляемые уведомления;
   отдельные autostart/lifecycle controls и platform adapters. Проверять unit
   и widget tests локально на закреплённом SDK, не ждать CI.
2. Подготовить настоящие mobile product hosts и UI-owned platform integration,
   не выдавая `tests/mobile_contract` за продукт. Согласовать границу mobile
   runtime/bridge по producer contract; VPN/runtime core не писать в UI repository.
3. Завершить не-Windows export/privileged adapters в доступном platform scope;
   реальное OS permission поведение и distribution ownership не подменять mocks.
4. Повторить эту проверку полноты. Только после реализации всего функционала
   переходить к новым интеграционным testserver runs пяти платформ.

## Внешние границы и CI

- `client`: только read-only contract/SDK; mobile bridge/native authorization
  и недостающие гарантии owning runtime фиксируются как внешние зависимости.
- `architecture`: product/security решения по OS/architecture/accessibility
  matrix и lifecycle defaults. Этот audit не меняет BA и не утверждает решения.
- Distribution owners / `system-tests`: immutable pairing, signatures, install
  outcome и реальный ресурс. Изменения этих repositories здесь не разрешены.
- GitHub runner infrastructure: исторический Android KVM failure из ledger
  остаётся отдельным внешним вопросом; это не причина менять permissions/hosts.
- Текущие workflows: push — short; integration — PR/manual; обычный repeat 1,
  manual 3; concurrency отменяет superseded workflow/ref. Наличие workflow
  не означает, что source gate пройден или platform acceptance завершена.

Evidence для наиболее крупных source gaps:
[desktop shell](../app/lib/client_desktop_app.dart),
[desktop entrypoint](../app/lib/main.dart),
[session composition](../app/lib/client_session_panel.dart),
[diagnostics panel](../app/lib/client_diagnostics_panel.dart),
[bundle destination](../app/lib/client_bundle_destination.dart),
[short workflow guards](../scripts/check-contract-workflows.test.mjs).
