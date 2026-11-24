# Сборка, версии и внешние действия

Локальная сборка не означает разрешение на установку/публикацию. Статус версии — [PROJECT_STATE](PROJECT_STATE.md), ограничения — [SECURITY](SECURITY.md), проверки — [TESTING](TESTING.md).

## Источники и версии

Hotfix 0.2.3: при недоступном GitHub API установщик и проверка обновлений получают manifests из `https://raw.githubusercontent.com/fefenke/kaban-max/main/release/`. Каталог `release/` должен описывать только уже опубликованный stable выпуск и совпадать с release assets; обновлять его вместе с публикацией. Пакеты/SHA256SUMS скачиваются по публичным pinned release URLs, не asset API. Curl используется для длинных redirect headers, при его отсутствии остаётся wget. Явные pins не заменяются latest; смешанные app/core tags отклоняются. Mirror override сохраняется. Maintained raw bootstrap из main передаёт исходный pin установщику через KABANMAX_RELEASE. Для повторной установки hotfix того же номера: `KABANMAX_RELEASE=0.2.3 KABANMAX_REINSTALL=1 sh install.sh`.

Пользователь запросил обновить существующий выпуск 0.2.3: меняются backend APK/IPK, install.sh и SHA256SUMS, без новой версии ядра или переписи tag/history. Source hotfix commit указывается в release notes. Остальные assets сохраняются побайтно. Hardware/публикационный результат — [отчёт](RELEASE_023.md).

Bootstrap старых установок: прежний UI при API403 может скачивать старый install.sh из immutable tag. Код уже установленного UI не меняется обновлением GitHub asset. Для такого роутера требуется один раз скачать свежий `https://raw.githubusercontent.com/fefenke/kaban-max/main/install.sh` и запустить с pin/reinstall выше. Новая backend 0.2.3 уже использует maintained main bootstrap; старые теги ради обхода не переписываются.

| Что | Источник истины |
| --- | --- |
| Upstream repo/commit/tag, local core package version, Go toolchain | `core/UPSTREAM` |
| Изменения Go | все `core/patches/*.patch` по имени |
| Branding | `scripts/brand-core.py`, после patches |
| Версия приложения/LuCI | аргумент release build / package variables; placeholder в `core/constants.uc` подставляется сборкой |
| Core compatibility floor | `core/constants.uc` + дополнительные проверки `config/validator.uc` |
| Формат/содержимое packages | package Makefiles, `scripts/build-release.sh`, `check-release.sh` |

Номер core не равен номеру приложения. Локальный tag/README не подтверждает GitHub release. Для нового patch проверять source minimum и включение тестов в runner/CI.

Защита формирования снимка мониторинга требует core с `0025-bounded-connection-snapshots.patch` вместе с backend/LuCI; обновление только UI не ограничивает аллокации прежнего core. Порог совместимости авторутинга остаётся r24, общий — r10. Проверка clean apply и race — `tests/core/run_connections_snapshot.sh`; [контракт диагностики](LOGGING.md).

## Локальная подготовка

Работать из корня. Frontend/сайт: Node.js 22+ и соответствующий lockfile/package manager. Backend tests: Bash, ucode с модулями. Core: Git, Python 3 и Go из UPSTREAM. Полная упаковка: инструменты pinned [release Dockerfile](../scripts/release.Dockerfile), официальный LuCI po2lmo, tar/zstd и package tools.

Сборка интерфейса: из `fe-app-kabanmax` выполнить `npm ci --ignore-scripts --no-audit --no-fund`, `npm run build`. Переводы: `node sync-locales.js`, сохранить существующие RU и заполнить новые; проверить localization tests. Не править генерируемый bundle вручную.

## Core

Уровни сетевого шума меняет patch `0026-actionable-log-levels.patch` у источника. Для этой политики нужен core с данным patch; одного обновления LuCI недостаточно. Regression runner — `sh tests/core/run_log_policy.sh SOURCE_GIT PROJECT`, без сети при заполненном Go module cache.

WAN two-event gate/per-question DNS/IPv6 FakeIP требуют текущей серии до `0028-wan-outage-log-gate.patch` и согласованного backend с новым диапазоном. Частичная установка только core или только generator не обеспечивает новый контракт. Проверка — `tests/core/run_network_availability.sh`. Новых packages/установки в этой задаче не было; source compatibility floors не означают наличие этих исправлений в старом core.

Локальная команда из корня, с загрузкой upstream/modules при пустом кэше:

```sh
bash scripts/build-core.sh base x86_64 dist/core-review
```

Другие допустимые variant/architecture сверять со скриптом. `CORE_SOURCE` может дать локальные Git-объекты, но сборка всё равно checkout-ит pinned commit и применяет всю серию patches. Нельзя считать произвольный изменённый checkout источником воспроизводимого release.

## Release packages

Public 0.2.3 содержит текущий r40, а не ранний private preview того же номера. Перед публикацией проверять все backend payload files, privacy source/packages и точные SHA; GPL corresponding source публикуется отдельным архивом с checksum. Публикация новой чистой версии сохраняет старую историю/теги по выбору пользователя. [Команды, native install и границы](RELEASE_023.md).

Точная процедура — [build workflow](../.github/workflows/build.yml), [build-release](../scripts/build-release.sh), [check-release](../scripts/check-release.sh). Вызов `scripts/build-release.sh` принимает **согласованную версию приложения x.y.z** и output directory; не копировать старый номер из отчёта. Результаты складывать в ignored `dist/`, не в исходники и не в соседний проект.

Перед выпуском: требуемые suites, чистая source preparation, package payload/version/license checks, согласованность app/LuCI/core/RU, manifests и SHA256. Cross-build ARM64 не равен запуску на ARM64. Все проверки фиксировать с их фактическим scope.

## Установка, публикация, откат

- Только новый явный запрос на соответствующее внешнее действие. Сначала подготовить конкретные проверяемые artifacts; не запрашивать разрешение на абстрактную будущую сборку вместо выполнения локальной работы.
- Сверить устройство, architecture, OpenWrt/opkg/apk, свободное место и сохранённую собственную конфигурацию. Не переносить чужой router config.
- Сохранять известный рабочий комплект и историю. Downgrade/несовместимость схем требуют оценки; старый APK сам по себе не гарантирует откат.
- Для согласованного обновления использовать **штатный install.sh/встроенный updater**, включая поддерживаемый local mirror для unpublished preview. Не подменять его ручными stop/reload и отдельной deployment-обвязкой: installer уже проверяет память, зависимости, checksum/config и возвращает службу. Заранее предупредить о паузе и учитывать зависимость внешнего доступа ассистента от KabanMax; выполнение/восстановление должно жить на роутере. Для отдельной диагностики с остановкой нужен автономный запуск либо заранее оговорённое действие пользователя. Не складывать большое ядро и backup одновременно в tmpfs при малой RAM; private backup держать на компьютере/flash с проверкой места. Эти требования не заменяют отдельное разрешение на доступ/установку.
- Не загружать `.local/`, всю папку `dist/`, ключи, конфиги и журналы. Проверить состав assets, исходники GPL, checksums и точный source commit.
- Отдельно подтвердить публикацию и отдельно установку. Успешный CI не доказывает аппаратную приёмку.

Пользовательская инструкция: [guide/install](guide/install.md). Политика обновления инженерных документов: [WORKFLOW](WORKFLOW.md).

Текущий preview **0.2.3/r29**: все 10 APK/IPK собраны/проверены; на один локальный ARM64 роутер полный base-комплект установлен штатным install.sh через loopback mirror (exit 0), без GitHub публикации. Это заменило первоначальную ручную logging-only установку. Неудачная отдельная deployment-обвязка, сохранность данных, команды, hashes и пределы smoke — [PREVIEW_023](PREVIEW_023.md); история WARP — [WARP_RECOVERY](WARP_RECOVERY.md).
