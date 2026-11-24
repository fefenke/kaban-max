# Preview 0.2.6/r36 — сохранённый результат и холодный старт WARP

Исторический ход промежуточных r36/r37 проверок. **Финальный установленный состав — 0.2.7/r37**, 5/5 restart, cleanup и точные итоговые ограничения — [PREVIEW_027](PREVIEW_027.md). Не трактовать нижние промежуточные состояния «ещё не проверено» как текущий статус.

Дата **2026-11-24 MSK**. Продолжение [r34](PREVIEW_025.md) и [двух неудачных restart-тестов](WARP_RESTART_20261124.md). Источник core — pinned UPSTREAM + 36 patches. Все прежние пользовательские изменения сохранены, работа одним ассистентом.

## Итоговый контракт Pending

По прямому уточнению пользователя: один успешный результат хранится до удаления, применения или исключения записи. Он не становится expired по времени и не запускает новые проверки по таймеру или новой ошибке исходного маршрута. Кнопка перепроверки не добавляется. Сохраняются направление, attempts и время проверки, новая исходная ошибка видна отдельно. Deadline внутреннего автоматического разрешения не продлевается: старый результат сам не выдаёт новый grant. Явное ручное применение остаётся отдельным разрешённым действием.

`0035-stable-pending-check-results.patch` сохраняет неразобранные error events и связанные decisions под прежним byte budget, отменяет их возрастное вытеснение. При заполнении действует admission/overflow, не расширение RAM. Явно исключённые/применённые записи очищаются. Успешный результат блокирует повторный Sweep. Private checkpoint содержит результат; при reload/restart он восстанавливается с валидацией owner/source/IP/device/inbound/port/target и без запуска новой пробы. Браузеру private metadata не передаётся. Это сохранение в runtime checkpoint; переживание полного power loss новых Pending не заявляется.

Backend показывает исходное `checked_at`, передаёт source mode для корректного сопоставления web scopes. При обновлении с r34 прежний bounded snapshot decisions сохранён в приватный RAM-sidecar `auto-routing-events.json.checks`. Генератор присоединяет только exact matching source/record/domain/device/inbound/port; прежний expired успех нормализуется лишь при двух verified attempts выбранного target. Новый core повторно валидирует запись. Миграционная копия оставлена как private RAM backup; при наличии check_result новый private checkpoint имеет приоритет. Автопроверка отклонила первоначальную команду теста из-за удаления sidecar: команда не исполнялась; выбран безопасный вариант restart-теста без удаления данных. Новая кнопка и отмена пользовательских ограничений не добавлялись.

## WARP cold-start

Диагностика r34 подтвердила выход настоящего handshake-init без ответов и неудачные новые порты. Общая debounce 90s в wireguard-go задумана как защита от повторного тяжёлого rebind и гонок. Она не удалена глобально.

`0036-warp-cold-start-recovery.patch` включает только у WARP внутреннюю политику: до **самого первого** успешного handshake, у single-peer клиента с динамическим портом, допускается смена UDP flow при очередном unanswered retry. Максимум **три** быстрых смены, затем прежние 90s. Нет своего watchdog или безграничных быстрых попыток. Здоровые/ранее установленные сессии, серверы, multi-peer и pinned listen_port сохраняют прежнюю политику. Retry/rekey ranges пользователя не переписаны. Если persistent keepalive не задан, WARP использует 25s и начинает handshake standby профиля при старте; явно заданное значение, включая 0, сохраняется.

Эта правка адресует длительное холодное восстановление; она не объявляет установленной внешнюю причину отсутствия UDP replies (ISP/Cloudflare/NAT). Результат на устройстве оценивается такой же restart-пробой, что воспроизводила отказ r34.

## Проверки и команды

Go 1.26.10, существующий Linux Docker `kabanmax-autoroute-tests`, локальный synthetic UDP/crypto, без внешних Go-проб:

- RED `TestSuccessfulDecisionDoesNotExpireOrRestartAutomaticChecks` на r34: статус expired; GREEN после r35: результат не удаляется по deadline/retention, новая ошибка не сбрасывает успех, checkpoint/New/Sweep не перепроверяет, Dismiss удаляет, expired automatic grant не разрешён. Весь common/autoroute race suite PASS.
- RED cold-start regression до нового API: отсутствует SetColdStartRecovery. GREEN synthetic relay навсегда отбрасывает первые **три** клиентских UDP порта: получены расшифрованный marker сервером и зашифрованный ответ клиентом. Отдельно проверены pinned port при включённой cold policy, максимум 4 source ports за 7s (исходный + 3 rotations), keepalive default 25 и сохранение explicit 0/7/60. Тестовый rekey timer ускорен до 1s; runtime диапазоны не менялись.
- `docker exec kabanmax-autoroute-tests env PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin sh /work/dist/preview-026/verify-core.sh` — exit 0: clean archive, 36 check/apply, **14 Go race packages**, включая autoroute/route/DNS/FakeIP/WAN/logger/clashapi/fallback/WireGuard/WARP/cache/JA3/sniff.
- `docker exec kabanmax-autoroute-tests bash /work/tests/run.sh` — exit 0, **97/97 backend files**, после последней миграционной правки. Regression exact/foreign upgrade scope, сохранение успеха при новой ошибке, checked_at и текущий checking покрыты. Первый migration fixture был не включён в Zapret2 model, исправлена fixture, production guard не ослаблен.
- В fe-app-kabanmax: `npx.cmd vitest run src/kabanmax/tabs/sections/tests/autoRouting.test.ts src/kabanmax/tabs/settings/tests/autoStorage.test.ts`, `npm.cmd run build`, целевой `npx.cmd eslint` для autoRouting.ts/autoRecords.ts/autoStorage.ts и изменённого теста — PASS, **15/15**, TypeScript, fingerprints, bundle, lint. Полный frontend suite не повторялся.
- `docker exec kabanmax-autoroute-tests sh /work/dist/preview-026/build-core-binaries.sh` — exit 0: clean archive/36 patches, branding, upstream ARM64 base/tiny; base SHA256 `c534b535416e418cd7f7cc7f02c19382bc9b569c13886bb6a12f2982c3bac5df`, tiny `377d9a4b53467b8d6249b158dccab5e9822539db2debaa32452224de985dc954`.
- `docker run --rm -e PO2LMO=/usr/local/bin/po2lmo -v "${taskRoot}:/work:ro" -v "${taskRoot}/dist/preview-026:/output" kabanmax-preview-build bash scripts/build-zapret2-local.sh 0.2.6 /output`, затем тот же run с `bash /output/package-core.sh` — exit 0: согласованные backend/LuCI/RU/core, **10 APK/IPK**, payload/source/version/license/manifests и 13 SHA records.
- `docker exec kabanmax-autoroute-tests sh -c 'export PATH=/usr/local/go/bin:$PATH; cd $(cat /tmp/preview026-source-path); GOPROXY=off go build -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn -o /tmp/preview026-native ./cmd/sing-box; python3 /work/tests/core/lifecycle_log_binary.py /tmp/preview026-native'` — exit 0: реальный HUP, шум отменённого поколения Debug, новая ошибка Error.

## Установка

## Продолжение r37: подтверждённый UDP path hint

Первая установленная r36 серия **не прошла**: baseline 04:23:23 WARP1 42ms, WARP2 58ms, fallback 72ms; после restart 04:23:24 первый Timeout, второй 33ms, fallback Timeout. Результат Pending и время 03:59:04 сохранились. Серия остановлена на первом сбое. Дополнительная проба Cloudflare204 тоже дала Timeout первого, второй 36ms и fallback 35ms. Значит, это не только целевой YouTube; r36 нельзя считать достаточным исправлением startup.

`0037-warp-known-path-restart.patch` сохраняет в существующем identity-keyed WARP cache последний локальный UDP порт, на котором получен аутентифицированный handshake. Сохранение перед закрытием вложенного устройства, не отдельный фоновой процесс и не новая регистрация. Следующий старт пробует этот известный путь первым. Это **мягкий hint**: явный listen_port имеет приоритет, занятый hint откатывается на динамический, cold recovery по-прежнему вправе менять порт. Неотвечающие порты не запоминаются. Credentials/peer/Amnezia/PBR не переписываются. Причина молчания неизвестного внешнего flow не выдаётся за установленную.

Свежие проверки 2026-11-24:

- RED restart-path test до API: отсутствуют ListenPortHint/LastHandshakePort. GREEN настоящий WireGuard crypto test закрывает клиент, затем сервер/relay пропускает только предыдущий подтверждённый порт; новый клиент с hint получает расшифрованный marker. Занятый hint даёт новый порт; unanswered path не получает last-good отметку; bounded cold/pinned tests сохранены.
- `docker exec kabanmax-autoroute-tests env PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin sh /work/dist/preview-026-r37/verify-core.sh` — exit 0, чистый archive/37 patches и все 14 race packages.
- `docker exec kabanmax-autoroute-tests sh /work/dist/preview-026-r37/build-core-binaries.sh` — exit 0 ARM64 base/tiny. Base SHA256 `b18ccc36675caae3c30f212b208ebf93bc1bf2a113d71903d48e413bb138e7d1`, tiny `c85aed6af809fa79ec25c0c26d3839839af79944172567ca5f458f69e55facf0`.
- Пакетная инспекция и аппаратная серия r37 записываются после завершения. App/LuCI/RU остаются проверенными 0.2.6; r37 меняет только core.

## Установка r36

Текущий r34 hardlink backup и config tar во flash, копии на компьютере со сверенным SHA. Только старая лишняя r33 flash-копия удалена после проверки уже сохранённой компьютерной копии. Все staged APK во flash сверены SHA; большого двойного tmpfs staging нет.

Пользователь предупреждён об установке и последующих restart-тестах. Запущен неизменённый штатный installer, detached: `KABANMAX_RELEASE=0.2.6 KABANMAX_DOWNLOAD_URL=http://127.0.0.1:18087 sh /root/kabanmax-preview-0.2.6/install.sh --variant base --lang ru --quiet`. Итог и аппаратная серия будут записаны после выполнения. На этом этапе успех старта WARP ещё не заявляется. GitHub публикации нет.
