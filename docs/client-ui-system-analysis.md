# Системный анализ мультиплатформенного Client UI: Protobuf v0

- Status: `target design`.
- Owner: `client-ui`.
- Дата: 2026-09-13.
- Основание: [Client UI BA, main](https://github.com/endless-net/architecture/blob/main/docs/ru/client-ui-business-analysis.md),
  UF-01–UF-23, UBR-01–UBR-40, UI-AC-01–UI-AC-27.
- Producer: [Client v0, main](https://github.com/endless-net/client/tree/main/proto/client/v0)
  и [нормативные правила](https://github.com/endless-net/client/blob/main/docs/client-ipc-protobuf.md).
- Статус реализации: контракт и SDK существуют; UI/runtime cutover и platform
  acceptance не заявлены. [Windows HTTP v2 as-is](architecture-and-future.md)
  сохраняет дату своей проверки и не является целевым дизайном.

## 1. Границы решения

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
и actual runtime acceptance ещё требуются. Production main пока использует старую
диагностику; этот слой не означает её cutover.
Составная session panel теперь содержит явный local diagnostics summary:
OS/Go, counts interfaces/routes/peers/conflicts/failures, connection phase и
truncation warning. Capability/caller/context ограничивают просмотр; domain
invalidation скрывает прежний summary. Shared widget regression проверяет отсутствие
авточтения, очистку и исключение browser URL из отображения. Полный payload
не сериализуется в clipboard/logs; подробные данные и archive export ещё не
реализованы. Native execution нового preview test ожидает CI.

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
Privileged helper, production shell cutover и actual runtime acceptance ещё
требуются; этот partial consumer flow не закрывает US-06.

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
acceptance или смены реального туннеля; production entrypoint остаётся отдельной работой.

Составная ClientSessionPanel имеет общий scroll container, enrollment mode dropdown
ограничен доступной шириной. US-14 widget regression проверяет всю session panel
при 360×640 и text scale 2, отсутствие RenderFlex overflow и достижимость profile
refresh через прокрутку. Это локальная layout-проверка, не полная accessibility
или native mobile product acceptance.

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

Session.expires_at и credential.expires_at являются разными фактами. Для каждого
UI показывает отдельно expiry, warning и доступный следующий шаг; отсутствие
Timestamp означает неизвестный срок. UI не устанавливает fictitious validity.
RenewSession не означает renewal node credential. Continuity показывается как
preserved/interrupted/unknown/not applicable по подтверждённому результату.

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
Экспорт через пользовательский save/share action не разрешает скрытую отправку.

## 6. Тестирование и release gates

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

Промежуточная consumer foundation: `app/lib/client_runtime_snapshot.dart`
использует generated SDK, закреплённый в pubspec по immutable client revision.
`app/test/client_runtime_snapshot_test.dart` проверяет часть US-01/03/10:
первый snapshot, pairing, instance/revision, operation kind, immutable copy и
capability availability. Workflow `contract-consumer.yml` запускает эти unit
проверки вместе с `client_event_stream_test.dart`: повторный snapshot при смене
capabilities, stream ordering/context, typed overflow, observer session denial
и независимый cursor новой подписки. EOF считается потерей подписки, а не
подтверждением Connected; cache/reconnect orchestration остаётся application work.
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
logout/forget, domain invalidation refresh и production shell ещё не перенесены.
Общая панель отдельно отображает authoritative session/credential expires_at в
UTC; отсутствие срока означает Unknown. Observer не видит эти поля, смена
контекста заменяет сроки, UI clock не синтезирует expired/connected state.
Shared widget test проверяет разные сроки и исчезновение одного без подстановки
второго. Это частичное US-09 evidence, не renewal UX или production acceptance.
Кнопка Renew session в общей панели вызывает journaled RenewSession только при
owner/profile, доступной capability и session.renewal; renewing отключает её.
Принятие операции не меняет сроки; credential renewal не вызывается из UI.
Shared widget suite проверяет gating и сохранение deadlines после acceptance.
Browser action, terminal-result recovery и production shell wiring ещё требуются.
`client_recovery_panel.dart` добавляет явный lookup сохранённых намерений через
session.recoverPending и подтверждение только terminal result через journal.
Pending не удаляется; ошибка lookup сохраняет намерения и не раскрывает raw
exception. Результаты скрываются при смене cache/caller context. Shared widget
suite проверяет pending/terminal и observer cleanup. Это ещё не полный recovery
UX: domain outcome details, NOT_FOUND resolution и browser actions остаются.
Shared mobile/desktop widget test проверяет pending Connect, доступный Disconnect,
отсутствие ложного Connected и очистку owner controls/context при observer snapshot.
Панель ещё не заменяет старый main/shell; localization, полный recovery UX и
остальные экраны остаются незавершёнными, как и product acceptance.
`client_session.dart` объединяет connection, typed state и intention journal:
до snapshot команды запрещены, запись предшествует отправке, поздний ответ после
смены контекста требует recovery. Pending recovery выполняет только GetOperation,
без replay payload и автоматической смены UUID. Session-тесты проверяют эти
границы. Перевод существующих экранов на этот session ещё не выполнен.
`client_state_controller.dart` содержит typed application state: ожидает первый
snapshot, очищает данные при stream loss/reconnect, меняет cache epoch при смене
profile/account/network, хранит caller-visible операции и domain invalidations.
Отмена idle subscription передаётся source без ожидания следующего события.
Тесты покрывают эти границы; прежний production controller ещё не заменён.
`client_mutations.dart` предоставляет typed SDK вызовы всех 19 mutation RPC,
проверяет UUID/instance/revision до отправки и соответствие kind/request ID
принятой операции. Запрос копируется перед отправкой; автоматического retry и
подмены UUID нет. GetOperation по request ID проверяет ту же идентичность.
`client_intent_journal.dart` сохраняет UUID/kind до callback отправки с flush,
без payload/credential. Pending запись переживает timeout; удаление допускается
только после обработки matching terminal result. Повреждённые записи сохраняются
и блокируют новые намерения вместо неявного повторного исполнения. Unit-тесты
переоткрывают storage, а process test использует сохранённый UUID для Connect и
GetOperation. Выбор caller-private installation-scoped directory, startup recovery
UI и обработка unresolved NOT_FOUND ещё требуют интеграции с production shell.
Это process-restart foundation, не доказательство power-loss durability или
защиты platform storage; mobile storage/OS acceptance остаются отдельными gates.

`client_session_process_test.dart` объединяет эти слои с producer fixture,
закреплённым на `ac30bfe0e959f3c93ef1059495f2356fa5476b06`: WatchEvents с
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
свидетельство остаётся pending. Этот слой ещё не подключён к production shell и
не подтверждает полный US, Android/iOS execution или UI/runtime cutover.

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
   US-01–14, emulator и UI-only функции, заменяя HTTP v2 consumer при cutover.
4. Distribution owners публикуют совместимые artifacts и authoritative update
   outcome; UI не запускает updater через daemon.
5. system-tests подтверждает UI-AC по принятому platform/release scope.

Не закрыты реализацией: transport adapter, mobile ownership, реальные defaults
managed/lifecycle, signed update source и platform release order. Принятые
контрактом semantics (один active context, fail-closed, operation replay,
deadline separation и observer redaction) не являются открытыми вопросами.
