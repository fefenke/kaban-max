# Журнал и мониторинг: ограничение памяти

**Локальный r46:** поздние stream TLS/unknown failures не выводятся в Error. Диагностируемые ошибки открытия/отложенного outbound handshake получают адрес, маршрут, этап и предметную проверку; без этого остаются Debug. Client handshake отдельно Debug. Типизированные DNS REFUSED/SERVFAIL сохраняют полезный Error. Fallback/WAN/lifecycle не менялись. [Точный контракт, границы и проверки](ACTIONABLE_CONNECTION_LOGS.md).

**Локальный r45:** возвращён прежний критерий stable fallback: успешный независимый confirmation означает healthy, без failed-check/suspect/confirmed Warn для этой пары. Общий код WARP/VLESS. Остальные уровни сообщений не менялись. По запросу установлен на локальный роутер. [Контракт](FALLBACK_CONFIRMATION_SUCCESS.md).

**Текущий локальный r44:** ошибки передачи уже установленного соединения не запускают fallback health и не создают дополнительный Warn `fallback active outbound failure [connection]`. Проверку по ошибке открытия нового соединения сохранили. Диагностические Warn подтверждения health и переключения сохранены; WAN/lifecycle/classified connection logging не менялись. Установлен на локальный роутер по запросу пользователя. [Исправление](FALLBACK_DIAL_ONLY.md).

**Локальный r42:** при пороге Warn видны Warn/Error/Fatal/Panic. Возвращены fallback Warn, classified copy errors и Applied target Warn. Lifecycle suppression сохранён; **WAN gate не изменён**, подавление связанных сетевых ошибок при подтверждённом WAN outage соответствует прямому уточнению пользователя. [Точный контракт и свежие проверки](WARP_RUNTIME_FIX.md). На роутер r42 ещё не установлен.

Текущий локальный контракт от 2026-11-23. Версия и публикационный статус — [PROJECT_STATE](PROJECT_STATE.md). Источник ядра — pinned UPSTREAM + patches; память снимков — `0025-bounded-connection-snapshots.patch`, уровни сообщений — `0026-actionable-log-levels.patch`.

2026-11-23 первоначальная logging-only установка заменена полным согласованным preview **0.2.3/r29**, включая новый LuCI bundle, backend и core snapshot. Level Warn сохранён; свежий frontend/backend/core/package scope и текущие ARM64 smoke — [PREVIEW_023](PREVIEW_023.md). Первоначальный старый лимит 2 МиБ/r22 и reboot при первой подготовке описаны в [WARP_RECOVERY](WARP_RECOVERY.md). Подтверждения устранения общего OOM нет.

2026-11-24 установлен 0.2.4/r31: общий logger переводит Warn/Error отменённого поколения core в Debug независимо от текста; root context живого поколения и критические startup errors не заглушены. Реальный loopback HUP smoke и race regression — [PREVIEW_024](PREVIEW_024.md). Дополнительных аппаратных reload ради проверки не было.

Patch `0033-auto-source-warnings.patch`: каждый новый принятый отказ исходного маршрута активного авторутинга выводится в Warn, включая уже существующую запись Pending. Общая классификация routine connection failures остаётся Debug; source callback повышает только их, поэтому TLS protocol/auth, уже имеющие Error, не дублируются. Повторный вызов Failed для одного события, отклонённый admission и ошибка alternative lease нового source Warn не создают. Новых dedup maps/timers нет. WARN отменённого root context по-прежнему переводится в Debug механизмом r30; WAN suppression сохраняется. Реестр получает структурное событие, не парсит текст журнала. Пользователь уточнил: требуется каждый новый отказ, а не только первый за время существования Pending.

## Что было подтверждено

Пользователь сообщил зависание после включения Info/Trace и открытия «Логи», а также недоступность списка/зависание при большом количестве соединений в «Мониторинге». Слабейшее указанное устройство — Cudy WR3000S с 256 МБ RAM. Присланная строка `The router ran out of memory and the kernel killed sing-box` подтверждает распознанное lifecycle убийство sing-box ядром. Она не устанавливает процесс, израсходовавший память.

Исходный journal ограничивал текст/JSON 2 МиБ, но не число объектов и отдельную строку. `prune` заново сериализовал все записи при сборе и чтении. RPC собирал весь текст даже для `unchanged`, а многостраничный снимок оставался в RAM после передачи. В replay 16000 строк процесс ucode достиг VmHWM 26776 kB при 1620890 байтах текста и 2040671 байте архива.

Core `/connections` копировал весь набор metadata, создавал ещё два массива Filter/Map и кодировал полный JSON. WebSocket повторял это каждую секунду; ucode fallback ещё держал chunks, объединённую строку и сериализацию RPC. Большой ответ мог также превышать примерно 256 КБ транспорта rpcd и отображаться как недоступный. Это подтверждённые механизмы расхода/отказа; конкретный аппаратный OOM и прежний общий OOM при выключенном авторутинге ими не объявляются объяснёнными.

## Текущий контракт

| Участок | Ограничение и поведение |
| --- | --- |
| Journal | До 24h, 256 КиБ текста, 2048 записей, 512 КиБ сериализованного архива; вытеснение старых записей |
| Одна строка | До 2048 байт, UTF-8 boundary + `[truncated]` |
| Сбор | Каждые 1.5s, последние 200 строк, максимум 64 КиБ входного буфера; file-backed capture читает только ограниченный хвост |
| Объекты journal | Размер сериализации вычисляется один раз при admission/restore; prune использует счётчики и удаляет префикс |
| Restore | Ограничивает записи до первой выдачи; старый archive.json больше 512 КиБ не парсится, отбрасывается с предупреждением и новым сбором системного хвоста |
| RPC | До 32 КиБ текста на страницу без разрезания UTF-8; `unchanged` не собирает текст; снимок освобождается после последней страницы, clear либо спустя 30s на очередном сборе |
| Core `/connections` | До 200 последних non-DNS соединений, детерминированно по CreatedAt/UUID; selection heap ограничен 200 элементами, без полного массива. `connectionsTotal` содержит реальное число, `truncated` — признак неполного списка |
| HTTP и WebSocket | Один контракт снимка; `/connections` также ограничен у сторонних клиентов, включая YACD. DELETE connection/all не изменён |
| Мониторинг LuCI | До 200 active и прежние 300 closed; явная строка «показано X из Y», фильтры только по отображаемой части. Пропуск строки в partial snapshot и переход из partial в full не создают ложное событие закрытия |
| Dashboard | Читает `connectionsTotal`, при старом core — длину массива |
| Резервный HTTP/RPC | `/connections` до 128 КиБ тела; прочие обычные ответы до 2 МиБ, заголовки до 16 КиБ. Переполнение возвращает явную ошибку safe size limit, которая видна в UI. Streaming decode ruleset sync остаётся отдельным путём |

256 КиБ — лимит текста, не обещание общего RSS процесса. Отсутствие записей дольше указанного срока не гарантируется: заполнение, кольцо logd и более 200 новых строк между сборами могут сокращать историю. При Info/Trace журнал заполняется быстрее. Это журнал диагностики, не без потерь traffic capture.

Для защиты формирования снимка нужен новый core вместе с LuCI/backend. Один frontend не ограничивает аллокации старого core. Общий compatibility floor остаётся прежним; это не обещание защиты старого ядра. Полный список сверх 200, серверные фильтры и пагинация сейчас не реализованы. Закрытые записи — наблюдения страницы, а не полный аудит соединений.

## Уровни, источники и шум

Настройка `log_level` задаёт порог sing-box; Warn включает Warn/Error/Fatal/Panic. На собственные KABANMAX `[info]/[warn]/[error]` она не влияет. Вкладка выбирает kabanmax/sing-box и относящийся к ним procd. Прямой kernel OOM может быть за пределами отбора, но lifecycle читает dmesg и публикует собственное предупреждение при совпадении PID жертвы.

Внешний `daemon.err` может сопровождать внутренний TRACE или WARN, поэтому по нему одному severity не определяется. Поиск — подстрока, не переключение порога. Copy/Download с поиском экспортируют совпавшие строки. Отдельный дублирующий фильтр «Только ошибки» не добавлен.

| Пример пользователя | Что следует из строки / действие |
| --- | --- |
| `connection download closed: write tcp4 remote->192.168...: no route to host`, 87m43s | Ошибка записи в сторону LAN-клиента после долгой сессии; не доказательство блокировки remote или отказа исходного Zapret dial. Проверять доступность клиента/локальный маршрут и повторяемость; не создавать WARP-исключение только по этой строке |
| `connection upload closed: raw read: no route to host` | Ошибка чтения существующего соединения; без контекста нельзя установить сторону/причину и считать её отказом обхода |
| `endpoint not connected` при закрытии | Сообщение об операции над уже не подключённым endpoint; само по себе не доказывает отказ нового соединения или всей WARP-секции |
| `TRACE ... connection upload closed` без ошибки | Техническая запись завершения; видна при Trace и не должна попадать под Warn |
| `dns: bad question size: 2` | Отказ обработки DNS-вопроса; конкретный отправитель/формат требует проверки, по одной строке причина и необходимость исправления клиента не устанавливаются |
| `version.maradns. CH TXT`, `version.pdns. CH TXT`, `REFUSED` | CHAOS/TXT запросы служебной информации DNS, upstream отказал. Это отличается от отказа обычного IN A/AAAA сайта; отправитель и связь с YouTube по таким строкам не установлены |
| `3 more exchanges failed in 10s` | Уже агрегированный core счётчик повторов; нельзя прибавлять его как один обычный DNS-запрос при дальнейшей группировке |
| `no fakeip record ... shortly before a crash ...` | Клиент использует FakeIP без сохранившегося соответствия. После повторного разрешения имени получает новую запись; crash/reboot и потеря RAM-cache могут объяснять событие, но не доказывают причину каждой строки |
| `tls: protocol version not supported` | Несовместимость версий TLS на конкретном взаимодействии; нужны server/flow/direction. Глобальное ослабление TLS не является исправлением |
| direct-out в окно restart | Возможны закрытия старых соединений при пересоздании core. Для понижения severity нужен контекст планового shutdown, а не только текст `direct-out` |

### Политика уровней после запроса пользователя

Таблица описывает локальный r42. При Warn видны Warn/Error/Fatal/Panic; Debug/Trace ниже порога. Уже сохранённые строки не удаляются. Уровень классифицируется у источника, а согласованные lifecycle/WAN исключения применяются отдельно.

| Событие | Уровень / область |
| --- | --- |
| Ошибка TCP upload/download copy или half-close существующего соединения | Classified: routine Debug, TLS/auth/неизвестная protocol error — Error; причина и close callback сохраняются |
| `EHOSTUNREACH`, `ENETUNREACH`, `ENOTCONN`, `ECONNRESET`, `ECONNABORTED`, `EPIPE`; отмена/EOF/закрытый socket при открытии/подтверждении handshake в ConnectionManager | Debug. Typed unwrap + точные suffix для userspace `no route to host`, `network is unreachable`, `endpoint not connected`, `connection reset by peer`, `broken pipe` |
| Отсутствующий FakeIP record | Warn; соединение по-прежнему отклоняется |
| DNS `bad question size` | Warn в Client и Router; FORMATERROR сохраняется |
| REFUSED на CHAOS/TXT для `version.bind.`, `version.maradns.`, `version.pdns.`, `hostname.bind.`, `id.server.` | Debug, без открытия/загрязнения окна отказов обычного DNS; возврат причины и IsLoggedFailure сохраняются |
| Первый отказ обычного DNS exchange | Warn с сервером/доменом/типом/классом/причиной |
| Повторные DNS failures того же server+domain+type+class за 10s | Один Warn: число дополнительных отказов и причина именно этого вопроса. Разные домены не смешиваются; окна/причины ограничены по памяти |
| Fallback probe-only failure с подтверждёнными свежими данными пользователя; промежуточный suspect | Warn. Успех независимого confirmURL больше не стирает primary failure |
| Fallback confirmed failure | Прежний Warn: именованный выход и причина подтверждённого отказа |
| `connection refused`, настоящие deadline/timeout при открытии соединения в ConnectionManager | Debug по дополнительному указанию пользователя; причины/close handler сохраняются |
| TLS/version/certificate/auth/config ошибки | Error при открытии и поздней copy; при подтверждённом отсутствии WAN действует прежнее подавление связанных сетевых сообщений |
| Ошибка выбранного Applied маршрута | Routine причина получает selected-route Warn; не маркируется как исходный отказ. Non-routine Error не дублируется |
| Поздний сбой stable TCP stream и смена участника | Warn. Late failure запускает внеочередную bounded health check; обычный EOF/close/cancel не запускает |
| Запуск/apply/проверка конфигурации, отсутствующие зависимости, OOM/crash, ошибки сохранения/отзыва и внутренние ошибки | Прежние уровни сохраняются. Прочие logger sites/зависимости не превращены в глобальный whitelist |

Предварительное предположение «полезность можно определить по возрасту 17–20 минут» не стало правилом: ошибки завершения понижены независимо от возраста. Deadline сначала сохранялся, затем по прямому дополнительному указанию переведён в Debug; тест обновлён под текущий контракт. Авторутинг получает те же ошибки/события, алгоритм fallback и обработка DNS не ослаблены. Не введено обещание автоматически объяснять причину каждого сообщения или доказывать WAN-loss по одному отказу.

Группировка UI всех произвольных сообщений остаётся предложением; DNS-группы реализованы у источника по одному вопросу. Для IN A/AAAA отказов YouTube нужны сами строки: присланные CH TXT не объясняют профильную зависимость.

WAN suppression реализован отдельным monitor/gate: после подтверждения — одна запись с наблюдаемой причиной, подавление связанных сетевых Warn/Error и одна запись восстановления со счётчиком. Carrier/TCP dial/отказ одного VPN не являются доказательством. Unknown не включает suppression. [Точный контракт проверок, TLS/память, netifd-причины и ограничения](NETWORK_AVAILABILITY.md).

## Проверка памяти и мониторинга — 2026-11-23 (этап до изменения уровней)

Linux x86_64, локальный Docker-контейнер `kabanmax-autoroute-tests`, проект `/work` read-only; ucode v0.0.20250529, Go 1.26.10. Windows frontend Node/npm из проекта. Никаких сетевых запросов к роутеру/VPS, установки или публикации.

| Точная команда | Scope / результат |
| --- | --- |
| `docker exec kabanmax-autoroute-tests sh -c 'cd /work && ucode -L kabanmax/files/usr/lib tests/service/log_journal_pressure.uc'` | До: 16000 records / text 1620890 / archive 2040671 / VmHWM 26776 kB. После: 2048 / 208896 / 265926 / VmHWM 6064 kB; elapsed 8s. Исходное elapsed не было корректно измерено; ускорение не заявляется |
| `docker exec kabanmax-autoroute-tests sh -c 'cd /work && bash tests/run.sh'` | PASS: 97/97 backend test files; перед реализацией новые journal/byte-cap/summary regression были RED |
| `docker exec kabanmax-autoroute-tests sh -c 'export PATH=/usr/local/go/bin:$PATH; sh /work/tests/core/run_connections_snapshot.sh /tmp/core /work'` | Clean archive pinned commit + все 25 patches; Go race clashapi/trafficcontrol PASS, selection 10000 → 200. Новая Go-регрессия была RED до реализации |
| `npx.cmd vitest run --maxWorkers=2 --reporter=dot` из `fe-app-kabanmax` | PASS: 177 файлов / 1701 тест; новые UI-регрессии перед реализацией были RED |
| `npx.cmd eslint src/kabanmax/tabs/logs/render.ts src/kabanmax/tabs/monitoring/render.ts src/kabanmax/tabs/monitoring/initController.ts src/kabanmax/tabs/monitoring/tests/initController.test.ts src/kabanmax/methods/custom/clashApi.ts src/kabanmax/methods/custom/tests/clashApi.test.ts` | PASS |
| `npm.cmd run build` из `fe-app-kabanmax` | PASS: fingerprint check, TypeScript и LuCI bundle; не release package |
| `docker exec kabanmax-autoroute-tests sh -c 'cd /work && bash tests/run.sh service/state_service && for file in kabanmax/files/usr/lib/core/exec.uc kabanmax/files/usr/lib/service/log_journal.uc kabanmax/files/usr/lib/service/state_service.uc kabanmax/files/usr/lib/singbox/clash_api.uc; do ucode -c -o /dev/null "$file" && ucode -S -c -o /dev/null "$file" || exit; done; export PATH=/usr/local/go/bin:$PATH; sh tests/core/run_connections_snapshot.sh /tmp/core /work'` | PASS: финальные restore/transfer tests, оба syntax-режима четырёх backend файлов, повтор clean apply/race и compile-only cmd/sing-box |
| `python -m unittest discover -s tests/docs -p 'test_*.py'` | PASS: 9 тестов |
| `python scripts/check-project-docs.py --write-facts`, затем `python scripts/check-project-docs.py` | PASS: source facts (25 patches), пути/UTF-8/coverage; не runtime evidence |
| `git diff --check` | PASS |
| `docker exec kabanmax-autoroute-tests sh -c 'cd /work && bash tests/run.sh service/log_journal && ucode -c -o /dev/null kabanmax/files/usr/lib/service/log_journal.uc && ucode -S -c -o /dev/null kabanmax/files/usr/lib/service/log_journal.uc'` | PASS после саморевью: bounded restore меняет revision и не оставляет старый полный текст в browser cache |

Ограничения: RSS — один локальный synthetic replay, не ARM64 и не предельный RSS всех процессов. Нет длительной аппаратной приёмки, WAN-loss/restart wire-теста, power-loss теста, YACD hardware smoke, сборки/установки пакетов. Пересмотреть вывод о конкретном OOM при наличии kernel context и динамики RSS на проблемном устройстве. Эта задача не диагностирует весь расход 256 МБ RAM.

## Проверка уровней — 2026-11-23 (этап до per-domain DNS/WAN)

Окружение: тот же локальный контейнер, pinned upstream + 26 patches, Go 1.26.10 x86_64; проекта/роутеров не устанавливалось. Новые тесты ConnectionManager и DNS сначала были RED (нет классификатора, CHAOS открывал error window; одиночный/повторный DNS имели Error/Error). При первом GREEN-кандидате регрессия обнаружила неправильное понижение deadline из-за E.IsClosedOrCanceled; классификация исправлена на отдельные typed причины.

Команды и итог:

- `docker exec kabanmax-autoroute-tests env PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin sh /work/tests/core/run_log_policy.sh /tmp/core /work` — PASS: clean archive/apply всех 26 patches; race `route`, `dns`, `protocol/group` и compile-only `cmd/sing-box`.
- `docker exec kabanmax-autoroute-tests bash /work/tests/run.sh packaging/core_patch_series` — PASS, 1/1 test file; общий minimum core не повышен.
- `python scripts/check-project-docs.py --write-facts`, `python scripts/check-project-docs.py`, `git diff --check` — финальный gate после source facts/doc update.

Тесты проверяют оба направления copy и неизменный close callback/cause, wrapped errno и userspace suffix, сохранение TLS/auth/refused/deadline на Error, реальный FORMATERROR у некорректного DNS, исключение служебного REFUSED из DNS window и уровни/счётчик повторного DNS. Существующие route/FakeIP, DNS и fallback suites выполняются тем же runner. Frontend/backend suites и RSS replay предыдущего этапа не выдаются за повторные. Нет аппаратного/restart/WAN-loss smoke, новых APK/IPK и публикации.
