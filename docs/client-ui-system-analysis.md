# Системный анализ мультиплатформенного Client UI: Protobuf v0

- Status: `target design`.
- Owner: `client-ui`.
- Дата: 2026-09-13.
- Основание: [Client UI BA, main](https://github.com/endless-net/architecture/blob/main/docs/ru/client-ui-business-analysis.md),
  UF-01–UF-23, UBR-01–UBR-40, UI-AC-01–UI-AC-27.
- Producer: [Client v0, main](https://github.com/endless-net/client/tree/main/proto/client/v0)
  и [нормативные правила](https://github.com/endless-net/client/blob/main/docs/client-ipc-protobuf.md).
- Статус реализации: контракт и SDK существуют; desktop UI source переведён на
  native v0, полный runtime/functionality cutover и platform acceptance не заявлены.
  [Windows HTTP v2 as-is](architecture-and-future.md)
  сохраняет дату своей проверки и не является целевым дизайном.

Текущий source gate по всем UF на `97fec77`:
[сводка реализации](client-ui-current-implementation.md). Проверенный актуальный
producer main `60ff0eec554df0b77fdcd9a8fed7d6db933da65e` не меняет proto/Dart SDK
относительно UI pin; смена pin/версий не требуется. Основные конкретные UI-owned
пробелы и внешние mobile/callback зависимости разделены в сводке.

### Принятые продуктовые решения — 2026-09-14

UF-15: metadata invalidation во время OS handoff больше не теряет успешный
receipt и не отправляет тот же релиз повторно. Receipt связан с lifecycle/caller
контекстом и fingerprint релиза, а не с identity заменённого объекта projection.
Disconnect/disable/observer/profile change и expiry по-прежнему отзывают старый
receipt. Ошибка той же доставки переживает refresh и требует явного Retry;
успех или ошибка прежнего релиза не подавляют notice нового релиза. Семь новых
async regression проверяют оба порядка завершения read/send, оба исхода для
нового релиза и disable/re-enable. Эти проверки используют controlled adapter;
фактический показ уведомления ОС и persistent dedup не заявляются.

UF-19: ресурс теперь показывает собственный ID и network ID рядом с именем,
поэтому disclosed overlap IDs можно сопоставить с загруженными строками.
Одинаковые имена/адреса не скрывают принадлежность ресурса сети. Два новых RU/EN
widget tests при 360×640/200% проверяют пересекающиеся одноимённые ресурсы и
точный profile/resource ID команды включения. Успешный browser adapter означает
«Адрес ресурса передан браузеру. Доступность назначения не проверена»; UI не
считает launch подтверждением reachability и не запускает собственные probes.
Это consumer evidence, не реальное применение маршрутов или доступ к ресурсу.

Producer main повторно проверен на UI `f192138`: remote и локальный origin/main
равны `f77191cfdf60a56889bc8d73c4f48cbaad2840c8`. Proto v0 и Dart SDK идентичны
закреплённым; версии/pin не меняются. [Аудит privileged adapter](native-privileged-recovery.md)
заменяет устаревшее описание ещё не подключённого Windows shell и фиксирует
недостающие конкретные Linux/macOS authorization/distribution и mobile bridge
контракты. Их отсутствие не даёт права копировать runtime или угадывать launcher.

UBR-09/10/UF-07: каталог сетей показывает Account ID и независимые IPv4/IPv6
диапазоны из `Network`, а для невыбранной сети — доступность выбора и роль
ответственного. Ранее отображались только имя/ID и disabled-кнопка. Отсутствующее
поле обозначено «Нет данных», данные из snapshot/другой сети не подставляются.
Действие размещено под сведениями, чтобы сохранить ширину текста при 200%.
Шесть RU/EN widget checks проверяют одноимённые сети с разным контекстом,
отсутствующие сведения, permission-required/admin, выбор по profile/network ID
и observer cleanup. Это не доказательство изменения runtime routes или прав.

UBR-23/UF-16: загруженный список профилей теперь показывает раздельно Account
identity, Account ID, неизменяемый control origin и ID выбранной сети из `Profile`.
Ранее source показывал только display name/ID, чего было недостаточно для выбора
между одинаково названными профилями. Отсутствующие поля обозначены «Нет данных»;
сведения из активного snapshot не подставляются в другой профиль. Состояние
профиля, доступность выбора и ответственный за действие локализованы в RU/EN.
Семь новых unit/widget checks проверяют все ProfileState, одинаковые имена с
разным контекстом, отсутствующие поля, policy denial, ID выбранного профиля и
observer cleanup при 360×640/200%. Это consumer evidence, не реальное переключение
туннеля или полная приёмка US-08/14.

Загруженная панель recovery при 360×640 и 200% в RU/EN падала на layout:
`Acknowledge result` / `Подтвердить результат` занимала всю ширину trailing
области ListTile. Действия и pending-статус перенесены под детали операции,
поэтому могут переносить текст и прокручиваться вместе с содержимым.
Восемь `client_catalog_layout_test.dart` проверяют достижимость и фактическое
нажатие network select, acknowledgement, browser action и показ pending в RU/EN.
Каталог сетей проходит ту же проверку без изменения source. Это widget/mock
проверки, а не подтверждение внешнего браузера, runtime outcome или OS accessibility.

Проверка accessibility исходного UI выявила clipping в загруженных dropdown:
при 360×640 и 200% длинной подписи требовалось 288 px, но default itemHeight
оставлял 48 px без RenderFlex exception. Поля выходного узла, address family,
LAN, enrollment mode и preferences теперь используют естественную высоту текста.
Два RU/EN widget regression в `client_choice_layout_test.dart` измеряют полную
высоту названий в реальном меню и выбранном поле; Escape отменяет выбор,
Enter повторно открывает меню, стрелка/Enter выбирают узел без отправки mutation.
Это проверка Flutter layout/keyboard events, не ручная OS screen-reader acceptance
и не завершение accessibility-аудита остальных загруженных панелей.

Verified update notice planner добавлен в `client_update_notifications.dart`.
Общая `validateClientUpdateInfo` используется и прежним reader, и planner:
подпись проверяет producer; UI проверяет pairing/context/срок/формат projection.
Planner не выводит release/version/key/URL или identity, различает ordinary,
security и mandatory фиксированным RU/EN текстом и предлагает проверить
совместимость, не устанавливает пакет. Fingerprint использует scope,
release/manifest/classification, а не revision; stale/expired/observer/disabled
состояния не дают уведомления или acknowledgment. Память bounded/in-memory.
`ClientUpdateNotificationSource` подключает planner к общей последовательной
очереди через `ClientSession.getUpdateInfo`: чтение только после opt-in и ready
owner context, затем по DOMAIN_UPDATES invalidation или явному retry ошибки.
Параллельных чтений нет; устаревший ответ после смены context отбрасывается.
Обычный snapshot не запускает повторное чтение. Одноразовый timer снимает notice
по expiresAt без polling. Ошибка проверки имеет фиксированное RU/EN объяснение
и явный retry в настройках уведомлений. OS adapter получает только фиксированный
текст; acknowledgment и dedup выполняются после успешной передачи системе.
Семь новых unit-тестов проверяют очередь и discovery, но фактический показ ОС,
platform acceptance и завершение UF-15/US-14 этим не заявляются.

Linux tray host detection: native argument-free `isAvailable` читает
`org.kde.StatusNotifierWatcher.IsStatusNotifierHostRegistered` через D-Bus
Properties.Get, с timeout 1000 ms и NO_AUTO_START. Проверяется строго bool;
ошибка/отсутствие/неправильный тип не означает доступный трей. Используется
[KDE wire interface](https://github.com/KDE/plasma-workspace/blob/master/xembed-sni-proxy/org.kde.StatusNotifierWatcher.xml)
с [семантикой host registration](https://specifications.freedesktop.org/status-notifier-item/latest/status-notifier-watcher.html).
Legacy tray fallback не используется.

Shell проверяет host перед первым скрытием и при close, а затем раз в секунду
с одним background read одновременно. Потеря host сбрасывает readiness и
показывает окно; поздний hide после этой потери повторно показывает UI.
Close без host проходит через Quit. Автоматическое восстановление readiness
после потери не заявляется; Windows/macOS пока используют plugin readiness.
Наличие host не доказывает фактическую видимость конкретной иконки или OS focus.
GLib unit, native syntax check в локальной Ubuntu и channel/widget tests пройдены;
реальный GNOME host/extension и native desktop acceptance ещё требуются.

COM single-instance correction: создание native window больше не регистрирует
factory. `main.dart` вызывает argument-free `initialize` только после успешного
instance lock и window initialization; secondary/version/error paths этого не
делают. Повторная успешная инициализация сохраняет существующий host.
При выходе `shutdown` отключает callback и отзывает factory до освобождения lock.
Если native shutdown не подтверждён, lock удерживается до process termination.
Это устраняет source-порядок, допускавший competing factory во вторичном UI.
Три новых Dart channel tests проверяют команды и boolean acknowledgment;
реальная гонка процессов и холодная COM activation ещё требуют acceptance.

Windows notification delivery source теперь реализована: строгий title/body
payload → WinRT XML text nodes → `ToastGeneric`/`ToastNotifier.Show`.
Повторно проверяется OS setting; неготовый COM activator даёт unavailable.
Успех означает передачу системе, как уже говорит RU/EN panel, а не факт баннера.
Async OS Failed/Focus Assist, показ и нажатие требуют отдельного evidence.

MSI регистрирует LocalServer32 для CLSID
`9627bf5f-5cfd-4c27-9822-3f86b95e4884` с фиксированным `--show-window` и связывает
его с Start Menu shortcut. Package/update identity и версии не меняются.
Обычный UI регистрирует WRL factory; native worker без первого показа не
регистрирует её. COM marker `-Embedding` не передаётся Dart CLI.
Activator принимает только AUMID `EndlessNet.Client`, строку `open-ui` и отсутствие
input; он post-ит сигнал показа текущего окна, не URL/profile/runtime command.
При закрытии host callback отключается и class registration отзывается.

Native unit executable проверяет factory/activation lifetime, payload admission
и реальное локальное DOM escaping без отправки toast. Windows Debug source
скомпилирован. Холодный старт/уже работающий UI, single-instance races,
foreground restrictions, COM registration/repair/uninstall и notification-center
поведение после выхода пока не приняты на установленном продукте.
Это заменяет прежнее состояние «delivery NotImplemented» ниже.

Windows notifications permission source: новый native channel читает
`ToastNotifier.Setting` для утверждённого `EndlessNet.Client`. Enabled → granted;
DisabledForApplication/User → denied; DisabledByGroupPolicy → managedDenied
с отдельным RU/EN текстом; DisabledByManifest → unsupported; неизвестное значение
или exception → unavailable. API apartment сбалансирован; настройки ОС не
изменяются. Windows не показывает grant-dialog этим методом: проверяется текущая
policy, согласно [ToastNotifier.Setting](https://learn.microsoft.com/en-us/uwp/api/windows.ui.notifications.toastnotifier.setting).
Доставка пока отвечает NotImplemented: permission success не выдаётся за Show.
Следующий шаг — COM activator, его MSI shortcut/registration и native toast
delivery/click по [desktop C++ notification contract](https://learn.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/send-local-toast-desktop-cpp-wrl).
Существующий AppUserModelID сам по себе эту часть не закрывает.

Desktop close correction: ошибка создания icon/menu сбрасывает tray readiness;
window initialization продолжается, и UI показывается даже при `showWindow=false`.
Ошибка обновления меню показывает окно и запрещает последующее скрытие в этот
трей. Close скрывает только при готовом трее; иначе проходит через существующий
Quit flow. Ошибка hide также ведёт в Quit; ошибка destroy трея не блокирует
destroy окна. Show/hide после window setup ожидаются напрямую, поскольку callback
`waitUntilReadyToShow` в закреплённом window_manager не ожидает async completion.
Это source/widget correction, не доказательство фактической видимости tray в
GNOME/macOS/Windows: потеря OS tray host без plugin error остаётся открытой.
UI_QUIT по producer v0 и runtime-owned lifecycle preferences сохранён; UI не
добавляет Disconnect, OS logoff/suspend/resume или изменение preferences при close.

Windows opt-in implementation: MSI больше не создаёт HKCU Run запись UI.
Windows host обслуживает `endlessnet/ui-autostart` (`read`, `setEnabled` с bool);
entrypoint подключает общий RU/EN panel. Только явное включение записывает
quoted путь текущего executable без runtime CLI и аргументов в
`HKCU\Software\Microsoft\Windows\CurrentVersion\Run\EndlessNet`.
Явное выключение удаляет совпадающую запись. Чтение не создаёт ключ/значение.
Чужая команда, старый путь, неправильный registry type, malformed или слишком
длинное значение дают безопасную ошибку, а не перезапись. Legacy формат
установщика не поддерживается. Ограничение 260 символов следует
[Windows Run contract](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys).

Результат `registered` означает наличие записи, а не разрешение Windows:
StartupApproved не читается и не изменяется, отдельная кнопка открывает Windows
Startup apps settings. `notConfigured` означает отсутствие записи текущего
пользователя. Служба и намерение VPN не изменяются. Это заменяет прежнее описание
безусловной MSI регистрации и Windows panel только со ссылкой на настройки.
Реальные login, OS policy, upgrade/uninstall и очистка UI-owned Run записи для
разных пользователей ещё требуют distribution acceptance; перенос executable
не мигрирует прежний путь. Native unit boundary не заменяет эти проверки.

Пользователь утвердил следующие решения при переносе цели в новую задачу:

- Windows AppUserModelID процесса UI и MSI shortcut: `EndlessNet.Client`.
  Существующие package/update identity и UpgradeCode сохраняются.
- Целевая матрица: Windows 11 x64; macOS 13+ ARM64/x64;
  Ubuntu 24.04 x64 GNOME. Минимальные Android/iOS определяются после
  получения bridge/SDK; неизвестные значения не считаются утверждёнными.
- Mobile bridge использует только предоставленный `client` контракт.
  Отсутствующий bridge — внешняя зависимость; runtime в UI не переносится.
- Enrollment использует системный браузер и проверяемый одноразовый callback,
  привязанный к попытке входа, без долговременных токенов в URL. Подход принят;
  точная схема callback требует producer контракта.
- Закрытие desktop окна скрывает его в доступный трей, иначе завершает UI.
  Выход UI сам не отключает VPN. Autostart и notifications — opt-in.
- Accessibility: клавиатура, видимый фокус, семантические названия,
  информация не только цветом, текст 200%; ручная проверка NVDA, VoiceOver,
  TalkBack и Orca остаётся обязательной частью acceptance.

Это решения целевого дизайна, не доказательство реализации или acceptance.
Они заменяют прежние формулировки о неутверждённой policy. Локали RU/EN и
`endlessnet.app` для новых macOS/Android/iOS hosts остаются требованиями.

Windows AppUserModelID теперь устанавливается до создания Flutter window;
ошибка установки завершает запуск. MSI shortcut получает тот же
`System.AppUserModel.ID`. Используются
[Windows process API](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-setcurrentprocessexplicitappusermodelid)
и [WiX ShortcutProperty](https://docs.firegiant.com/wix/schema/wxs/shortcutproperty/).
Это основа shell identity; native Windows notifications и проверка установленного
ярлыка/группировки taskbar ещё не выполнены.

### Актуализация source cutover — 2026-09-13

[Проверка полноты реализации от 2026-09-14](client-ui-implementation-audit.md)
сверяет все 23 UF и группы UBR/UI-AC с текущим source. Первый этап не закрыт:
mobile product hosts, notifications/autostart/lifecycle adapters, не-Windows
export/authorization ещё требуют реализации. Archive preview дополнен ниже;
это не пересмотр исторического audit commit. Unit totals
и исторические CI runs не заменяют этот gate.

Дополнение 2026-09-14: общий planner
[`ClientDeadlineNotifications`](../app/lib/client_deadline_notifications.dart)
разделяет четыре typed события session/credential EXPIRING/EXPIRED и выдаёт
фиксированные RU/EN тексты без identity, URL, deadline или raw reason.
Состояние доставки ограничено одним runtime/caller/profile context; успешная
доставка требует явного acknowledge. Reconnect сохраняет dedup подтверждённых
событий, но инвалидирует незавершённые receipts; смена контекста и observer
очищают историю. Дедупликация только in-memory: restart UI или возврат к ранее
покинутому profile может повторить уведомление. UI clock не создаёт expiry.
[11 short unit tests](../app/test/client_deadline_notifications_test.dart)
проверяют planner, не OS delivery. Он ещё не подключён к shell: настройки,
permission, доставка/нажатие, persistent policy и остальные значимые события
остаются незавершёнными. UF-15/US-14 не закрыты.

Следующий слой — [`ClientNotificationDelivery`](../app/lib/client_notification_delivery.dart)
— подписывается на `ClientStateController`, сериализует delivery и использует
актуальную локаль при передаче каждого сообщения адаптеру. Adapter получает
только фиксированные title/body. Permission denied, unsupported, unavailable
и failed сохраняются раздельно; исключение не раскрывает native error.
Ошибка требует явного retry, повторные snapshot не создают retry storm.
Disable, потеря stream, смена profile/account и dispose отбрасывают поздний
результат. Уже переданное ОС сообщение отозвать этим слоем нельзя; адаптер
должен завершать каждый вызов, иначе очередь ждёт его завершения.
[11 short tests](../app/test/client_notification_delivery_test.dart) проверяют
state subscription и управляемые async completions, не ОС. Shell wiring,
persisted settings, permissions и native adapters этим слоем не реализованы.

Shell wiring дополнен: `ClientDesktopApp` владеет dispatcher, передаёт локаль,
отключает отправку при завершении UI и освобождает подписку при dispose.
[`ClientNotificationsPanel`](../app/lib/client_notifications_panel.dart) внутри
прокручиваемой session panel позволяет включить deadline notices на текущий
запуск, выключить их и явно повторить неуспешную доставку. Все пять outcomes
имеют отдельные RU/EN тексты; delivered означает передачу системе, не доказанный
показ. Без adapter переключатель недоступен и показано unsupported.
В production entrypoint adapter пока отсутствует; persisted preference,
OS permission/click handling и native delivery ещё нужны. Начальное off —
временное безопасное поведение этой незавершённой функции, не утверждение
окончательной продуктовой политики. [10 widget vectors](../app/test/client_notifications_panel_test.dart)
и [shell regression](../app/test/client_app_notifications_test.dart) проверяют
явный toggle/retry, смену языка без replay и отсутствие runtime mutation.

Persistence дополнена: [`ClientNotificationStore`](../app/lib/client_notification_store.dart)
читает/сохраняет только `0`/`1` в UI settings `notifications`, отдельно от языка,
endpoint и runtime state. Чтение ограничено двумя байтами, malformed/non-file
отклоняется без неявного исправления; запись сериализована через unique temp
и rename. Entry point читает выбор до запуска shell; отсутствующий или
нечитаемый выбор оставляет отправку выключенной. Восстановленный on не
активирует отсутствующий adapter и не перезаписывается при старте/выходе.
Explicit UI choice сохраняется по порядку; поздняя ошибка старой записи не
заменяет результат новой. Ошибка read/save показывает fixed RU/EN предупреждение
о выборе только на текущий запуск. Quit ждёт текущую запись, stale toggle
во время quit не принимается. [Четыре store tests](../app/test/client_notification_store_test.dart)
и пять shell tests проверяют эти границы. Это local/unit evidence, не native
restart/mobile secure container или notification permission acceptance.
Production native delivery и окончательная default policy остаются открытыми.

Linux source delivery добавлена через
[`notifications.cc`](../app/linux/runner/notifications.cc) и
[`native channel`](../app/lib/client_native_notifications.dart); entrypoint
подключает adapter только на Linux. GTK session bus вызывает стандартный
[Notify](https://specifications.freedesktop.org/notification/latest/protocol.html)
асинхронно с 5-second timeout: запрос несёт fixed title/body, без profile/URL,
actions и произвольных hints; markup экранируется, звук подавлен, срок показа
выбирает desktop server. Положительный notification ID означает принятие
сервером, не показ. D-Bus access/auth denial, unknown method и недоступность
различаются без raw error. Missing Flutter plugin остаётся unsupported.
Native syntax check выполнен локально в Ubuntu с Flutter 3.38.1 headers и
GTK 3.24.41/GIO 2.80.0 (`-std=c++14 -Wall -Werror -fsyntax-only`);
[две GLib unit-проверки](../app/linux/runner/notification_protocol_test.cc)
проверяют реальную GVariant-сериализацию/экранирование и error mapping без bus.
[11 Dart channel tests](../app/test/client_native_notifications_test.dart)
проверяют payload, outcomes, malformed response, missing plugin и UTF8 bound.
Полная Linux app build/desktop delivery не выполнялась. Click activation,
desktop-entry packaging, Wayland focus, sandbox/portal, OS notification policy
и остальные четыре платформенных адаптера остаются незавершёнными.

Linux activation source дополнена: `Notify.actions` содержит только пару
`default`/`EndlessNet`. [Receipt guard](../app/linux/runner/notification_activations.h)
хранит не более 64 последних ID без private context. `ActionInvoked` принимается
только от notification service для известного ID/default, однократно; он вызывает
только `gtk_window_present` существующего окна через weak reference, не RPC,
URL и не выбор профиля. `NotificationClosed` удаляет ID, смена владельца D-Bus
service очищает receipts и инвалидирует старые in-flight registration results.
Уничтожение channel отменяет signal subscriptions; pending callback удерживает
только безопасный lifetime контекста и method call. Повтор/чужой ID/другое
действие/закрытый/вытесненный receipt отклоняются четырьмя GLib unit tests
(включая прежние protocol/errors); native syntax check повторён успешно.
Это source/unit evidence: сервер может игнорировать actions согласно
[спецификации](https://specifications.freedesktop.org/notification/latest/protocol.html),
а реальный desktop/Wayland focus и restart не квалифицированы. Старые receipts
за пределами последних 64 не активируют UI; app restart не восстанавливает их.

Linux diagnostics destination source дополнена:
[`bundle_destination.cc`](../app/linux/runner/bundle_destination.cc) регистрирует
существующий UI-only `chooseDirectory` без аргументов. Асинхронный
[GtkFileChooserNative](https://docs.gtk.org/gtk3/class.FileChooserNative.html)
выбирает одну локальную папку; не читает archive handle/bytes, не создаёт папки
и не получает private runtime context. Cancel/закрытие окна возвращает null,
непригодный результат или конкурирующий chooser — fixed error. Parent destroy
и channel teardown закрывают диалог и завершают ожидающий вызов без сохранения.
Shell включает существующий guarded export на Windows/Linux; macOS/mobile
остаются unsupported. [14 short tests](../app/test/client_bundle_destination_test.dart)
проверяют shared channel/flow: платформенную границу, missing/malformed reply,
отмену, context checks до/после выбора и сохранения, отсутствие replay.
Linux C++ syntax check с GTK/Flutter headers пройден; native dialog interaction,
filesystem/portal permission, captions относительно UI locale и полная native
app build не проверены. OS labels выбирает GTK; полное UI-AC-13 не заявлено.

macOS destination source дополнена в
[`MainFlutterWindow.swift`](../app/macos/Runner/MainFlutterWindow.swift):
`NSOpenPanel` выбирает только одну папку без создания каталога. UI получает
временный UUID lease/path, не bookmark; одновременный chooser или новый grant
при ещё открытом предыдущем отклоняется. User-selected read/write entitlement
добавлен в DebugProfile/Release без отключения sandbox. Согласно
[App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox),
доступ открывается системой при выборе и освобождается через
`stopAccessingSecurityScopedResource` после записи/ошибки или закрытия окна.
Shell выполняет scoped export с `finally` release даже при stale context;
malformed path с известным lease также освобождается. Ошибка release не
выдаётся за успешный export и не запускает повтор. Bookmark/path не сохраняется.
[7 channel tests](../app/test/client_mac_bundle_destination_test.dart) проверяют
эти Dart boundaries. Нативные AppKit compilation, NSOpenPanel/grant lifetime,
подпись/entitlement effectiveness и sandbox-protected IPC пока не проверены.
Mobile export отсутствует; наличие macOS source не означает готовность платформы.

Повторная read-only сверка `client/main` после этого дополнения: remote main и
локальный origin/main остаются `c3f1c855cc4dd788dbbbc091a4f6f3e82cba65b1`.
Producer repository, его пользовательские изменения, pin и версии не менялись.

macOS notifications source дополнена в `MainFlutterWindow.swift` через
[`UNUserNotificationCenter`](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter).
Перед add проверяются текущие authorization settings; без разрешения delivery
возвращает permissionDenied, не вызывает OS prompt. Отдельная RU/EN
[`permission panel`](../app/lib/client_notification_permission_panel.dart)
показывается в shell только при наличии request adapter: явное действие вызывает
`requestAuthorization(.alert)`, без sound/badge; результат не включает preference
и не повторяет delivery автоматически. Ошибки/unsupported/denied/granted разделены.
Background/foreground delivery содержит fixed title/body и случайный ID без
userInfo/URL. Delegate показывает banner/list для известных IDs, а default click
однократно открывает только текущее окно; receipt list ограничен 64 и не
восстанавливается после restart. Window close очищает delegate/pending requests;
уже переданный системе показ этим source не гарантированно отзывается.
[10 short permission tests](../app/test/client_notification_permission_test.dart)
проверяют channel/result mapping, explicit single-flight action, RU/EN тексты,
отсутствие запроса при rebuild, disabled/stale click и disposal. Прежние delivery
channel tests сохраняются. Native Swift/AppKit compilation, OS prompt, grant
и реальный click/foreground behavior не проверены; Windows/mobile notification
adapters ещё отсутствуют. Deployment target и версии не менялись.

Linux UI-autostart source дополнена:
[`ClientLinuxAutostart`](../app/lib/client_linux_autostart.dart) управляет только
`$XDG_CONFIG_HOME/autostart/endlessnet.app.desktop` (при отсутствии XDG setting —
`$HOME/.config/autostart`). [XDG autostart](https://specifications.freedesktop.org/autostart/latest/)
включается explicit записью текущего UI executable без runtime flags; выключение
пишет `Hidden=true`, а не удаляет override. Exec учитывает оба слоя escaping и
проценты; control characters, `=` и относительный executable отклоняются.
Записи строго распознаются по текущему формату/executable; неизвестный файл,
symlink/non-file или entry от другого пути не перезаписывается. После переноса
бинарника такая запись требует отдельного исправления — миграция не реализована.
Чтение ограничено, записи сериализованы через unique temp/rename.
Отсутствие user entry не называется выключенным системным автозапуском: system
policy не читается. [RU/EN panel](../app/lib/client_autostart_panel.dart) делает
read при построении и explicit enable/disable/refresh; ошибка не превращается
в успех или автоматический retry. Shell блокирует quit на время записи.
[6 store tests](../app/test/client_linux_autostart_test.dart) и
[5 widget tests](../app/test/client_autostart_panel_test.dart) проверяют эти
компоненты; фактический login launch, desktop policy, install/upgrade/uninstall
и другие платформенные autostart adapters не квалифицированы.

macOS autostart source дополнена через
[`SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice)
и UI-only `endlessnet/ui-autostart` channel. Read передаёт только состояние,
explicit setEnabled — boolean; endpoint, executable path и runtime commands
через канал не передаются. Enabled/notRegistered/requiresApproval различаются,
notFound/error не становится disabled. Повторный enable уже registered/pending
service не вызывает register снова. Требование одобрения показывается в RU/EN
как необходимость действия в Login Items; UI не считает registration доказанным
запуском и не меняет runtime connection intent.
Модель вынесена в [`client_autostart_setting.dart`](../app/lib/client_autostart_setting.dart).
[9 short channel/widget tests](../app/test/client_native_autostart_test.dart)
проверяют все исходы чтения/записи, shape, missing/malformed/error response,
RU/EN approval/unsupported и запрет write при unsupported. На macOS <13
возвращается unsupported; deployment target 12.0 не повышался и старый API
не добавлялся. Реальная ServiceManagement compilation/registration, system
approval, login launch, install/upgrade и Windows/mobile scope ещё не проверены.

Повторная read-only сверка producer 2026-09-14: remote `client/main` на
`c3f1c855cc4dd788dbbbc091a4f6f3e82cba65b1`; `proto/client/v0` и
`packages/client_api` не отличаются от consumer pin
`cd05fcddb858877b10ecefe7b0b4a3819d2c6f3b`. Pin и версии не менялись.
Нормативный `docs/client-ipc-protobuf.md` также не изменился относительно
предыдущей сверки `25f58dc468be4fbcf9abafb4793de7eca5f08c27`.
Актуальные нормативные пояснения readiness требуют rebootstrap после typed
STALE_STATE. Shared session regression проверяет очистку старой проекции,
новый snapshot без прежней identity capability и сохранение UUID без replay;
это не переоценка producer/runtime acceptance.

Проверено на `036541aead97074bf741f2827126b7144043f5bf`: production
`app/lib/main.dart` создаёт `ClientSession`/`ClientDesktopApp`; старые HTTP DTO,
transport, controller/widgets и service emulator удалены коммитами `2d50c16` и
`63b1d83`. Release pairing переведён на exact native descriptor в `78f909e`.
Текущие границы и ограничения описаны в
[native desktop cutover](native-desktop-cutover.md) и
[producer scenario host](native-scenario-host.md).
Это проверка исходников и wiring, не runtime revalidation или доказательство
полного переноса UF/UBR/UI-AC. Ни отсутствие HTTP symbols, ни удаление старых
тестов не подтверждают функциональную полноту. Исторические job results ниже
относятся только к указанным immutable revisions; общий scope остаётся 104 IDs,
0/14 сценариев с полным acceptance. Mobile bridge, OS effects и distribution
outcomes требуют отдельного evidence.

## 1. Границы решения

Build identity UI без `ENDLESSNET_TARGET` теперь определяется по ABI самого
процесса, а не фиксированному windows/amd64. Тот же resolved target показывается
в `--version`; явный build target имеет приоритет. Unit-тесты проверяют 16 ABI,
override и отказ для неподдержанного ABI. Это не утверждённая support matrix:
В product `app` добавлены заготовки Linux/macOS native-hosts с ID `endlessnet.app`
и отображаемым именем `EndlessNet`; существующий Windows-host не изменён.
Статические short-тесты проверяют идентификаторы, имя macOS build product и
получение версии из Flutter build settings. Нативные сборки новых hosts,
доступ к protected IPC из macOS sandbox, lifecycle, экспорт диагностики и
production-иконки ещё требуют реализации/проверки. Это не platform acceptance.
Android/iOS product-hosts пока отсутствуют.

Решение пользователя: основной application/bundle ID новых Android, iOS и macOS
hosts — `endlessnet.app`, отображаемое имя — `EndlessNet`. ID не привязывается к
домену endlessnet.ru. Dev-ID отдельно не утверждён. Выбор имени не подтверждает
регистрацию/доступность в developer accounts и не меняет существующий Windows ID.

Защита управления профилями: callbacks привязаны к controller, snapshot, каталогу,
domain epoch и показанному имени. Подтверждение удаления имеет отдельный token
поколения: отмена, повторное открытие и смена профиля отменяют старые callbacks.
Поздний lookup старого controller не отображается в новом. Семь short widget
тестов проверяют эти условия без RPC/network/native execution.

Решение пользователя от 2026-09-13: приняты локали `ru` и `en`. UI-AC-13
должен проверять весь ключевой сценарий в каждой локали без смешения языков и
потери security-смысла. Каталог подписей операций содержит обе локали; язык
всего приложения ещё не переключается, остальные тексты и системные Flutter
компоненты требуют локализации. Это не закрывает UI-AC-13.

ClientConnectionPanel принимает локаль для статусов, контекста, ограничений,
typed action/failure и сообщений команд. UTC deadlines остаются ISO, без
пересчёта состояния по часам UI. Shared tests проверяют 29 typed projections
в каждой локали и четыре результата команды, полные тексты панели, live region,
смену языка без повторной команды и отсутствие optimistic Connected. Это
локализация компонента, не подключённый full-app language selector.

ClientRecoveryPanel также принимает `ru`/`en`: названия операций, lookup/ack,
browser/export и notices локализованы. Notices хранятся типизированно и при
смене локали перерисовываются без повторного RPC или внешнего действия.
22 shared widget-вектора сравнивают весь текст панели в обеих локалях,
включая ошибки/отмену и отсутствие native export adapter. Это component
evidence; full-app locale switching, системные диалоги и UI-AC-13 ещё не приняты.

ClientOperationDetails принимает выбранную локаль и отображает пояснения всех
typed outcomes на RU/EN. Два shared widget tests проверяют по 14 векторов целиком,
включая remote/local cleanup и suppression секретов. Локаль пока передаётся
компоненту явно в тестах; production shell ещё не предоставляет смену языка.

ClientProfilesPanel локализован на RU/EN, включая поля, пустой каталог, активный
профиль, подтверждение удаления и семь типизированных notices. Предупреждение
явно сохраняет различие локального удаления, выхода и регистрации на сервере.
18 short widget-векторов проверяют каталог, подтверждение, pending/terminal/error,
смену языка без повторной команды и live region. Terminal notice не выдаёт
результат операции за новый runtime snapshot. Это component unit evidence;
full-app language selection и UI-AC-13 остаются незавершёнными.

Создание профиля также принимает RU/EN: пояснение назначения владельца,
поля и accepted/result/unknown notices. Форма привязана к controller и cache
epoch; отправка проверяет показанные поля, snapshot и profiles domain epoch.
Поздние ответы старого контекста не очищают новую форму и не показывают notices.
12 short widget-векторов проверяют смену имени/origin/snapshot/controller,
поздние успех/ошибку и полные RU/EN тексты без повторной команды при смене языка.
Это локальные проверки компонента, не atomic ownership/OS acceptance.

ClientNetworksPanel принимает RU/EN для каталога, selected/empty и notices.
Каталог привязан к controller, active profile и epochs профилей/сетей; callback
выбора дополнительно проверяет показанные snapshot и каталог. Поздний lookup
старого controller не публикуется. 12 short widget-векторов проверяют эти races,
полные RU/EN тексты, смену языка без повторного запроса и отсутствие optimistic
selection. Это component evidence, не реальное переключение сети или UI-AC-13.

ClientPeersPanel локализован на RU/EN: поиск/загрузка, snapshot, пути, кандидаты,
отсутствующие наблюдения и ошибки. Enum snapshot/path/health отображаются
понятными подписями; диагностические reason keys остаются кодами, а адреса,
имена, ISO timestamps и protobuf durations — исходными данными службы.
Один unit-тест проверяет все 12 enum-значений в обеих локалях; шесть widget-тестов
сравнивают весь текст раскрытых деталей, пустого ответа и ошибки, включая смену
языка без повторного запроса. Экран не выполняет probes и не пересчитывает
доступность. Это component evidence, не full-app UI-AC-13/OS acceptance.

ClientIdentityPanel принимает RU/EN для сравнения origin/key/announcement,
предупреждений administrator approval и типизированных notices. Согласие
не переносится на повторное подтверждение, перезагруженные сведения или другой
controller: callbacks проверяют показанный snapshot, identity и поколение
подтверждения. Десять новых short widget-векторов проверяют полные тексты,
отказ отправки trust при изменившемся ключе, ошибки, повторное подтверждение
и смену языка без повторного чтения/команды. Проверки UI не доказывают
реальное повышение прав, установление доверия или принятие UI-AC-13.

ClientCleanupPanel локализован на RU/EN с явным различием logout и local forget:
очистка на сервере до локального удаления против возможного сохранения удалённой
регистрации и сохранения владельца установки. Подтверждение и отмена привязаны
к controller, snapshot, domain epochs и поколению согласия; старое согласие
не отправляет другую команду. 16 short widget-векторов проверяют полные тексты
обоих действий и трёх notices в RU/EN, отсутствие replay при смене языка,
retarget/reconfirm/snapshot/controller races. Это component evidence, не
подтверждение реальной remote cleanup или полного UI-AC-13.

ClientEnrollmentPanel поддерживает RU/EN, включая все режимы регистрации,
вход через браузер/токен и typed notices. Форма отделена по controller и
epochs профилей/сессии, callback отправки связан с показанными полями и snapshot.
Изменение hostname/token/mode/login method отменяет старый callback. Токен
очищается перед вызовом команды; ошибки не выводят исходные исключения.
17 short тестов проверяют enum-подписи, оба способа входа и три notices в RU/EN,
очистку токена, отсутствие replay при смене языка и четыре input races.
Это component evidence, не реальный login/registration или full-app UI-AC-13.

ClientSupportPanel поддерживает RU/EN для встроенной справки, четырёх ссылок,
неизвестной offline topic и безопасного сообщения ошибки. Справка работает без
runtime; locale rebuild не повторяет lookup и не открывает браузер заново.
14 short widget-векторов сравнивают весь текст обеих локалей, offline/error,
каждую ссылку и повторное чтение перед открытием. Это проверка компонента с
mock browser; полный offline corpus, full-app language switching и нативное
открытие браузера ещё не приняты.

ClientUpdatePanel локализует сведения о сборках, source/compatibility/discovery,
classification/channel, срок проверки и notices. Шесть unit-тестов проверяют
все 32 значения этих enum на RU/EN; четыре widget-вектора сравнивают весь текст
недоступного источника/несовместимой пары и ошибки, без повторного lookup при
смене языка. Неизвестное/недоступное состояние не превращается в up-to-date.
Диагностические reason keys и версии сохраняются как данные; уведомление
ничего не устанавливает и не отключает. Это component evidence, не
distribution acceptance, full-app localization или реальная проверка обновления.

ClientDiagnosticsPanel поддерживает RU/EN для сводки, журнала, предупреждений
о сокращении/экспорте и пяти typed notices. Устаревшее blanket-сообщение об
отсутствии экспорта заменено указанием отдельного recovery/download/export пути.
Создание архива не означает экспорт или отправку. Подтверждение и отмена
привязаны к snapshot, preview, controller и поколению согласия. 15 short тестов
проверяют пять connection phases, полные RU/EN тексты сводки/пустого журнала,
все notices, сокрытие browser action из diagnostics и запрет старого согласия
после повторного подтверждения. Это component evidence, не полная детальная
диагностика, native export или full-app UI-AC-13.

ClientDiagnosticsDetails добавляет раскрываемые разделы интерфейсов, маршрутов,
конфликтов и ошибок из уже загруженного snapshot. Отображаются name/index/MTU,
addresses/prefixes/flags, target/interface/uses-interface/peer, overlap prefixes
и reason code; ошибки ограничены локализованным typed code и retryability.
Отсутствие ошибки обозначено как «не сообщена», не как доказательство успеха.
Четыре short widget-теста сравнивают весь раскрытый RU/EN текст с пустыми и
непустыми данными, переключение языка и отсутствие private browser/reason
payload. Разделы не выполняют RPC, copy или upload; новое preview пересоздаёт
их состояние. Это partial US-07; реальная platform diagnostics/export
acceptance не подтверждена.

Раскрываемые tunnel/DNS разделы отображают наличие инспекции отдельно от
пустого результата: tunnel ok/interface/MTU/listen port/typed failure, peers с
public key/endpoint/allowed IPs/handshake/counters/keepalive; DNS search domain,
TTL, servers и records с node/hostname/label/FQDN/addresses. Optional timestamp
и duration не заменяются нулём; большие счётчики сохраняют точность. Восемь
short widget-тестов сравнивают полный RU/EN текст для отсутствующей/пустой
инспекции, заполненных данных и отсутствующих timings; изменение языка
сохраняет раскрытие разделов. Это только просмотр snapshot, без probe,
capture, upload, clipboard или подтверждения фактической работы tunnel/DNS.

ClientResourcesPanel локализует RU/EN поиск, фильтры, effective/requested,
availability/mutation, источник/lock, overlap и пять typed notices. Коды причин,
идентификаторы и адреса остаются данными службы. Два unit-теста покрывают все
11 resource-kind/setting-source значений; 14 widget-векторов сравнивают полный
каталог приложения, пустой результат и все notices в обеих локалях, без
повторного lookup/browser/mutation при смене языка. Фактическое значение не
заменяется запрошенным после принятия команды. Это component evidence, не
реальный доступ к ресурсам или full-app UI-AC-13.

ClientPreferencesPanel поддерживает RU/EN для всех preference keys, lifecycle,
effective/requested, policy/source/lock, черновика, сброса и notices. Значение
«без переопределения» не смешивается с false. Apply/discard проверяют поколение
черновика, поэтому старый callback не применяет и не удаляет более новые правки.
12 short тестов покрывают каталоги подписей, optional/boolean/lifecycle значения,
RU/EN просмотр/lock/apply/reset/error и stale draft actions. Locale rebuild
не повторяет команды. Это component evidence, не OS lifecycle/policy acceptance
и не full-app UI-AC-13.

ClientExitPanel привязывает действия к controller/snapshot, загруженному каталогу
и поколению черновика/подтверждения. Изменение узла, IP family или LAN policy
отменяет прежнее подтверждение очистки. Старые select/confirm/cancel callbacks
не используют новое согласие и не меняют новый черновик. Поздние lookup/error
от прежнего контроллера не отображаются в новом контексте. Восемь short widget
тестов проверяют эти гонки и успешное выполнение свежего явного действия.
Это component evidence US-05, не traffic/fail-closed или native acceptance;
полнота локализации приложения этим набором не подтверждается.

Exit-панель поддерживает RU/EN для режимов IP, LAN policy, apply state,
requested/effective, ограничений, предупреждений single-family, подтверждения
очистки и двух typed notices. Fail-closed показывается как сообщение службы,
не как самостоятельно проверенная защита трафика. Отсутствие кода ошибки
показывается как «не сообщена», а не как доказательство отсутствия ошибки.
17 short тестов покрывают все 12 enum-значений и полный текст панели в обеих
локалях: каталог, IPv4/IPv6, подтверждение, select/clear и read error. Смена
локали сохраняет черновик и переводит notice без повторного read/mutation.
Это component evidence, не full-app UI-AC-13 или реальная routing acceptance.

Оболочка предоставляет явный выбор English/Русский и передаёт ClientLocale во
все 16 панелей ClientSessionPanel. Переводятся команды оболочки, её typed
notices, состояние local connection и подтверждение выхода. Выбор действует
в пределах запуска для встраиваемой оболочки без storage adapter. Desktop main
подключает UI-owned хранилище языка. Material/Cupertino delegates получают
выбранную локаль; native OS dialogs остаются отдельной platform acceptance.
Шесть short widget-тестов проверяют выбор через раскрывающееся меню в обеих
локалях, передачу locale всем панелям, сохранение controller/snapshot/form state
и введённого имени профиля, перевод ошибки без reconnect или записи mutation
в journal, а также тексты quit/stay. Это проверка композиции, не завершённая
UI-AC-13 или native accessibility acceptance.

ClientTray получает выбранную локаль оболочки при создании и переключении.
RU/EN каталоги покрывают 12 service states и четыре local link states; меню,
tooltip status и четыре typed notices переводятся без повторной команды.
Смена локали инвалидирует ключи connect/disconnect старого native menu,
а повторный выбор той же локали ничего не меняет. Десять short unit-тестов
проверяют все подписи, полный текст меню/notices и переключение во время
ожидания результата. Это model/component evidence, не проверка отрисовки
нативного трея, OS accessibility или полной UI-AC-13.

Desktop main читает `language` из caller-home `.endlessnet/ui-settings` до
первого отображения. Это отдельная UI-настройка `en`/`ru`, не runtime state,
не профиль и не intention journal. При отсутствии настройки сохраняется
начальный English; ошибка чтения/записи показывается безопасным RU/EN notice
и не блокирует IPC. Автоматической перезаписи повреждённого файла нет.
Явные изменения сериализуются, запись выполняется через уникальный временный
каталог и rename, чтение ограничено тремя байтами. Нефайловый target отклоняется.
Шесть storage unit-тестов проверяют восстановление выбора новым экземпляром,
порядок записи, повреждения/oversize и восстановление после ошибки. Пять
widget-теста покрывают read/write failure, порядок быстрых изменений без
reconnect и ожидание сохранения при выходе observer UI, а также после ошибки
IPC с явным подтверждением выхода. Завершённая запись не сохраняется как
объект ожидания; прежний owner quit regression также проходит. Native restart
и mobile container paths этим не квалифицированы; это не полная UI-AC-13 acceptance.

MaterialApp использует штатные GlobalMaterialLocalizations.delegates и только
`en`/`ru`. Существующий consumer lock дополнен SDK flutter_localizations и его
зависимостью intl 0.20.2 из Flutter 3.38.1; прежние версии не менялись.
`pub get --enforce-lockfile`, analyze и short widget-проверки выполнены локально
на Flutter 3.38.1/Dart 3.10.0, совпадающем с CI pin. Composed-app regression
проверяет Locale, LTR, Copy/Paste/Select all/Back/Dismiss Material и Copy
Cupertino при переключении в обе стороны, с сохранением формы и без RPC replay.
Нативные clipboard/OS dialogs и screen-reader execution не квалифицированы.

Сверка BA от 2026-09-13: функциональная карта UF-01–23, требования UBR-01–40
и UI-AC-01–27 сохраняются целиком. BA имеет статус draft; UI-Q01/07/16/20/21
оставляют открытыми версии ОС, принятые assistive technologies, lifecycle
defaults, platform variants и distribution ownership. Цель этой задачи сохраняет
пять платформ; эти открытые решения нельзя выдавать за accepted exceptions.
UI-AC-01/11/17 требуют реального ресурса/transport/traffic, UI-AC-10 — distribution,
UI-AC-12/13 — принятых accessibility mechanisms/локалей. Mock-прохождение не
закрывает эти критерии. Эта сверка не меняет BA и не утверждает product решения.

Общая Flutter presentation использует application layer с типизированными моделями
и командами. Транспорт скрыт за platform adapter. Runtime единолично управляет
identity, trust, tunnel intent, credential, policy application и операциями.
UI не читает private files, не запускает core как адаптер и не устанавливает
package через daemon. Server-side права определяют producers.

[Dart SDK](https://github.com/endless-net/client/tree/main/packages/client_api)
закрепляется по immutable source revision. Источник Go-моделей и RPC —
[clientipc](https://github.com/endless-net/client/tree/main/clientipc).
Handwritten HTTP v2 DTO/routes и OpenAPI vendor copy не являются целевой границей.
При cutover заменяются consumer, emulator, helper и release pairing вместе;
совместный production fallback не проектируется.

| Платформа | Transport/authorization | UI/distribution | Условие реализации |
| --- | --- | --- | --- |
| Windows | Прямой protected named pipe; проверенный SID/owner/admin | Flutter window/tray, fixed helper, MSI/WinGet | Проверить Dart gRPC channel ↔ Go handler на pipe, не запускать core-адаптер |
| Linux | Unix socket и peer UID; privileged helper отдельно | Window/tray variant и distro packages | Проверить local credentials, desktop authorization и lifecycle |
| macOS | gRPC over local HTTP/2, protected Unix socket и peer identity | Menu bar, подписанные app/helper | Проверить sandbox/helper integration и signing owner |
| Android | Native bridge ↔ VPN runtime, app identity и OS permission | Mobile navigation, foreground/background policy, store | Назначить runtime owner и проверить bridge |
| iOS | Native bridge ↔ Network Extension, проверенная app identity | Mobile navigation, extension lifecycle, store | Назначить runtime owner и проверить extension boundary |

Generated gRPC SDK не является готовым named-pipe/mobile adapter. Connect Go
поддерживает gRPC, но local channel и caller identity требуют отдельного
transport proof. До него capability не объявляется supported.

Desktop binding уже принят producer: gRPC over local HTTP/2 на named pipe
Windows и Unix socket Linux/macOS, без TCP listener и HTTP/1 fallback.
[Go local transport, main](https://github.com/endless-net/client/tree/main/clientipc/local)
не заменяет доказательство Dart channel и packaged application integration.
Mobile использует отдельно проверенный native bridge, не desktop socket.

## 2. Bootstrap, состояние и права

Последующий [трёхплатформенный native build-only run](native-ui-build-2026-09-14.md#второй-проход-на-8e78e55)
на `8e78e55` завершился success для Linux, Windows 2022 и macOS. Integration
steps пропущены. Он подтверждает compile source этого commit, но не последующий
tray fix и не runtime/OS acceptance; ограничения исходной цели остаются в силе.

Linux tray correction: pinned
[`tray_manager v0.5.3`](https://github.com/leanflutter/tray_manager/blob/v0.5.3/packages/tray_manager/linux/tray_manager_plugin.cc)
не реализует setToolTip/popUpContextMenu. Общий shell ранее вызывал tooltip
перед setContextMenu, поэтому MissingPluginException прерывал установку меню.
Новый [`client_tray_host.dart`](../app/lib/client_tray_host.dart) на Linux
использует setContextMenu; AppIndicator открывает его самостоятельно, runtime
status уже присутствует в menu row. Windows/macOS сохраняют tooltip/popup.
Неизвестный host не считается Linux; после dispose/late tooltip menu keys
не переиспользуются. Ошибка popup показывает безопасный UI notice.
[Десять short tests](../app/test/client_tray_host_test.dart) проверяют platform
method selection, lifetime и свежие menu keys. Фактическая desktop tray/DE
интеграция ещё не принята; это не отказ от UF-02/05 и не runtime fallback.

Native build evidence: [первый compile-only run 2026-09-14](native-ui-build-2026-09-14.md)
на `88947c2` подтвердил настоящую macOS Debug сборку, включая Swift adapters.
Linux/Windows остановились на prerequisites/CMake; исходный run failed.
Compile gate исправлен по логам (AppIndicator dependency, windows-2022,
CRLF-safe fail-fast trace check). Новые Linux/Windows результаты ещё требуются.
Исторические записи «Swift не скомпилирован» выше описывают прежний evidence;
OS permission/IPC/behavior и полная platform acceptance по-прежнему не доказаны.

Native compilation gate: существующий `contract-consumer.yml` теперь собирает
настоящие Windows/Linux/macOS Debug hosts в тех же трёх OS jobs, без отдельной
матрицы jobs. Ручной input `native_build_only=true` исключает producer checkout,
Go testserver build, complete consumer suite и transport probe; остаются locked
dependencies, analyzer и native compile. Этот режим позволяет проверять исходники
платформ на стадии реализации, не начиная integration/testserver acceptance.
По умолчанию PR/manual сохраняют полную suite; pass=1, три повтора opt-in,
superseded cancellation и short-only branch push не изменены. Структурный
[workflow test](../scripts/check-contract-workflows.test.mjs) проверяет guard
каждого integration шага; успешное исполнение native jobs требует собственного
evidence и не выводится из наличия YAML.

Credential notification дополнение: authoritative
`CREDENTIAL_STATE_BLOCKED` теперь даёт отдельный fixed RU/EN notice, не expiry
и не предположение о причине. Account/profile/URL/recovery reason не передаются
OS adapter. Он использует тот же explicit notification toggle и dispatcher;
подпись настройки явно включает blocked credentials. Fingerprint блокировки
не зависит от deadline: reconnect/renewing/unknown и изменение expiresAt не
создают повтор. Только наблюдаемый VALID завершает episode в текущем scope,
включая наблюдение при выключенной доставке; новая блокировка допускает новое
уведомление. История по-прежнему bounded/in-memory, не переживает UI restart.
[Восемь planner tests](../app/test/client_blocked_notifications_test.dart) и
дополнительный [dispatcher test](../app/test/client_notification_delivery_test.dart)
проверяют новые semantics; существующая exhaustive enum matrix обновлена.
Это unit evidence, не новый OS delivery/platform acceptance. Другие значимые
события UF-15 и недостающие native adapters остаются открытыми.

macOS approval navigation дополнение: при requiresApproval отдельная explicit
RU/EN кнопка вызывает
[`SMAppService.openSystemSettingsLoginItems()`](https://developer.apple.com/documentation/servicemanagement/smappservice/opensystemsettingsloginitems())
через `endlessnet/ui-autostart` / `openSettings` без arguments. Она не вызывает
register/unregister, не отправляет runtime RPC и не считает dispatch одобрением.
Только explicit Refresh перечитывает authoritative autostart state. Native
source ограничен macOS 13+, прежний deployment target не изменён; unsupported
не показывает действие. Восемь
[short channel/widget tests](../app/test/client_autostart_settings_test.dart)
проверяют форму канала, RU/EN outcomes, busy/disabled/dispose, safe error и
отсутствие оптимистического enable. Native Swift compilation и фактическое
открытие/approval/login по-прежнему не проверены; это не platform acceptance.

Windows UI autostart control: entrypoint подключает отдельную RU/EN панель,
которая по явному нажатию открывает фиксированный
[`ms-settings:startupapps`](https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings)
через external application launcher. Пользователь управляет зарегистрированным
EndlessNet в Windows Settings; UI не читает/перезаписывает StartupApproved или
Run и не меняет runtime intent. Текущее разрешение явно обозначено как
непроверенное; successful launch не считается enable/disable acceptance.
False/exception дают безопасное сообщение и путь к ручному открытию настроек.
[`client_windows_autostart_test.dart`](../app/test/client_windows_autostart_test.dart)
содержит восемь short tests: fixed URI, RU/EN success/failure, explicit action,
busy/disabled guards, adapter replacement/disposal и error sanitization.
Реальное открытие страницы, наличие установленного entry, policy/permission,
login/upgrade/repair/uninstall ещё не проверены. MSI identity и registration
этой UI-функцией не меняются; UF-02/21 целиком не закрыты.

Windows packaging cutover correction: MSI больше не регистрирует устаревший
`endlessnet:` handler через `--enroll`, который текущий UI startup parser
отвергает. [`installer_test.go`](../tools/windows-packaging/installer_test.go)
запрещает этот handler и старые enrollment flags; существующий
[`client_startup_test.dart`](../app/test/client_startup_test.dart) сохраняет
отказ от startup enrollment. Это удаление не заменяет запланированный новый
deep-link flow и не доказывает cleanup установленного старого package.
MSI HKCU Run запись UI `EndlessNet` уже существует, не изменена; Windows UI
autostart control, OS policy и upgrade behavior остаются отдельными задачами.

Локальная [Windows x64 Debug сборка 2026-09-14](windows-ui-build-2026-09-14.md)
проверила настоящий app на `7f01918` с Flutter 3.38.1 и завершилась успешно.
Это compile/link evidence, не запуск UI, protected IPC, signed distribution или
platform acceptance. Общий implementation gate и mobile bridge dependency
остаются открытыми; integration runs в этой проверке не выполнялись.

UI сначала различает отсутствие installation, отсутствие доступного runtime и
ошибку authorization локального канала. При доступном runtime GetRuntimeInfo
подтверждает protocol, v0, exact descriptor digest, instance ID, build, caller
access и capabilities. Default zero protobuf не доказывает согласование.
Digest проверяется до mutations; несовместимость ведёт к repair/update UI.
Представление UNAVAILABLE транспорта не подменяет ServiceState.ERROR.
После bootstrap каждый RPC, включая новый WatchEvents после reconnect, передаёт
ровно по одному значению protocol/version/descriptor digest metadata из pinned
producer. Только authenticated GetRuntimeInfo может опустить metadata для
диагностики несовместимой установки. Authorization проверяется до metadata;
ошибка доступа не интерпретируется как разрешение на negotiation/fallback.

WatchEvents открывается после bootstrap. Первый SnapshotEvent содержит runtime
и Status, включая connection_phase и current_operations. Это исходная точка
состояния; старый UI cache до её получения помечается устаревшим. Фаза Connecting
видна даже при запуске UI после начала подключения.

| Источник | Представление | Правило |
| --- | --- | --- |
| Неподходящий digest/protocol | Incompatible | Нет mutations; предложение проверенного repair/update |
| Service/control NeedsEnrollment/Login/Approval | Требуемое действие и роль | Connected intent не перекрывает отсутствие допуска |
| ServerIdentityChanged/RecoveryBlocked/PolicyBlocked | Blocked/recovery UI | Без автодоверия и без неявного удаления регистрации |
| connection_phase Connecting/Disconnecting | Прогресс с действующим контекстом | Приоритет у явной blocked/error причины |
| Service Connected и phase Connected | Runtime подключён | Не обещать доступ к конкретному ресурсу без проверки |
| Agent previous snapshot | Данные прежней map revision | Не смешивать с новой authoritative map |
| Operation pending/running/waiting | Прогресс/ожидание пользователя | Accepted не равно выполнено |
| Operation succeeded/failed/cancelled | Terminal outcome | Сообщение по типу результата/Failure, не по diagnostic text |

Observer видит очищенные status/capabilities/support. Owner имеет profile/session,
peer/resource и operation доступ. Administrator выполняет только разрешённые
privileged операции. UI не отправляет SID, роль или «admin=true».
Observer snapshots/events не содержат operation IDs, credential deadlines,
account identity или сетевые адреса. Любая смена caller/context очищает cache.
Для managed denial используется reason/action owner, а не предложение elevation
для обхода server policy.

На пустой установке без owner и enrollment только CreateProfile и Enroll,
помеченные producer `allows_initial_ownership_claim`, могут атомарно закрепить
authenticated peer как owner вместе с принятой mutation. Это не общий доступ
observer к owner RPC. Конкурирующий другой caller получает OWNER_REQUIRED и
не видит операцию победителя. Ownerless существующая enrollment требует admin;
logout/local forget не снимают ownership. UI не обещает возможность захвата
по локально сохранённому признаку «первый запуск».

## 3. Команды и восстановление

US-07 read foundation: `ClientSession.getDiagnostics` и local RPC binding читают
typed preview для текущего owner profile. Проверяются runtime/revision и metadata
вложенного status, если он присутствует; возвращается frozen copy с сохранённым
truncated. Любая domain invalidation во время aggregate read отклоняет ответ,
включая повторную invalidation peers. Чтение не создаёт bundle, не пишет clipboard,
не выполняет upload и не добавляет intention. Локальная session regression
проверяет эти границы; UI preview, redaction/export policy, chunks, native execution
и actual runtime acceptance на этапе этой foundation ещё требовались.
Production main теперь использует native session panel; это source wiring,
а не доказательство полноты diagnostics acceptance.
Составная session panel теперь содержит явный local diagnostics summary:
OS/Go, counts interfaces/routes/peers/conflicts/failures, connection phase и
truncation warning. Capability/caller/context ограничивают просмотр; domain
invalidation скрывает прежний summary. Shared widget regression проверяет отсутствие
авточтения, очистку и исключение browser URL из отображения. Полный payload
не сериализуется в clipboard/logs; подробные данные и archive export ещё не
реализованы. Native execution нового preview test ожидает CI.
`readClientBundleChunks` — transport assembly foundation: frozen handle, 5 MiB
bound, 64 KiB requests, exact offset/EOF, expiry и caller-context checks до/после
RPC. Shared tests проверяют two-chunk read, malformed offsets/EOF, отсутствие
progress, expiry и caller change. После EOF проверяется SHA-256 всего содержимого;
same-size corruption test отклоняется. Используется уже закреплённый crypto 3.0.7
как direct dependency, версия не повышалась. Checksum подтверждает соответствие
handle, не redaction/подлинность произвольного архива; session binding и explicit
file export ещё нужны.
`ClientSession.readDiagnosticsBundle(requestId)` теперь заново выполняет typed
GetOperation с expected CREATE_DIAGNOSTICS_BUNDLE kind, требует succeeded outcome
и читает свежий handle через защищённый local channel. Перед каждым chunk и после
него проверяются session/cache/profile/session-domain epochs. Consumer test
проверяет свежий lookup, pending rejection и caller change во время чтения.
Чтение не acknowledge intention и не сохраняет файл; UI/export binding и producer
process/native execution этого пути ещё требуются.
После явного diagnostics preview UI предлагает отдельное подтверждение создания
локального redacted bundle. Session panel отправляет journaled
CreateDiagnosticsBundle с текущим ProfileRef; cancellation/invalidation не
отправляют команду, acceptance не означает archive readiness. Shared widget test
проверяет эти границы. Download/export UI, полноценный preview и native execution
нового create flow остаются открытыми; source wiring production main описан выше.
Diagnostics panel при invalidation/caller change теперь удаляет сам protobuf из
widget state, notice и confirmation, а не только скрывает summary. Listener
переподключается при замене controller и снимается при dispose; очищенный context
не допускает возврата late response. Это очистка ссылок, не обещание secure memory
erasure managed Dart heap.
Producer process suite содержит bundle fixture: journaled create, terminal lookup,
повторный GetOperation перед download, два точных ReadDiagnosticsBundle запроса,
SHA-256 и сохранение intention до явного acknowledgement. Test envelope проверен
локально; execution этого нового process scenario ожидает desktop GitHub runners.
Synthetic bytes [1,2,3] проверяют transport/checksum, не формат/redaction архива.
Дополнительные shared bundle vectors проверяют отказ до RPC при empty handle,
размере >5 MiB, отсутствующем expiry, некорректных nanos/checksum; oversized chunk
отклоняется, RPC error передаётся без повторного чтения. Это unit-level evidence;
оно не подменяет process execution, redaction или native export acceptance.
`exportClientBundle` — filesystem export primitive для уже проверенных bytes:
только явно переданный absolute destination, новая уникальная подпапка,
`diagnostics.bundle` без предположения ZIP, flush и повторная context check.
При ошибке удаляется только созданная подпапка. Filesystem regression проверяет
неперезапись, два отдельных экспорта и cleanup после отмены. Native destination
picker, session/UI binding, OS permissions и формат/redaction имеют отдельные
acceptance gates; путь никогда не берётся из bundle handle.
`ClientSession.exportDiagnosticsBundle` связывает свежий operation lookup,
checksum-verified read и файловую запись одним session/context guard. Session
regression проверяет успешный файл, отсутствие нового output при checksum mismatch
и смене caller во время загрузки. Intention не acknowledge автоматически.
Это не полный US-07 acceptance; default Windows binding описан ниже.
Recovery UI теперь предоставляет explicit export action только для succeeded
bundle outcome и переданного native adapter. Перед callback повторяется recovery;
adapter получает request ID и context guard, не старый handle/путь. Cancellation
отличается от saved, intention остаётся для отдельного acknowledgement. Shared
widget test проверяет explicit invocation, fresh lookup и cancellation. Default
session panel без native adapter сообщает недоступность.
Windows desktop теперь передаёт adapter: системный IFileOpenDialog выбирает
существующую filesystem-папку, возвращая только путь или null при отмене через
UI-owned MethodChannel. Пакет сохраняется через `ClientSession.exportDiagnosticsBundle`
в новую подпапку; caller/profile/session guards проверяются до/после picker и
сохранения. URL, handle и bytes не передаются native chooser. Short unit-тесты
проверяют отмену, неверные пути, ошибки и смену контекста без повтора команды.
Реальное взаимодействие с диалогом Windows ещё не принято; адаптеры Linux,
macOS, Android и iOS отсутствуют. Полноценное системное сохранение на пяти
платформах остаётся незавершённым.
Helper не пишет файлы, clipboard или сеть вне переданного RPC callback.

Проверенный consumer commit `ed43df36c8feab083abd9b7b7b41e9ad3112dbd4`:
[desktop run](https://github.com/endless-net/client-ui/actions/runs/34730432514)
успешен на Windows/Linux/macOS, по 109 consumer + 15 profile/network tests;
[iOS job](https://github.com/endless-net/client-ui/actions/runs/34730432531/job/103652189494)
успешен, 23 simulator tests, включая trust UI race regression.
[Android job](https://github.com/endless-net/client-ui/actions/runs/34730432531/job/103652189664)
failed до тестов из-за KVM. Это один consumer commit, но разные scopes:
desktop Go/Dart interoperability и mobile shared widget suite; не complete
five-platform product acceptance. Windows EOF ниже не повторился, причина
не установлена. Ни один полный US этим запуском не закрывается.

US-06 read foundation: `ClientSession.getServerIdentity` вызывает typed RPC
для текущего active ProfileRef только после owner snapshot. Проверяются
наличие identity/metadata, profile/instance/revision; late response отклоняется
после смены cache/context, DOMAIN_SERVER_IDENTITY или DOMAIN_PROFILES invalidation.
Результат — отдельная frozen protobuf copy, не разрешение доверять ключу.
Две session regressions проверяют также повторную invalidation и observer denial.
`ClientIdentityPanel` в составной session panel показывает origin, trusted/announced
key и announcement. Explicit checkbox и отдельный confirm требуют administrator
и AVAILABLE IDENTITY_RECOVERY. Перед journaled mutation выполняется повторный read:
любое расхождение показанных полей отменяет отправку и требует нового сравнения.
Cache/domain changes очищают UI; invalidation во время записи intention также
проверяется перед RPC. Shared mobile widget test проверяет owner denial, смену
announcement, точные подтверждённые поля и сброс invalidated data без автодоверия.
Форма дополнительно привязана к context tuple при создании: callback старого
виджета отвергается даже после invalidation до следующего frame. Regression
доставляет late read и вызывает captured callback без перерисовки; без этой
проверки тест падает, с ней проходит. Это локальная consumer race verification,
не native/runtime acceptance.
Desktop process suite теперь содержит отдельный synthetic administrator scenario:
GetServerIdentity → TrustServerIdentity с точными origin/key/announcement →
GetOperation, при открытом WatchEvents. Journal проверяется на точные UUID/kind
без identity payload; acceptance не меняет snapshot оптимистично. Testserver
моделирует роль только для этой fixture, не даёт UI способ задавать свою роль.
Process scenario проверен desktop run выше; локально standalone Go testserver
не запускался. Проверка operation envelope локально включает trust outcome.
На `f6386db` trust process fixture прошла на Linux, macOS и Windows; Windows job
в целом failed (107 passed / 1 failed): connect fixture получила EOF от testserver
вместо ожидаемого lifecycle event
([job](https://github.com/endless-net/client-ui/actions/runs/34730155723/job/103651358745)).
Причина выхода не сохранена прежним фильтром stderr; гонка cancellation/Verify —
гипотеза, не установленная причина. Harness теперь сохраняет только точные
фиксированные lifecycle errors и exit code; payload/headers не добавляются.
Это диагностика следующего запуска, не исправление или Windows acceptance.
Этот process flow сам по себе не проверяет privileged helper или production shell.
Их последующий source cutover описан в native desktop cutover; actual runtime
acceptance ещё требуется, и этот partial consumer flow не закрывает US-06.

На `b2d218420af01e69739447c9b3d802554dd8912b` iOS simulator job успешно
выполнил **22 tests passed**
([job](https://github.com/endless-net/client-ui/actions/runs/34729192852/job/103648732270)).
Это повторная проверка shared widget/profile/network suite после SafeArea fix,
включая настоящий tap с верхним inset. Предыдущие failures ниже остаются
историческим evidence; причина intermittent VM Service startup timeout этим
успехом не установлена. Успех job не означает успех всего mobile run или приёмку
native VPN bridge, реального runtime, полного product shell и traffic path.

Повторный iOS job на `52eac5c` завершился до тестов: 0 passed, timeout ожидания
VM Service после успешного build/simctl launch
([job](https://github.com/endless-net/client-ui/actions/runs/34728449505/job/103646732566)).
SafeArea этим запуском не проверена. Workflow теперь сохраняет при failure screenshot
изолированного synthetic simulator и последние 5 минут Runner log до shutdown;
это диагностический шаг, не исправление VM Service и не platform acceptance.
Тайм-аут и права runner не менялись; artifacts хранятся 3 дня.

Native iOS run на `840a6f5` впервые выполнил suite: 16 passed / 5 failed
([job](https://github.com/endless-net/client-ui/actions/runs/34727879154/job/103645229712)).
Пять failures сопровождались hit-test miss верхних кнопок на y=24. Shared test
scaffold и составная session panel теперь используют SafeArea; локальная regression
проверяет верхний inset 59 и настоящий tap, layout — также нижний inset 34.
Повторный simulator execution зафиксирован выше; локальные unit tests сами по себе не закрывают iOS acceptance.

UBR-09 context: панель подключения показывает owner с active profile отдельные Account ID, Network name
и ID, device hostname и node ID из текущего Status. Отсутствующее значение
отмечается Unknown; каталоги не используются для угадывания этих полей. Shared
widget regression проверяет обновление Network и очистку private context при
переходе в observer. Это UBR-09 consumer foundation, не полная локализация или
платформенная acceptance.

US-04 read foundation: `client_networks.dart` собирает полный immutable каталог
через ListNetworks с фиксированным ProfileRef и opaque page tokens. Проверяются
instance/revision, неизменность selected ID, duplicate IDs и pagination cycles;
LocalClientEvents предоставляет typed RPC binding. Шесть проверок входят в общий
`client_profiles_test.dart` и mobile harness. Session.listNetworks теперь требует
owner/active profile и отклоняет late result после cache/domain invalidation,
смены профиля, другого instance/profile или старой revision. Session regression
проверяет две последовательные invalidations и смену active profile.
ClientNetworksPanel подключает refresh и journaled SelectNetwork с profile/network
IDs из свежего каталога, разрешая выбор только при AVAILABLE selection restriction.
Shared widget-тест проверяет restriction, отсутствие optimistic network state,
invalidation и observer cleanup. Это ещё не доказательство network lifecycle
acceptance или смены реального туннеля; подключение production entrypoint
проверено отдельно в source cutover, не этим reader test.

US-04 peer foundation: ClientPeersPanel подключён к Session.listPeers и native
ListPeers. Поиск выполняется явно; редактирование запроса сбрасывает прежний
результат, а request serial не позволяет поздней странице заменить новый запрос.
Session проверяет owner/profile, revision и повторные PEERS/NETWORKS/PROFILES
invalidations между страницами. Экран показывает snapshot_state, applied/target
map revisions, stable peer ID, overlay addresses, selected path/endpoint и
переданные producer причины, health, RTT и timestamps кандидатов. Он не запускает
сетевые probes и не считает PREVIOUS snapshot доказательством текущей связности.
Shared widget regression подаёт typed StatusChanged со сменой Network и новой
revision: уже показанные peers и поисковая строка очищаются, автоматического
запроса нет. Отдельный сценарий задерживает старый ответ до завершения явного
запроса в новом контексте и проверяет, что старый результат не возвращается.
Эти два теста включены в общий mobile harness; это проверка consumer на
синтетическом event stream, не выполнение SelectNetwork в native runtime.
Shared tests входят в desktop/mobile harness; локальные результаты не закрывают
native IPC interoperability, локализацию, accessibility или platform acceptance.

Составная ClientSessionPanel имеет общий scroll container, enrollment mode dropdown
ограничен доступной шириной. US-14 widget regression проверяет всю session panel
при 360×640 и text scale 2, отсутствие RenderFlex overflow и достижимость profile
refresh через прокрутку. Это локальная layout-проверка, не полная accessibility
или native mobile product acceptance.

US-14: fixed-text результаты Connect/Disconnect/RenewSession помечены отдельным
semantic live region. Shared regression проверяет точный текст pending-объявления
без profile/credential payload и удаление semantic node при переходе в observer.
Это проверка Flutter semantics tree, а не фактического озвучивания VoiceOver,
TalkBack или Windows screen reader; полная accessibility и локализация открыты.

ClientOperationDetails отображает закрытые enum состояния операции, continuity,
ошибки, владельца действия и required action через английские подписи, а не wire
names. Raw reason key и browser URL не отображаются. Shared regression проверяет
подписи и скрытие чувствительных полей; это не полная локализация US-14.

UBR-04/05: основная connection panel для owner с активным профилем показывает
typed pending_action, recovery.failure и status.failures с action owner. Raw
reason_key и browser URL не отображаются, action не запускается при render.
Замена snapshot удаляет прежние подсказки. Shared widget regression проверяет
эту проекцию; это не полный набор next steps и не usability acceptance UI-AC-02.

US-03/09: Connect, Disconnect и RenewSession привязаны к immutable snapshot,
который разрешил кнопку. Отложенный callback после замены profile/caller,
capabilities, status или session, отключения подписки либо dispose не вызывает
команду. Повторный callback во время незавершённого submit также отклоняется;
Disconnect во время Connect остаётся доступным. 24 widget regressions в
`client_connection_activation_test.dart` включены в desktop suite и mobile host.
Они моделируют queued activation напрямую, не доказывают реальные OS input events.
Локальный анализ mobile host невозможен без его ephemeral dependency resolution;
исполнение Android/iOS этих новых сценариев остаётся за CI.

`client_cleanup_panel.dart` подключает отдельные journaled Logout и
ForgetLocalEnrollment(confirmed=true) для active profile. Каждое действие требует
подтверждения; local forget дополнительно требует ACCESS_ADMINISTRATOR и capability.
Неудачный logout не вызывает local forget, а смена cache/caller скрывает confirmation.
Shared widget-тест проверяет cancel, явный dispatch, administrator gating и отсутствие
fallback; реальное remote cleanup, elevation helper и platform acceptance ещё нужны.

`client_enrollment_panel.dart` подключает явный Enroll выбранного профиля через
session journal: hostname, typed mode и ровно одна authentication alternative
(browser_login=true или enrollment_token). Форма требует owner, active profile
и доступную CAPABILITY_ENROLLMENT; token field masked, очищается до dispatch и
не включается в ошибки/журнал. Snapshot/cache change пересоздаёт форму. Shared
widget-тест проверяет capability gating, обе auth alternatives на callback boundary,
очистку token и observer transition. End-to-end enrollment и initial Enroll claim
без выбранного профиля пока не доказаны; initial ownership UI начинается с CreateProfile.
Process suite `client_session_process_test.dart` теперь задаёт отдельные browser/token
Enroll сценарии для pinned producer testserver: exact authentication oneof, mutation
context, terminal enrollment result через GetOperation и UUID/kind-only journal.
Они выполняются только при ENDLESSNET_TESTSERVER в desktop CI; добавление сценариев
не является доказательством их прохождения или реальной backend enrollment.

`client_operation_details.dart` отображает typed outcome в recovery panel:
remote cleanup confirmation отдельно от local registration removal, failure code,
action owner и correlation ID, selection/enrollment IDs и connection continuity.
Произвольные reason strings и browser URL не рендерятся. Shared mobile/desktop
widget-тест проверяет cleanup distinction, failed logout и сокрытие browser URL.
Это presentation foundation: native permission/helper actions,
загрузка bundle и полная outcome-specific UX ещё требуют реализации и acceptance.
OPEN_BROWSER в recovery panel теперь запускается только по явной кнопке после
нового lookup той же operation/request identity. UI проверяет HTTPS, отсутствие
userinfo и переданный expires_at; producer отвечает за trusted origin/provider
policy. Launcher подключён через externalApplication без логирования URL/errors.
Запуск не подтверждает intention и не меняет operation state. Shared widget-тест
проверяет fresh URL, invalid schemes/userinfo и expiry; реальный OS browser flow
и завершение enrollment пока не являются подтверждённой platform acceptance.

UI сохраняет request ID до отправки намерения, не сохраняя enrollment token в
журнале операций. Mutations включают ожидаемые instance/revision из свежего
состояния. Timeout оставляет исход неизвестным; GetOperation по request ID
восстанавливает принятую команду. Повтор того же payload использует тот же ID.
Новый payload получает новый ID только после нового намерения пользователя.

STALE_STATE означает refresh и повторное подтверждение применимости действия,
а не автоматическое исполнение команды на другом профиле. BUSY не скрывается
универсальным success. Cancellation OS/browser до принятия не меняет trust;
закрытие окна после принятия операции не отменяет durable runtime work.
Disconnect остаётся доступен и исключает возврат connected intent запоздавшим
результатом иной операции.

current_operations показывает все видимые owner nonterminal operations, включая
inactive profiles. Terminal result восстанавливается по сохранённому request ID.
Тип действия берётся только из immutable `Operation.kind`, заданного producer
по RPC annotation; не из operation ID, outcome, активного профиля или последней
нажатой кнопки. UNSPECIFIED/unknown kind — невалидный producer output: UI не
угадывает действие и не показывает успешное выполнение. Проверка одинакова для
mutation response, GetOperation, первого snapshot и последующих событий.
Reconnect получает свежий snapshot и перечитывает инвалидированные домены.
Sequence локальна потоку: resume cursor и слияние пропущенных deltas не используются.
При переполнении потока consumer переподключается; unsubscribe не отменяет work.
Смена profile удаляет старые lists, deadlines, selection и notifications context.

## 4. Сценарии и соответствие BA

| SA | UF / UBR | Алгоритм и отрицательные исходы | Приёмка |
| --- | --- | --- | --- |
| US-01 Bootstrap/shell | UF-01/02/04; UBR-01/03/04/16/18/21/33–35 | Проверка installation/transport/digest; первый snapshot; supported capability по платформе | UI-AC-01/02/04/10/11/15/23/26 |
| US-02 Enrollment | UF-03/09; UBR-02/06/07/09/22/36 | Пустой профиль, initial ownership claim, выбор, Enroll; browser action без логирования token; ожидание approval/операции; competing caller/denial/expiry/timeout | UI-AC-01/04/05/07/22 |
| US-03 Connection | UF-04/05; UBR-04/05/08/14/36/37 | Connect/Disconnect, phase и operation; runtime restart, stale revision и потерянный ответ | UI-AC-02/03/04/22/23 |
| US-04 Peers/network | UF-06/07; UBR-09/10/14/22 | ListPeers/ListNetworks, выбор по ID, сброс cache прежней Network; недоступный/stale выбор | UI-AC-14/20/23 |
| US-05 Exit node | UF-08; UBR-05/22/39 | Catalog → allowed family mode/LAN constraints → select/clear → requested/effective отдельно IPv4/IPv6; partial apply/clear, path loss fail-closed и apply failure | UI-AC-17 |
| US-06 Recovery/trust | UF-09/10; UBR-02/05/11/12/14/22 | Сравнить origin/key/announcement, fixed helper, operation; mismatch/отмена/нет privilege не меняют trust | UI-AC-04/06/07 |
| US-07 Diagnostics | UF-11; UBR-06/13/14/31 | Preview → create → handle/chunks → локальный export; redaction, expiry, caller mismatch и offset bounds | UI-AC-05/08/27 |
| US-08 Logout/profiles | UF-12/16; UBR-15/23/38 | Create/select/rename; logout с remote confirmation; отдельный local forget; inactive clean profile remove | UI-AC-09/16/22 |
| US-09 Expiry/renewal | UF-09/15/17; UBR-24/25/40 | Независимые session/credential clocks, unknown deadline; user renew только session, runtime credential recovery | UI-AC-18/26 |
| US-10 Preferences/policy | UF-18/20; UBR-22/27/28 | Get/Set/Reset, presence против false, source/lock, requested/effective; весь patch валидируется до записи | UI-AC-19/24 |
| US-11 Resources | UF-19; UBR-22/29 | Search/page, kind/availability/overlap, local enable; скрытые ресурсы, stale page и conflict | UI-AC-20/24 |
| US-12 Lifecycle | UF-21; UBR-26/33/34 | UI launch отдельно; explicit quit отдельно от crash; logoff/suspend/resume сообщает OS adapter | UI-AC-03/15/21 |
| US-13 Distribution/help | UF-13/22/23; UBR-16/17/21/30/32 | Verified update projection, external updater outcome, повторный bootstrap; source unavailable не равно up-to-date | UI-AC-10/11/25 |
| US-14 Presentation/privacy | UF-14/15; UBR-18/19/20/33–35 | Локализация reasons, assistive technologies, уведомления без секретов и дублей; offline help | UI-AC-05/12/13/15/26 |

Сценарии описывают contract consumer; не заменяют проверку actual runtime.
Profile removal не удаляет последнюю активную запись: после logout она остаётся
пустой, пока пользователь не выберет другой профиль. UI объясняет это правило.
Rename никогда не меняет Account identity/control origin.

## 5. Сроки, предпочтения и диагностика

US-13 reader foundation: `readClientUpdateInfo` сохраняет различия UNKNOWN,
SOURCE_UNAVAILABLE, VERIFICATION_FAILED и UP_TO_DATE. Проверяет instance/revision,
installed runtime и caller-reported UI identity, immutable copy, verified metadata,
expiry/verification time, target platform/architecture, classification/channel и
HTTPS URLs без userinfo. Это проверка согласованности producer projection, не
криптографическая проверка manifest. Никаких installer/browser действий reader
не выполняет. Shared tests покрывают valid/invalid projections и invalidation.
Local/session binding теперь вызывает generated GetUpdateInfo через текущий
native channel. Owner не обязан иметь active profile для этого installation-level
read; observer запрещён до RPC. Cache/context replacement, повторные UPDATES
invalidations и устаревшая response revision отклоняются; journal не меняется.
Session test проверяет эти границы. `ClientUpdatePanel` подключён к production
desktop shell: UI build берётся из тех же compile-time полей, что versionText,
core build — из snapshot. Только явный Check updates вызывает чтение; observer
не может его запустить. Source state и installed-pair compatibility независимы,
classification/channel не запускают installer и не отключают соединение.
Context invalidation удаляет projection, late response отвергается; expiry timer
убирает просроченное предложение без автоматического повторного чтения. Shared
widget tests проверяют эти границы, включая expiry после показа. Trusted source
configuration, About/Help, external distribution action/outcome и platform
acceptance ещё не реализованы/не подтверждены этим слоем.

US-13 support foundation: `ClientSession.getSupportInfo` вызывает generated RPC,
разрешённый observer без active profile. Reader сверяет BuildIdentity с текущим
snapshot, сохраняет immutable SupportInfo, отклоняет HTTP/file URLs, userinfo,
whitespace/control characters. Пустые destinations остаются пустыми; URL не
открываются автоматически. Runtime отвечает за trusted configured sources;
одна проверка HTTPS не устанавливает доверие к owning domain. В SupportInfo v0
нет metadata/revision: consumer не синтезирует их, а отклоняет ответ при смене
cache/context или повторной SUPPORT invalidation. Offline key остаётся opaque,
не является путём к файлу. Shared reader/session tests локально проверяют эти
границы. `ClientSupportPanel` подключён к session panel: базовая встроенная
справка доступна без runtime/network, Refresh support — отдельное действие.
Documentation/support/privacy/license кнопки существуют только для непустых
producer destinations; click повторно читает SupportInfo и открывает лишь тот
же raw URL в неизменном context. UI не разрешает unknown offline key как path,
а сообщает, что producer topic не bundled; базовая UI-owned справка остаётся.
Shared widget tests используют fake launcher и проверяют open, changed/unsafe
URL, invalidation и launcher отказ. Это не native browser acceptance; полный
platform evidence и согласованное отображение producer offline-help keys ещё
нужны. UI-owned справка расширена до 12 RU/EN тем: служба/доступ, регистрация,
сети/подключение, recovery, trust, exit/LAN, ресурсы, preferences/policy,
cleanup, диагностика/privacy, обновления и язык/support. Темы раскрываются без
RPC, browser, файловых путей из ключа или иных внешних действий. Они не задают
неутверждённые OS defaults, VPN permission flows или команды установки.
Три short теста проверяют состав каталога и ключевые смысловые ограничения,
раскрывают все 12 тем в обеих локалях при 360×640/text scale 2, проверяют
отсутствие overflow/RPC/browser и сохранение раскрытия при смене языка.
Это UI component evidence, не product approval всех текстов или OS accessibility.

US-13 process foundation: `client_information_process_test.dart` содержит семь
сценариев producer-host — observer support и шесть owner update states. Runtime
build и UI claim намеренно synthetic (не OS attestation); GetUpdateInfo ожидает
точный reported_ui. WatchEvents остаётся открыт, active profile отсутствует,
journal пуст и HostVerify отвергает лишние RPC. Observer role задаётся только
тестовому процессу, не production UI; update запрещается consumer до запроса.
Это не проверка server-side отказа, настоящих подписей или installer effects.
Локально валидируются fixture projections; process execution ожидается в desktop CI.

US-12 foundation: desktop shell отправляет journaled NotifyLifecycle(UI_QUIT)
при явном Quit owner с активным профилем; observer не отправляет мутацию.
Открытие UI не означает runtime start. Pending acceptance разрешает закрыть UI,
но UUID остаётся для recovery; отсутствие подтверждения предлагает Stay/Exit UI,
а не повтор команды. Widget tests проверяют owner/observer и Stay при unavailable
runtime с отключённой native window/tray integration; Quit вызывается через
callback. Producer-process ui-quit case проверяет точный event/context и recovery
при открытом WatchEvents, execution ожидается на desktop CI. OS logoff/suspend/
resume, crash-versus-quit, применение preferences и mobile lifecycle acceptance
остаются незакрытыми; UI не подменяет события OS adapter.

Уточнение ownership по повторно сверенным `client/origin/main` и remote main
`c3f1c855cc4dd788dbbbc091a4f6f3e82cba65b1`: комментарий
[NotifyLifecycle в service.proto](https://github.com/endless-net/client/blob/main/proto/client/v0/service.proto)
явно оставляет OS lifecycle runtime adapters; enum
[LifecycleEvent](https://github.com/endless-net/client/blob/main/proto/client/v0/features.proto)
содержит только UNSPECIFIED и UI_QUIT. UI не должен создавать RPC для
logoff/suspend/resume или считать скрытие/потерю фокуса окна таким событием.
Consumer теперь отвергает event, отличный от UI_QUIT, до транспорта;
три short negative tests проверяют missing/UNSPECIFIED/unknown wire value при
валидном mutation context. Native OS events и применение lifecycle policy —
внешняя реализация `client`, а не недостающий UI RPC adapter. В UI остаются
настройки, явный quit, восстановление свежего состояния после interruption и
platform acceptance; это уточнение не закрывает US-12 и не меняет BA.

UI resume дополнение: shell слушает
[Flutter AppLifecycleState](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html).
После hidden/paused → resumed немедленно очищается snapshot/cache epoch,
затем выполняется новый protected connection bootstrap/WatchEvents. До свежего
snapshot прежняя identity не показывается. Пока окно скрыто, подписка сохраняется
для tray; inactive/resumed без hidden/paused не вызывает reconnect. Если shell
занят, один pending refresh выполняется после завершения текущего действия;
ошибка показывает безопасный runtime notice без automatic retry. После принятого
quit refresh запрещён, observer снимается при dispose. Ни NotifyLifecycle,
ни Connect/Disconnect runtime intention при resume не отправляются.
[Четыре short widget tests](../app/test/client_app_resume_test.dart) проверяют
hidden/paused flows, synchronous invalidation, свежий account, focus-only no-op,
coalescing во время bootstrap, failure/no retry и disposal. Это simulation
framework events: Flutter paused относится к Android/iOS, не означает desktop
OS sleep; native sleep/wake delivery, mobile product hosts, OS acceptance и
восстановление всех interrupted операций ещё требуют отдельного evidence.

US-05 read foundation: `ClientSession.getExitNodes` читает ListExitNodes и
GetExitNode через typed local binding. Каталог и status должны иметь одну runtime
revision; IPv4/IPv6 обязательны и не синтезируются из aggregate. Optional IDs,
typed failures и fail_closed сохраняются независимо по каждой семье. Узел,
исчезнувший из каталога после policy/path change, не подменяется другим; текущий
status сохраняется. Allowed modes не расширяются до dual-stack. Reader проверяет
структуру и согласованность intent с family modes, effective IDs, приоритетом
FAILED, family/LAN convergence для APPLIED и заявлением aggregate fail_closed.
Противоречивый status отвергается без исправления или догадок. Это не доказывает
реальную блокировку обходного трафика. Shared tests проверяют partial apply,
missing families и пагинацию; session tests — owner/context invalidation.
`ClientExitPanel` показывает requested/effective и apply/failure/fail-closed
раздельно для IPv4/IPv6. Выбор требует явных node, разрешённого family mode и
LAN policy; недоступный режим не подменяется. Clear подтверждается отдельно.
Policy lock запрещает изменения, invalidation удаляет draft и блокирует callbacks
старого кадра. Select/Clear связаны с session journal; acceptance операции не
означает applied, результат восстанавливается отдельно. Четыре shared widget
tests проверяют select, cancel/confirm clear, lock и invalidation; значения
dropdown задаются через callbacks, не native gestures. Producer process suite
добавляет select-exit, clear-exit и failed-exit: joint read перед командой,
точные profile/node/family/LAN и mutation context, recovery по исходному UUID,
typed selection либо failure без автоматического retry/clear/downgrade.
Последняя per-family projection не меняется от operation outcome, journal
сохраняется до явного acknowledgement. Новые process cases ожидают CI execution;
actual traffic/platform acceptance остаётся отдельным незакрытым требованием.

US-11 read foundation: `ClientSession.listResources` использует typed local RPC
и immutable каталог. Search ограничен 256 UTF-8 bytes; фильтры фиксируются перед
первым await. Страницы по 100 entries принимаются только для одной runtime revision,
без повторных tokens/IDs и несовпадений kind/target. Каталог не публикуется частично.
Resources/profile/network invalidation отменяет незавершённое чтение; observer
не вызывает RPC. Overlap IDs сохраняются без дополнительных lookup: resource
вне текущего search/filter не равнозначен скрытому resource. Авторизация, поиск
и RESOURCE_CONFLICT остаются обязанностью producer, UI не выбирает route сам.
Shared reader tests включены в mobile harness; их runner execution ещё не
подтверждено. `ClientResourcesPanel` добавляет explicit search/kind filters,
requested/effective, availability/lock/reason/action-owner и disclosed overlap IDs.
Изменение запроса удаляет старый каталог, late response не возвращает старые данные.
Profile/domain invalidation удаляет также поисковый текст и фильтры. Enable/Disable
отправляет SetResourceEnabled через session journal с context check перед RPC;
acceptance не означает effective apply. Shared widget tests проверяют explicit
disable, policy lock, late query и stale callback. Application browser action
требует явного click и повторного чтения того же query/profile. HTTPS URI без
credentials должен остаться неизменным и AVAILABLE; смена URL, denial или
invalidation запрещают launch. Session panel вызывает внешний OS browser только
после context check. Shared tests используют browser callback, не настоящий OS
browser. Producer-process mutation evidence, локализация и actual runtime
acceptance остаются незавершёнными.

Producer-host suite дополнен US-11 fixtures: ListResources с точными profile,
search/kinds/page, Enable/Disable через SetResourceEnabled и отдельный terminal
ERROR_CODE_RESOURCE_CONFLICT. Recovery использует исходный UUID, control request
correlation сохраняется отдельно. Успех/конфликт не меняют cached effective state;
до явного acknowledge намерение остаётся в journal. Execution этих новых fixtures
на runners пока не подтверждено. Script не доказывает actual conflict detection,
route enforcement или отсутствие утечки скрытых backend ресурсов.

Реализован read foundation US-10: `ClientSession.getPreferences` через прямой
typed local binding читает `GetPreferences` и `ListManagedSettings`. Consumer
публикует immutable projection только при совпадении instance/revision обоих
ответов, явно заданном active profile и действующем owner context. Повторные
invalidation preferences/managed settings/profiles отменяют незавершённое чтение;
устаревшая ревизия относительно текущего status не принимается. Optional `false`
сохраняется отдельно от отсутствующего override; requested/effective, source и
lock не вычисляются UI. Некорректные и повторяющиеся managed keys/value kinds
отвергаются. Read не пишет intention journal и не повторяется автоматически.
Lifecycle effective, присутствующий requested и каждый allowed value должны
быть определёнными значениями enum; дубли allowed values отклоняют всю проекцию
до второго RPC. Managed lifecycle value проверяется так же. Отсутствующий
requested и пустой allowed values допустимы и не превращаются в default override
или разрешение изменения. `client_preferences_validation_test.dart` покрывает
эти отрицательные исходы для всех пяти lifecycle-полей. Локальные Go tests,
Flutter analysis и Flutter tests прошли (256 passed, 27 skipped); пропуски и
reader tests не являются доказательством platform/runtime acceptance.
Shared tests входят в desktop и mobile harness, session checks — в desktop suite;
runner execution этого изменения ещё не подтверждено.

`ClientPreferencesPanel` реализует editor foundation для трёх boolean и пяти
lifecycle полей. Поля входят в один явный Set patch только после выбора;
explicit false не теряет presence. Reset override — отдельная команда с key,
а не запись default/false. При наличии черновика Reset недоступен до Apply/Discard.
Источник, lock, availability, reason и action owner выводятся из producer control;
любой запрещающий control блокирует редактирование, lifecycle menu ограничено
allowed values. Invalidation удаляет projection и draft, включая устаревшие
callbacks до следующего frame. Session panel отправляет Set/Reset через intention
journal с повторной context check перед RPC. Acceptance не подменяет effective
projection: после команды нужен recovery и refresh. Shared widget tests проверяют
patch всех восьми полей, отдельный reset, policy denial и stale draft callbacks.
Локализация, producer-process Set/Reset evidence, atomic producer validation/apply
и platform lifecycle acceptance остаются отдельными требованиями. Production
shell использует native session panel; Set/Reset process evidence описан ниже.

Для Set/Reset добавлены producer-host process fixtures: owner-scoped typed reads,
Set всех восьми полей с явными false и отдельный Reset двух keys, journaled
acceptance и recovery исходного UUID при открытом WatchEvents. Scripted SUCCEEDED
не обновляет ранее прочитанный effective projection. Пока desktop runner execution
этих fixtures не подтверждено; локально они пропускаются без producer-host.
Это не проверка actual runtime atomic validation, policy enforcement или OS apply.

Session.expires_at и credential.expires_at являются разными фактами. Для каждого
UI показывает отдельно expiry, warning и доступный следующий шаг; отсутствие
Timestamp означает неизвестный срок. UI не устанавливает fictitious validity.
RenewSession не означает renewal node credential. Continuity показывается как
preserved/interrupted/unknown/not applicable по подтверждённому результату.

US-09 UI foundation: shared connection panel показывает отдельные typed states,
expiry и warning timestamps для session и credential. Недоступность RenewSession
объясняется availability/capability, а RENEWING отображается как in progress.
Ни прошедший warning timestamp, ни отсутствие expiry не меняют runtime state.
`client_connection_activation_test.dart` проверяет 42 комбинации состояний,
ограничения кнопки и очистку при потере связи в desktop/mobile harness.
Это consumer evidence, не подтверждение реального renewal или platform acceptance.

Requested preference не выдаётся за effective. Если сохранённое намерение ещё
не применилось, UI показывает расхождение и причину операции. Reset снимает
user override; false остаётся явным значением. Managed policy не меняется
локальным UI. Exit failure не приводит к silent clear. Ограничения IPv4/IPv6,
LAN и overlaps проверяются реальным трафиком в platform acceptance.

Выбор exit требует явного `family_mode` из `allowed_family_modes` выбранного
узла. Пустой список не допускает выбор; UNSPECIFIED/NONE/unknown не отправляются
как режим SelectExitNode. Недоступный режим не заменяется молча другим.
IPV4_ONLY/IPV6_ONLY явно предупреждают, что другая семья не защищена этим exit.
UI отображает `ipv4` и `ipv6` requested/effective IDs, apply state, failure и
фактический fail-closed независимо. Aggregate success/effective не выводится из
успеха одной семьи: нужны convergence всех выбранных семей, очистка исключённых
семей и применение LAN policy. Clear относится к обеим семьям; частичный clear
остаётся pending/failed. Отсутствие ID означает отсутствие exit selection, а не
неизвестность; NONE допустим как cleared requested mode, не как Select request.

Перед bundle UI показывает фиксированный состав snapshot/recent logs и
ограничения из pinned producer specification. Create не запускает сбор трафика
на заданный интервал. Max 5 MiB, срок handle 15 минут, chunks до 256 KiB;
эти значения не заменяют проверку ответа runtime. Packet capture, configurable
trace duration и upload требуют отдельного scope/контракта и сейчас недоступны.
Реализован RU/EN pre-create текст: неполная история/truncation, отсутствие
гарантированного времени создания, caller/profile binding и invalidation
handle при logout/removal, отдельный verified download/export и проверка
файла перед передачей. Шесть существующих widget-векторов create outcome
сравнивают все четыре абзаца до submit, проверяют zero create до согласия и
непригодность старого подтверждения после cancel/reconfirm. Это проверка
описания и согласия, не доказательство фактического состава архива на hosts.
Экспорт через пользовательский save/share action не разрешает скрытую отправку.

## 6. Тестирование и release gates

### Порядок реализации и запусков

Сначала реализуем весь UF/UBR/UI-AC/US scope и проверяем его локальными
unit/widget-тестами. Ожидание CI не является условием продолжения разработки.
К интеграционной квалификации пяти платформ переходим после проверки полноты
реализации всего функционала. Уже существующие интеграционные тесты сохраняются,
но не подменяют этот порядок и не служат доказательством полноты продукта.

Обычный push на main запускает только `Client UI short`: `go test -short ./...`
и `flutter test --no-pub --tags short`, без producer host, emulator, packaging
или межплатформенной матрицы. Каждый Flutter test file явно имеет метку `short`
или `integration`; новые suites без классификации отклоняются policy-тестом.
Short включает быстрые unit/widget и bounded temporary-filesystem тесты с
подставными зависимостями; socket/process fixtures исключены. Полные desktop,
mobile, local-RPC и packaging проверки выполняются на PR; контрактные workflows
сохраняют manual dispatch с 1/3 проходами. Релизный tag workflow не меняется.
Новый запуск отменяет прежний для того же workflow/ref, кроме отдельной публикации.

`app/test/support/mutation_wire_server.dart` — отдельный строгий single-call
fixture для всех 19 mutation RPC. `client_mutation_wire_test.dart` проверяет
точные protobuf bytes и pairing metadata, копирование запроса до отправки,
pending envelope, отклонение чужого request ID/operation kind без повторного
RPC. Набор сверяется со всеми concrete OperationKind и включён в mobile harness.
Это shared envelope evidence: не все варианты payload, terminal outcomes,
бизнес-эффекты, policy или platform acceptance. Production код fixture не
импортирует; остальные RPC им не реализованы.

Дополнительный UI-owned wire mock: `app/test/support/loopback_contract_server.dart`
использует generated server bindings текущего SDK. Shared тест запускает его на
случайном loopback TCP порту и проверяет bootstrap → WatchEvents → Connect →
GetOperation → StatusChanged с disk-backed journal. Это только test transport:
production код его не импортирует, native Go-host/OS IPC тесты не заменяются.
В mobile harness это protobuf serialization/gRPC/session evidence, не проверка
OS identity, защищённого bridge, VPN или producer runtime. Остальные RPC пока
не реализованы этим fixture и отклоняются; полнота контракта не заявляется.

Второй wire vector моделирует UNAVAILABLE после synthetic acceptance: старая
ClientSession закрывается, новая открывает тот же journal и получает свежий
snapshot с pending operation. Новый UUID/повтор Connect запрещены, GetOperation
читает исходный request ID. Это restart consumer session в одном тестовом
процессе, не crash/power-loss или producer durability acceptance.

[Coverage ledger](client-ui-test-coverage.md) и
[`tests/client-coverage.json`](../tests/client-coverage.json) трассируют весь
scope из 104 UF/UBR/UI-AC/US identifiers. Проверка структуры и отдельный
`--require-complete` gate не смешиваются: первая может быть зелёной при
незавершённых функциях, второй требует полный исходный scope и acceptance.

Contract tests используют pinned generated SDK и producer-owned
[testserver, main](https://github.com/endless-net/client/tree/main/clientipc/testserver).
Необъявленный вызов scripted fixture возвращает typed UNSUPPORTED и проваливает
Verify, не универсальный success. Временная недоступность моделируется отдельным
явным сценарием с typed Failure. Имеющийся HTTP v2 emulator не является evidence
нового контракта и заменяется при cutover.
Проверяются: exact digest, caller filtering, phase/operations в первом snapshot,
lost response/request replay, conflict payload, stale instance/revision,
restart/resume, stream overflow, cross-profile cache invalidation, deadline
independence, policy lock/reset, partial apply failure, exit fail-closed,
pagination/overlap, trust mismatch и remote-unconfirmed cleanup.
Дополнительно обязательны operation kind во всех путях восстановления,
initial-claim denial, explicit family selection и partial IPv4/IPv6 apply/clear.

Standalone testserver запускается на уникальном test endpoint с synthetic JSON
script. Harness ждёт `ready`, сверяет digest, выполняет сценарий, закрывает
consumer channels и отправляет `verify` через stdin. Требуются одновременно
`verified` и exit code 0; EOF, timeout, оставшиеся/лишние вызовы — провал теста.
Симулированная роль задаётся harness, не RPC caller. Скрипт доказывает реакцию UI
на ответы, но не durable deduplication, claim race или реальное fail-closed:
эти свойства отдельно проверяются на actual provider/runtime.

Для UI-AC-01–27 тестовая матрица фиксирует platform, capability, caller,
предусловия, RPC/внешнее действие, expected result и evidence owner. Coverage
table US-01–14 выше задаёт обязательную трассировку. Unsupported платформы
имеют обоснованный deferred/different-by-design статус, не зелёный runtime test.
Deferred не считается выполнением цели полного мультиплатформенного покрытия.
GitHub jobs должны запускать сценарии на Windows, Linux и macOS, а mobile UI
и bridge-проверки — на Android emulator и iOS simulator. Host Dart unit test
не считается Android/iOS execution. Emulator/simulator evidence не доказывает
VPN entitlement, store distribution, device background lifecycle или реальный
трафик: для этих свойств требуется отдельное platform acceptance.

| Уровень | Что доказывает | Владелец |
| --- | --- | --- |
| Schema/SDK CI | Lint/build, baseline check, deterministic generation, Go/Dart usability | client |
| UI component/contract | Presentation, emulator scenarios, localization/privacy | client-ui |
| Local transport | Реальный pipe/socket/native bridge и authenticated peer | client + client-ui |
| Platform lifecycle | OS prompts, quit/crash/sleep/reboot, helper, packaging | Соответствующий runtime/UI/distribution owner |
| Product acceptance | Pinned UI/core/backend, разрешённый и запрещённый реальный ресурс, continuity | system-tests + releases |

Публичная [матрица acceptance](https://github.com/endless-net/architecture/blob/main/docs/ru/typed-protobuf-cutover-verification.md)
сохраняет владение системными release-критериями. Этот SA не создаёт production
evidence и не меняет датированные свидетельства.

## 7. Реализация и открытые platform решения

UBR-37/UI-AC-23: ClientRuntimeOperationsPanel подключён к общей session panel
отдельно от local-journal recovery. Он показывает owner-visible current_operations
из первого snapshot, включая inactive profiles, и последующие OperationChanged.
Получение terminal result не синтезирует Connected и не подтверждает/удаляет
намерение из журнала. Observer, новый baseline и detach очищают старый список.
Shared RU/EN widget tests проверяют эту проекцию без journal callbacks; это не
installed-runtime restart или полная UI-AC-23 приёмка.

Сверка wiring на `4d063f1e3dc4020118bce6215a2fb7f5320d75fa`: main создаёт
ClientSession/ClientDesktopApp, desktop shell включает ClientSessionPanel, а
панель связывает native reads/mutations/recovery. Нижеследующее описывает текущую
consumer реализацию; это не повторная сверка BA и не platform acceptance.

Промежуточная consumer foundation: `app/lib/client_runtime_snapshot.dart`
использует generated SDK, закреплённый в pubspec по immutable client revision.
`app/test/client_runtime_snapshot_test.dart` проверяет часть US-01/03/10:
первый snapshot, pairing, instance/revision, operation kind, immutable copy и
capability availability. Workflow `contract-consumer.yml` запускает эти unit
проверки вместе с `client_event_stream_test.dart`: повторный snapshot при смене
capabilities, stream ordering/context, typed overflow, observer session denial
и независимый cursor новой подписки. EOF считается потерей подписки, а не
подтверждением Connected; cache epoch управляется ClientStateController,
а явный reconnect подключён в ClientDesktopApp.
`local_client_events.dart` связывает bootstrap/local gRPC с проверенным потоком.
`client_connection_panel.dart` — общий typed UI-компонент connection/status;
`client_session_panel.dart` связывает его кнопки с journaled v0-командами.
`client_profiles.dart` собирает полный immutable ListProfiles catalog с одной
instance/revision, неизменным active ID и непрозрачными page tokens; несогласованные
страницы не публикуются. LocalClientEvents предоставляет реальный typed RPC binding.
Тесты пагинации включены в desktop и mobile harness. Session.listProfiles требует
owner snapshot и отклоняет результат после смены epoch/caller/cache, другого
instance или с revision старше текущего snapshot. Session tests проверяют late
observer result и stale revision; profile lifecycle UI и platform execution
evidence ещё нужны для полного US-08.
`client_profiles_panel.dart` теперь подключает refresh и journaled SelectProfile
и RenameProfile к общей session panel. Создание профиля вынесено в
`client_create_profile_panel.dart`: имя и HTTPS origin проверяются до journaled
CreateProfile, но initial ownership claim решает только producer. Observer может
отправить это конкретное намерение без права читать каталог или выполнять другие
owner RPC. Смена snapshot/cache очищает поля и скрывает поздний ответ; созданный
ID не превращается в локально синтезированный active profile. Shared widget-тест
проверяет input validation и observer-to-owner context transition. Реальный
ownership race и platform runtime acceptance этим widget-тестом не доказаны.
Переименование подключено
к общей session panel. Переименование проверяет непустое имя,
лимит 128 UTF-8 bytes и отсутствие control characters, отправляет opaque profile
ID и не подменяет authoritative catalog локальным именем. Общий widget-тест
проверяет ограничения имени, dispatch и отсутствие optimistic результата;
это не доказывает runtime/profile lifecycle acceptance на платформах.
Повторные DOMAIN_PROFILES invalidations скрывают каталог и отклоняют запросы,
начатые до события, даже если domain/profile уже встречался в invalidation set.
RemoveProfile подключён отдельно от logout/local forget: кнопка доступна только
для inactive EMPTY profile, требует отдельного подтверждения и journaled dispatch.
Invalidation скрывает устаревшее подтверждение; callback повторно проверяет каталог.
Producer окончательно проверяет отсутствие registration/session; UI не выполняет
автоматический logout или local forget при отказе удаления. Shared widget-тест
проверяет cancel/confirm, запрет active profile и сброс подтверждения при invalidation.
Выбор профиля подключён
к общей session panel. Выбор использует opaque ID и profile.selection restriction;
acceptance очищает каталог, но не синтезирует active profile. Widget-тест включён
в desktop/mobile suite и проверяет owner/observer cleanup. Create/rename/remove,
logout/forget и domain invalidation подключены к native session panel; полнота
profile lifecycle и реальные runtime effects требуют отдельной приёмки.
Общая панель отдельно отображает authoritative session/credential expires_at в
UTC; отсутствие срока означает Unknown. Observer не видит эти поля, смена
контекста заменяет сроки, UI clock не синтезирует expired/connected state.
Shared widget test проверяет разные сроки и исчезновение одного без подстановки
второго. Это частичное US-09 evidence, не renewal UX или production acceptance.
Кнопка Renew session в общей панели вызывает journaled RenewSession только при
owner/profile, доступной capability и session.renewal; renewing отключает её.
Принятие операции не меняет сроки; credential renewal не вызывается из UI.
Shared widget suite проверяет gating и сохранение deadlines после acceptance.
Terminal-result lookup/acknowledgement и явные browser actions подключены через
ClientRecoveryPanel в desktop shell. Это не реальное browser/renewal acceptance.
`client_recovery_panel.dart` добавляет явный lookup сохранённых намерений через
session.recoverPending и подтверждение только terminal result через journal.
Pending не удаляется; ошибка lookup сохраняет намерения и не раскрывает raw
exception. Результаты скрываются при смене cache/caller context. Shared widget
suite проверяет pending/terminal и observer cleanup. Это ещё не полный recovery
UX: typed outcome details и явные browser actions уже отображаются;
unresolved NOT_FOUND сохраняет journal и остаётся открытым recovery решением.
Shared mobile/desktop widget test проверяет pending Connect, доступный Disconnect,
отсутствие ложного Connected и очистку owner controls/context при observer snapshot.
Панель используется текущим native main/shell; localization, полный recovery UX
и функциональная полнота всех сценариев остаются незавершёнными, как и product acceptance.
`client_session.dart` объединяет connection, typed state и intention journal:
до snapshot команды запрещены, запись предшествует отправке, поздний ответ после
смены контекста требует recovery. Pending recovery выполняет только GetOperation,
без replay payload и автоматической смены UUID. Session-тесты проверяют эти
границы. Текущие native панели используют этот session; удаление старых экранов
не доказывает перенос всех их бизнес-сценариев.
`client_state_controller.dart` содержит typed application state: ожидает первый
snapshot, очищает данные при stream loss/reconnect, меняет cache epoch при смене
profile/account/network, хранит caller-visible операции и domain invalidations.
Отмена idle subscription передаётся source без ожидания следующего события.
Тесты покрывают эти границы; native desktop shell использует этот controller
через ClientSession, прежний HTTP controller удалён.
`client_mutations.dart` предоставляет typed SDK вызовы всех 19 mutation RPC,
проверяет UUID/instance/revision до отправки и соответствие kind/request ID
принятой операции. Запрос копируется перед отправкой; автоматического retry и
подмены UUID нет. GetOperation по request ID проверяет ту же идентичность.
`client_intent_journal.dart` сохраняет UUID/kind до callback отправки с flush,
без payload/credential. Pending запись переживает timeout; удаление допускается
только после обработки matching terminal result. Повреждённые записи сохраняются
и блокируют новые намерения вместо неявного повторного исполнения. Unit-тесты
переоткрывают storage, а process test использует сохранённый UUID для Connect и
GetOperation. Main задаёт endpoint-scoped directory через clientJournalDirectory,
а shell предоставляет явный recovery UI. Защита directory средствами каждой OS
и обработка unresolved NOT_FOUND ещё требуют отдельного решения/подтверждения.
Это process-restart foundation, не доказательство power-loss durability или
защиты platform storage; mobile storage/OS acceptance остаются отдельными gates.

`client_session_process_test.dart` объединяет эти слои с producer fixture,
закреплённым в `contract-consumer.yml` на
`80d9cdc16241ca03200381b6b1b04fa5acca1987`: WatchEvents с
hold_open, snapshot-gated Connect, pending acceptance, lookup и journal
acknowledgement после terminal result. Подготовка ID в fixture выполняется заранее
для exact request matching через injected UUID factory; запись в outbox происходит
только в обычном submit перед RPC. Production factory использует Random.secure.
Session отклоняет параллельный submit одного kind и новый UUID при сохранённом
намерении того же kind: сначала lookup/terminal acknowledgement. Другие kinds
не блокируются этим guard, поэтому Disconnect не ожидает завершения Connect.
Это не cross-process lock нескольких UI instances. Native RPC
execution этого сценария требует успешного CI, локальный skip его не доказывает.
`client_operation.dart` проверяет state/outcome envelope всех 19 mutation kinds
в snapshot и operation events. `client_operation_test.dart` содержит отдельные
векторы по каждому kind и проверяет полноту относительно generated enum:
nonterminal не имеет outcome, WAITING_FOR_USER требует typed action,
FAILED/CANCELLED — typed Failure, SUCCEEDED — соответствующий kind результат.
Это не доказательство доменного эффекта, durable recovery или всех полей
вложенного результата; эти проверки остаются отдельными сценариями.
`local_client_events_test.dart` запускает отдельный pinned Go testserver,
проверяет snapshot/typed overflow/повторную подписку и требует успешного Verify.
Тот же process scenario проверяет Connect acceptance и lookup по исходному
request ID; scripted lookup не является доказательством runtime deduplication.
Workflow запускает unit и process integration на Windows/Linux/macOS с прежним
закреплённым Flutter SDK. Без ENDLESSNET_TESTSERVER process test пропускается;
такой локальный запуск не является interoperability evidence. До успешного CI
свидетельство конкретного изменения остаётся pending. Слой подключён к native
desktop shell; это не подтверждает полный US, Android/iOS native transport
или полноту UI/runtime cutover. Результаты закреплены в test coverage ledger.

Отдельный `mobile-contract.yml` запускает `tests/mobile_contract` внутри Android
emulator и iOS simulator. Общий `mobile_contract_widget_test.dart` проверяет
synthetic snapshot → typed controller → widget и очистку после stream loss.
Сгенерированные native projects служат только тестовым host, не production app.
До успешного CI native execution остаётся pending; даже успешный запуск не
закрывает весь US-01/03, mobile native bridge, OS prompts, VPN/Network Extension,
фоновые режимы, traffic acceptance или оставшиеся BA/SA сценарии.

1. client реализует новый snapshot, credential projection, operations и RPC
   authorization; backend owners предоставляют authoritative deadline/policy.
2. client/client-ui проверяют local transport binding; Windows сохраняет прямой
   named pipe. Для mobile назначается owner и проверяется native boundary.
3. client-ui закрепляет generated package, реализует state/application layer,
   US-01–14 и UI-only функции; использует producer-owned scenario host вместо
   удалённого HTTP emulator. Source cutover не закрывает весь functional scope.
4. Distribution owners публикуют совместимые artifacts и authoritative update
   outcome; UI не запускает updater через daemon.
5. system-tests подтверждает UI-AC по принятому platform/release scope.

Не закрыты реализацией/приёмкой: mobile transport adapter и ownership, реальные defaults
managed/lifecycle, signed update source и platform release order. Принятые
контрактом semantics (один active context, fail-closed, operation replay,
deadline separation и observer redaction) не являются открытыми вопросами.
