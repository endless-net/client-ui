# EndlessNet Client UI

Минимальный Flutter desktop-каркас показывает пустое окно. Сетевой runtime,
ключи, системные привилегии, подключение SDK и продуктовая логика здесь не реализованы.

## Проверки

Flutter 3.47.7, revision `abaf9c523780a608bd46686fd5e53740a07077f8`, Dart 3.13.5.
Зависимости закреплены в [lockfile](app/pubspec.lock), профиль —
[.ci/profile.json](.ci/profile.json).

```bash
python3 -B scripts/ci.py check
```

Команда проверяет pin SDK, locked dependencies, Dart format и Flutter analyze.
Unit tests проверяют границы publisher и архивов. У пустого UI нет widget/unit
сценариев: `UNIT_ABSENT` не означает покрытие. Integration/E2E не запускаются.

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
SDK producer Client будет подключаться по отдельной опубликованной exact версии,
когда появится использующая его логика. Данные сохраняются прямыми миграциями.
Production signing, auto-update и deployment требуют отдельного этапа.
