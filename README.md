# EndlessNet Client UI

Общий брендбук и библиотека компонентов Admin + Client UI находятся в
[packages/endlessnet_ui](packages/endlessnet_ui/README.md). Это единый producer;
подключение приложений по опубликованному exact Git source выполняется отдельно.
Functional и component design tests библиотеки запускаются раздельно:
`python3 -B scripts/check_ui_library.py` и
`python3 -B scripts/check_ui_library.py --design`.

Windows11 x64: установите единый MSI и запустите EndlessNet из меню «Пуск».
Он содержит Flutter UI, Client как фоновую службу, CLI и необходимые библиотеки.
При добавлении UI к установленному Client сохраняются identity, регистрация и
настройки службы. Общий сервер — `https://endlessnet.ru`, ручные JSON не нужны.
UI обнаруживает текущий runtime через защищённые machine settings и OS-auth pipe;
ключи, маршруты и сеансы остаются у службы. «Войти и подключить компьютер» запускает
существующий Client enrollment, показывает ссылку/ожидание/исход и после подтверждения
однократно отправляет Connect. Уже зарегистрированный клиент управляется кнопками
«Подключить»/«Отключить». Для единственного устройства показано
«Туннель готов, других устройств нет». Закрытие UI не отключает службу.
Если сессия пользователя истекла, «Войти снова» открывает отдельное подтверждение
тем же пользователем. Исходный запрос восстанавливается после закрытия UI;
повторной регистрации устройства не происходит. Успешный вход и фактическое
соединение показаны отдельно. Неизвестный результат обновления доступа Node
требует проверки владельцем сервиса и не исправляется повторным входом.
Технический запуск `--config <absolute path> --runtime-instance <absolute path>`
сохранён для явной конфигурации; обычный запуск без аргументов использует Windows
Known Folder ProgramData и native admin-authority reader. DLL берётся рядом с EXE,
config не переопределяет её или compiled contract digest.

Панель подключения005 использует тот же Client SDK и authenticated channel:
показывает intent, локальное применение, Direct-путь, собственный адрес EndlessNet,
offline-ограничения и ошибки/следующий шаг. Работа приложения второго устройства
проверяется отдельно. Connect/Disconnect выполняются по явному действию с CAS
instance/revision и сроками30s/10s. ACK, stale или timeout приводят к чтению status,
без автоматического повторения команды. Unknown/partial cleanup не считается
успешным отключением. Poll interval/read timeout берутся из existing config.
Возврат окна из background инвалидирует прежний read и запрашивает fresh status;
late ответы прежнего профиля/runtime не меняют экран. Закрытие UI не отправляет
Disconnect и не владеет lifetime daemon. Ключи, grants и OS settings UI не получает.

## Проверки

Flutter 3.47.7, revision `abaf9c523780a608bd46686fd5e53740a07077f8`, Dart 3.13.5.
Зависимости закреплены в [lockfile](app/pubspec.lock), профиль —
[.ci/profile.json](.ci/profile.json).

`endlessnet_client_api` получается из `https://github.com/endless-net/client.git`,
revision `acc543b5d2515655378fbcf8d64557c9dd546614` опубликованного `api/v0.7.0`,
package path `api/dart`. Manifest и lockfile закрепляют remote Git source без
соседнего checkout или `dependency_overrides`. Разрешение зависимости не означает
реализации IPC, consent или другой runtime-интеграции. Версия Dart package `0.0.0`
принадлежит producer и не заменяет независимый API tag.

```bash
python3 -B scripts/ci.py check
```

Команда проверяет pin SDK, locked dependencies, Dart format и Flutter analyze.
Declared unit tests проверяют controller, generated RPC adapter и widget-панель;
publisher fixtures — границы выпуска/архивов. Используются memory Client/store
и injected browser callback: они не доказывают Windows IPC/disk durability или
установленную Client/UI pair. Integration/E2E не запускаются.

## Native сборки

Каждая команда выполняется на соответствующей ОС:

```bash
python3 -B scripts/ci.py build --target linux-amd64
python -B scripts/ci.py build --target windows-amd64
python3 -B scripts/ci.py build --target darwin-amd64
python3 -B scripts/ci.py build --target darwin-arm64
```

Linux baseline — Ubuntu 26.04 с clang, cmake, ninja, pkg-config, GTK3 и C++ headers.
Windows требует Visual Studio Desktop development with C++. macOS требует Xcode.
Для macOS helper задаёт конкретный ARCHS и отключает production codesigning;
исполняемый файл проверяется `lipo`. Windows PE и Linux ELF проверяются по headers.
Архив содержит весь Flutter bundle с библиотеками и assets, а не один executable.

Выходы находятся в `.artifacts/`: архив, SHA256 и source/tool identity.
Наличие локальных изменений записывается в identity; такой архив нельзя опубликовать.
Нет web, Android или iOS target. Сборка не доказывает runtime-поведение ОС.

Tracked plugin registrants используют LF по `.gitattributes`, как Flutter generator.
Это исключает ложный modified status после Windows checkout с `core.autocrlf=true`.
Содержательные изменения исходников по-прежнему блокируют CI build и publisher.

## CI и выпуск

Автономный public workflow не читает Service Kit и приватный workspace.
GitHub-hosted runners собирают Windows amd64, Linux amd64 и macOS amd64/arm64.
Branch, PR и manual validation сохраняют только Actions artifacts.

Push обычного `v0.MINOR.PATCH` после checks и всех native builds публикует четыре
архива, `checksums.txt`, `source.json` и автоматические notes. Helper сверяет peeled
remote tag с exact source commit. Частичный upload остаётся draft; повтор дополняет
только недостающие идентичные assets. Конфликт bytes, перемещённый tag и отсутствие
target завершаются ошибкой без перезаписи. Новые теги/releases ради проверки не нужны:
publisher тестируется локальными fake GitHub fixtures.

Новая v0-линейка использует hard cutover без обратной совместимости даже между
patch-версиями. Compatibility shims, fallback, dual APIs и local replace запрещены.
SDK producer Client закреплён на отдельной опубликованной exact версии;
использующая его runtime-логика остаётся отдельным этапом. Данные сохраняются прямыми миграциями.
Production signing, auto-update и deployment требуют отдельного этапа.

## UI correlation journal

app/lib/client/windows_correlation_store.dart открывает bounded append-only journal
по явно переданному абсолютному пути в подготовленном приватном per-user каталоге.
Factory не выбирает путь и не создаёт ACL/каталоги. В журнале только UI correlation:
profile/origin, UUID, hostname/mode и первый recovery deadline; device keys, native
grants и server credentials не записываются. Запись завершается после flush.
Recovery bound может только сокращаться при чтении более раннего producer deadline;
увеличение/удаление запрещены, прежние append-only записи сохраняются.
Corrupt/partial/existing-empty file, конфликт UUID/deadline, исчерпание budget или
ошибка lock/IO запрещают работу без truncate/reset/fallback. Lock удерживается
до await store.close(); app обязан дождаться текущей операции перед завершением.
Это Windows adapter; другие ОС не получают неподтверждённую гарантию file locking.

Отдельная native Windows проверка (не базовый unit gate), из app/:

```powershell
dart run test/integration/windows_correlation_store.dart
```

Fixture использует только собственный временный каталог и дочерние Dart-процессы;
проверяет flush acknowledgement, restart, межпроцессный lock, immutable deadline
и отказ при повреждении без сброса файла. Это не power-loss или installed-app
acceptance. Production namespace/ACL и shell подключены ниже; actual configured
installed startup проверяется отдельно.

## Windows pipe transport

app/lib/client/windows_pipe.dart использует public grpc/http2 connector API и
app/native/windows/endlessnet_windows_pipe.dll. Windows CMake собирает DLL и
включает в bundle рядом с exe. Helper атомарно возвращает Win32 error вместе с
ReadFile/WriteFile/GetOverlappedResult/CreateFile; отдельного Dart GetLastError нет.
Дополнительная compile dependency — обычный Windows C++ toolchain сборки Flutter.

WindowsPipeConfig требует trusted instance UUID/SID, absolute local path этой DLL,
connect/write deadlines≤30s и pending write budget≤1MiB. Connector открывает только
локальный named pipe, проверяет owner SID по handle до HTTP2, выполняет SDK
GetRuntimeInfo handshake exact instance/protocol/IPC0/contract digest. Канал
одноразовый, без TCP/role claim/automatic reconnect или mutation retry. Native
isolate отменяет pending I/O до освобождения OVERLAPPED/buffers.

Отдельный Client Windows integration fixture TestWindowsDartUIOwnedPipe принимает
explicit absolute ENDLESSNET_DART_BINARY, ENDLESSNET_UI_PIPE_PROBE (этот app/test/
integration/windows_pipe_probe.dart) и ENDLESSNET_UI_PIPE_LIBRARY. Без explicit
probe этот transport suite skipped, в unit gate не входит. Fixture использует
настоящую pipe OS boundary, synthetic handlers и текущий OS token; не настраивает
production, не создаёт OS users и не подтверждает весь enrollment. Реальный
installed discovery/config, consent/trust и shell lifecycle требуют отдельной
проверки полной установки; source adapters подключены в main.

## Подтверждение сервера

ServerTrustController/ServerTrustPanel читают public identity через Client и
показывают отдельный диалог origin/key IDs/announcement. Принятие доступно только
по явному действию; UI hint administrator не заменяет проверку настоящего OS
caller у Client. Stale dialog/profile/controller не отправляет старую команду.
После TrustServerIdentity обязательна свежая matching identity; lost response
остаётся unknown до ручного read без повторной mutation. Эта операция не
создаёт новую enrollment attempt и сама не доказывает регистрацию Node.
Панель подключается к enrollment component optional controller seam; actual
app composition/config/launcher подключены; actual discovery/native trust
acceptance требуют полной установки.

## UI launch config boundary

lib/app/launch_config.dart определяет собственный UI launch config: schema1,
instance_id/server_sid/profile_id/control_origin и explicit connect/write/RPC
timeouts, poll interval, journal/pending-write/Failure budgets. Все поля обязательны,
no defaults; nested/unknown/secret keys, duplicate decoded keys и malformed input
отвергаются. Это UI input contract, не Client discovery file или deployment example.
Производственные значения/создание файла относятся к установочному внешнему контуру.

windows_config_reader.dart использует native reader: absolute fixed local path,
pinned directory/file handles, no reparse/UNC/traversal, SYSTEM/Administrators
owner и write grants только им. Reader не создаёт/исправляет ACL и не активирует
сервисы. Missing/busy/untrusted/invalid/component/platform ошибки различаются без
вывода raw config. Worker читает≤64KiB; reader не повышает права процесса.

Client descriptor digest compiled в lib/client/contract_identity.dart. CI
сверяет его с api/client.binpb из actual exact Git SDK cache и manifest/lock.
Конфигурация не может принять другой digest и обойти pairing. Config/reader,
per-user storage и launcher подключены в lib/app/windows_runtime_platform.dart.
Native reader fixture запускается отдельно: dart run
test/integration/windows_config_reader.dart <absolute compiled helper DLL>.
Он не создаёт production config и не доказывает установленную Client/UI pair.

## Windows per-user state и browser launcher

lib/app/windows_user_services.dart выбирает собственный UI journal через Windows
LocalAppData текущего пользователя: EndlessNet/ClientUI/correlation.bin. Native
helper создаёт только эти два каталога и файл UI; protected DACL допускает текущего
пользователя, SYSTEM и Administrators. Существующие ACL/content не исправляются.
Reparse/UNC и доступ других principals отвергаются. Guard удерживает directory и
file handles без delete sharing до close(), включая новый пустой файл. Journal
инициализируется только по native createdEmpty acknowledgement; существующий
пустой/повреждённый файл по-прежнему fail-closed. Закрывать journal перед guard.

Browser launcher — отдельный explicit-action adapter через ShellExecuteExW в
worker isolate, только для проверенного HTTPS URL. Он не подтверждает вход/Node
и не запускается автоматически. Main использует его только для текущего browserAction.

Отдельная проверка в собственном Temp: собрать native/windows через CMake с
-DENDLESSNET_NATIVE_FIXTURE=ON и выполнить из app/ dart run
test/integration/windows_user_state.dart <absolute fixture DLL>. Export с Temp
root отсутствует в обычной DLL (option OFF); production adapter отвергает fixture
DLL. Проверяются DACL/reopen/original UUID, удержание file/directory от rename,
отказ при расширении ACL; browser получает только отрицательные входы без запуска.
Fixture не пишет в настоящий LocalAppData и не меняет настройки Client/ОС.

Enrollment snapshot инвалидирует старое trust observation при изменении
profile/origin/instance/revision, новом server_identity restriction или потере
доступности. In-flight read/confirmation старого поколения не восстанавливает
это observation; новый read не может быть старше известного local snapshot.
UI только инвалидирует кэш, доверие по-прежнему подтверждается Client.

## App session и закрытие окна

lib/app/session.dart последовательно получает config, connection и storage;
после каждого await проверяет отмену запуска. Частичный startup закрывает только
полученные ресурсы, продолжая cleanup при ошибке другого ресурса. Контроллеры
привязываются к config profile; initialize только читает/восстанавливает UUID.
Trust observation загружается отдельным явным действием панели.

Крестик скрывает окно в системный трей Windows. «Открыть» возвращает то же окно
и обновляет состояние службы. «Выйти из интерфейса» завершает UI и убирает
значок, сохраняя службу и туннель. Если трей недоступен, крестик предлагает
подтвердить выход и оставляет окно открытым при отказе.

AppLifecycleListener ждёт close при завершении через Windows WM_CLOSE: dispose controllers,
cancel/terminate pipe, затем завершение journal operation/close и release guard.
Повторный exit разделяет один cleanup; при ошибке exit отменяется с безопасным
сообщением. Асинхронный Flutter exit dispatch сохраняет дочерние lifecycle
observers до своего завершения, команды UI блокируются overlay. Force kill и
power loss этим контрактом не покрываются. Unit/widget fixtures проверяют
startup cancellation, original UUID reopen, late reply, cleanup/error/exit await
без запуска настоящего browser или изменения production config.

При потере канала доступно явное переподключение: закрывается прежняя сессия,
заново читается trusted config и открываются IPC/journal. Восстанавливается тот же
UUID, Enroll не повторяется. До первой попытки можно отдельно перечитать state/
availability без сохранения UUID. После dispose контроллер отклоняет команды
независимо от состояния старых кнопок и keyboard focus.

UI применяет один active waiting deadline к polling/browser/actions: для known
состояния — login/approval/total, для uncertain — минимум сохранённого UI recovery,
producer recovery и total. Исторический recovery не останавливает подтверждённое
обычное ожидание; при новой потере ответа его нельзя продлить. Более ранний
producer bound сохраняется до принятия snapshot, ошибка flush останавливает
automatic polling. Истечение UI budget не объявляет remote rollback или Node denial.

Отдельный `app/test/integration/owner_chain_test.dart` проверяет реальные
controller/panel, native pipe и журнал на Docker owner chain. Его запускает
opt-in Client test `TestWindowsUIAgainstActualOwnerChain`, передавая только Temp
конфигурацию и публичные идентификаторы. Два запуска проверяют unknown outcome и
восстановление исходного UUID до подтверждённой регистрации. Этот entrypoint
не входит в unit profile; VK/browser и discovery являются изолированными fixtures.

Общий брендбук и библиотека компонентов Admin + Client UI находятся в
[packages/endlessnet_ui](packages/endlessnet_ui/README.md). Это единый producer;
оба приложения подключают exact опубликованный Git source
`acc88b52f96ddac996a88c6c3638edfb4b0bd119`, path `packages/endlessnet_ui`.
App использует общую light/dark тему, BrandMark и C02 в панели подключения;
Client SDK/IPC/controllers не меняются. Consumer adoption остаётся локальным
до отдельного запроса публикации приложений.
Functional и component design tests библиотеки запускаются раздельно:
`python3 -B scripts/check_ui_library.py` и
`python3 -B scripts/check_ui_library.py --design`.

Обычный Windows release включает готовый `EndlessNet-v0.MINOR.PATCH-windows-amd64.msi`.
В нём уже задан `https://endlessnet.ru`; ServiceProfile/UiPolicy пользователь
не готовит. Внутренние значения входят в Client runtime как `install-defaults.json`.
Идентификатор установки, SID пользователя и локальный IPv4 endpoint определяются
на целевой Windows. Для endpoint используется существующая модель Client с одним
активным default IPv4 интерфейсом; NAT discovery этим не объявляется.

Для ручной сборки того же пакета (WiX7, CMake, Visual Studio C++ и Flutter):

```powershell
./scripts/build-windows-installer.ps1 -UIBundle <flutter-release-bundle> -ClientBundle <client-runtime-bundle> -Version 0.5.0 -OutputDir <output>
```

Client bundle содержит `client.exe`, `wintun.dll`, `WINTUN-LICENSE.txt` и
`install-defaults.json` из producer build. UI executable version совпадает с MSI;
для сборки используется `flutter build windows --release --build-name=0.5.0`.
Builder автоматически формирует и проверяет настройки настоящими Client/UI
валидаторами. GitHub workflow делает это при сборке Windows, используя exact
Client release/commit из `.ci/profile.json`; publisher проверяет MSI вместе
с четырьмя runtime archives. Installation ID, default profile, OS owner, SCM settings и state сохраняются при upgrade.
Build и publisher отклоняют pin, не совпадающий с latest stable Client release;
при новом producer release требуется явно обновить pin и пересобрать MSI.
`source.json` и release notes указывают bundled Client tag/commit.
UI policy формируется из фактически сохранённого service profile, включая существующий UUID.

Публикатор GitHub Release требует отделённую подпись CMS
`windows-update.p7s` для `windows-update.json`. Описание связывает версию,
commit, SHA-256 и размер MSI. CI проверяет эту подпись закреплённым публичным
сертификатом EndlessNet до создания релиза. Закрытый ключ передаётся
одноразовому GitHub runner из двух секретов окружения `release` —
`WINDOWS_CODESIGN_PFX_BASE64` и `WINDOWS_CODESIGN_PFX_PASSWORD`.

UI проверяет GitHub Releases при запуске и каждую минуту. По подтверждению
локальный интерфейс запускает `endlessnet-updater` через SCM с выбранной
версией. Служба скачивает описание и пакет из GitHub, проверяет закреплённую
подпись, размер, SHA-256 и версию MSI, затем вызывает Windows Installer
через уже установленные полномочия службы. Публичный ключ поставляется
внутри MSI. При переходе с раннего клиента нужен один ручной запуск MSI.
Сборка для ветки/PR создаёт MSI для проверки пакета.

Windows shortcut единого установщика использует
`--config <policy.json> --runtime-instance <runtime-instance>`.
В таком policy отсутствует install-time `instance_id`: текущий UUID читается
из отдельного файла через тот же admin-owned native reader. Затем применяется
существующая OS-auth named-pipe проверка. Для явного запуска с заранее известным
instance остаётся исходный `--config <config.json>`; автоматического fallback нет.

## Локальный MCP для Windows

Откройте **MCP** в верхней панели EndlessNet, выберите **Разрешить** и
скопируйте конфигурацию. Для Codex используйте абсолютный `command` и
массив `args` из конфигурации. Заполните путь и `clientId` в команде PowerShell.

```powershell
codex mcp add endlessnet-client-ui -- 'C:\путь\endlessnet_client_ui.exe' --mcp-stdio --client 'clientId-из-окна'
```

Codex запускает тот же EXE в режиме stdio. Оставьте EndlessNet запущенным.

Доступны `app_status`, `logs_read`, `connectivity_refresh`,
`connectivity_connect` и `connectivity_disconnect`. Ответ `acknowledged`
означает, что локальная служба приняла вызов. Фактическое состояние
показывается в поле `connectivity` и может обновляться после ответа.

Доступ выключен по умолчанию. Разрешение действует до выхода из приложения,
максимум восемь часов. Кнопка **Отозвать** завершает доступ, а **Заменить разрешение**
выдаёт новый `clientId`. После замены обновите аргументы MCP-сервера.
