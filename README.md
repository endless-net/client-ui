# EndlessNet Client UI

Общий брендбук и библиотека компонентов Admin + Client UI находятся в
[packages/endlessnet_ui](packages/endlessnet_ui/README.md). Это единый producer;
подключение приложений по опубликованному exact Git source выполняется отдельно.
Functional и component design tests библиотеки запускаются раздельно:
`python3 -B scripts/check_ui_library.py` и
`python3 -B scripts/check_ui_library.py --design`.

Windows main подключает config, authenticated pipe, correlation journal и панели
регистрации/подтверждения сервера через published Client SDK. Запуск требует
--config <absolute local path>; сам файл проверяется native admin-authority reader.
DLL берётся рядом с текущим executable, config не переопределяет её или digest.
Рабочие значения установки предоставляет внешний платформенный контур.
UI восстанавливает исходный UUID; Enroll, browser и trust выполняются только по
явным действиям. UI не получает device keys, grants или системные привилегии.
Actual configured startup/installed pair и живой browser/VK flow ещё не проверены.

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
revision `0600e7a17d3bc8ad4c2c844109b4abbbeb7ae0a9` опубликованного `api/v0.2.0`,
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

AppLifecycleListener ждёт close при обычном Windows WM_CLOSE: dispose controllers,
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

Единый MSI собирается на Windows с WiX7, CMake, Visual Studio C++ и Flutter:

```powershell
./scripts/build-windows-installer.ps1 -UIBundle <flutter-release-bundle> -ClientBundle <client-runtime-bundle> -ServiceProfile <service.json> -UiPolicy <policy.json> -Version 0.1.0 -OutputDir <output>
```

Client bundle содержит `client.exe`, `wintun.dll` и `WINTUN-LICENSE.txt` из
producer build. Service profile — JSON строковых `ENDLESSNET_CLIENT_*`
настроек; UI policy — существующая schema1 без `instance_id`, с теми же
default profile/control origin. Builder проверяет их настоящими Client/UI
валидаторами. Installation ID создаётся при первой установке; состояние
и policy сохраняются при major upgrade. Visual C++ runtime включается рядом
с UI из установленного VS redist либо `-CrtDirectory`.
UI executable version должен совпадать с MSI: например,
`flutter build windows --release --build-name=0.1.0`.
Для подписи UI, update script и MSI:
`-Sign -CertificateThumbprint <thumbprint> -SignTool <signtool>`;
сертификат с private key берётся из CurrentUser/My build-аккаунта.
Без `-Sign` получается только неподписанный пакет для локальной проверки.
Builder не запускает установку.

UI проверяет GitHub Releases `endless-net/client-ui` при запуске и каждую
минуту, независимо от соединения с Client. Новый release должен содержать
`EndlessNet-v0.MINOR.PATCH-windows-amd64.msi` с GitHub SHA256 digest.
До нажатия «Скачать и обновить» пакет не скачивается. Перед обычным
`msiexec /i` проверяются hash, Windows Authenticode, тот же издатель, что у
установленного UI, UpgradeCode и точная версия MSI. Неподписанные пакеты
отклоняются; metadata error/rate limit не выдаётся за отсутствие обновлений.
Коды Windows Installer определяют завершение, ошибку или необходимость
перезагрузки; закрытие UI не отменяет уже запущенную установку.

Windows shortcut единого установщика использует
`--config <policy.json> --runtime-instance <runtime-instance>`.
В таком policy отсутствует install-time `instance_id`: текущий UUID читается
из отдельного файла через тот же admin-owned native reader. Затем применяется
существующая OS-auth named-pipe проверка. Для явного запуска с заранее известным
instance остаётся исходный `--config <config.json>`; автоматического fallback нет.
