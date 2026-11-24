# Preview 0.2.5/r34 — результат авторутинга после истечения TTL

Дата: **2026-11-24 MSK**. Продолжение [0.2.4](PREVIEW_024.md), pinned core UPSTREAM + 34 patches. До установки нового preview работал 0.2.4/r33.

## Подтверждённая причина

На устройстве у спорного WhatsApp IP candidate имел `proposed/repeated_transport_failure_alternative_reachable`, но `decisions=0`; target/attempts исчезли. У web-пробы deadline равен 60 секундам. `cleanupLocked` удалял решение сразу по deadline, оставляя событие ошибки на настроенный retention (по умолчанию час). LuCI превращал proposed без target в «Рабочая альтернатива не найдена». Новые ошибки исходного META и последующие задания объясняют возврат в очередь/проверку. Отказ конкретного WARP этим текстом не доказан; предыдущий ответ, сводивший проблему только к надписи, был неполным.

## Изменение

Patch `0034-retain-probe-diagnostics.patch` разделяет срок диагностического результата и срок разрешения применить проверенный маршрут. Решение хранится до configured retention под прежним byte budget; исходный deadline не продлевается. Snapshot просроченного proposed сохраняет target/attempts, но выставляет `expired/check_expired`, `apply_allowed=false`, `auto_apply_eligible=false`. Apply по прежнему deadline не разрешает маршрут. Удаление/замена результата по source scope и отмена generation сохраняются.

LuCI показывает «Проверка устарела; последняя рабочая альтернатива: …». Proposed без target показывает «Результат проверки недоступен». Успех, устаревшая диагностика и отрицательный результат не смешиваются. Проверка нового задания по-прежнему показывает текущий прогресс. Исторический успех не доказывает доступность сейчас; одно TCP-соединение не принимается за протокольный успех. Новые строки включены в RU/POT и bundle.

## Проверки

Linux Docker `kabanmax-autoroute-tests`, Go 1.26.10; frontend Windows Node. Без субагентов и нагрузки:

- RED: `docker exec kabanmax-autoroute-tests sh -c 'export PATH=/usr/local/go/bin:$PATH; cd /tmp/lifecycle-log.qgN43U; GOPROXY=off go test -count=1 -run TestExpiredDecisionKeepsDiagnosticButCannotGrant -tags=badlinkname,tfogo_checklinkname0,with_wireguard ./common/autoroute'` — exit 1 до патча: TTL deleted the last successful diagnostic.
- GREEN: тот же source после r34, `GOPROXY=off go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./common/autoroute` — exit 0, весь autoroute suite. Сохранены target/attempts, expired Apply не создаёт lease, retention удаляет старую диагностику.
- `npx.cmd vitest run src/kabanmax/tabs/sections/tests/autoRouting.test.ts` — RED 2/14 до UI изменения, GREEN 14/14 после; исходники LuCI state helper и тест. Первый sandbox запуск esbuild был недоступен из-за чтения родительского каталога; разрешённый запуск выполнился.
- `npm.cmd run build`, `npx.cmd eslint src/kabanmax/tabs/sections/autoRouting.ts src/kabanmax/tabs/sections/tests/autoRouting.test.ts` — exit 0: TypeScript, fingerprint gate, новый bundle, целевой lint.
- `docker exec kabanmax-autoroute-tests bash /work/tests/run.sh diagnostics/auto_routing` и `... packaging/core_patch_series` — exit 0: backend сохраняет expired WARP target/attempts, current checking не скрывается старым результатом; core version gate.
- `docker exec kabanmax-autoroute-tests sh /work/dist/preview-025/build-core-binaries.sh` — exit 0: clean pinned archive/check/apply 34 patches, branding, upstream ARM64 base/tiny. Base SHA256 `aac0c395f4bab5860758e40124cf9ae34ea0d80354b81495735d9c3ae73634b7`; tiny `5935785fe5091e084dd40350b6c65ee290cfe9c1d30ea5aed8c309f65bb12eb6`.
- `docker run --rm -e PO2LMO=/usr/local/bin/po2lmo -v "${taskRoot}:/work:ro" -v "${taskRoot}/dist/preview-025:/output" kabanmax-preview-build bash scripts/build-zapret2-local.sh 0.2.5 /output`, затем тот же run с `bash /output/package-core.sh` — exit 0: 10 APK/IPK, source/payload/version/license, 13 SHA records. Новые frontend/RU пакеты и core согласованы.

CI/runner включают новую Go regression. Полные frontend/backend suites, новый hardware WAN-loss/reboot и многодневный soak не выполнялись: изменение ограничено lifecycle диагностики autoroute; предыдущие проверки не выдаются за свежие.

## Установка и ограничения

Рабочий r33 сохранён hardlink во flash и копией на компьютере с SHA256; UCI/runtime и `/etc/kabanmax` — private tar на устройстве и компьютере. Только лишняя старая r31 flash-копия удалена после подтверждения уже сохранённого компьютерного SHA256. Пакеты staged во flash, не двойным большим RAM staging.

Пользователь предупреждён об одном перерыве связи. Запущен detached штатный неизменённый installer: `KABANMAX_RELEASE=0.2.5 KABANMAX_DOWNLOAD_URL=http://127.0.0.1:18086 sh /root/kabanmax-preview-0.2.5/install.sh --variant base --lang ru --quiet`. Installer exit **0**, все четыре пакета 0.2.5/r34 установлены, KabanMax автоматически запущен. SHA256 фактического core совпал с base artifact. Ручные stop/reload не выполнялись.

Аппаратный smoke **03:45–03:47 MSK 2026-11-24**: authenticated `GET /kabanmax/auto`, отфильтрованный по исходному WhatsApp IP, показал новое решение `proposed`, target WARP. Direct дважды transport timeout; WARP дважды `verified/authenticated_https_transport`, TLS verified, HTTP403. Это подтверждение ответа конкретного IP с исходным hostname через WARP, не доказательство успешной авторизации или всех функций WhatsApp. Автоматический диагностический probe выполнился штатно после восстановления Pending, маршрут не применялся, `leases=0`.

Решение создано в 03:45:43, deadline 03:46:43. После 03:46:47 повторный тот же GET сохранил **все четыре attempts и WARP target**, со статусом `expired/check_expired`, `apply_allowed=false`, `auto_apply_eligible=false`. Значит, реальная запись прошла прежнюю границу 60s без потери результата. Backend projection и новый русский UI label проверены локальными тестами/пакетом; интерактивный браузерный smoke пользователя ещё не подтверждён.

UCI config, persisted applied и suppression JSON побайтно совпали с private backup SHA256. Собственный mirror остановлен по проверенному PID/cmdline, собственные APK hardlinks удалены; рабочий r33 backup сохранён. Running, один core PID, MemAvailable около 53 МиБ на read-only снимке. Повторные diagnostic API пробы r33 ранее отклонялись штатным cooldown; ограничения не отключались. GitHub публикации нет.
