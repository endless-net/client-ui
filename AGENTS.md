# Правила работы: client-ui

Репозиторий публичный и использует автономный локальный профиль по STD-030,
STD-035 и STD-036. Этот профиль заменяет прежний private include: чтение
Service Kit или приватного workspace, их credentials, код, workflows и образы
не являются обязательной зависимостью. Приватный профиль не копируется сюда.

- Перед изменениями прочитать существующие документы затронутого контракта.
  Зафиксировать revision и dirty state прочитанных источников; недоступность
  необходимого источника назвать явно.
- Выполнять только запрошенную работу в этом репозитории. Сохранять чужие локальные
  изменения; соседний checkout или упоминание consumer не разрешает его менять.
  Commit/push, PR, выпуск, deployment и реальные инфраструктурные операции требуют
  соответствующего запроса. Skills без явного разрешения не изменять.
- Spec Kit устанавливается и запускается только в workspace. В этом репозитории
  не создавать его конфигурацию, skills, команды или конституцию. При работе через
  workspace использовать его согласованные spec/plan/tasks; автономная работа
  опирается на этот AGENTS.md. Предложение и успешная сборка не означают принятие
  продукта или разрешение перейти к runtime.
- Схема, генерация и SDK принадлежат producer (STD-006/007). Consumer не создаёт
  ручную копию доменной модели. API/wire/runtime versions и migration status
  фиксировать отдельно; credentials не помещать в Git, логи или generated files.
- Для public CI использовать GitHub-hosted runners и публичные локальные configs
  (STD-015/029/033/035). Общие Bash/scripts/baseline checks выполняются в Ubuntu
  26.04; platform-specific проверки отдельно указывают OS и точный scope.
- При отказе необходимого инструмента или проверке с skip фиксировать not-verified,
  не pass. Для изменения кода выполнять применимые обязательные проверки всего
  затронутого модуля, а не только изменённых строк. Для документации проверить
  локальные ссылки и `git diff --check`.

## Сохранённые правила локального профиля

Неизвестные policy/timeout/limit values не выдумываются. Наблюдаемые результаты,
запрещённые исходы и применимые проверки связываются с постановкой задачи.

- STD-016/018/020/023/024: authority определяется настоящим caller/resource/action,
  dependency failure не расширяет доступ; bounded deadline/cancellation/retry,
  immutable replay inputs, expiry и current-state checks у соответствующего owner.
  Shape/serialization fixtures не доказывают runtime authentication или durable replay.
- STD-034: локальная работа ограничена запрошенным owner scope; consumer references
  не разрешают менять чужой checkout. Host lifecycle/provision/deployment/
  activation/rollback относятся к внешнему платформенному контуру вне активного
  состава. Эти функции не переходят сервисам или Service Kit; место и owner
  требуют отдельного решения COMPOSITION-Q-01. Изолированный test fixture
  не получает production authority.
- Public consumer может получать private producer API по закреплённой версии с
  read-only credentials при сборке. Это не разрешает Service Kit dependency;
  credentials не попадают в Git/logs/artifacts и недоверенные external PR, а
  отсутствие необходимого доступа завершает fetch ошибкой без fallback.
- Применимость и exact revision источников и результатов проверок фиксируются;
  proposed решения не становятся accepted из-за документа или успешной сборки.

Локальные особенности указывают причину, область и заменяемое положение.
Наличие документов не расширяет разрешённые записи или публикации.

## Проверки владельца

В текущем checkout нет `pubspec.yaml`, Flutter package, runtime или собственного
API-модуля. Поэтому Go/Flutter команды сейчас неприменимы и не получают pass.
Для документации проверить существующие локальные ссылки и `git diff --check`.

При появлении настоящего Flutter package выполнять его locked dependency setup,
`flutter analyze` и `flutter test` из корня этого package, а также применимые
платформенные проверки. Не создавать пакет или тест ради фиктивной проверки.
UI потребляет SDK producer Client по существующему immutable revision, не
копирует схемы; consent/отображение requested/effective/local state не дают UI
права управлять туннелем в обход Client и OS caller authority. Секретные ключи и
session renewal grants не экспортируются UI.
