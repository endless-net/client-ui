# Desktop native compile — 2026-09-14

Source: `88947c270f0e64f5ce4a77f4043a243ff7fbdd8e`, `client-ui/main`.
[Run 34789555820](https://github.com/endless-net/client-ui/actions/runs/34789555820)
завершён с failure; manual `native_build_only=true`, repetitions=1.

| Host job | Результат | Наблюдение |
| --- | --- | --- |
| [macOS](https://github.com/endless-net/client-ui/actions/runs/34789555820/job/103811130359) | Success | Flutter 3.38.1: `Built build/macos/Build/Products/Debug/EndlessNet.app`; analyzer и dependency drift check успешны |
| [Linux](https://github.com/endless-net/client-ui/actions/runs/34789555820/job/103811130452) | Failure до компиляции | tray_manager CMake требует ayatana-appindicator3-0.1 / appindicator3-0.1 |
| [Windows](https://github.com/endless-net/client-ui/actions/runs/34789555820/job/103811130459) | Failure до компиляции | Flutter выбрал Visual Studio 16 2019; CMake не нашёл экземпляр VS |

У всех jobs producer checkout, setup-go, testserver build, complete consumer
suite и late-header transport probe пропущены. Integration tests не запускались.

macOS success подтверждает компиляцию Swift host adapters для diagnostics,
notifications и autostart, а не их OS effects, permission, sandbox access,
protected IPC, подпись дистрибутива или VPN traffic. Лог содержит linker warnings
о недоступном Metal toolchain search path и script-phase outputs; сборка при
этом завершилась успешно. Приложение не запускалось.

Windows trace step был ошибочно green: новый structural test содержал LF-only
сопоставление и упал на CRLF, но следующая успешная node-команда замаскировала
exit status в PowerShell. Исправление проверяется для LF и CRLF, а trace step
использует fail-fast Bash на каждой ОС. Нельзя считать исходный green step
доказательством прохождения всех trace tests.

Подготовленные fixes требуют нового compile evidence:

- Linux build dependencies включают `libayatana-appindicator3-dev`, согласно
  [требованиям tray_manager](https://github.com/leanflutter/tray_manager#linux-requirements).
- Windows build использует `windows-2022`, как существующий Windows packaging
  workflow; SDK/version продукта не меняются. Успех нового target ещё не доказан.
- Structural tests нормализуют CRLF и проверяют отказ при снятом testserver guard.

Owning follow-up: `client-ui` — повторить compile-only на исправленном source,
завершить весь исходный функционал, затем перейти к integration/platform
acceptance. Runtime, инфраструктура runners и другие repositories не менялись.

См. [SA](client-ui-system-analysis.md) и [аудит](client-ui-implementation-audit.md).
