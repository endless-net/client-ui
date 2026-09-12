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
проверки на Windows/Linux/macOS с прежним закреплённым Flutter SDK. Этот слой
ещё не подключён к production shell/transport и не подтверждает полный US,
testserver integration, Android/iOS execution или UI/runtime cutover.

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
