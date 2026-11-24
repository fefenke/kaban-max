# Проверочный комплект 0.2.3 — 2026-11-23

## Результат и состав

По прямому запросу пользователя собран согласованный preview приложения/LuCI/RU **0.2.3** и core **1.14.4-r29**, установлен на один локальный OpenWrt ARM64 роутер для нескольких дней пользовательской приёмки. GitHub push/release не выполнялись. Исходная база `98e5605` и пользовательский diff сохранены; изменения не коммитились автоматически.

Включены подготовленные r23/r24 исправления авторутинга, byte-budget/retention/checkpoint и реестр за первой сотней, защита памяти журнала/мониторинга, уровни сетевых логов, DNS per-question/WAN gate, согласованный FakeIPv6 и WARP network-reset forwarding. Планы анимации/TLS-разбиения и новые продуктовые функции не добавлялись. [Storage](AUTO_ROUTING_STORAGE.md), [logging](LOGGING.md), [WAN/DNS](NETWORK_AVAILABILITY.md), [WARP](WARP_RECOVERY.md).

## Свежая проверка

Дата всех проверок: 2026-11-23. Windows frontend; Linux x86_64 Docker backend/core; Go 1.26.10. Прогоны выполнялись одним ассистентом без субагентов. Предыдущие PASS не использовались вместо свежих.

| Команда | Scope и результат |
| --- | --- |
| Из `fe-app-kabanmax`: `npm.cmd test -- --run --maxWorkers=2`; затем `npm.cmd run build` | PASS 177 файлов / 1701 тест; TypeScript, fingerprints sync, LuCI bundle |
| `npx.cmd eslint src/kabanmax/methods/custom/clashApi.ts src/kabanmax/methods/custom/tests/clashApi.test.ts src/kabanmax/tabs/logs/render.ts src/kabanmax/tabs/monitoring/initController.ts src/kabanmax/tabs/monitoring/render.ts src/kabanmax/tabs/monitoring/tests/initController.test.ts src/kabanmax/tabs/sections/autoRecords.ts src/kabanmax/tabs/sections/autoRouting.ts src/kabanmax/tabs/sections/tests/autoRouting.test.ts src/kabanmax/tabs/settings/form/autoStorage.ts src/kabanmax/tabs/settings/form/updates.ts src/kabanmax/tabs/settings/tests/autoStorage.test.ts` | PASS все изменённые frontend files |
| `docker exec kabanmax-autoroute-tests bash /work/tests/run.sh` | PASS 97/97 backend files |
| `docker exec kabanmax-autoroute-tests sh -c 'set -e; while IFS= read -r file; do ucode -c -o /dev/null "/work/$file"; ucode -S -c -o /dev/null "/work/$file"; done < /work/dist/preview-023/changed-ucode.txt'` | PASS оба syntax режима 29 изменённых/новых ucode files; список получен из tracked diff + nonignored untracked |
| `docker exec kabanmax-autoroute-tests env PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin sh /work/dist/preview-023/core-verify.sh` | PASS clean archive pinned commit + check/apply 29 patches, свежие regression tests из `tests/core`; race scope ниже |
| `python scripts/check-project-docs.py`; `python -m unittest discover -s tests/docs -p 'test_*.py'`; `git diff --check` | PASS docs gate, 9 docs tests, diff whitespace |

Core runner основан на `tests/core/run_auto_routing.sh`: пути `/core`, `/extra-tests`, `/source` заменены на текущие `/work/core`, `/work/tests/core`, `/tmp/core`; добавлен `warp_stability_test.go`. `go test -count=1 -race -p=2` с tags `badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn` прошёл `common/autoroute`, `route`, `dns`, `dns/transport/fakeip`, `common/wanstate`, `log`, `experimental/clashapi`, `protocol/group`, `experimental/cachefile`, `common/ja3`, `common/sniff`, `protocol/warp`, `common/cloudflare`, `protocol/wireguard`, `common/tls`, `common/tlsfragment`, `parser/...`, `protocol/parser`, `cmd/sing-box`. Всего 26 packages с тестами; `parser/xhttp` без test files. WAN unit tests не запускали внешние probes; аппаратной нагрузки не выполнялось.

Первый Windows frontend запуск был заблокирован sandbox/esbuild чтением родительского каталога; повторный разрешённый запуск прошёл без глобальных настроек. Для Git при повышенных правах обнаружена другая ownership; глобальный safe.directory не менялся, список syntax scope собран обычным локальным Git. Начальные packaging attempts без `PO2LMO` и Git index в archive исправлены настройкой штатных prerequisites; это не продуктовые исправления.

## Сборка и package verification

Артефакты: ignored `dist/preview-023/`. Созданы 10 APK/IPK: backend/LuCI/RU 0.2.3 и core r29 base/tiny для `aarch64_cortex-a53`. Никаких приватных backup/config/log файлов в packages нет; payload inspector проверил запрещённые каталоги и соответствие исходникам. Сборка инструментов использовала пустой Docker context, без передачи `.local/`.

Точные команды из корня:

```powershell
docker build -t kabanmax-preview-build -f scripts/release.Dockerfile dist/preview-023-build-context
docker exec kabanmax-autoroute-tests sh /work/dist/preview-023/build-core-binaries.sh
# $taskRoot = абсолютный путь текущего репозитория
docker run --rm -e PO2LMO=/usr/local/bin/po2lmo -v "${taskRoot}:/work:ro" -v "${taskRoot}/dist/preview-023:/output" kabanmax-preview-build bash scripts/build-zapret2-local.sh 0.2.3 /output
docker run --rm -v "${taskRoot}:/work:ro" -v "${taskRoot}/dist/preview-023:/output" kabanmax-preview-build bash /output/package-core.sh
```

Core binary build: чистый `git archive` pinned commit, все 29 patches, `scripts/brand-core.py`, временный Git index для штатной LF-проверки; upstream `build.sh --variant base|tiny --arch aarch64_cortex-a53 --version 1.14.4-r29 --binary-only`, `SOURCE_DATE_EPOCH=1793880000`, Go 1.26.10, затем штатный `release/kabanmax/package.sh --format all`. Base/tiny binaries и packaging sources перенесены из контейнера в артефакты; `core-release.json` и 13 SHA256 records согласованы с release.json.

`scripts/check-release.sh` и `scripts/inspect-release.py` PASS: все 10 APK/IPK, byte-for-byte равенство APK/IPK payload, frontend version substitution/source, freshly built core binary, licenses, manifests и все 13 checksums. Установлен base; tiny не запускался на устройстве.

SHA256 base executable: `3666a9877f23b3c646c86a498ea2e49031d043afad6eb1cfc06301597fa3f5b3`; tiny: `718993a8a6dfd4942a974ed704e0c8fe051f0e47e5c8d9e45d029b974de52dc0`. Полный список package hashes — в локальном `SHA256SUMS`.

## Установка и неудачная первая попытка

До установки сохранены известный рабочий executable через hardlink во flash и архив старых package files, UCI/config, durable autoroute и APK metadata. Приватная копия архива есть на компьютере в конкретном ignored `.local/` каталоге; содержимое не выводилось и не публиковалось. Пакеты передавались прямо во flash; новое ядро и его backup не складывались в RAM. Offline APK simulate и checksums четырёх переданных APK прошли.

Первая попытка через отдельную операционную обвязку была ошибочной: `reload` остановленной службы вернул 0 с `reload skipped`, поэтому конструкция `reload || start` не запустила сервис. Обвязка откатила файлы, но её восстановление имело тот же дефект. Пользователь дважды запускал службу сам. Ошибка признана; свой таймер отменён, дальнейших ручных stop/reload не выполнялось. Это дефект использованного временного deployment script, не доказательство ошибки package hooks или самого KabanMax. Этот путь повторно не использовать.

Установка завершена **штатным неизменённым install.sh** через поддерживаемый `KABANMAX_DOWNLOAD_URL`, с временным loopback-only mirror проверенных артефактов. Команда на роутере:

```sh
KABANMAX_RELEASE=0.2.3 KABANMAX_DOWNLOAD_URL=http://127.0.0.1:18083 \
 sh /root/kabanmax-preview-0.2.3/install.sh --variant base --lang ru --quiet
```

Installer запущен detached, сам выполнил проверки, остановку/transaction/start и вернул exit **0**: `KabanMax обновлён до 0.2.3 и запущен`. Временный mirror после успеха выключен, временные четыре APK удалены только из собственного staging/mirror; рабочий rollback backup сохранён. Свободно около 40 МиБ flash. Устанавливать последующие проверочные комплекты штатным механизмом, не подменяя его ручной обвязкой остановок.

## ARM64 smoke после установки

Около 23:38 MSK: uptime 37 минут (в этой установке reboot не наблюдался); `/etc/init.d/kabanmax status` — running. APK database: backend/LuCI/RU 0.2.3, sing-box-kabanmax 1.14.4-r29; `sing-box version` и `core.constants.KABANMAX_VERSION` совпали. Runtime level Warn; FakeIPv4 прежний, FakeIPv6 `2001:2::/112`. Установленный UI SHA256 `7e5fb91dae4e084639531319cd79e319a2c996507119cd02986fdc3ebbf7dac2` равен подготовленному bundle с version substitution. Hash installed core равен base binary выше.

Read-only `/delay` через профили 1/2: Cloudflare 204 — 35/32 мс; YouTube 204 — 41/41 мс; главная YouTube — 208/253 мс. Это текущая HTTPS-доступность, не подтверждение каждого CDN/протокола или длительной стабильности. Поздний `/connections` snapshot: 42/42, truncated=false; активного видео в тот момент не было, его успешное воспроизведение после данного полного обновления отдельно не заявляется.

Ключи/ID/token обоих WARP в приватном before/after сравнении совпали. Сохранённые applied/suppression JSON семантически полностью совпали с backup. Число active autoroute sources осталось **0**, включение не менялось. При отсутствии sources core API ожидаемо отвечает `automatic_routing_unavailable`; backend registry_error пуст, settings module читает 86400s save / 3600s retention / 4 МиБ budget (1 МиБ compact data). Активный hardware autoroute flow этой установкой не проверен: его не включали ради smoke.

MemAvailable около 32 МиБ; журнал около 8 КиБ, не обещание общего RSS и не диагноз исторического OOM. Нет WAN-loss/reboot/power-loss/load soak, браузерной приёмки всех экранов, Tiny runtime или проверки семи устройств. Пользователь проверяет несколько дней; приёмочный результат и будущая публикация требуют отдельной фиксации/нового запроса. При открытом старом LuCI обновить страницу с очисткой кэша.
