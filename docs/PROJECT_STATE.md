# Текущее состояние проекта

**2026-11-25**. [AGENTS](../AGENTS.md), [навигатор](DEVELOPMENT_INDEX.md), [архив](archive/README.md). [Late DNS: r41, публикация готовится](AUTO_ROUTING_LATE_DNS.md).

## Рабочее дерево и выпуск

- **Установлен 0.2.3/core r40, API quota hotfix `212e593`**, stock installer exit 0, running; config неизменён. Raw fallback KabanMax/Zapret2 принудительно проверен native PASS; обычная проверка обоих обновлений PASS. [Release 0.2.3](https://github.com/fefenke/kaban-max/releases/tag/0.2.3): заменены backend APK/IPK/install.sh/SHA256SUMS, все 16 assets сверены, tag `489c074` сохранён. **После restart WARP1 HTTPS 35ms, WARP2 дважды HTTP504 — остаётся открыто.** [Приёмка, сохранение Applied diagnostics и границы](RELEASE_023.md).

- **Предыдущая приёмка 0.2.9/r39, section-wide applied IP:** устранена device-привязка persistent web approvals и удалён uncovered UI status, старые записи мигрируют; core 14 race packages, backend 99/99, frontend 14/14 + build/lint PASS. Оба старых Applied мигрировали на all_devices/all_ports и сохранены в RAM; collector включён, registry errors нет. WARP HTTPS 35/38ms, fallback 34ms; flash used 33352/free 58492 KiB. [Установка](PREVIEW_029.md), [контракт](AUTO_ROUTING_SECTION_IP.md).

- **WARP port hints, введены в 0.2.8/r38 и сохранены в текущем r39:** отдельная подсказка на профиль, 10 минут подтверждённой работы, максимум одно сохранение за router boot. Подошедший старый порт закрывает окно без flash write; поздние изменения RAM-only. Оба WARP/fallback прошли HTTPS 36/35/34ms, binary SHA совпал. Native capture видит два профиля, resident timer обновляет RAM checkpoint; до 10 минут конфиг побайтно совпадает с backup. При последующей установке r39 native UCI уже содержит оба hint 38071/42987, пережившие restart. Непрерывный десятиминутный аппаратный soak/полный reboot не заявляются. [Установка](PREVIEW_028.md), [контракт](WARP_PORT_HINTS.md).

- Базовый локальный commit: `98e5605`, описание Git — release 0.2.2; локальные теги включают 0.2.2. Это сведения Git/README, **не свежая проверка GitHub release**.
- Release commit `489c074` включает r23–r40, документацию, тесты и LuCI bundle. Source и tag `0.2.3` опубликованы нефорсированным atomic push; родительская история сохранена.
- **Предыдущая аппаратная приёмка 0.2.7 / core r37:** Финальная r37 серия: **5/5 реальных restart**, оба WARP и fallback прошли HTTPS после каждого. Последняя проба после UI update: 33/35ms, fallback 34ms. Подтверждённый UDP path сохраняется как мягкий cache hint; external UDP outage cause не объявляется доказанной. [Полная приёмка](PREVIEW_027.md).
- **Flash приведена к норме:** после 0.2.8 used 33312 KiB (~33 MiB), free 58528 KiB, 36%. Первичная r37 установка заполнила flash из-за собственных APK/backups ассистента и повредила partial binary; рабочий r36 восстановлен, затем r37 штатно установлен с LAN mirror компьютера. Дубликаты удалены после SHA сверки уже имеющихся PC copies. Собственные staging/test каталоги и LAN mirror убраны. Tailscale/настройки/результаты не удалялись. [Авария и уборка](PREVIEW_027.md).
- **Журнал активного авторутинга r33:** каждый новый принятый source failure, ранее скрытый в Debug, получает Warn, включая повторные отказы существующей Pending записи. Общие refused/no-route остаются Debug, TLS/auth Error не дублируются. Targeted autoroute/route race PASS. Docker/live доступ восстановлен. [Контракт](LOGGING.md).

- **Публикация подтверждена:** GitHub release ID `457032455`, draft=false, prerelease=false; `/releases/latest` возвращает 0.2.3. Публичные app/core manifests скачаны с роутера: 0.2.3/r40. Нынешний active autoroute source — 1 (изменение пользователя), hardware flow/WAN-loss/reboot/load soak не заявляются. Публикация только после приёмки и нового запроса. История 0.2.3 — [PREVIEW_023](PREVIEW_023.md).

## Факты из исходников

<!-- BEGIN GENERATED PROJECT FACTS -->
| Факт из исходников | Значение |
| --- | --- |
| Upstream | `https://github.com/ushan0v/sing-box-forkop.git` |
| Закреплённый commit | `60d96c99815a672712915a5c00114bf0f690ad80` |
| Версия локального ядра | `1.14.4-r41` |
| Go toolchain | `1.26.10` |
| Количество core patches | 41 |
| Общий minimum core | `1.14.4-r10` |
| Minimum core авторутинга | `1.14.4-r24` |
<!-- END GENERATED PROJECT FACTS -->

Обновление таблицы: `python scripts/check-project-docs.py --write-facts`. Источники — UPSTREAM, серия patches, валидатор/константы. Таблица не подтверждает установку, публикацию или тесты.

## Последние изменения поведения

- **r35–r37 / app 0.2.7:** успешный Pending сохраняется до разбора без протухания/повторного probe; восстановление через private checkpoint. Поле 1h убрано, ограничение — общий memory budget. Dirty-only flash по умолчанию 1d не изменён: новые два применения ещё в RAM, flash applied entries=0, mtime 20 ноября. WARP cold recovery имеет максимум три быстрых rotations до первого handshake, затем прежний 90s backoff; cache hint переиспользует подтверждённый порт, explicit bind и busy fallback защищены. [Контракт и tests](PREVIEW_027.md).

- **r23:** EAGAIN/EWOULDBLOCK не запускают авторутинг; source не показывается как альтернатива; отзыв отсутствующего lease идемпотентен; сбой private checkpoint после сохранения intent не выключает секцию. [Разбор №2–4](AUTO_ROUTING_FIELD_ERRORS.md).
- **r24:** компактные routes/exclusions в RAM; dirty-only atomic flash checkpoint `1d` (`12h` допустим); retention `1h`; accounted budget `4 МиБ`. Вместо 64 записей — byte admission; pressure checkpoint не чаще 15 минут; grants/denies сохраняются. Учтены in-flight context и быстрый путь успешных соединений. [Контракт](AUTO_ROUTING_STORAGE.md).
- **Документация:** актуальный вход, машинная карта компонентов, журнал контекста, один ассистент и обязательное обновление документов. [WORKFLOW](WORKFLOW.md).
- **Диагностика:** журнал до 256 КиБ/2048 записей, bounded input/RPC; core `/connections` до 200 строк с реальным total. Replay VmHWM 26776 → 6064 kB не диагностирует весь аппаратный OOM. Copy/close, routine transport, refused/timeout, FakeIP, malformed/service DNS и fallback suspect/probe-only — Debug. DNS: первый отказ Warn, повторы только server+domain+type+class, bounded windows. TLS/auth и confirmed fallback остаются; при подтверждённом WAN-loss сетевой шум gated между одной записью причины и одной recovery. [LOGGING](LOGGING.md), [WAN](NETWORK_AVAILABILITY.md).
- **IPv6 FakeIP:** `2001:2::/112`, прежний размер пула; generator/nft/forecast/public-IP/autoroute guard согласованы. Store migration сохраняет IPv4 и отбрасывает старые IPv6-соответствия без удаления общего cache. Chromium/runtime hardware не проверялся. [Причина и миграция](NETWORK_AVAILABILITY.md).

## Доказательства и пределы

| Работа | Результат (дата в отчёте) | Источник |
| --- | --- | --- |
| Preview 0.2.4/r31 · 24 ноября | Lifecycle и scope RED/GREEN, backend 97/97, core race/HUP, 10 APK/IPK PASS; install exit 0. Synthetic live reset PASS; WARP1 снова отказал, WARP2 доступен | [точные команды](PREVIEW_024.md) |
| Полный preview 0.2.3 | Свежие frontend 177/1701, backend 97/97, core race scope, syntax/lint/build; 10 APK/IPK и 13 SHA256 records PASS. Штатная ARM64 установка exit 0; версии/WARP/HTTPS и сохранность registry/credentials проверены; приёмка пользователем впереди | [точные команды и границы](PREVIEW_023.md) |
| WARP recovery r29 | RED/GREEN; 29 patches, 4 race packages + cmd compile; generator/packaging по 1/1, 4 logging suites, оба syntax режима, docs gate PASS. ARM64 manual install + HTTPS/YouTube smoke, видеоданные и подтверждение пользователя; повторный reload/WAN soak не выполнен | [команды и границы](WARP_RECOVERY.md) |
| Авторутинг r24 | frontend 177 файлов / 1697 тестов; backend 97/97; TypeScript, целевой lint, bundle PASS | [точные команды](AUTO_ROUTING_STORAGE.md) |
| Ядро r24 | clean apply 24 patches, семь Go race suites, compile check PASS; 2000 synthetic routes при 8 МиБ | [метод и ограничения](AUTO_ROUTING_STORAGE.md) |
| Документация | отдельная текущая проверка; runtime suites не выдаются за повторные | [аудит](DOCUMENTATION_AUDIT.md) |
| Журнал/мониторинг | frontend 177 файлов / 1701 тест; backend 97/97; clean apply 25 patches + Go race clashapi/trafficcontrol + cmd compile; replay 16000 строк; TypeScript/lint/bundle, docs 9 tests/gate PASS | [точные команды и пределы](LOGGING.md) |
| Уровни core-логов | clean apply 26 patches; race route/DNS/fallback + cmd compile PASS; packaging 1/1. Предыдущие frontend/backend suites не выдаются за свежие | [точные команды и границы](LOGGING.md) |
| WAN/DNS/FakeIPv6 | clean apply 28 patches; 7 Go race packages + cmd compile PASS; backend 97/97 после IPv6 changes. Внешние WAN-пробы в тестах не запускались; frontend/RSS старые | [точные команды, upstream и пределы](NETWORK_AVAILABILITY.md) |

## Открыто




1. Общий OOM при **выключенном авторутинге**: причина не установлена. Не приписывать авторутингу или Tailscale без данных. [KNOWN_ISSUES](KNOWN_ISSUES.md).
2. Исторический отказ удаления исключений на конкретном роутере полностью не воспроизведён. Cleanup при disabled source проверен локально, а не на всех семи устройствах.
3. Длительная приёмка OpenWrt/LuCI, ARM64 runtime, реальных WARP/VPN/DNS/NFQUEUE/PBR/mwan3 и reboot/power loss не выполнялась в r23/r24 задачах.
4. Шумные «no route to host»/«endpoint not connected»/refused/timeout в ConnectionManager — Debug, не исправление сети. WAN two-event suppression и DNS per-question реализованы локально; hardware WAN-loss/PBR/IPv6-only/Edge ещё не проверены. Анимация отложена; TLS-разбиение на три записи не реализовано.
5. r37 прошёл 5/5 restart/HTTPS; pending результата не протухают и не перепроверяются автоматически, поле 1h удалено в 0.2.7. Открыты многодневная приёмка, полный power loss, hardware WAN-loss и пользовательский UI Delete. Не выдавать ограниченный smoke за эти проверки.

Далее — пользовательская приёмка preview несколько дней. Новые установки/публикация/live доступ вне текущего разрешённого scope автоматически не разрешены. [ROADMAP](ROADMAP.md).
