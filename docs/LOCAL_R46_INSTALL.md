# Локальная установка0.2.3/r46 и выбор confirmation URL

2026-11-26, два прямых запроса пользователя: установить совместно подготовленные logging/DNS исправления на локальный роутер; добавить выбираемый confirmation URL и также установить. Другие роутеры и GitHub не затрагивались.

## Итоговый комплект

App/LuCI/RU0.2.3, ARM64 base core1.14.4-r46. Содержит0046 actionability logging, backend DNS HUP guard и однострочный UI change: `confirm_url` использует тот же `LATENCY_TEST_URL_OPTIONS` через LuCI `form.Value.value`, что и основной health URL. Поэтому доступен список и произвольный ввод. Default Cloudflare generate_204/HTTP204 сохранён; основной default gstatic. Сохранённые адреса не переписываются; backend по-прежнему требует другой HTTPS URL. HTTP-код подтверждения остаётся настраиваемым, должен соответствовать выбранному адресу.

## Проверка и упаковка

Существующие backend/core проверки — в [logging](ACTIONABLE_CONNECTION_LOGS.md) и [DNS](RELOAD_DNS_PAUSE.md). После UI-правки `npx.cmd eslint src/kabanmax/tabs/sections/fallback.ts` —PASS. `npm.cmd run build` —PASS fingerprints/TypeScript/tsup/LuCI patch. Первоначальный обычный запуск esbuild не смог прочитать родительский каталог в sandbox; повтор с разрешённым выполнением прошёл. Глобальные настройки не менялись. Новые tests, повторяющие однострочное подключение готового widget, не добавлялись; полный старый frontend suite не объявляется свежим.

Existing offline `kabanmax-preview-build`, `--network none`, `bash /work/dist/auto-routing-r46/package-release.sh`: после нового bundle PASS10APK/IPK payload/source/binary/license agreement,13SHA records. Новый UI SHA после substitution версии0.2.3: `1ff1cd2370ecd9707dc6eb182a7758579221ebd820fe2c23d545a5627cccbf4f`. Итоговый комплект ignored `dist/auto-routing-r46/release` обновлён.

## Установка на устройство

До начала: r45/running, flash used34024/free57820KiB. Сохранён только SHA UCI для before/after comparison; содержимое/секреты не выводились. Четыре APK/installer/manifests/SHA256SUMS переданы во временный flash mirror, переданные позиции проверены по SHA. Автономный runner запустил loopback-only mirror и неизменённый штатный installer: `KABANMAX_RELEASE=0.2.3 KABANMAX_REINSTALL=1 KABANMAX_DOWNLOAD_URL=http://127.0.0.1:18083 sh install.sh --variant base --lang ru --quiet`. Пользователь предупреждён о паузе. Ручного stop/reload не было; installer выполнил transaction/start сам, exit0. Mirror завершается runner.

`/etc/init.d/kabanmax status`: running; `sing-box version`:r46; executable SHA `a66dbd8baab8423fa251c71a824d4bcbfffe1d736e93b5aceffc8959f1ef457f` совпал с финальным. `sha256sum -c /tmp/kabanmax-r46-config-before.sha256`:OK. Новый `dns_capture_pause` существует, активен hook из mangle до DNAT. Capture/DNS pause после установки пусты: трафик не оставлен заблокированным.

Во время первой установки пользователь добавил UI-пожелание. После сборки отдельно передан и SHA-checked новый LuCI APK. Native `apk add --simulate --allow-untrusted --no-network FILE` показал только1replacement LuCI. Затем тот же `apk add` без simulate установил пакет с обычными pre/post-upgrade hooks: exit0. У LuCI hook обновляет state/rpcd, не sing-box; PID ядра до/после совпал. Это UI-only package update после уже завершённого полного штатного installer, не ручная подмена runtime или его stop/start. Отсутствующие offline feed indexes дали warnings; зависимостей не скачивали, transaction успешен.

Установленный UI SHA совпал с новым выше; UCI повторно OK. Native HTTPS delay через Cloudflare generate_204, timeout8000: WARP1=45ms, WARP2=39ms, VLESS fallback=78ms, API HTTP200. Backend:1source, AutoApply=true, disabled0, registry/diagnostics errors пусты. Временные собственные APK удалены после двух успешных установок, flash used34296/free57548KiB,37%.

Короткая аппаратная проверка не доказывает устранение всех переменчивых WARP timeout или сообщения региона. Отдельный HUP с непрерывными клиентскими DNS/browser captures после нового guard в этой установке не запускали. Поля browser UI пользователю нужно перечитать после Ctrl+F5; фактический визуальный браузерный тест не выполнялся. Source docs gate/diff проверяются отдельно. Публикации нет.
