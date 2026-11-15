# Проверки

## Финальная QA 0.1.6 — 2026-11-16

**Локальный GO; аппаратные сценарии UNVERIFIED.** Один агент, контейнеры без сети, никаких устройств/VPS. Источник core: pinned `60d96c99815a672712915a5c00114bf0f690ad80` + patches 0001–0007. Полные логи в ignored `.local/audit/final-qa-publish/`.

Последовательно из `fe-app-kabanmax`:

```powershell
node node_modules/vitest/vitest.mjs run
node node_modules/typescript/bin/tsc --noEmit
$qaFiles = Get-Content ../.local/audit/final-qa-publish/lint-files.json -Raw | ConvertFrom-Json
node node_modules/eslint/bin/eslint.js src/constants.ts @qaFiles
node ../scripts/generate-fingerprints.mjs --check
node node_modules/tsup/dist/cli-default.js src/main.ts
```

PASS **175 файлов / 1682 теста**, tsc/lint/catalog/bundle. Список lint получен из изменённых и untracked frontend src/tests JS/TS. Два новых сценария проверяют повтор после отмены/ошибки. Контрактный тест воспроизвёл отсутствующий reserved tag `infrastructure-direct-out`; LuCI исправлен, RED → GREEN. Bundle в обоих пакетных форматах побайтно соответствует сборке после подстановки 0.1.6.

Из корня PowerShell, `$taskRoot=(Get-Location).Path`:

```powershell
docker run --rm --network none --mount "type=bind,source=$taskRoot,target=/work,readonly" -w /work forkop-zapret2-test-tools:local bash -c 'set -e; bash tests/run.sh; bash -n install.sh; bash tests/installer-translation-smoke.sh; bash tests/installer-release-pin.sh; bash tests/legacy-namespace.sh; find kabanmax/files/usr/lib -name "*.uc" -print0 | xargs -0 -n1 ucode -c -o /dev/null'
docker run --rm --network none --mount "type=bind,source=$taskRoot\luci-app-kabanmax\po\ru\kabanmax.po,target=/input.po,readonly" kabanmax-release:2.1.0 /usr/local/bin/po2lmo /input.po /tmp/final-qa.lmo
git diff --check
```

PASS **91/91 backend**, syntax, translation/pin/namespace smoke, po2lmo и diff check. Первый backend дал 3 failed files: migration managed infrastructure detour/bootstrap override, minimum==package, reserved tags/ACL. Ожидания сверены с generator/validator/контрактом и обновлены; целевые три файла и затем полный backend passed. `auto_action` остаётся write-only. Save & Apply/no-op/invalid config, installer stop/reconnect и Zapret2 activation rollback проверяют существующие mocks, не реальный OpenWrt.

```powershell
docker run --rm --network none --mount "type=bind,source=$taskRoot\.local\core-src,target=/source,readonly" --mount "type=bind,source=$taskRoot\core,target=/core,readonly" --mount "type=bind,source=$taskRoot\scripts,target=/scripts,readonly" --mount "type=bind,source=$taskRoot\tests\core,target=/extra-tests,readonly" --mount type=volume,source=kabanmax-chrome155-go-mod,target=/go/pkg/mod --mount type=volume,source=kabanmax-chrome155-go-build,target=/go/build -e GOMODCACHE=/go/pkg/mod -e GOTOOLCHAIN=go1.26.10 -e GOCACHE=/go/build kabanmax-release:2.1.0 sh /extra-tests/run_auto_routing.sh
```

PASS clean archive/apply семи patches и `go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./common/autoroute ./route ./experimental/clashapi ./protocol/group ./experimental/cachefile`.

```powershell
docker run --rm --network none --mount "type=bind,source=$taskRoot,target=/work,readonly" --mount "type=bind,source=$taskRoot\.local\core-src,target=/source,readonly" --mount "type=bind,source=$taskRoot\.local\audit\final-qa-publish\release,target=/output" --mount type=volume,source=kabanmax-chrome155-go-mod,target=/go/pkg/mod --mount type=volume,source=kabanmax-chrome155-go-build,target=/go/build -e CORE_SOURCE=/source -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0=/source -e GOMODCACHE=/go/pkg/mod -e GOTOOLCHAIN=go1.26.10 -e GOCACHE=/go/build -e GOPROXY=off -e GOFLAGS=-p=2 -e PO2LMO=/usr/local/bin/po2lmo -w /work kabanmax-release:2.1.0 bash -c 'set -e; bash scripts/build-zapret2-local.sh 0.1.6 /output; bash scripts/build-core.sh base aarch64_cortex-a53 /output; bash scripts/build-core.sh tiny aarch64_cortex-a53 /output'
```

PASS 10 IPK/APK: app/LuCI/RU noarch и ARM64 base/tiny r11. Отдельная clean build `bash scripts/build-core.sh base x86_64 /output` теми же mounts/env в `final-qa-publish/smoke` — только для executable smoke, её пакеты не публикуются. Core manifest: r11, tag/app 0.1.6, pinned source. Затем:

```powershell
docker run --rm --network none --mount "type=bind,source=$taskRoot,target=/work,readonly" --mount "type=bind,source=$taskRoot\.local\audit\final-qa-publish\release,target=/output" -w /work kabanmax-release:2.1.0 bash -c 'set -e; bash -n scripts/check-release.sh tests/release-manifest-smoke.sh; bash tests/release-manifest-smoke.sh; bash scripts/finalize-release.sh /output'
docker run --rm --network none --cap-add NET_ADMIN --mount "type=bind,source=$taskRoot\tests\core,target=/tests,readonly" --mount "type=bind,source=$taskRoot\.local\audit\final-qa-publish\smoke,target=/output,readonly" --mount "type=bind,source=$taskRoot\.local\audit\auto-routing-04b\fixtures,target=/fixtures,readonly" --mount "type=bind,source=$taskRoot\.local\audit\auto-routing-04b\tools,target=/tools,readonly" kabanmax-release:2.1.0 python3 /tests/auto_routing_binary.py /output/build/amd64/base/sing-box /fixtures /tools
```

PASS 13 SHA256/14 assets, manifest и installer parser. Release checker сначала дал RED при minimum r10/package r11; исправлен на `package >= minimum`. Новый smoke принимает r10/r11 и r11/r11, отвергает minimum r12. Global minimum остаётся r10, opt-in требует r11.

Executable PASS: ordinary/strict HTTPS, manual-only web, IP-only diagnostic без Apply, настоящий FakeIP, CDN/domain/mixed DNS isolation, mark/first-match, delete/suppression/TTL/restart при disabled/all/selected pre-resolve. SHA256 x86 base `190a9f483a34ecd0b246d2760ab8fb98cff2e93996d4489026e1b458d758668a`, ARM64 base `c8cb7551fe1699493e03ff149f988e2c6872e657061aa331f265c34aa19f3179`, ARM64 tiny `2bf781b079a94de9d12a7b5a7e9d1c2bfff87cd3afa033e5cdc0abc3b9662c83`.

`python3 /work/.local/audit/final-qa-publish/inspect_packages.py` в release container PASS: metadata/dependencies/layout/licenses пяти IPK, core binary identity, source bundle, payload всех пяти APK. Первое сравнение обнаружило только штатные APK `lib/apk/packages/<name>.{list,conffiles,conffiles_static}`; они явно учтены. Это извлечение, не установка.

UNVERIFIED: OpenWrt logread/TZ (локально только BusyBox), настоящий LuCI/RPC, NFQUEUE/PBR/mwan3, WARP/VPN/физический egress/DNS/Direct leaks, ARM64 runtime, package install/upgrade/downgrade на OpenWrt. Только prerelease; DPI и доступность целого приложения не доказаны. Сканируются publishable changed/untracked/staged files; `.local`, `.env`, binaries/логи и VitePress temp исключаются. Это не аудит всей истории.

Документация: `node node_modules/vitepress/bin/vitepress.js build` из `docs` сначала дал 2 dead links из engineering `audits/README.md` на исключённые handoff/tests. `audits/**` исключён из пользовательского сайта аналогично `superpowers/**`; повтор exit 0. Dead-link проверка не отключалась. `.vitepress/.temp/` добавлен в ignore без удаления пользовательских файлов. Windows sandbox блокировал esbuild/Docker, повтор с разрешённым локальным доступом прошёл. Первый elevated Git-вызов без safe.directory не видел origin; явный per-command `-c safe.directory=...` с URL подтвердил main `24d225c...` и теги 0.1.0–0.1.5. Глобальная Git/ExecutionPolicy конфигурация не менялась.

После staging новые patch-файлы впервые попали в `git diff --cached --check`: unified-diff context (`space + tab`, `space` у пустой строки) дал ложные whitespace ошибки. Patches не переписывались; `.gitattributes` отключает whitespace lint только для `core/patches/*.patch`, сохраняя обычную проверку исходников. Clean apply/race/build подтверждают применимость; повтор staged diff check PASS.

## №07 — продолжение, 2026-11-16

Свежий полный Vitest после синхронизации каталогов и уточнения тестовых контрактов: 175 файлов / 1677 тестов passed. До исправлений 7 failures сохранены в `task07-vitest-output.txt`: отсутствующие/устаревшие переводы, временные поля URI ошибочно приравнены к UCI, невалидный выдуманный ID в пустом селекторе и устаревшие названия fingerprint. Сериализация/повторное открытие и отсутствие временных полей проверяются `tests/bundle/connectionLinks.test.js`. Этот полный прогон предшествовал последующим исправлениям журналов и release-check, поэтому его необходимо повторить.

Воспроизведён возврат очищенных записей из CLI fallback при недоступном журнале. `src/kabanmax/methods/shell/tests/checkLogs.test.ts` RED → GREEN, 7/7; fallback к системному кольцу удалён. Неполный JSON `{success:true}` ошибочно означал актуальную версию: `releaseCheck.test.ts` RED → GREEN, 4/4; теперь поле update_available обязательно. Установленный файл Zapret2 без version ошибочно предлагалось установить: `zapret2.test.ts` RED → GREEN. `bash tests/run.sh service/` в offline Docker: 14 файлов / 0 failures. `bash tests/installer-translation-smoke.sh` в offline Docker: fresh yes/no и update с пакетом/без пакета для interactive/noninteractive passed; это изолированные функции, не полный запуск install.sh.

После этих изменений `node node_modules/vitest/vitest.mjs run`: 175 файлов / 1678 тестов passed; полный вывод `.local/audit/task07-finish/task07-vitest-final.txt`, исходные failures — рядом. `node node_modules/typescript/bin/tsc --noEmit`, целевой ESLint изменённых файлов, tsup bundle, po2lmo и `git diff --check` — exit 0. Следующий шаг: проверить стабильность журнала при смене TZ и полный жизненный цикл Zapret2, затем расширить installer mock до повторного запуска/ошибок и проверить LuCI Save & Apply.

Продолжение: повторная параллельная проверка обновлений воспроизведена в `updateFeedback.test.ts`, защита RED → GREEN. Повторная очистка и новая запись проверены в `logs/tests/initController.test.ts`; `tests/service/zapret2.test.uc` проверяет наличие файла отдельно от процесса, offline `bash tests/run.sh service/zapret2` — 2/2 файлов. Свежий полный Vitest — 175 файлов / 1679 тестов passed (`.local/audit/task07-finish/task07-vitest-current.txt`); tsc, targeted lint и bundle — exit 0. Сборка выполнялась параллельно тестам; при финальной приёмке повторить последовательно.

Mock установщика воспроизвёл автоподбор русского пакета при `--lang=en` и LuCI `auto`. `tests/installer-translation-smoke.sh` RED → GREEN после исправления приоритета явного языка в `install.sh`. Offline `bash -n install.sh`, mock fresh yes/no/interactive/noninteractive, явный en/ru, состояние установленного пакета и `tests/installer-release-pin.sh` — exit 0. Полную операцию с повторным запуском и отменой mock пока не моделирует. Локальный контейнер предоставляет BusyBox logread, не OpenWrt logread; реальное изменение timezone и поведение logd не подтверждены.

Позднее: воспроизведён старт новой операции до обязательного reload после изменения пакетов; `installerRun.test.ts` RED → GREEN, новая операция блокируется до reload. Отсутствующий и неисполнимый файл Zapret2 различаются в backend status и UI; `service/zapret2` — 2/2, `zapret2Feedback.test.ts` passed. После последней сборки `node node_modules/vitest/vitest.mjs run` — 175 файлов / 1680 тестов passed, вывод `.local/audit/task07-finish/task07-vitest-after.txt`. `node node_modules/typescript/bin/tsc --noEmit`, целевой ESLint, сборка bundle, po2lmo, `git diff --check` — exit 0. Offline diagnostics — 10/10 файлов. №07 не закрыт: TZ OpenWrt logread, полный mock re-entry/cancel и часть переходов/reconnect требуют проверки.

## №07 — частичная проверка 2026-11-16

Из `fe-app-kabanmax`: `node node_modules/vitest/vitest.mjs run src/kabanmax/tabs/logs/tests/initController.test.ts` — 8/8, после воспроизведения падения нового теста до исправления; `node node_modules/typescript/bin/tsc --noEmit` — exit 0; `node node_modules/eslint/bin/eslint.js src/kabanmax/tabs/logs/initController.ts src/kabanmax/tabs/logs/tests/initController.test.ts` — exit 0; `node node_modules/tsup/dist/cli-default.js src/main.ts` — сборка bundle успешна. Vitest и tsup требовали разрешённого запуска вне sandbox: esbuild не мог читать родительский каталог.

`node node_modules/vitest/vitest.mjs run` — 170 файлов успешно, 5 с ошибками; 1669 тестов успешно, 7 ошибок: два теста локализации, два контракта password fields, requiredFields, settingsRoundTrip Zapret2, serverForm fingerprints. Причины и исходное состояние ошибок не установлены. `git diff --check` — exit 0 (предупреждения CRLF). Backend и po2lmo не запускались; Docker внутри sandbox недоступен. Ни роутер, ни внешние сервисы не использовались. Проверка №07 неполная.

Продолжение: после разрешённого доступа к локальному Docker без сети выполнены `bash tests/run.sh service/zapret2`, `service/state_service`, `service/installer`: 4 файла, 0 ошибок; `po2lmo /input.po /tmp/task07.lmo` — exit 0. Из frontend: `node node_modules/vitest/vitest.mjs run src/kabanmax/tabs/logs/tests src/kabanmax/tabs/components/tests` — 13 файлов / 79 тестов passed; новый тест гонки установщика до исправления падал. Целевой ESLint и `tsc --noEmit` — exit 0. Состояние №07 остаётся частичным.

## Свежая проверка №04Б-ФИНАЛ — 2026-11-16

Продолжение r11 отдельным patch 0007; 0001–0006, прежний audited r11 и r9/r10 сохранены. Все тесты локальные, `--network none`, один агент, без релизных пакетов/внешних проб/роутеров/VPS. Исторический блок 2026-11-15 ниже не является текущим результатом.

PASS: 31 backend-файл (10 diagnostics + cli + state_service + validator_requirements + 16 generator + 2 nft), 15 frontend-файлов / **121 тест**, tsc, targeted lint, fingerprint catalog check, LuCI bundle build и po2lmo. Пять core race-пакетов; в autoroute теперь 27 тестовых функций (14 прежних + 13 новых, включая table subtests). Проверено чистое применение всех семи patches к pinned commit.

Новый binary-only test build r11 в `.local/audit/auto-routing-04b-final`; это не release. ARM64 только cross-build:

| Artifact | Bytes | SHA256 |
| --- | ---: | --- |
| `build/amd64/base/sing-box` | 35016830 | `190a9f483a34ecd0b246d2760ab8fb98cff2e93996d4489026e1b458d758668a` |
| `build/arm64/base/sing-box` | 32440446 | `c8cb7551fe1699493e03ff149f988e2c6872e657061aa331f265c34aa19f3179` |

Старый audited r11 в `.local/audit/auto-routing-04b` по-прежнему имеет SHA `1024236d...` / `6442348a...`. SHA patch 0006 совпал с сохранённой копией: `67703b3a1fdf0df1d66236c3e8f7f2c8708bec77efd463566cec04115459bf7f`.

Из корня репозитория, PowerShell:

```powershell
$taskRoot=(Get-Location).Path
docker run --rm --network none --mount "type=bind,source=$taskRoot\.local\core-src,target=/source,readonly" --mount "type=bind,source=$taskRoot\core,target=/core,readonly" --mount "type=bind,source=$taskRoot\scripts,target=/scripts,readonly" --mount "type=bind,source=$taskRoot\tests\core,target=/extra-tests,readonly" --mount "type=bind,source=$taskRoot\.local\audit\auto-routing-04b-final,target=/output" --mount type=volume,source=kabanmax-chrome155-go-mod,target=/go/pkg/mod --mount type=volume,source=kabanmax-chrome155-go-build,target=/go/build -e GOMODCACHE=/go/pkg/mod -e GOTOOLCHAIN=go1.26.10 -e GOCACHE=/go/build -e AUTO_BUILD=1 kabanmax-release:2.1.0 sh /extra-tests/run_auto_routing.sh
docker run --rm --network none --cap-add NET_ADMIN --mount "type=bind,source=$taskRoot\tests\core,target=/tests,readonly" --mount "type=bind,source=$taskRoot\.local\audit\auto-routing-04b-final,target=/output,readonly" --mount "type=bind,source=$taskRoot\.local\audit\auto-routing-04b\fixtures,target=/fixtures,readonly" --mount "type=bind,source=$taskRoot\.local\audit\auto-routing-04b\tools,target=/tools,readonly" kabanmax-release:2.1.0 python3 /tests/auto_routing_binary.py /output/build/amd64/base/sing-box /fixtures /tools
docker run --rm --network none --mount "type=bind,source=$taskRoot\tests,target=/work/tests,readonly" --mount "type=bind,source=$taskRoot\kabanmax,target=/work/kabanmax,readonly" --mount "type=bind,source=$taskRoot\luci-app-kabanmax,target=/work/luci-app-kabanmax,readonly" --mount "type=bind,source=$taskRoot\scripts,target=/work/scripts,readonly" --mount "type=bind,source=$taskRoot\core,target=/work/core,readonly" -w /work forkop-zapret2-test-tools:local bash -c 'bash tests/run.sh diagnostics/ && bash tests/run.sh service/cli && bash tests/run.sh service/state_service && bash tests/run.sh config/validator_requirements && bash tests/run.sh singbox/generator && bash tests/run.sh nft/'
docker run --rm --network none --mount "type=bind,source=$taskRoot\luci-app-kabanmax\po\ru\kabanmax.po,target=/input.po,readonly" kabanmax-release:2.1.0 /usr/local/bin/po2lmo /input.po /tmp/task04b-final.lmo
```

`run_auto_routing.sh` выполняет `go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./common/autoroute ./route ./experimental/clashapi ./protocol/group ./experimental/cachefile`, затем binary-only amd64/arm64. Build inputs — pinned upstream + patches, не scratch working tree.

Из `fe-app-kabanmax`:

```powershell
node node_modules/vitest/vitest.mjs run tests/bundle/connectionLinks.test.js src/kabanmax/tabs/sections/tests src/kabanmax/tabs/diagnostic/tests/routeForecast.test.ts src/kabanmax/tabs/diagnostic/tests/renderRouteForecast.test.ts
node node_modules/typescript/bin/tsc --noEmit
node node_modules/eslint/bin/eslint.js src/kabanmax/tabs/sections/autoRouting.ts src/kabanmax/tabs/sections/tests/autoRouting.test.ts
node ../scripts/generate-fingerprints.mjs --check
node node_modules/tsup/dist/cli-default.js src/main.ts
```

На **собранном executable**: ordinary HTTPS без nonce, два EOF исходного marked Zapret2 против двух валидных HTTPS-ответов Direct, proposal без auto-apply при включённой галочке, реальное ручное Apply/Delete, healthy original без смены, domain isolation общего CDN-IP, metadata фактически выбранного IP, mixed DNS без pinning соседей; всё для pre-resolve disabled/all/selected. Отдельно ordinary через настоящую core FakeIP map и атрибутированный IP-only TCP diagnostic с rejected Apply. Прежний strict smoke: actual mark через отдельную synthetic nft NAT table, два strict ответа, Block выше/ниже, TLS/process guard, ложный DNS owner, FakeIP, suppression, TTL=2s, restart — также PASS. NET_ADMIN только внутри одноразового контейнера без host network; fixtures/инструменты прежние локальные, никаких загрузок или глобального nft flush.

Только **controlled adapter / httptest race tests**, не реальные WARP/провайдер: два независимых WARP dial, запрещённый Direct имеет 0 dials, обычные 3xx/401/403/429/405/5xx/captcha/малое тело/cache/content restrictions, invalid TLS, один сбой, общий отказ, body stall, строгий auto-apply, web recheck без auto-apply. Существующие tests сохраняют coverage отмены generation, cooldown, DNS change, stale/consumed decision, scope IPv6/source/inbound/port, suppression stable ID и позднего сбоя заменённой lease. UDP только наблюдается.

RED → GREEN в этой доработке: отсутствующий web режим/eligibility поля, отсутствие default web backend contract, отсутствие UI canApply, захват mixed DNS адреса прежней lease, скрытое применение web recheck и body-stall после успешных headers. Исправления сопровождались свежими повторами. Captcha marker detection ограничен эвристикой; generic HTTPS даёт только ручное предложение, не verified_for_apply. Полная функциональность приложений/UDP, физический egress/PBR/NFQUEUE, реальный WARP и OpenWrt UI требуют отдельной приёмки. Текущие ограничения — [контракт №04Б](AUTO_ROUTING_IMPLEMENTATION_04B.md).

## Свежая проверка №04Б — 2026-11-15

Все контейнеры запускались с `--network none`; никаких реальных российских сервисов, VPS/роутеров и установок. Existing r10 artifacts не заменялись. Docker/Node запускались после sandbox approval; исходный dirty tree сохранён. Ниже команды из корня репозитория (PowerShell).

### Core: чистый upstream + все patches

```powershell
$taskRoot=(Get-Location).Path
docker run --rm --network none --mount "type=bind,source=$taskRoot\.local\core-src,target=/source,readonly" --mount "type=bind,source=$taskRoot\core,target=/core,readonly" --mount "type=bind,source=$taskRoot\scripts,target=/scripts,readonly" --mount "type=bind,source=$taskRoot\tests\core,target=/extra-tests,readonly" --mount "type=bind,source=$taskRoot\.local\audit\auto-routing-04b,target=/output" --mount type=volume,source=kabanmax-chrome155-go-mod,target=/go/pkg/mod --mount type=volume,source=kabanmax-chrome155-go-build,target=/go/build -e GOMODCACHE=/go/pkg/mod -e GOTOOLCHAIN=go1.26.10 -e GOCACHE=/go/build -e AUTO_BUILD=1 kabanmax-release:2.1.0 sh /extra-tests/run_auto_routing.sh
```

Результат: pinned commit архивируется заново, `git apply --check` + apply всех шести patches; PASS `go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./common/autoroute ./route ./experimental/clashapi ./protocol/group ./experimental/cachefile`. В новом пакете 14 regression-тестов. Отдельные binary-only base builds x86_64 и ARM64 r11, без IPK/APK/dist/release.

Окончательные binary-only artifacts в ignored `.local/audit/auto-routing-04b/`:

| Artifact | Bytes | SHA256 |
| --- | ---: | --- |
| `build/amd64/base/sing-box` | 34992254 | `1024236d9601dd812b7ef0e324b2f1563c06ee304a00e9fcab06cb0365e65f94` |
| `build/arm64/base/sing-box` | 32440446 | `6442348abfb0cbcabe9ddd2370e9000a428708849ab3e9a60164f5fef27861cc` |

ARM64 только cross-build, без запуска на устройстве. Дополнительный свежий race-run `./common/autoroute` прошёл после расширения guard-теста случаями исключённых LAN-подсетей/System, повреждённого exclusion, алиаса infrastructure endpoint, FakeIP и российского TLD; production source после финальной сборки не менялся.

### Сам executable

```powershell
docker run --rm --network none --cap-add NET_ADMIN --mount "type=bind,source=$taskRoot\tests\core,target=/tests,readonly" --mount "type=bind,source=$taskRoot\.local\audit\auto-routing-04b,target=/output,readonly" kabanmax-release:2.1.0 python3 /tests/auto_routing_binary.py /output/build/amd64/base/sing-box /output/fixtures /output/tools
```

PASS на окончательном x86_64 executable из таблицы выше: actual socket routing mark выбирает синтетический TLS-failure endpoint через NAT отдельной nft table в одноразовом контейнере; Direct получает success endpoint. По две независимые TLS-попытки на маршрут; применение действительно меняет последующие соединения. Общий CDN-IP не меняет другой домен. Настоящий core FakeIP map сохраняет domain isolation. Посторонний DNS Answer owner не допускает HTTPS-проб (regression RED → GREEN). Предшествующие Block/TLS rule и неизвестный process context также не допускают HTTPS-проб. Delete возвращает исходный маршрут и suppression; min DNS TTL=2s снимает lease; новый процесс не восстанавливает lease. Проверено с pre-resolve disabled/all/selected. Настоящий provider WARP и NFQUEUE здесь не проверяются: WARP покрыт controlled adapter race-тестом.

Fixtures — только синтетические сертификат/ключ (Go generator `tests/core/auto_cert.go`) в ignored `.local/audit/auto-routing-04b/fixtures`. nft и совместимые библиотеки взяты из уже имеющегося локального test-tools image; пакеты/загрузки не устанавливались. NET_ADMIN только внутри отдельного network namespace, без host network и без flush существующих таблиц.

### Backend

```powershell
docker run --rm --network none --mount "type=bind,source=$taskRoot\tests,target=/work/tests,readonly" --mount "type=bind,source=$taskRoot\kabanmax,target=/work/kabanmax,readonly" --mount "type=bind,source=$taskRoot\luci-app-kabanmax,target=/work/luci-app-kabanmax,readonly" --mount "type=bind,source=$taskRoot\scripts,target=/work/scripts,readonly" --mount "type=bind,source=$taskRoot\core,target=/work/core,readonly" -w /work forkop-zapret2-test-tools:local bash -c 'bash tests/run.sh diagnostics/ && bash tests/run.sh service/cli && bash tests/run.sh service/state_service && bash tests/run.sh config/validator_requirements && bash tests/run.sh singbox/generator && bash tests/run.sh nft/'
```

PASS: 10 + 1 + 1 + 1 + 16 + 2 = **31 backend-файл**. Новые проверки: IP-only IPv4/IPv6, no-progress без host, неизвестная attribution, default JSON r10, opt-in contract, suppression отдельно от manual UCI, corrupt ownership fail closed, write session ACL до API I/O и маскирование contract/protected/suppressed в отчётах. Это целевые suites; весь backend целиком не запускался.

### Frontend и переводы

Из `fe-app-kabanmax`:

```powershell
node node_modules/vitest/vitest.mjs run tests/bundle/connectionLinks.test.js src/kabanmax/tabs/sections/tests src/kabanmax/tabs/diagnostic/tests/routeForecast.test.ts src/kabanmax/tabs/diagnostic/tests/renderRouteForecast.test.ts
node node_modules/typescript/bin/tsc --noEmit
node node_modules/eslint/bin/eslint.js src/kabanmax/tabs/sections/autoRouting.ts src/kabanmax/tabs/sections/tests/autoRouting.test.ts src/kabanmax/tabs/diagnostic/renderRouteForecast.ts
node ../scripts/generate-fingerprints.mjs --check
node node_modules/tsup/dist/cli-default.js src/main.ts
```

PASS **15 файлов / 120 тестов**, tsc, targeted lint, catalog check и LuCI bundle build. В bundle присутствует autoRouting; исходный bundle предварительно сохранён в ignored `before-ui/main.js`. Русский PO успешно скомпилирован:

```powershell
docker run --rm --network none --mount "type=bind,source=$taskRoot\luci-app-kabanmax\po\ru\kabanmax.po,target=/input.po,readonly" kabanmax-release:2.1.0 /usr/local/bin/po2lmo /input.po /tmp/task04b.lmo
```

### Что не получилось с первого раза

TDD/regression RED воспроизводились для отсутствующего core/UI модуля, перепутанного направления inbound Read/Write, shared no-progress между соединениями, clear/probe generation race, suppression после rename, дублирования suppression scope и недостаточного support masking. Исправлены и повторно проверены. Для immediate rollback сначала воспроизведён отсутствующий метод, затем добавлен regression позднего сбоя старой lease: замена сохраняется. На executable воспроизведено принятие постороннего DNS Answer owner; verifier теперь требует exact owner, qtype и IN class. Не использовать старые промежуточные SHA как итоговые.

Первый ARM64 build использовал неподдерживаемое `--arch aarch64`: исправлен на штатный `aarch64_generic`, оба binary-only build затем прошли. `npm run build` был остановлен Windows ExecutionPolicy на npm.ps1: политика не менялась, те же build-шаги выполнены напрямую через Node. Одна генерация сертификата без cached toolchain mount пыталась скачать toolchain в network-none и не прошла; повтор с существующими Go volumes прошёл, внешней загрузки не было. Ранее approval review временно упёрся в usage limit; после команды пользователя «продолжи» разрешённые offline проверки были повторены штатно.

Аппаратные PBR/NFQUEUE, реальная WARP registration/egress, роутерные RPC/UI и физический WAN address не проверялись. Подробные действующие ограничения — [№04Б](AUTO_ROUTING_IMPLEMENTATION_04B.md). Остальные результаты ниже относятся к прежним задачам и не выдаются за свежие.


## ТЗ №04 — безопасная часть, свежие проверки 2026-11-15

Реализован только read-only forecast, не авто-переключение. [Отчёт и препятствия](AUTO_ROUTING_DIAGNOSTICS_04.md). Один агент, синтетические данные; контейнеры `--network none`, исходники read-only. Ядро r10 и результаты №03 не пересобирались и не выдаются за свежие проверки №04.

Из корня KABANMAX, PowerShell:

```powershell
$taskRoot = (Get-Location).Path
docker run --rm --network none --mount "type=bind,source=$taskRoot\tests,target=/work/tests,readonly" --mount "type=bind,source=$taskRoot\kabanmax,target=/work/kabanmax,readonly" --mount "type=bind,source=$taskRoot\luci-app-kabanmax,target=/work/luci-app-kabanmax,readonly" --mount "type=bind,source=$taskRoot\scripts,target=/work/scripts,readonly" --mount "type=bind,source=$taskRoot\core,target=/work/core,readonly" -w /work forkop-zapret2-test-tools:local bash -c 'bash tests/run.sh diagnostics/ && bash tests/run.sh service/cli && bash tests/run.sh singbox/generator_pre_routing_resolve'
docker run --rm --network none --mount "type=bind,source=$taskRoot\luci-app-kabanmax\po\ru\kabanmax.po,target=/input.po,readonly" kabanmax-release:2.1.0 /usr/local/bin/po2lmo /input.po /tmp/task04.lmo
git diff --check
```

Результат backend: `0 of 9`, `0 of 1`, `0 of 1 test files failed` — **11 файлов passed**. Два новых файла содержат 11 test cases: ordered Block/Bypass/Zapret2, scope устройств и System, порты/range, IPv6, FakeIP, домены, unknown SRS/protocol/logical, лимиты/повторы, actual generator при disabled/all/selected pre-resolve, CLI custom config_path и отсутствие commands/commit. PO compilation exit 0. `git diff --check` exit 0 с предупреждениями CRLF→LF существующего dirty tree.

Из `fe-app-kabanmax`:

```powershell
node node_modules/vitest/vitest.mjs run src/kabanmax/tabs/diagnostic/tests/routeForecast.test.ts src/kabanmax/tabs/diagnostic/tests/renderRouteForecast.test.ts src/kabanmax/methods/shell/tests/diagnosticChecks.test.ts
node node_modules/typescript/bin/tsc --noEmit
node node_modules/eslint/bin/eslint.js src/kabanmax/tabs/diagnostic/routeForecast.ts src/kabanmax/tabs/diagnostic/renderRouteForecast.ts src/kabanmax/tabs/diagnostic/renderDiagnostic.ts src/kabanmax/tabs/diagnostic/tests/routeForecast.test.ts src/kabanmax/tabs/diagnostic/tests/renderRouteForecast.test.ts
```

Frontend: **3 файла / 10 тестов passed**, tsc и целевой lint exit 0. Проверены отдельные exec args без shell, ошибочный JSON/exec, unknown output, отсутствие verified, только явный click, блокировка одновременных click и вывод данных через textContent. Сборка bundle/пакетов и live LuCI не выполнялись.

Неудачные запуски сохранены как ограничения/исправления:

- Новый backend-тест до реализации: `No module named diagnostics.route_policy`, 1/1 failed. После реализации исправлен fixture `...null`, затем trailing-dot нормализация домена; новый regression для неполного inbound предотвращает ложное несовпадение при неизвестном источнике. Конечный прогон выше зелёный.
- Generated/CLI fixture сначала использовал неверное имя `sing_box_config_path`; исправлен на штатное `config_path`, production path helper не менялся.
- Vitest сначала не запускался из sandbox: esbuild получил Access denied к конфигурации; повторён с разрешённым локальным доступом. Затем до реализации ожидаемо failed на отсутствующем `routeForecast`. После реализации — passed.
- Первый tsc выявил типы DOM-атрибутов `maxlength`, числовые min/max и `aria-live`; исправлены на типизированные props / setAttribute, свежий tsc passed.
- Самостоятельный review выявил ложный прогноз при known-domain + unknown SRS и неизвестный IP System. Добавленные assertions сначала дали `expected unknown, got predicted`; исправлен консервативный matcher, повторён весь целевой backend-прогон. Независимый субагент-review не использовался по запрету пользователя.
- Первый общий прогон после review выявил избыточное unknown на служебном route-options: override_port ошибочно считался неизвестным matcher. Параметры override_address/override_port отделены при классификации opaque условий; совпавшее действие с override по-прежнему не симулируется. После исправления повторена указанная выше полная backend-команда: `0 of 9`, `0 of 1`, `0 of 1 test files failed`.
- Docker в sandbox не имел доступа к pipe/config; те же offline-команды выполнены с разрешённым локальным доступом. Внешняя сеть не включалась.

НЕ проверены и НЕ реализованы: active evidence transport, автоматическое обнаружение сбоя приложения, proposals/apply, managed IP-списки, suppression, TTL/rollback/reboot автоматики. Нет реальных адресов/VPS/сервисов, роутеров, установки, коммитов и публикации. Матрица следующих проверок — в отчёте №04 и одобренном design.

## ТЗ №03 — свежие локальные проверки r10, 2026-11-15

Источник: pinned commit + все пять patches, Go 1.26.10. Production-код/patches не менялись. [Отчёт, SHA256, lifecycle и аппаратная матрица](LIFECYCLE_FALLBACK_03.md). Все Docker-вызовы с `--network none`; localhost mock-сервисы не являются внешней сетью.

Из корня репозитория, общая функция для точного повторения core-команд:

```powershell
$taskRoot=(Get-Location).Path
New-Item -ItemType Directory -Force .local/audit/r10-03 | Out-Null
function Invoke-R10Core($runner) {
  docker run --rm --network none --mount "type=bind,source=$taskRoot\.local\core-src,target=/source,readonly" --mount "type=bind,source=$taskRoot\core,target=/core,readonly" --mount "type=bind,source=$taskRoot\scripts,target=/scripts,readonly" --mount "type=bind,source=$taskRoot\tests\core,target=/extra-tests,readonly" --mount "type=bind,source=$taskRoot\shared,target=/shared,readonly" --mount "type=bind,source=$taskRoot\.local\audit\dns-policy,target=/fixtures,readonly" --mount "type=bind,source=$taskRoot\.local\audit\r10-03,target=/output" --mount type=volume,source=kabanmax-chrome155-go-mod,target=/go/pkg/mod --mount type=volume,source=kabanmax-chrome155-go-build,target=/go/build -e GOMODCACHE=/go/pkg/mod -e GOTOOLCHAIN=go1.26.10 -e GOCACHE=/go/build kabanmax-release:2.1.0 sh "/extra-tests/$runner"
  if ($LASTEXITCODE -ne 0) { throw "r10 runner failed: $runner" }
}
Invoke-R10Core run_startup_dns_devices.sh
Invoke-R10Core run_dns_policy.sh
Invoke-R10Core run_editor_reload.sh
Invoke-R10Core run_r10_review.sh
Invoke-R10Core run_fingerprints.sh
Invoke-R10Core run_lifecycle_cold.sh
```

Все runners завершились с кодом 0, каждый применяет patches к чистому archive. Используется `go test -count=1 -race -p=2`; точные tags/фильтры находятся в runner-файлах.

| Runner | Свежий результат пакетов |
| --- | --- |
| startup_dns_devices | route 1.073s; route/rule 2.196s |
| dns_policy | dns 1.317s; cmd/sing-box 1.433s |
| editor_reload | cmd/sing-box 1.239s; protocol/group 1.459s |
| r10_review | полный protocol/group 6.609s; experimental/cachefile 2.764s; обе base binary-only сборки passed |
| fingerprints | common/tls 1.202s; protocol/parser 1.028s |
| lifecycle_cold | cmd/sing-box 2.178s; dns/transport/fakeip 20.321s; experimental/clashapi 2.223s; common/urltest 1.588s; parser/subscription 1.019s; локальные common/tlsfragment 1.055s |

Новые тесты проверяют сохранённый/удалённый/повреждённый cache, удалённого участника, unpin, отдельное восстановление внешнего selector и Fallback.Fixed. `TestLifecycleSelectorInterrupt` проверяет оба значения опции на внешнем зарегистрированном соединении. Loopback TCP Fallback/reload regressions №01 повторены с patches r10; rename/delete/URI не переделывались.

Сам собранный executable проверен так:

```powershell
docker run --rm --network none --mount "type=bind,source=$taskRoot\.local\audit\r10-03,target=/output,readonly" --mount "type=bind,source=$taskRoot\tests\core,target=/extra-tests,readonly" --mount "type=bind,source=$taskRoot\.local\audit\dns-policy,target=/fixtures,readonly" kabanmax-release:2.1.0 python3 /extra-tests/r10_binary_smoke.py /output/build/amd64/base/sing-box
```

Код 0: пять PASS-строк — generated mixed DNS/FakeIP + graceful disk-cache restart, resolved-isolation, resolved-control, missing-provider, direct-control. Положительные контроли подтверждают доступность настоящего loopback listener; защищённые случаи до него не доходят. ARM64 только кросс-собран, не запускался. Build tags/version/размеры/SHA256 записаны в `.local/audit/r10-03/build.log` и отчёте №03. APK/IPK/tiny/full не собирались, `dist` и r9 не монтировались в контейнер.

Backend:

```powershell
docker run --rm --network none --mount "type=bind,source=$taskRoot\tests,target=/work/tests,readonly" --mount "type=bind,source=$taskRoot\kabanmax,target=/work/kabanmax,readonly" --mount "type=bind,source=$taskRoot\luci-app-kabanmax,target=/work/luci-app-kabanmax,readonly" --mount "type=bind,source=$taskRoot\scripts,target=/work/scripts,readonly" --mount "type=bind,source=$taskRoot\core,target=/work/core,readonly" -w /work forkop-zapret2-test-tools:local bash -c 'for f in singbox/ nft/ config/validator_requirements service/lifecycle service/initd diagnostics/; do bash tests/run.sh "$f" || exit; done'
```

Код 0, **39/39 файлов** (`27+2+1+1+1+7`). Проверяются r10 requirements/r9 outdated, generated groups/DNS/routes, invalid/no-op/changed config, provider pending и capture pause/readiness. Это конфигурационные и fake-system tests, не kernel nft.

Повторный экспорт актуального backend:

```powershell
New-Item -ItemType Directory -Force .local/audit/r10-03/fixtures | Out-Null
docker run --rm --network none --mount "type=bind,source=$taskRoot\tests,target=/work/tests,readonly" --mount "type=bind,source=$taskRoot\kabanmax,target=/work/kabanmax,readonly" --mount "type=bind,source=$taskRoot\.local\audit\r10-03\fixtures,target=/fixtures" -e KABANMAX_DNS_FIXTURES=/fixtures -w /work/tests forkop-zapret2-test-tools:local ucode -L fakes -L lib -L ../kabanmax/files/usr/lib singbox/export_dns_policy.uc
```

8 fixtures, код 0. Сравнение `Name,Hash` через `Get-FileHash` и `Compare-Object` с проверенными `/fixtures` дало пустой diff: byte-identical. Будущий запуск можно направить на этот новый каталог. `git diff --check` прошёл; CRLF→LF warnings не являются ошибками.

Первый build runner завершился 128 до компиляции: `require_lf_checkout` upstream вызывает `git ls-files` даже для archive. Временный `git init` + индекс Go-файлов внутри контейнера удовлетворяет проверку без коммита; повторная сборка прошла. Первое обращение к Docker было ограничено sandbox; последующие offline вызовы выполнены со штатным разрешением. Эти неудачные вызовы не считаются прошедшими проверками.

Расширенный прогон `common/tlsfragment` выявил **три** внешних upstream-теста `TestTLSFragment`, `TestTLSRecordFragment`, `TestTLS2Fragment`: они пытаются dial `1.1.1.1:443` и завершились `network is unreachable` при `--network none`. Сеть не включалась, production не менялся. Runner явно выбирает остальные локальные проверки (`TestClientHelloRecord|TestFragment|TestIndex|TestIntegrationWait`); внешние TLS-тесты остаются непроверенными. Этот неудачный полный пакетный запуск не выдаётся за зелёный.

Не выполнялись: frontend full suite/build (production UI не менялся), live nft/conntrack/PBR/mwan3/роутеры/VPS, power-loss, настоящий reboot, ARM64 runtime, установка и публикация. Полная полевая матрица — в отчёте №03.

## ТЗ №02 — свежие локальные проверки 2026-11-15

Один агент, без сетевого доступа контейнеров, роутеров/VPS, релизной сборки, установки и публикации. Состояние №01 сохранено. Источник core: `core/UPSTREAM`, прежний commit `60d96c99815a672712915a5c00114bf0f690ad80`, локальный package/minimum `1.14.4-r10`, **все пять patches**. Runners получают чистое дерево через `git archive` и применяют patches по имени; dirty `.local/core-src` служит только read-only источником Git-объектов. Подробная матрица и ограничения — [ТЗ №02](STARTUP_DNS_DEVICES_02.md).

### Backend

```powershell
$taskRoot=(Get-Location).Path
docker run --rm --network none --mount "type=bind,source=$taskRoot\tests,target=/work/tests,readonly" --mount "type=bind,source=$taskRoot\kabanmax,target=/work/kabanmax,readonly" --mount "type=bind,source=$taskRoot\luci-app-kabanmax,target=/work/luci-app-kabanmax,readonly" --mount "type=bind,source=$taskRoot\scripts,target=/work/scripts,readonly" --mount "type=bind,source=$taskRoot\core,target=/work/core,readonly" -w /work forkop-zapret2-test-tools:local bash -c 'for f in singbox/ nft/ config/rule config/validator_runtime config/validator_requirements service/lifecycle diagnostics/; do bash tests/run.sh "$f" || exit; done'
```

Итоговые целевые проверки: **40 backend-файлов passed** — `27 + 2 + 1 + 1 + 1 + 1 + 7`. Последний общий запуск прошёл первые 33 файла и выявил устаревшее ожидание r9 в `diagnostics/checks.test.uc`; после обновления fixture и явной проверки `r9.outdated=true` отдельно повторён `bash tests/run.sh diagnostics/` в том же контейнере: **0 of 7 failed**. Это совокупность свежих целевых прогонов, не один полностью зелёный общий запуск.

Регрессии: option/list local zones, `.lan/home.arpa/internal/PTR`, приоритет перед Bypass DNS, marks со сторонними битами и исключения, source/System/IPv4/IPv6/невалидные устройства/пауза, pending capture и атомарное снятие, валидный domain-only provider, повторное включение guards при core reload и no-op, r10 minimum. Старые nft ожидания обновлены только для OR-marks, новых pending sets и готовности domain-only providers. Исправления №01 остаются в singbox/nft regression coverage.

### Generated fixtures и core

```powershell
New-Item -ItemType Directory -Force .local/audit/dns-policy | Out-Null
$taskRoot=(Get-Location).Path
docker run --rm --network none --mount "type=bind,source=$taskRoot\tests,target=/work/tests,readonly" --mount "type=bind,source=$taskRoot\kabanmax,target=/work/kabanmax,readonly" --mount "type=bind,source=$taskRoot\.local\audit\dns-policy,target=/fixtures" -e KABANMAX_DNS_FIXTURES=/fixtures -w /work/tests forkop-zapret2-test-tools:local ucode -L fakes -L lib -L ../kabanmax/files/usr/lib singbox/export_dns_policy.uc

function Invoke-StartupCore($runner) {
    docker run --rm --network none --mount "type=bind,source=$taskRoot\.local\core-src,target=/source,readonly" --mount "type=bind,source=$taskRoot\core,target=/core,readonly" --mount "type=bind,source=$taskRoot\tests\core,target=/extra-tests,readonly" --mount "type=bind,source=$taskRoot\.local\audit\dns-policy,target=/fixtures,readonly" --mount type=volume,source=kabanmax-chrome155-go-mod,target=/go/pkg/mod --mount type=volume,source=kabanmax-chrome155-go-build,target=/go/build -e GOMODCACHE=/go/pkg/mod -e GOTOOLCHAIN=go1.26.10 -e GOCACHE=/go/build kabanmax-release:2.1.0 sh "/extra-tests/$runner"
}
Invoke-StartupCore run_startup_dns_devices.sh
Invoke-StartupCore run_dns_policy.sh
```

Экспортированы восемь fixtures; оба runner завершились с кодом 0. Свежие `go test -count=1 -race` без test cache: `route` **1.149s**, `route/rule` **2.277s**, `dns` **1.331s**, `cmd/sing-box` **1.413s**. DNS/cmd повторены после добавления настоящего FakeIP integration test. Точные build tags и фильтры зафиксированы в runner-файлах. Проверены новые `TestKabanmaxMixedResolvedRoute`, `TestKabanmaxMixedGeneratedRoutes`, `TestKabanmaxUnavailableRouteRejectsOnlyItsDevices`, `TestKabanmaxUnavailableSetDoesNotDisappear`, `TestKabanmaxGeneratedDNSMixedAnswers`, `TestKabanmaxGeneratedDNSMixedRealFakeIP`, а также прежние DNS/dial и pinned remote-set tests. Mixed DNS использует шесть режимов (`policy/srs-only/priority/detour-off/resolve-all/resolve-selected`) и девять последовательных наборов адресов, включая пустой, полностью совпавший, частично совпавший и A+AAAA.

Generated route walker выполняет реальные `resolve` actions с синтетическим `Lookup`, включая отказ DNS, и проверяет отдельные реальные адреса/смешанные resolved-кандидаты, source scope и порядок. DNS walker отключает DNS-кэш для получения нового ответа на каждой итерации. Отдельные существующие loopback DNS/SOCKS dialer-тесты №01 повторены уже со всеми patches r10, включая отказ VPN/детура и отсутствие пользовательского DNS на bootstrap. Дополнительно настоящий Box/FakeIP transport/store и UDP `source-dns-in` с локальным TCP DNS upstream вернули адрес `198.18.0.0/16` для смешанного реального ответа. В этом тесте заменены source-адреса на loopback, привилегированные socket options и SRS на synthetic inline; detour выключен. Mock Lookup, реальный FakeIP и loopback dialer — разные уровни проверки, не packet-level стенд nft/TPROXY.

Форматирование выполнено `gofmt -w` для четырёх новых Go-тестов. Новые patches проверены последовательным применением к чистому pinned дереву в обоих runner; patch 0005 дополнительно отформатирован `gofmt` перед повторным экспортом. Рабочий `.local/core-src` не редактировался.

### Frontend и diff

Из `fe-app-kabanmax`:

```powershell
node node_modules/vitest/vitest.mjs run src/kabanmax/tabs/sections/tests/makeDeviceOptionsExclusive.test.ts src/kabanmax/tabs/sections/tests/configureSectionSection.test.ts src/kabanmax/tabs/sections/tests/validators.test.ts
```

**3 файла / 11 тестов passed.** Frontend production-код №02 не менялся; полный frontend suite/build не запускался. `git diff --check` завершился с кодом 0; сообщения CRLF→LF — предупреждения Git, не ошибки whitespace.

### Воспроизведения и неудачные запуски

- До исправлений новые ucode-регрессии падали на `.home.arpa` и `meta mark != 0`; отдельно воспроизведён неправильный приоритет explicit local zone относительно доменного Bypass.
- На прежнем core mixed A и A+AAAA оставались в Direct dial-списке целиком. Нужный результат проверялся до patch 0003 и получен после него. Ужесточённый mixed DNS-тест отдельно падал на выдаче реального неоднородного ответа до защиты FakeIP.
- Missing provider давал false в matcher и позволял нижний маршрут. Регрессия падала до patch 0004; дополнительный logical device-тест обнаружил потерю флага между дочерними условиями, поэтому флаг сбрасывается на границе route-проверки, не в `ResetRuleCache()`.
- Неполные тестовые фикстуры исправлены: пропущенный `t.done()`, отсутствующий tag inline set, A как 16-byte mapped адрес и AAAA с nil после ошибочного `To4()`. Их ранние результаты не считаются доказательствами прохождения сценариев. CRLF в новом shell runner вызывал `\r: not found` уже после Go-тестов; runner переведён в LF.
- После r10 диагностическая fixture первоначально ожидала, что r9 актуален. Новая проверка binary replacement использует новый inode: запись другого same-size содержимого в тот же файл за одну секунду закономерно попадала в stat-cache features, что не моделирует замену бинарника пакетом.
- Первые Docker/frontend вызовы ограничивались sandbox; выполнены после штатного разрешения локального доступа. Один последующий Docker-запуск не состоялся из-за сбоя automatic approval review по usage limit. После команды пользователя «продолжай» штатный повтор разрешения прошёл; этот отказ не обходился и не считается тестом.

Не выполнялись: настоящий nft kernel/conntrack/flow offload стенд, live mwan3/PBR/корпоративный VPN, полевые DNS/VPN протоколы, reboot/persistent/optimistic cache приёмка, сборка APK/IPK/ARM64 r10 и полная финальная приёмка. Для №03 см. тематический документ.

## DNS / UCI / GeoIP ? 2026-11-15 (????????, ?? ????????? ???????)

???????? [????? ? ??](audits/README.md) ????????? ??? ?????????; SHA-256 ????? ????? ?????? ? ??????????? (`Get-FileHash -Algorithm SHA256`). ??????????? ?????? ?? upstream ?? ??????????????? ?? ????. ??????????? ???????? ????: `core/UPSTREAM` commit `60d96c99815a672712915a5c00114bf0f690ad80`, package `1.14.4-r9`, Go `1.26.10`, ??????? patches; production Go-??? ?? ???????.

### ??????????????? ? backend

?? ??????????? `bash tests/run.sh singbox/paths`: `1 of 1 test files failed`, ????? ?????????????? path helper. ????? `generator_dns_policy`: ??? ???????? failed ? ????? resolver ??? bootstrap ?????? ????????? DNS, response evaluate ????????????. ????? ??????????? ??? ????? passed. ?????? expectations DNS ????????? ?? ????? ?????????? query ? response: ??? ?????? ?? ??????????, ??? query ??? ?????? ????????? IP-??????? SRS.

??????? ?? ????? ??????? (?????????, Docker ??? ????, ????????? read-only):

```powershell
$taskRoot=(Get-Location).Path
docker run --rm --network none --mount "type=bind,source=$taskRoot\tests,target=/work/tests,readonly" --mount "type=bind,source=$taskRoot\kabanmax,target=/work/kabanmax,readonly" --mount "type=bind,source=$taskRoot\luci-app-kabanmax,target=/work/luci-app-kabanmax,readonly" --mount "type=bind,source=$taskRoot\scripts,target=/work/scripts,readonly" --mount "type=bind,source=$taskRoot\core,target=/work/core,readonly" -w /work forkop-zapret2-test-tools:local bash -c 'for f in singbox/ nft/ruleset_sync config/migration config/validator_runtime service/lifecycle diagnostics/; do bash tests/run.sh "$f" || exit; done'
```

?????????: ?? ??????? `0 of 26`, `0 of 1`, `0 of 2`, `0 of 1`, `0 of 1`, `0 of 7 test files failed`, ????? **38 ??????? ?????? passed**. ????? ???????? ???????? ???????? ?????? runtime-????? ????????????? ????????? `bash tests/run.sh singbox/runtime` ? ??? ?? offline backend-?????????? ? read-only `tests`/`kabanmax`: `0 of 1 test files failed`. Runtime default-path regression ????????? ?????? `/etc/sing-box/config.json` ? ???????? `/tmp/sing-box`, ?? ??????? ????????? ???????? ??????? ????????? ?????.

????????: ?????????????/??????/default/custom config/cache paths, ???????? ? ????????? no-op save; ?????? ???? ?????? ? JSON. DNS detour on/off, DNS endpoint ?? IP/?????, ?????????? raw resolver ? ?????? subscription override, ????????? IPv6/System source variants, port-limited Bypass. WARP API ? ?????????? DNS ????? ??? ?? WARP ?????????? ????????? ???????????????? dialer, ?? ????? ???????????? ??????. nft sync regression ???????????? ??????????? provider tags/IPv4/IPv6 ? route matcher ??? Telegram, Discord, WhatsApp, Facebook/Instagram, mixed SRS, IPv6-only ? inline IP-literal; domain-only Meta-?????? ?? ??????? ????????? IP-????????. Production nft ?? ???????.

### ?????? ???? ? ???????? loopback dialer

??????? ?????????????? synthetic fixtures ?? ????????? ucode generator:

```powershell
New-Item -ItemType Directory -Force .local/audit/dns-policy | Out-Null
$taskRoot=(Get-Location).Path
docker run --rm --network none --mount "type=bind,source=$taskRoot\tests,target=/work/tests,readonly" --mount "type=bind,source=$taskRoot\kabanmax,target=/work/kabanmax,readonly" --mount "type=bind,source=$taskRoot\.local\audit\dns-policy,target=/fixtures" -e KABANMAX_DNS_FIXTURES=/fixtures -w /work/tests forkop-zapret2-test-tools:local ucode -L fakes -L lib -L ../kabanmax/files/usr/lib singbox/export_dns_policy.uc
```

?????:

```powershell
$taskRoot=(Get-Location).Path
docker run --rm --network none --mount "type=bind,source=$taskRoot\.local\core-src,target=/source,readonly" --mount "type=bind,source=$taskRoot\core,target=/core,readonly" --mount "type=bind,source=$taskRoot\tests\core,target=/extra-tests,readonly" --mount "type=bind,source=$taskRoot\.local\audit\dns-policy,target=/fixtures,readonly" --mount type=volume,source=kabanmax-chrome155-go-mod,target=/go/pkg/mod --mount type=volume,source=kabanmax-chrome155-go-build,target=/go/build -e GOMODCACHE=/go/pkg/mod -e GOTOOLCHAIN=go1.26.10 -e GOCACHE=/go/build kabanmax-release:2.1.0 sh /extra-tests/run_dns_policy.sh
```

Runner ????????? ?????? UPSTREAM commit ????? `git archive`, ????????? patches ?????? ? ????????? ????????, ???????? ?????? ????? ?????. `GOPROXY=off go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn -run 'TestKabanmaxGeneratedDNS|TestDomainOnlyRuleTakesSubnetOnlyRuleSet' ./dns ./cmd/sing-box`.

?????? ????????? ????? ?????????? ??????? VPN: `dns` passed **1.166s**, `cmd/sing-box` passed **1.345s**, ??? test result cache. 13 ????????? DNS-?????????: inline ? IP-only/mixed SRS, IPv4/IPv6, ??????????/??????, ?????? ??????, ????? ??????? ??????, ???????? ???????????, local zone, detour off; ???????? ???????????? ???????? DNS ? existing domain-only core regression. DNS walker ?????????? mock transports ? ?????? ????????? ??????????. Inline synthetic rule sets ???????? ?????????? SRS; ??? ?? ???????? ????????? community-???????.

9 loopback-????????? `cmd/sing-box` ??????? ? ????????? Box ?? generated JSON, ??????? ?????? ???????? transport addresses, ????????? SRS ? ???????? listeners/experimental. ???????? TCP DNS ? SOCKS5: ?????? ??????/????????? ????????, detour on/off, DNS endpoint ?? ?????/IPv4/IPv6. ??????????? bootstrap ?????? ???????? IP ??????? ???????, ?? lookup ????????????????? ?????????? ???? ? ????????? DNS. ????? ???????? SOCKS listener ? ??????????? ??????? ????? protected dial ? ????? DNS lookup ??????????? ???????, ?? ?????? Direct/bootstrap. Fake SOCKS ?????? ????????? ?????? loopback; ??????? ???? ???????????. ??? ???????? ??????? ???????????? ? ????????? dialer, ?? packet-level TPROXY/nft ?????.

????? ???????????????? ????? ????????? backend-??????? ???? ? ?????? `for f in singbox/generator_dns singbox/generator_providers singbox/runtime; do bash tests/run.sh "$f" || exit; done`: `0 of 2`, `0 of 1`, `0 of 1 test files failed`. ??????? default-???? ?????????? runtime ?????? ? ???????? ??????? native download default ??? ??????????? ?????????? DNS detour. ???????? ?????????????? ??? 6 fixtures; `Get-FileHash -Algorithm SHA256` + `Compare-Object -Property Path,Hash` ??????????? ?????????? ???????????? ??? ??????????? core-????????, ??????? core-????? ?? ??????????? ??? ????????? ?? ??????. ??????????? ????? ?????????? ?? ??????????? ?? ??????? ?????????? ???????????? ???????? ????? ???????.

??????????? `gofmt` ???????? ?????? ? ???? ????? Go-??????. `git diff --check` passed (?????????????? CRLF ? LF ?? ???????? ????????). Frontend ? ??? generated bundle ?? ???????? ???? ???????, frontend build/full suite ?? ???????????.

### ????????? ??????? ? ??????? ?????????????

- Docker initially ?? ??? ???????? ?? sandbox; ??????????? ????????? ?????? ???? ?? offline-?????????? ??????. ??? ??????????? ?????????, ?? ?????? ????????.
- ? ?????? bash-????? PowerShell ??????? `$f` ?? ??????? ???????: ?????? ?????? ???????? ???????? 86 backend-??????. Packaging/program_modes ????? ??? ???????? mounted repository (? ????????? ???????????? ???????? build.sh). ???? ?????? ?? ????????? ?????? ???????? ??? ??????????????? ???????? ???????????. ?????????? quoting, ?????????? ??????? ?????? ???????????.
- Fixture ? UCI `null` ??????????? ? ?????? `null`, ? ?? ????????????? ?????; missing-case ????????? ????????? ?????. ?????? ???????? lower FakeIP ???????? ???????????? ?????? fully_routed_ips: ???????? ????? ???????? matcher ??????. ??? ?????? ????? fixtures, ?? ?????????????? ??????? ????????.
- ????????? native ????????? ????????????? resolver ? raw resolver. Provider bootstrap ?????????? ????? ???????????? managed merge patch: ????? `override_patch.domain_resolver` ??????????, ?? ???? ?? ???????????????? JSON ??? ???????????? patch ??????????. ??? ?????????? ?????? ?????? ?????? ??? ???? ? patch ????????; ????????? default-???? core ?? ?????????.
- `match_response` ???????????? ????? IP ? `respond` ?????????? ???? DNS-?????. ?????????? ????????? RR ? ????????? ?????? ? IP ???????????? ??????/??? Bypass ?? ????????? ????????? packet-route ???????; ??? ???????????? follow-up ?? ????????? ?? ?????????? ? ????? ?????????. Domain-only SRS ????? ????? ????????? ? ?????????????? evaluate-???????? ????? ????????? ???????, ????????? generator ?? ????? ?????????? ?????????? ??????.
- ???????????? ????? resolver/?????? ???????????? ????? ??????? ??????????? ????; ????????????? ???????? ???????????????? DNS dependency graphs ?? ???????????. Bootstrap ???????? ????????? ?????????????, ??????? ?????? UDP:53; ??? ???????????????? ?????? ?? ?????????? ??????????? ?? ?????? ?????????? ?????.
- ???????? ?????????, ??????????/??????? UDP:53, DoH/DoT TLS, cold boot ?? WR3000S/U ? ??? ???? ???????? ? ??????? ???? ??????? ?????????? ???????????? ?????. ????/patches ?? ????????; ???????? ??????, ???????, ????????? ? ?????????? ?? ???????????.

## Задачи №2/3/4: WARP и Save & Apply — 2026-11-15

Цепочки событий:

- Save & Apply: LuCI штатно сохраняет UCI → procd `on_config_change` → `initd.reload`/lock → validate → build nft → `runtime.write_config(false)`/core check только изменённого JSON → сравнение → при изменении JSON capture pause/drop → SIGHUP Close/Create → readiness → capture resume. No-op сохраняет core. Ручной reload и interface-up намеренно forced; не путать их с Save.
- Cold start: validate/build/check → запуск core → WARP post-start goroutine → валидный кэш либо API через `profile.detour` → WireGuard. Готовность портов core не означает готовность каждого WARP. На reboot штатный `/tmp` кэш отсутствует; регистрационные id/token/key не содержат адресов/peer. Временные ошибки API уже повторяются с backoff 5–60s до успеха/отмены endpoint; никаких новых циклов/задержек не добавлено.
- Первое/повторное сохранение: native поля UCI → `connections.tunnel_endpoint` → profile/amnezia → JSON → та же apply-цепочка. Смена обфускации вызывает общий reload; восстановление после него само по себе не доказывает дефект обфускации.

Подтверждены два дефекта: без API detour `protocol/warp.createConfig` выбирает стандартный HTTP transport без core mark (nft `mangle_output` может захватить его обратно), а условие `endpoint.profile != null` оставляло автоматическую регистрацию вне выбранной секции. Исправлен только native generator: всегда задаёт профиль и API detour секции/`direct-out`. Каскад не меняется; raw JSON не переписывается. Новый `generator_warp_stability` сначала отказал в трёх случаях из четырёх: прямой API с/без credentials и API через секцию без credentials; после исправления passed. Непосредственный kernel packet loop на роутере не воспроизводился: локальное доказательство — конфигурационный контракт + исходники transport/nft, не полный сетевой стенд.

Backend, из корня (Docker без сети, все входы read-only):

```powershell
$taskRoot = (Get-Location).Path
foreach ($taskFilter in @('singbox/generator_warp_stability', 'singbox/generator_runtime', 'singbox/runtime', 'service/lifecycle', 'service/initd', 'nft/apply')) {
  docker run --rm --network none --mount "type=bind,source=$taskRoot\tests,target=/work/tests,readonly" --mount "type=bind,source=$taskRoot\kabanmax,target=/work/kabanmax,readonly" --mount "type=bind,source=$taskRoot\luci-app-kabanmax,target=/work/luci-app-kabanmax,readonly" --mount "type=bind,source=$taskRoot\scripts,target=/work/scripts,readonly" --mount "type=bind,source=$taskRoot\core,target=/work/core,readonly" -w /work forkop-zapret2-test-tools:local bash tests/run.sh $taskFilter
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

Каждый из шести файлов passed (`0 of 1 test files failed`). Добавленный runtime-сценарий проверяет первый WARP JSON с односторонней обфускацией, byte-stable no-op, правки мониторинга/отключённой секции без reload и реальное изменение `i1` с первого применения. Lifecycle покрывает config no-op, pending, отказ валидации и capture pause/resume, nft — drop маркированного защищённого трафика во время паузы. Изменение другой активной секции, которое меняет общий JSON, по-прежнему пересоздаёт весь core: сохранение неизменённого endpoint не реализовано, это техническое ограничение текущего reload. Это не доказательство отсутствия всех возможных утечек на устройстве.

Frontend из `fe-app-kabanmax`:

```powershell
npm.cmd test -- --run tests/bundle/warpProfile.test.js src/kabanmax/tabs/sections/tunnels/tests/model.test.ts src/kabanmax/tabs/sections/tunnels/tests/validate.test.ts src/kabanmax/tabs/sections/tunnels/tests/warpGenerate.test.ts --maxWorkers=2
```

4 файла / 33 теста passed. Сериализация профиля и обфускации, генерация и UI error handling; отдельный дефект обфускации не воспроизведён. Frontend не менялся, build/lint не запускались.

Core, из корня, чистый Git archive UPSTREAM + текущие patches, без внешней сети:

```powershell
$taskRoot = (Get-Location).Path
docker run --rm --network none --mount "type=bind,source=$taskRoot\.local\core-src,target=/source,readonly" --mount "type=bind,source=$taskRoot\core,target=/core,readonly" --mount "type=bind,source=$taskRoot\tests\core,target=/extra-tests,readonly" --mount type=volume,source=kabanmax-chrome155-go-mod,target=/go/pkg/mod --mount type=volume,source=kabanmax-chrome155-go-build,target=/go/build -e GOMODCACHE=/go/pkg/mod -e GOTOOLCHAIN=go1.26.10 -e GOCACHE=/go/build kabanmax-release:2.1.0 sh /extra-tests/run_warp_stability.sh
```

`go test -count=1 -race -p=2` с точными tags/именами из runner: protocol/warp passed (1.084s), common/cloudflare passed (1.017s). Новые тесты доказывают использование явного outbound при регистрации и чтении профиля и независимость второго профиля от зависшего первого. Существующие тесты проверяют временный TLS timeout → невалидный ответ → успех без пересоздания endpoint, немедленный отказ dial при неготовности, отмену retries при close, cache identity, validation, сохранение auth token и формат регистрации. Cache hit/валидация/отсутствие fetch при валидном кэше подтверждены чтением `startHandler`, не отдельным сквозным тестом reboot. Само ядро/patches не изменялись.

Неудачные запуски: Docker/esbuild сначала упёрлись в sandbox ACL; повтор с разрешением локального запуска прошёл. Первый тест двух профилей ошибочно имел одинаковый синтетический ключ — штатная защита генератора его отвергла; исправлены независимые fixtures. Новый runtime-тест сначала вызвал ещё не объявленный ucode helper — helper перенесён выше теста, повтор passed. Первый core-фильтр пропустил Cloudflare-тесты (`no tests to run`); итоговый runner включает их точные имена и оба пакета проверены свежим запуском. Попытка фильтра `config/connections` дала `0 of 0`: проверкой не считается. `git diff --check` passed (имеется прежнее предупреждение CRLF в README).

Будущая приёмка WR3000S/WR3000U, только по отдельному разрешению и с тестовым клиентом:

1. Сохранить приватно исходную конфигурацию/способ отката, не публиковать URI/token/IP/логи целиком. Проверить WAN, DNS, синхронизацию времени. Создать два независимых тестовых WARP-профиля; не клонировать один WireGuard key для разных настроек одного сервера.
2. На установившейся тестовой сессии выполнить Save без правок дважды и правку мониторинга/отключённой секции: сравнить хеш JSON, PID и число reload/новых API fetch, проверить непрерывность сессии. При реальном изменении активной секции ожидается общий reload/переподключение, а не обещание сохранения потока.
3. На тестовом туннеле изменить допустимый `i1` один раз, применить, проверить новое значение JSON и работу нового подключения без второго Save. API detour и транспортный каскад должны оставаться раздельными.
4. Холодная загрузка и restart: два профиля с выбранной независимой рабочей секцией API, затем сценарий без неё (прямой API); проверить profile route, readiness каждого endpoint и отсутствие повторной регистрации при валидном RAM-кэше после restart. После reboot API-fetch ожидаем, кэш `/tmp` исчезает.
5. На изолированном стенде временно сделать API недоступным только для теста, восстановить доступ: проверить backoff и восстановление обоих endpoint без Save, отмену ожидания при stop. Не блокировать общую сеть работающего устройства.
6. В период неготовности VPN и reload использовать нейтральный согласованный контрольный адрес и проверить отсутствие прямого выхода защищённого тестового клиента; сверить nft capture/drop и policy routing. Не использовать российские сервисы, реальные VPS или нагрузочный трафик. Live kill-switch/WAN/NTP/провайдерские блокировки локально не пройдены.

Передача следующему чату: применён минимальный фикс двух API-route дефектов, no-op/обфускация проверены локально; полевые причины всех timeout и сохранение endpoint при значимом reload остаются открытыми. Постоянный cache на flash не вводился. `AGENTS.md` проверен, менять инструкции не потребовалось; `docs/AI_HANDOFF.md` отсутствует и не создавался. Релизная сборка, пакеты, установка, коммит/push и публикация не выполнялись.

## Дополнение №12: каталог uTLS — 2026-11-15

Frontend из `fe-app-kabanmax`:

```powershell
npm.cmd test -- --run tests/bundle/connectionLinks.test.js src/kabanmax/tabs/sections/tests/connectionUri.test.ts src/kabanmax/tabs/sections/tests/tlsFingerprints.test.ts tests/bundle/optionLifecycle.test.js tests/bundle/dialogTitles.test.js tests/coreFeatures.test.js tests/bundle/coreFeatures.test.js --maxWorkers=2
npm.cmd run build
node node_modules/eslint/bin/eslint.js src/kabanmax/services/tlsFingerprints.ts src/kabanmax/services/coreFeatures.service.ts src/kabanmax/tabs/sections/fingerprintOptions.ts src/kabanmax/tabs/sections/links.ts src/kabanmax/tabs/sections/connectionEditor.ts src/kabanmax/tabs/sections/connectionUri.ts src/kabanmax/tabs/sections/tests/tlsFingerprints.test.ts src/kabanmax/tabs/servers/form/security.ts src/kabanmax/tabs/servers/constants.ts tests/bundle/connectionLinks.test.js
```

Результат: 7 файлов / 187 тестов passed; catalog `--check`, TypeScript/tsup и ESLint passed. Сценарии: семейство Chrome → 133/155, наследование снимает override, экспорт эффективного `fp`, URI и ID не меняются, старый алиас не появляется новым пунктом и не переписывается при no-op, Randomized/QQ/360, запреты без uTLS/TLS и на QUIC. Единственный источник IDs — `shared/tls-fingerprints.json`; при изменении выполнить `node scripts/generate-fingerprints.mjs` из корня. Build проверяет generated ucode.

Backend: та же Docker-команда из раздела редактора VPN ниже с `tests/run.sh` и фильтрами `config/validator_fingerprint`, `singbox/generator_tags`, `singbox/features`: каждый из трёх файлов passed. Новый red/green тест сначала воспроизвёл отказ backend принимать поддерживаемые каталогом IDs, затем прошёл после перехода на каталог. Проверен также REALITY, выведенный из `pbk` при `security=tls`: Android/360 отказываются, Randomized принимается. Компиляция перевода той же `po2lmo` командой ниже в `/tmp/task12.lmo`: passed.

Реальное ядро и uTLS, без внешней сети:

```powershell
$repoRoot = (Get-Location).Path
docker run --rm --network none --mount "type=bind,source=$repoRoot\.local\core-src,target=/source,readonly" --mount "type=bind,source=$repoRoot\core,target=/core,readonly" --mount "type=bind,source=$repoRoot\shared,target=/shared,readonly" --mount "type=bind,source=$repoRoot\tests\core,target=/extra-tests,readonly" --mount type=volume,source=kabanmax-chrome155-go-mod,target=/go/pkg/mod --mount type=volume,source=kabanmax-chrome155-go-build,target=/go/build -e GOMODCACHE=/go/pkg/mod -e GOTOOLCHAIN=go1.26.10 -e GOCACHE=/go/build kabanmax-release:2.1.0 sh /extra-tests/run_fingerprints.sh
```

Runner использует чистый Git archive закреплённого UPSTREAM, текущие patches, `go test -count=1 -race` и только целевые common/tls + protocol/parser тесты. Результат: common/tls passed (1.176s), protocol/parser passed (1.024s). Все 16 входных IDs прошли построение настоящего ClientHello, сверку ClientHelloID/версии/алиасов, TLS handshake через net.Pipe с проверкой сертификата по тестовому trust root, REALITY constructor compatibility и parser override. Random проверен на единственный браузерный выбор в процессе, Randomized — на сохранение seed и ALPN h2. Старые Chrome-алиасы доказанно возвращают тот же ClientHelloID = 133. Полевой рейтинг блокировок этими тестами не определяется.

Неудачный эксперимент: первый локальный TLS 1.3 handshake на unbuffered net.Pipe зависал на SessionTicket, как в известном helper существующих тестов. На тестовом сервере отключены session tickets; сертификаты по-прежнему проверяются. Повтор прошёл для всех профилей; production TLS и ядро ради теста не менялись. Все test URI/учётные данные синтетические, никаких роутеров/VPS или сетевых провайдеров не использовали.

Не выполнялись: обновление ядра/uTLS, новые браузерные версии, пакеты, публикация, живой роутер, внешние TLS/REALITY handshake и измерения устойчивости к блокировкам. Git: `git diff --check` passed. Поддержка новых номеров версий требует отдельного mapper/handshake-контракта; скрытые aliases не доказывают разные пресеты.

## Редактор VPN и старые соединения — 2026-11-15

Итоговый frontend из `fe-app-kabanmax`:

```powershell
npm.cmd test -- --run src/kabanmax/cbi/tests src/kabanmax/tabs/sections/tests/connectionUri.test.ts src/kabanmax/tabs/sections/tests/outboundNames.test.ts tests/bundle/connectionLinks.test.js tests/bundle/optionLifecycle.test.js tests/bundle/dialogTitles.test.js --maxWorkers=2
npm.cmd run build
node node_modules/eslint/bin/eslint.js src/kabanmax/tabs/sections/connectionUri.ts src/kabanmax/tabs/sections/connectionEditor.ts src/kabanmax/tabs/sections/links.ts src/kabanmax/tabs/sections/form.ts src/kabanmax/cbi/modal.ts src/kabanmax/cbi/dynamicList.ts tests/bundle/connectionLinks.test.js tests/lib/luciForm.js tests/lib/bundle.js src/kabanmax/tabs/sections/tests/connectionUri.test.ts
```

Результат: 16 файлов / 220 тестов passed; TypeScript/tsup и ESLint passed. Проверены байтовый no-op URI, неизвестные query/fragment, IPv6, encoding учётных данных и query, неверные порты/адреса, SNI/port edit, REALITY → TLS, Vision/WS rejection, эффективный экспорт override без записи в исходный URI, замена URI через raw/import, запрет устаревших полей, повторное открытие, стабильный ID/порядок, синхронизация URLTest/Fallback и отсутствие секретов в проверяемых сообщениях/ошибках. Отдельный red/green сценарий подтвердил рассинхронизацию нового черновика URLTest при rename ручного сервера; исправлена и повторно проверена вместе со всем указанным набором. VMess/base64/JSON и специальные схемы проверены на сохранение raw, а не на структурированное редактирование.

Backend из корня; каждый фильтр проверяет один файл, без сети:

```powershell
$repoRoot = (Get-Location).Path
foreach ($taskFilter in @('singbox/generator_groups', 'singbox/generator_tags', 'config/validator_fingerprint', 'config/validator_groups', 'service/lifecycle')) {
  docker run --rm --network none --mount "type=bind,source=$repoRoot\tests,target=/work/tests,readonly" --mount "type=bind,source=$repoRoot\kabanmax,target=/work/kabanmax,readonly" --mount "type=bind,source=$repoRoot\luci-app-kabanmax,target=/work/luci-app-kabanmax,readonly" --mount "type=bind,source=$repoRoot\scripts,target=/work/scripts,readonly" --mount "type=bind,source=$repoRoot\core,target=/work/core,readonly" -w /work forkop-zapret2-test-tools:local bash tests/run.sh $taskFilter
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

Результат: все пять файлов passed (`0 of 1 test files failed` каждый). Lifecycle-проверка с invalid config доказывает: валидация отказывает до записи runtime config и сигнала reload, старый PID/порты/перехват остаются. Это не подмена проверки живого устройства.

Core: только локальный Git-объект закреплённого `core/UPSTREAM`, чистый `git archive` в контейнерный tmp, затем текущие patches и дополнительный test. Dirty `.local/core-src` не является входом сборки. Публичные исходники смонтированы read-only, внешняя сеть выключена:

```powershell
$repoRoot = (Get-Location).Path
docker run --rm --network none --mount "type=bind,source=$repoRoot\.local\core-src,target=/source,readonly" --mount "type=bind,source=$repoRoot\core,target=/core,readonly" --mount "type=bind,source=$repoRoot\tests\core,target=/extra-tests,readonly" --mount type=volume,source=kabanmax-chrome155-go-mod,target=/go/pkg/mod --mount type=volume,source=kabanmax-chrome155-go-build,target=/go/build -e GOMODCACHE=/go/pkg/mod -e GOTOOLCHAIN=go1.26.10 -e GOCACHE=/go/build kabanmax-release:2.1.0 sh /extra-tests/run_editor_reload.sh
```

Runner использует `go test -count=1 -race -p=2` с точными tags/именами тестов в `tests/core/run_editor_reload.sh`. Результат: cmd/sing-box passed (1.224s), protocol/group passed (1.458s), без Go test result cache. Close/Create core закрывает loopback TCP-сессию к endpoint A, новая идёт к B; URI/rename сервера/rename Fallback меняют fingerprint; повторное сохранение не меняет его; перенос статистики не восстанавливает здоровье. Отдельно проверены сохранение старого потока при обычном switch Fallback и запрет старому потоку/успешному dial отменять новый сбой. Это локальный цикл, используемый SIGHUP, а не полноценный live Save & Apply на роутере.

Переводы:

```powershell
$repoRoot = (Get-Location).Path
docker run --rm --network none --mount "type=bind,source=$repoRoot\luci-app-kabanmax\po\ru\kabanmax.po,target=/input.po,readonly" kabanmax-release:2.1.0 /usr/local/bin/po2lmo /input.po /tmp/task09.lmo
```

Результат: passed (40 новых русских записей). `git diff --check` passed.

Неудачные промежуточные проверки: первый core-запуск без существующих Go volumes остановился на недоступных offline зависимостях и неверном quoting `-run` через PowerShell; исправлено файловым runner и прежними локальными volumes, сетевые зависимости не устанавливались. UI-регрессии выявили коллизию editor mode с XHTTP mode, обработку пустых необязательных полей и сохранение изменённого raw URI при возврате к полям; исправлены отдельными ключами и явным import/source guard. Harness дополнен браузерным URL, clipboard и UI setter для поведения, существующего в браузере. Не выдавать эти ошибки окружения за дефекты ядра.

Не проверялись: живой роутер/VPS, реальный провайдер, браузерный визуальный smoke-test, внешние TLS handshake, перезагрузка оборудования, полный тестовый набор и выпуск пакетов. Ошибки пользователя после прежних сохранений не сопоставлялись с реальными сообщениями: для точного полевого диагноза нужны тип ошибки и стадия Apply без секретов/URI. Ручной выбор selector по исходникам сохраняется, пока тег существует; его не сбрасывали ради тестов.

## Ссылки Fallback — 2026-11-15

Из `fe-app-kabanmax`:

- `npm.cmd test -- --run tests/bundle/connectionLinks.test.js --maxWorkers=2` до исправления: 2 новых теста failed, 15 passed. Точные причины: старое имя после rename и оставшаяся ссылка после delete. Первый sandbox-запуск не стартовал из-за запрета esbuild читать родительский каталог; повтор вне sandbox воспроизвёл оба дефекта.
- `npm.cmd test -- --run tests/bundle/connectionLinks.test.js src/kabanmax/tabs/sections/tests/outboundNames.test.ts src/kabanmax/cbi/tests/childItemIdentity.test.ts src/kabanmax/cbi/tests/childItemLists.test.js --maxWorkers=2`: 4 файла / 69 тестов passed. Проверяются URI edit с постоянным ID, повторные rename/save, reorder, delete/re-add без наследования выбора и изоляция секций.
- `npm.cmd run build`: TypeScript + tsup passed; обновлён LuCI `main.js`. Первая сборка выявила тип массива UciValue, исправлено преобразованием элементов в строки.
- `node node_modules/eslint/bin/eslint.js src/kabanmax/tabs/sections/links.ts src/kabanmax/tabs/sections/form.ts tests/bundle/connectionLinks.test.js`: passed.

Из корня, только текущие исходники, без сети:

```powershell
$repoRoot = (Get-Location).Path
docker run --rm --network none --mount "type=bind,source=$repoRoot\tests,target=/work/tests,readonly" --mount "type=bind,source=$repoRoot\kabanmax,target=/work/kabanmax,readonly" --mount "type=bind,source=$repoRoot\luci-app-kabanmax,target=/work/luci-app-kabanmax,readonly" --mount "type=bind,source=$repoRoot\scripts,target=/work/scripts,readonly" --mount "type=bind,source=$repoRoot\core,target=/work/core,readonly" -w /work forkop-zapret2-test-tools:local bash tests/run.sh singbox/generator_groups
```

Результат: `0 of 1 test files failed`, включая новую проверку смены URI под тем же ID и повторной генерации без дублей/смены приоритетов. Проверка Git: `git diff --check`.

Не выполнялись: полный frontend/backend набор, сборка/тесты ядра, live reload, установка и публикация. Сбой исключительно от изменения URI и непреднамеренное появление дублей локально не воспроизведены; `#1` для повторённого имени подтверждён существующим тестом как штатная защита. Regex и уже сохранённые старые имена могут требовать ручного выбора; это не доказательство исправления всех полевых симптомов.

## Разрешённые локальные проверки
- Frontend lint, Vitest, TypeScript/tsup build; DOM/bundle тесты работают с подменами LuCI.
- `bash tests/run.sh`: каждый backend `.test.uc` отдельным интерпретатором, `fakes/` и `lib/` впереди production modules, временный каталог удаляется. Запуск не должен вызывать реальную службу роутера.
- Core tests только в локальном checkout с patch; чистая проверка применимости patch.
- Статическая проверка shell/Python, целостность файлов/Git, docs links, manifest/checksums. Packaging не является установкой.

## Команды ядра
Из checkout с применённым patch:
```sh
go test -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./cmd/sing-box ./parser/... ./protocol/group ./common/tls ./common/tlsfragment
```
Точные tags согласовать с текущим toolchain/upstream; ошибка окружения не равна провалу алгоритма. Основные регрессии: first/second retry rounds, пауза после failed pair, fresh data/old stream/dial-only, late data при резервном probing, замена nested identity, 24h expiry и reload fingerprints.

## Не запускать автоматически
SSH/Clash API к живым узлам, смену fallback/TLS/маршрутов, нагрузку, packet capture и curl через реальные VPS. Они требуют отдельной задачи с целями, ограничением трафика и откатом. Тестировать через разрешённые нейтральные HTTPS назначения; см. SECURITY.

## Результаты реорганизации 2026-11-13
Результаты заполняются после фактических запусков в `.local/audit/verification.json` и кратко в конце этой страницы. Полные логи локальны и исключены из Git. Исторические тесты 0.1.3 указаны отдельно в PROJECT_STATE. Успех локального набора не подтверждает доступность провайдера или всех моделей роутеров.

Свежий запуск после переноса:

| Проверка | Результат |
| --- | --- |
| `npm run lint` | passed |
| `npm test -- --run --maxWorkers=2` | 164 файла, 1590 тестов passed |
| `npm run build` | TypeScript + tsup passed |
| `bash tests/run.sh` | 0 ошибок из 79 файлов |
| Pinned upstream + `git apply --check` + patch | passed |
| Первоначальный Go race-набор изоляции: cmd/sing-box, parser, protocol/group, common/tlsfragment | все 4 пакета passed |
| `cd docs && npm run build` | VitePress passed, без dead links пользовательского сайта |
| `bash -n install.sh build.sh scripts/*.sh` (каждый файл отдельно) | passed |
| `PO2LMO=/usr/local/bin/po2lmo bash scripts/build-zapret2-local.sh 0.1.3 /tmp/packages` | app/LuCI/RU в APK/IPK, 6 пакетов |
| Сохранённый release 0.1.3 | 13/13 записей SHA256SUMS совпали |
| Перенос | 23 035 обычных файлов сверены; потерь и неожиданных изменений нет; reparse points сверены отдельно |
| Резервные Git bundles | 3/3 прошли verify; HEAD всех 4 checkout сохранены |

Окружение: новые временные контейнеры, без mount чужих проектов. Frontend/core/packaging — локальный `kabanmax-release:2.1.0`, backend — `forkop-zapret2-test-tools:local` (имя историческое, в него передан только текущий source snapshot). Первый frontend run дал 1 failure: в кэшированном образе отсутствовали полные ICU-локали, русская строка Intl возвращалась по-английски. После `apk add --no-cache icu-data-full` полный повтор прошёл. Production-код ради этого не менялся. Dockerfile текущего release image уже содержит `icu-data-full`; пересобирать образ при несовпадении окружения.

Полный ARM64 core binary заново не собирался: проверены patch и race-тесты. Существующие бинарники сохранены и сверены. Live UI/провайдер/VPS, удалённые GitHub alerts и публикация не проверялись. Инженерные docs отдельно проверены на существование относительных ссылок и явные secret patterns; это не полный аудит Git-истории.

## Резолв, журнал и интерфейс — 2026-11-13

Новые локальные проверки после реализации, отдельно от результатов изоляции выше:

| Команда | Результат |
| --- | --- |
| `npm.cmd ci --cache ../.local/npm-cache --no-audit --no-fund` из `fe-app-kabanmax` | восстановлены отсутствовавшие package-файлы зависимостей, 271 пакет; побочный diff yarn.lock отменён |
| `npm.cmd test -- --run --maxWorkers=2` из `fe-app-kabanmax` | 167 файлов / 1607 тестов passed, включая проверки обновлённого bundle |
| `npm.cmd run lint` из `fe-app-kabanmax` | passed |
| `npm.cmd run build` из `fe-app-kabanmax` | TypeScript + tsup passed, LuCI main.js обновлён |
| Docker-команда ниже, `bash tests/run.sh` | 82/82 backend-файла passed |
| `git diff --check` | passed |

Точная backend-команда из корня проекта в PowerShell, контейнер без сети, публичные исходники только для чтения:

```powershell
$repoRoot = (Get-Location).Path
docker run --rm --network none `
  --mount "type=bind,source=$repoRoot\tests,target=/work/tests,readonly" `
  --mount "type=bind,source=$repoRoot\kabanmax,target=/work/kabanmax,readonly" `
  --mount "type=bind,source=$repoRoot\luci-app-kabanmax,target=/work/luci-app-kabanmax,readonly" `
  --mount "type=bind,source=$repoRoot\scripts,target=/work/scripts,readonly" `
  --mount "type=bind,source=$repoRoot\core,target=/work/core,readonly" `
  --mount "type=bind,source=$repoRoot\build.sh,target=/work/build.sh,readonly" `
  --mount "type=bind,source=$repoRoot\install.sh,target=/work/install.sh,readonly" `
  -w /work forkop-zapret2-test-tools:local bash tests/run.sh
```

Точечные RED/GREEN: два файла `pre_routing_resolve` первоначально отказали из-за отсутствия генерации/валидации, затем прошли; frontend validator/settings также проверены до реализации. Журнал проверяет 24h expiry, раннее вытеснение по размеру, реальный размер JSON, сохранение возраста после reload, отсутствие возвращения старых строк после очистки, повторяющиеся строки и окно дедупликации, отсутствие удалённого текста в метаданных. Сервисные тесты покрывают сбор без UI, восстановление файла, отказ очистки при ошибке чтения и откат при ошибке записи. Ошибки двух последних сценариев сначала воспроизведены тестами и исправлены после ревью.

Первый полный frontend run выявил отсутствующие переводы; после обновления bundle интеграционные тесты выявили лишнюю запись default-значения и `rmempty=false` у поля доменов. В shipped config добавлен выключенный режим, обязательность списка оставлена собственной валидации по принятому в проекте шаблону. Повтор полного набора прошёл. Первый backend run с неполным набором bind mounts отказал в packaging/page/source тестах из-за отсутствующих публичных файлов; повтор с командой выше прошёл. В новом тесте размера исправлено имя assertion `includes` на существующий `contains`.

Live UI, маршрутизация на роутере, потери при экстремальном переполнении logd, ARM64/Go пересборка и packaging в этой функциональной задаче не проверялись. Изменений Go-кода нет. Журнал хранится в RAM до перезагрузки; сбор polling каждые 1.5s сохраняет собранные строки, но не доказывает отсутствие потерь в системном кольце между чтениями.

## Выпуск 0.1.4 — 2026-11-13

По отдельному запросу выполнена публикация commit `d370c50`, тег 0.1.4. Повторены frontend `npm.cmd test -- --run --maxWorkers=2` (167/1607), `npm.cmd run lint`, `npm.cmd run build`, backend-команда выше (82/82), docs `npm.cmd run build` (VitePress 1.6.4, passed). Docs-зависимости восстановлены `npm.cmd ci --cache ../.local/npm-cache --no-audit --no-fund`; побочные изменения lockfile отменены, удалён только созданный сборкой `.vitepress/.temp`.

В локальном `kabanmax-release:2.1.0` без сети, с readonly bind исходников kabanmax/luci/scripts/build.sh/install.sh и отдельным writable `/out`, выполнено `PO2LMO=/usr/local/bin/po2lmo bash scripts/build-zapret2-local.sh 0.1.4 /out`: 6 пакетов приложения/LuCI/RU. Пакеты ядра не пересобирались: 4 файла r8 совпали с GitHub API SHA256/размерами assets 0.1.3 и скопированы без изменения. Затем `bash scripts/check-release.sh /out` проверил все 13 SHA256 и согласованность двух manifests. В публичном релизе 14 файлов вместе с SHA256SUMS; каждый серверный SHA256 и размер совпал с локальным. Тег указывает на точный release-коммит. GitHub Actions Frontend CI, Backend CI и Documentation завершились success; установка/live-проверки не выполнялись.

## Fingerprint отдельного подключения — 2026-11-13

Свежие проверки override `tls_fingerprint` после реализации:

- `npm.cmd run build` — TypeScript/tsup passed, bundle обновлён.
- `npx.cmd eslint src/kabanmax/services/coreFeatures.service.ts src/kabanmax/tabs/sections/links.ts src/kabanmax/tabs/sections/coreSupport.ts src/kabanmax/tabs/sections/tests/fingerprint.test.ts tests/bundle/connectionLinks.test.js` — passed.
- `npm.cmd test -- --run tests/bundle/connectionLinks.test.js src/kabanmax/tabs/sections/tests/fingerprint.test.ts src/kabanmax/tabs/sections/tests/tlsOptions.test.ts` — 3 файла / 20 тестов passed.
- Backend-команда из предыдущего раздела с полным набором readonly mounts, `bash tests/run.sh` — 84/84 файла passed.
- `git diff --check` — passed перед финальным документированием.

RED/GREEN воспроизведён для frontend capability helper, backend генератора и валидатора. Bundle regression сначала отказал на отсутствующем поле в старом main.js, затем прошёл после сборки. Проверены одинаковые URI с одинаковыми fragment names, переименованная запись и назначение override по постоянному ID; соседняя запись и исходная URI сохраняются, возврат к наследованию удаляет override. Валидация отвергает неизвестные профили, отсутствие uTLS в сборке, plaintext, Trojan security=none, HTTP с неэффективным security=tls query, VLESS с pbk без security и QUIC/XHTTP h3. Ядро применяет профиль к разобранному TLS-объекту, сохраняя SNI/Reality, и самостоятельно отвергает неподдерживаемые override.

Первый Go запуск без GOMODCACHE не нашёл закэшированный toolchain; без обязательных build tags отказал из-за ограничений сборки badtls/ktls. Правильное окружение указано ниже. Это ошибки запуска проверок, production-код ради них не менялся. Подключения к действующим роутерам/VPS и развёртывания не выполнялись; публичный endpoint тестов fragmentation указан ниже.

Точная команда core из корня проекта в PowerShell; checkout содержит публичный pinned upstream с обоими patches, его .git скрыт от контейнера:

```powershell
$repoRoot = (Get-Location).Path
docker run --rm --network none `
  --mount "type=bind,source=$repoRoot\.local\core-chrome155,target=/source" `
  --mount type=tmpfs,destination=/source/.git `
  --mount type=volume,source=kabanmax-chrome155-go-mod,target=/go/pkg/mod `
  --mount type=volume,source=kabanmax-chrome155-go-build,target=/go/build `
  -e GOMODCACHE=/go/pkg/mod -e GOTOOLCHAIN=go1.26.10 -e GOCACHE=/go/build `
  -w /source kabanmax-release:2.1.0 go test -race -p=2 `
  '-tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn' `
  ./cmd/sing-box ./parser/... ./protocol/parser ./protocol/group ./common/tls ./common/tlsfragment
```

Результат полного core race-набора: 13 пакетов с тестами passed, `parser/xhttp` — no test files. В offline запуске все пакеты кроме `common/tlsfragment` прошли; его три существующих теста подключаются к публичному `1.1.1.1:443` и отказали с `network is unreachable`. Повторена та же Docker-команда без `--network none`, со списком пакетов только `./common/tlsfragment`: passed (1.679s). Результаты относятся к одному итоговому source snapshot; новых изменений между запусками не было. К действующим роутерам/VPS не подключались; публичный TLS endpoint использовали только существующие тесты fragmentation.

После финального ревью добавлен отказ override `android` для REALITY: ядро также отвергает `360` (этого профиля нет в списке UI). Общий capability helper учитывает точный список TLS 1.2-only профилей из `checkRealityFingerprint`; обычный TLS с Android и остальные профили REALITY сохраняются. Новый frontend regression сначала воспроизвёл ошибочное принятие. Повторены ESLint затронутых файлов и `npm.cmd run build` — passed; targeted frontend команда выше теперь 3 файла / 21 тест passed, backend `bash tests/run.sh fingerprint` — 1/1 passed. Go исходники не менялись; предыдущие core результаты сохраняют применимость к этому же ядру.

Финальный полный повтор после этой правки: `npm.cmd run lint` и `npm.cmd test -- --run` — 170 файлов / 1616 тестов passed; Docker-команда backend выше — 84/84 passed. Результаты сохранены локально в `.local/audit/frontend-015-final.txt` и `backend-015-final.txt`. Пересобраны шесть APK/IPK приложения; четыре ARM64 core APK/IPK включают финальный parser override. `bash scripts/check-release.sh /out` — все 13 checksum-записей и согласованность manifest/assets прошли. Сборка docs: `npm.cmd run build` из `docs` — passed. Ошибочная команда `npm.cmd run docs:build` ранее завершилась отсутствием такого script и заменена корректной; она ничего не проверяла.
