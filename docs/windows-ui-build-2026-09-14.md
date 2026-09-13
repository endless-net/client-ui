# Локальная компиляция Windows UI — 2026-09-14

Source commit: `7f01918507c32c0a01af29f025fd4e3396767440`, ветка `main`.
Рабочее дерево перед сборкой и после неё чистое. Проверялся настоящий `app`,
не `tests/mobile_contract` и не synthetic producer host.

Закреплённый Flutter 3.38.1 / Dart 3.10.0:

```powershell
# Из app, SDK находится внутри ignored .dart_tool.
.\.dart_tool\flutter-sdk-3.38.1\bin\flutter.bat build windows --debug --no-pub
```

Команда завершилась с кодом 0: `Built build\windows\x64\runner\Debug\endlessnet.exe`.
Размер executable: 1 058 304 bytes.
SHA-256: `f7b4daa1b7e4e6cf64668d1a22a12952468ac0ca4a45d908f965364d871e4059`.
Это идентификатор локального debug executable, не подпись или provenance всего
каталога сборки. Generated build output остаётся ignored и не публикуется.

## Что доказано

- Windows x64 Debug target компилируется и линкуется с pinned dependencies.
- Общие Dart изменения, Windows native runner и подключённые plugins совместно
  проходят эту сборку без изменения pubspec/lock или исходных файлов.

## Что не проверялось

Executable не запускался. Нет evidence protected named pipe/caller identity,
actual snapshot/rendering, real notifications/autostart, installer/repair/update,
MSI/WinGet/signing, release optimization, real VPN traffic или platform acceptance.
Debug executable требует остальных файлов output directory; один executable не
является дистрибутивом. Сборка не подтверждает macOS/Linux/mobile targets.
Интеграционные тесты не запускались: общий implementation gate остаётся открытым.

Следующий owning scope — `client-ui`: завершить исходный UI scope, затем native
integration и distribution acceptance с pinned core artifact. Runtime transport
и OS/VPN behavior остаются evidence owning `client`, не изменённого этой проверкой.

См. [SA](client-ui-system-analysis.md),
[аудит полноты](client-ui-implementation-audit.md).
