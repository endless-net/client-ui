# EndlessNet UI

Единый публичный Flutter package для Admin и Client UI: общий брендбук,
светлая/тёмная темы, tokens, fonts/assets и C01–C20. Владелец — Client UI.
Предметные controllers, API/IPC, авторизация и platform authority сюда не входят.
Исходники общих элементов не копируются в consumers.

Публичная точка входа: `package:endlessnet_ui/endlessnet_ui.dart`.
Consumers используют Git dependency `https://github.com/endless-net/client-ui.git`,
path `packages/endlessnet_ui`, exact опубликованный source SHA. До разрешённой
publication consumer pins не объявляются готовыми; path overrides не применяются.
Fonts и картинки используют package-qualified names и поставляются в package.

## Каталог и отдельные тесты

Из корня Client UI:

```bash
python3 -B scripts/check_ui_library.py
python3 -B scripts/check_ui_library.py --design
```

Первая команда выполняет только functional unit tests и guard. Вторая — только
component design suite, независимо от ordinary unit run. Матрицы тем/ширины/text
scale относятся к synthetic C01–C20, не к полным feature screens.

Из package для каталога:

```bash
flutter run -d chrome -t tool/component_catalog/main.dart
```

Реестр variants/states/N/A и contracts — `tool/component_catalog/cases.dart`.
Библиотечные tests находятся в `test/`; дизайн — отдельно в
`test_design/components/`. Catalog использует production widgets и вымышленные
данные. Browser auth, SDK или сеть не требуются. Golden/capture scripts отсутствуют.

## Источники и права

Guard для consumer feature tests также поставляется этим package:
`dart run endlessnet_ui:check_test_boundaries` из каталога приложения и
`package:endlessnet_ui/testing/test_boundaries.dart` для unit entrypoint.
Он читает только тесты/профиль consumer и не запускает design suite. Testing API
не экспортируется widget barrel и не попадает в web/desktop UI автоматически.

EndlessNet first-party logos/palette взяты без изменений из публичного front,
source `c36e42d149a02e0ab32307e4da71897d28f5fbeb`, `logo-pack`.
Права сохраняет владелец EndlessNet; новая открытая лицензия на first-party
ассеты и код этим переносом не объявляется. Service Kit не использовался.
Inter4.1 — официальный `https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip`,
SHA256 `9883fdd4a49d4fb66bd8177ba6625ef9a64aa45899767dde3d36aa425756b11e`.
NotoSansMono-Regular — неизменённый source ServerDeck
`4c836a8df4d562fce6e61191628b8cec7cdef56f`, `assets/brand/fonts/`.
Inter и Noto поставляются с OFL1.1 в `assets/fonts/LICENSE-*.txt`.
Код C01–C20 создан в предыдущем Admin-only этапе010 и переносится в общий producer;
private domain SDK/Service Kit implementation в public package не переносились.

| Asset | SHA256 |
| --- | --- |
| fonts/Inter-Regular.ttf | `40d692fce188e4471e2b3cba937be967878f631ad3ebbbdcd587687c7ebe0c82` |
| fonts/Inter-Medium.ttf | `97ad806f526e41546d46365bb3a393145f75b7b1568913db74549ad8b8dba872` |
| fonts/Inter-SemiBold.ttf | `78a843fade9d4612a5567302fb595b56976eb5fcebf4fea5a5912d638bafcde3` |
| fonts/NotoSansMono-Regular.ttf | `d9e2b23d19f8230be7146f409a52b1d23117e635e28f2e2892cf91b7382f325b` |
| brand/logo-dark.png | `fdf6cebd201ab495d5aa912e4f86f47bdc3586a87ec7ce2deb8052b82846d063` |
| brand/logo-light.png | `f2ae9117f61bb96f13ee0466cd245ede0d9acdc727e7911383ecb66833c8a769` |
| brand/mark.png | `21a797ce04c1f74370dd97bbc0bf8db4d305405500cf6f140064d134a071dbc8` |
| brand/mark-small.png | `3dfa3114e4e08a8d2f9b3c9f8d9d6eff794b848715b21ea3613b54c65de6502f` |
