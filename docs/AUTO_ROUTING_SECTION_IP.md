# Применённый IP — все устройства выбранной секции

Пользователь явно подтвердил 2026-11-24: «Применить» должно охватывать все устройства выбранной секции. Статус «часть соединений не охвачена этим правилом» удалён. Установлен preview 0.2.9/core r39, оба прежних Applied мигрировали на all_devices/all_ports. [Установка и аппаратный smoke](PREVIEW_029.md).

## Найденная причина

Read-only диагностика r38 показала `disabled_sources=[]`, `registry_error=""`, 34230/4194304 accounted bytes, memory_pressure=false, registry_overflow=0. В этот момент сбор не выключен. Два применённых IP имели `all_ports=true`, но сохраняли ограничение на origin LAN device/inbound. Новые ошибки тех же IP пришли с другого LAN device. Таблица объединяла строки по IP, отмечала uncovered, одновременно скрывала эти ошибки из Pending из-за наличия Applied IP. Это объясняет наблюдавшийся статус, но не доказывает отсутствие какого-либо более раннего runtime disable.

## Текущий контракт

- Применённый persistent web IP получает `all_devices=true` и `all_ports=true`: TCP/UDP и любой порт/устройство, чьё соединение выиграло именно эту исходную секцию, направляются через выбранный Direct/WARP.
- Origin device/inbound/port и failure/source ID остаются для проверки пользовательского действия и ownership. Не требуется подделывать wildcard source IP или расширять валидатор scope.
- Внутри секции один persistent grant на IP. Повторное применение заменяет прежний grant. Старые web approvals восстанавливаются как section-wide без нового probe; конфликт разрешается последним по Created. Соседняя секция/IP и multi-address DNS не получают разрешений.
- Source-context ограничения, winning-route check, infrastructure protection, target checks и явные исключения сохраняются. При выборе section-wide grant дополнительно проверяется exclusion реального текущего устройства, а не только origin из записи.
- Compact store сохраняет `all_devices`. `remember` и manual action удаляют заменённые узкие approvals этого IP только внутри той же секции. Миграция остаётся RAM-first с прежним dirty-only flash schedule, без принудительного flash flush при restart.
- UI больше не выводит uncovered status. Ошибки уже выбранного альтернативного маршрута продолжают отображаться как новые ошибки Applied; они не должны выдаваться за новые ошибки META.
- Pending скрывается только если фактически покрыт активным grant. Старый узкий lease не может скрыть событие другого устройства; covered members не попадают в последующее групповое Apply.
- Strict краткоживущие application decisions и scoped исключения этим запросом не переводятся в section-wide approvals.

## Локальная проверка 2026-11-24

Linux x86_64 Docker `kabanmax-autoroute-tests`, Go 1.26.10, clean archive pinned commit + 39 patches; сеть Go-тестов только loopback. Windows frontend — локальный Node.

- RED `docker exec kabanmax-autoroute-tests bash /work/tests/run.sh diagnostics/auto_uncovered_pending` — до fix exit 1, оба новых tests ожидали Pending row, получили 0. RED Go `TestAppliedIPIsSectionWideAcrossDevicesAndPorts` на r38 — exit 1, другой device остался в META.
- `docker exec kabanmax-autoroute-tests env PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin sh /work/dist/auto-section-ip/verify-core.sh` — exit 0: clean apply 39 patches, **14 Go race packages**. Helper — `tests/core/run_auto_routing.sh` с `/core`→`/work/core`, `/extra-tests`→`/work/tests/core`, `/source`→`/tmp/core`. Проверены другой device/port/TCP/UDP, migration, explicit exclusion, section/IP boundaries, existing autoroute/fallback/DNS/WireGuard contracts. Два старых tests требовали прежний device restriction для web IP; ожидания обновлены по явному запросу. Strict scope tests сохранены.
- `docker exec kabanmax-autoroute-tests bash /work/tests/run.sh` — exit 0, **99/99 backend files**. После добавления storage regression отдельно `bash /work/tests/run.sh diagnostics/auto_registry` — exit 0; flag compaction и дедупликация не трогают чужую секцию.
- В `fe-app-kabanmax`: `npx.cmd vitest run src/kabanmax/tabs/sections/tests/autoRouting.test.ts` — 14/14 PASS; `npm.cmd run build` — TypeScript, generated fingerprints и LuCI bundle PASS; `npx.cmd eslint src/kabanmax/tabs/sections/autoRouting.ts src/kabanmax/tabs/sections/tests/autoRouting.test.ts` — exit 0.

Native migration проверена на двух прежних Applied: оба активны с all_devices/all_ports, флаг сохраняется в RAM intent, forced flash flush не выполнялся. Финальные syntax/backend tests — [PREVIEW_029](PREVIEW_029.md). Полный router reboot, WAN-loss и многодневный soak не выдаются за выполненные.
