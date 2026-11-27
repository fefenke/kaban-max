# WARP/fallback и журналы: локальный r42 — 2026-11-25

Локальный r42 заменяется [r43](AUTO_ROUTING_R43.md): согласованы probe budgets, добавлена рискованная protocol опция и уточнён Applied status. Ни один из этих локальных пакетов ещё не установлен/не опубликован; ниже снимок приёмки r42.

Статус26ноября: подготовлены исходники, x86/ARM64 binaries и10APK/IPK, не опубликованы и не установлены. Приложение0.2.3, core1.14.4-r42. Источник — прежний pinned upstream и append-only patch0042. Работа одним исполнителем. На вопрос об установке пользователь уточнил содержимое пакета; согласия на установку пока нет.

## Согласованный порядок журналирования

При пороге Warn видны Warn, Error, Fatal и Panic; Info/Debug/Trace ниже порога. Warn/Error уходящего поколения при плановом reload/stop понижаются независимо от текста. Fatal/Panic не понижаются. Ошибка отдельного отменённого запроса не отменяет root context работающего core.

**Уточнение пользователя2026-11-25:** при подтверждённом отсутствии WAN связанные сетевые сообщения должны подавляться. Исходный WAN gate и его тесты оставлены побайтно прежними. Первоначальная трактовка этого подавления как дефекта в аудите была неверной; в текущий patch изменения WAN не входят. Unknown и один неудачный WAN раунд по-прежнему не включают gate.

Вне этих окон:

- Fallback suspect/probe-only — Warn, как до глобального downgrade. Переключение stable fallback — Warn. Поздний сбой TCP stream запускает ограниченную внеочередную health check и даёт Warn с классом причины, не меняет выбор сам по себе. Burst debounce5s и capacity-one wake queue сохранены.
- Принятый исходный отказ авторутинга — прежний отдельный source Warn. Ошибка выбранного маршрута — новый отдельный selected-route Warn для routine причины; TLS/auth и другие не routine причины имеют Error, повторное одинаковое Error callback не добавляется. Источник и выбранная альтернатива не смешиваются.
- TCP copy/half-close: вместо безусловного Debug используется существующая классификация. TLS/auth/неизвестная ошибка протокола — Error; routine errno, timeout, cancellation и закрытие сохраняют прежнюю отдельную политику Debug. Таким образом общий routine timeout не объявляется VLESS protocol error; отказ WARP/fallback имеет собственное Warn уведомление.
- Отсутствующий FakeIP record и malformed DNS question снова Warn. Ранее они также были глобально понижены. DNS first failure/grouped repeats сохраняют Warn; служебный CHAOS/TXT REFUSED остаётся Debug. Ни grouping DNS, ни сбор реестра не отключены.

## Переключение и задержка обнаружения

Успех confirmURL больше не заменяет неудачу основного URL. Частичный отказ сохраняет `primary=...; confirmation=ok`, проходит второй свежий раунд, затем проверяется резерв через тот же основной URL. Только прошедшая проверка делает резерв доступным. Когда основной сервис не проходит ни на одном, текущий участник сохраняется и состояние становится degraded: нет прыжка на первый участник без рабочей альтернативы. Восстановление приоритета требует прежних трёх fresh successes. Identity, cancellation, frozen-leaf и bounded-budget safeguards сохранены.

Свежие байты другого сервиса не отменяют частичный отказ основного URL. Старые соединения, dial-only и старый round по-прежнему не могут отменять новый отказ. Для полного отказа обеих probe-служб прежняя защита по свежим данным остаётся.

Обнаружена ещё одна программная задержка: раньше observer отмечал положительные чтения, но не late read/write failure после успешного dial. Теперь wrapper наблюдает обычные и buffered операции, сохраняет half-close через Upstream и запрещает bypass observation при оптимизированном копировании. Не меняет deadlines, не повторяет отправленные данные, не запускает health от EOF/closed/cancelled context. Одна ошибка stream уведомляет один раз; общий debounce сохранён. Это устраняет ожидание периодического5m check при наблюдаемой поздней транспортной ошибке. **Гарантии мгновенного обнаружения молча зависшего потока нет**; пользовательский health interval не изменён.

## Что установлено на живом роутере

Дополнительный Applied/Pending разбор26ноября, штатный AutoApply после диагностического recheck и исправление отсутствовавшего failed-check retry — [отдельный отчёт](AUTO_ROUTING_PENDING_RETRY.md). Успешные результаты не перепроверяются. В UI уточнены selected-route error и healthy-original статусы; permissions прежние.

Прежняя матрица r41: первый Google timeout8s, первый Cloudflare33ms, второй тот же Google37ms; fallback удерживал первый без событий. Позже в этой сессии оба native Google HTTPS delay стали32/35ms без рестарта, смены профиля/порта/selector. Bind instance и порты оставались прежними; оба профиля имели fresh handshake/data. Поэтому конкретный наблюдавшийся отказ был частичным, а восстановление не требовало пересоздания профиля. Это не доказывает внешнюю первопричину.

Обычный curl и curl через LOCAL PROXY также проходили, но LOCAL PROXY маршрутизируется через другой outbound; эти успехи **не выдаются за проверку WARP**. Текущий DNS Google содержит несколько IPv4; serial TCP dial способен расходовать deadline на одном адресе. Пока нет доказательства, что именно это было причиной полевого отказа, и соответствующий алгоритм по догадке не изменялся.

## Проверки2026-11-25

Docker — существующий `kabanmax-autoroute-tests`, `/work` read-only, Go1.26.10, `GOPROXY=off`; test tree `/tmp/warp-runtime-r42.*`. Не затрагивались другие контейнеры, роутеры или глобальные настройки.

| Точная команда / scope | Свежий результат |
| --- | --- |
| `go test -count=1 -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./protocol/group ./log ./common/wanstate ./route -run 'TestStablePartialFailure\|TestStableSharedService\|TestWANStateGates\|TestWANOutageEmits\|TestConnectionCopyErrors'` на r41 до исправления | RED: partial/shared service failures и copy severity. Экспериментальные WAN expectations также RED, затем **отменены по уточнению пользователя**, не часть исправления |
| `go test -count=1 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./protocol/group -run 'TestStableStreamFailure\|TestStableRoutineStream'` | RED для обычного и buffered late timeout; после patch GREEN в полном group race suite |
| `go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./protocol/group ./log ./common/wanstate ./route ./dns ./common/autoroute` | PASS6packages после первого исправления; group после stream observer повторно PASS |
| `go test -count=1 -race ./log -run TestWarnThreshold` | PASS: Warn/Error, Panic и subprocess Fatal после отмены поколения |
| `sh /work/tests/core/run_network_availability.sh /tmp/core /work` | PASS: clean apply всех42patches,7race packages, compile-only cmd. Включены новые partial/stream/threshold tests |
| `bash tests/run.sh packaging/core_patch_series` | PASS1/1 |
| `go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./transport/wireguard ./protocol/warp ./protocol/wireguard` | PASS3packages: dead UDP paths, encrypted returned content, bounded cold-start rotations, pinned/hinted ports |
| `sh /work/dist/warp-runtime-r42/build-core-binaries.sh` | PASS: clean pinned42patches, branded amd64 base и ARM64 base/tiny |
| `python3 /work/tests/core/lifecycle_log_binary.py /tmp/warp-runtime-r42-core-output/build/amd64/base/sing-box` | PASS: real executable HUP, old flow Debug, fresh-generation DNS Error |

ARM64 base SHA256 `58c3ec4ca590e99beaf13e0110be9c37cd474eba8d99c19561b16d7a95d07cae`; tiny `0897a1db3a9fc56a64103df640090ea91a8906267bf8780c47e7fe6a19a4ef77`. Локальная сборка и loopback tests не являются аппаратной приёмкой. Полный reload/reboot soak, конкретная внешняя причина Google outage и стабильность под пользовательским видео остаются непроверенными. Не заявляется, что любые будущие отказы WARP устранены.

## Финальные проверки26ноября

- `sh /tmp/warp-runtime-r42-full.sh` — PASS14Go race packages на clean pinned source+42patches; helper — tracked `tests/core/run_auto_routing.sh` с mount paths, заменёнными на существующие `/work` и `/tmp/core`. Включён failed-check retry regression.
- `sh /work/dist/warp-runtime-r42/build-core-binaries.sh` — PASS финальные amd64 base/ARM64 base+tiny. Build и baseline test trees разделены. Hashes выше относятся к финальной сборке с readiness/stale-stream guards и Pending retry, не к предварительным binaries.
- `python3 /work/tests/core/fallback_partial_binary.py /tmp/release023r41-exec-core` — RED: через8s резерв не выбран, Warn отсутствует. Затем та же команда с `/tmp/warp-runtime-r42-core-output/build/amd64/base/sing-box` — PASS: настоящий TLS-verified application body, partial failover, shared-service outage удерживает backup, приоритет восстанавливается после fresh threshold, Warn видны. Использованы допустимые production minima1s, safeguards не отключались.
- `python3 /work/tests/core/lifecycle_log_binary.py /tmp/warp-runtime-r42-core-output/build/amd64/base/sing-box` — PASS финальный real HUP.
- `npx.cmd vitest run --maxWorkers=2 --reporter=dot` из frontend — PASS177files/1703tests. Targeted ESLint и `npm.cmd run build` — PASS; обновлены bundle и два русских перевода.
- Existing image `kabanmax-preview-build`, `--network none`: `bash /work/dist/warp-runtime-r42/package-release.sh`, затем `bash /work/dist/warp-runtime-r42/verify-release.sh` — PASS10APK/IPK payload/source/license/binary matches и13SHA256 records. Первый inspector остановился из-за отсутствия ожидаемой output/build binary reference; reference добавлен, проверка выполнена без ослабления assertions.
- Новые добавленные строки tracked diff и12новых текстовых файлов: credential/email/tool-marker regex findings0. Сырые source/device context, реальные конфиги/ключи и журналы в artifacts не добавлялись. Package payloads сверены с исходниками; старая Git история не переписывалась. Это scope проверки новых материалов, не повторный аудит всей истории.

Ограничение5s web attempt против8s настроенного fallback остаётся открытым; retry устраняет неподвижный Pending, но не увеличивает deadline. Оно не скрывается за утверждением «всё исправлено». Установка и аппаратная проверка требуют отдельного согласия по AGENTS; пока оно не получено, опубликованный release и устройство остаются на r41.
