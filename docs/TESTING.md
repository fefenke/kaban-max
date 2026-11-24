# Проверки: выбор, команды, доказательства

Последний подтверждённый результат — [PROJECT_STATE](PROJECT_STATE.md) со ссылкой на датированный отчёт. Команды ниже — рецепт, а не утверждение, что их только что запускали. После каждого логического изменения обновлять [документацию](WORKFLOW.md).

## Выбрать минимальную достаточную проверку

API quota hotfix: `bash tests/installer-api-fallback.sh` симулирует API отказ, raw manifests обоих компонентов, pinned public assets, curl HTTP/timeout; service release/installer/zapret2 tests проверяют raw fallback и неизменные manifest/digest guards. Это сетевые заглушки; реальная доступность CDN/redirect требует отдельного native smoke.

Executable `tests/core/auto_error_binary.py` использует порог Warn: первая принятая транспортная ошибка после r33 видима на этом уровне. Error скрывает её и делает проверку наличия строки некорректной. Assertions IP/timeout и отсутствия дубликатов обязательны; disabled logging проверяется отдельно.

SOCKS dial failure до handshake не подтверждает TLS. Harness проверяет отказ auto-apply при неизвестном протоколе; положительный сценарий задаёт явный ожидаемый HTTPS body prefix синтетического сервера. Успешный TCP dial не подменяет TLS/status/body evidence.

Section-wide Applied IP r39: RED→GREEN другого device, старые approvals/restore, guards соседнего source/IP и реальные exclusions; 14 Go race packages, backend 99/99, frontend 14/14/build/lint, native two-grant migration. [Точные команды и пределы](AUTO_ROUTING_SECTION_IP.md), [установка](PREVIEW_029.md).

Проверки постоянных WARP-портов r38 (boot allowance, десятиминутный timer, unchanged/no-commit, ownership, реальные локальные WireGuard data/keepalive) — [команды и ограничения](WARP_PORT_HINTS.md). Unit timers не заменяют десятиминутную аппаратную приёмку.

| Изменение | Сначала | Когда расширять |
| --- | --- | --- |
| Только инженерный текст/карта | docs unit tests + doc gate | VitePress, если затронуты сайт/config/ссылки пользовательских страниц |
| Frontend | ближайший Vitest, TypeScript, lint изменённых файлов | полный frontend + build при общем UI/RPC/форменном влиянии |
| ucode | оба режима syntax + целевой `tests/run.sh FILTER` | весь backend при общих config/service/migration изменениях |
| Core patch | clean apply pinned серии + целевой Go test | соответствующие race suites и compile; executable smoke, если проверяется wire/runtime поведение |
| Установщик/пакеты | shell syntax + synthetic installer/packaging tests | реальная упаковка/проверка payload и manifests перед выпуском |

Нет ucode/Go/Docker/прав — указать **не выполнено**, не PASS. Не отключать ACL/firewall/TLS ради теста. Живые роутеры/VPS и нагрузочные тесты — только по отдельному запросу.

## Документация — из корня

```sh
python -m unittest discover -s tests/docs -p 'test_*.py'
python scripts/check-project-docs.py
```

CI: [Documentation integrity](../.github/workflows/docs-check.yml) проверяет committed base...HEAD. Для source facts — `--write-facts`, для проверки структуры без Git diff — `--no-diff`. Архивные SHA256 проверяются по manifest; текст архива не считается текущим контрактом.

## Frontend — из fe-app-kabanmax

```sh
npm ci --ignore-scripts --no-audit --no-fund
npm test -- --run --maxWorkers=2
npm run build
```

Точечный пример: `npx vitest run src/kabanmax/tabs/sections/tests/autoRouting.test.ts`. Lint: `npx eslint PATH_TO_CHANGED_FILE`. В PowerShell использовать `npm.cmd`/`npx.cmd`, если script shim заблокирован; не менять глобальную ExecutionPolicy. `npm run build` включает TypeScript и fingerprint sync check, затем создаёт LuCI bundle. Полный `npm run lint` отдельно от CI build/test.

## Backend — из корня, Linux/контейнер с ucode

```sh
bash tests/run.sh diagnostics/auto
bash tests/run.sh
ucode -c -o /dev/null kabanmax/files/usr/lib/config/auto_storage.uc
ucode -S -c -o /dev/null kabanmax/files/usr/lib/config/auto_storage.uc
```

FILTER — подстрока пути, не glob. Каждый test-файл запускается отдельно с `tests/fakes`, `tests/lib` и библиотекой проекта; внешний side effect должен быть подменён. ucode version/build prerequisites — в [backend CI](../.github/workflows/backend-ci.yml). Release Dockerfile сам по себе не обещает установленный ucode. Не предполагать, что старый локальный контейнер/образ существует или подходит.

## Core

Источник: [UPSTREAM](../core/UPSTREAM) + все patches по имени. Не тестировать произвольный `.local/core-src` вместо этой серии. В [runner](../tests/core/run_auto_routing.sh) смонтированы `/source` с Git-объектом pinned commit, `/core`, `/scripts`, `/extra-tests`; нужен Go toolchain/кэш модулей. Runner делает clean archive/apply и race suites. `.github/workflows/core-ci.yml` содержит воспроизводимую CI-подготовку.

В чистом подготовленном source tree:

```sh
go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./common/autoroute ./route ./experimental/clashapi ./protocol/group ./experimental/cachefile ./common/ja3 ./common/sniff
```

Перед этим скопировать соответствующие `tests/core/auto*test.go` по схеме runner. Самостоятельный `go test` без этих дополнительных тестов не доказывает их прохождение. Compile, cross-build, binary smoke и аппаратный runtime — разные результаты.

## Сайт

Из `docs`: `npm ci --ignore-scripts --no-audit --no-fund`, затем `npm run build`. Workflow сайта использует `yarn install --frozen-lockfile` и `yarn build`; не обновлять lockfiles попутно и не смешивать их без отдельной причины. Наличие `package-lock.json` и `yarn.lock` — существующее состояние репозитория, не разрешение удалить один.

## Датированные результаты

- WAN/per-domain DNS/FakeIPv6: `sh tests/core/run_network_availability.sh SOURCE_GIT PROJECT` — clean apply + 7 race packages и cmd compile. WAN tests не запускают внешние probes, отдельно проверяют настоящий logger output из двух WAN-событий. Backend generator/nft/ip/forecast проверяют один диапазон. [Точные результаты и аппаратные ограничения](NETWORK_AVAILABILITY.md).

- Уровни логов: `sh tests/core/run_log_policy.sh SOURCE_GIT PROJECT` — clean apply всей серии + race route/DNS/fallback и compile-only cmd; [RED/GREEN и ограничения](LOGGING.md). Предыдущие frontend/RSS результаты не являются новым прогоном этой задачи.

- Журнал/мониторинг: [контракт и replay памяти](LOGGING.md). `tests/service/log_journal_pressure.uc` — локальный синтетический replay, не нагрузка на роутер. `sh tests/core/run_connections_snapshot.sh SOURCE_GIT PROJECT` делает clean apply всей pinned серии и Go race для bounded snapshot.

- Авторутинг r23: [field report](AUTO_ROUTING_FIELD_ERRORS.md).
- Авторутинг r24: [storage report](AUTO_ROUTING_STORAGE.md), включая 2000 synthetic routes, limitations и 7 race suites.
- Реорганизация документации: [DOCUMENTATION_AUDIT](DOCUMENTATION_AUDIT.md). Runtime suites в ней не перезапускались автоматически.
- Подробная прежняя история команд — [архив TESTING](archive/context-2026-11-23/TESTING.md.txt).

Для нового evidence указать дату, базу/версию, полную команду, окружение, exit/result, что не проверено и когда пересмотреть вывод. Старое PASS не становится свежим после правки текста.
