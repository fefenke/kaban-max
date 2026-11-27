# Журнал инженерного контекста

- 2026-11-27: подготовлена публикация 0.2.3/r46, оформлены README/сайт/установка; отдельно разрешена очистка истории и старых тегов. Сохранены приватные backups всех выпусков; 35 очищенных коммитов, 13 комплектов LuCI без метаданных PNG и исходный архив проверены. Свежие frontend/backend/core race/package/docs проверки PASS. Фактический статус публикации — [в отчёте](PUBLICATION_023.md). Роутеры не затрагивались.

- 2026-11-27: подготовлена команда установки неопубликованного r46 с ПК на заданный список роутеров: package/variant selection, local SHA, двухфазный upload/launch, file runner и статус. Локальные mock/WhatIf/shell syntax PASS; к остальным роутерам ассистент не подключался. [Инструкция](UPDATE_LOCAL_PREVIEW.md).

- 2026-11-26: полныйr46 установлен на локальный роутер, затем по дополнительному запросу установлен LuCI confirmation URL combobox без перезапуска core. Installer/UI/SHA/UCI/HTTPS PASS; повторные HUP с клиентским DNS capture ещё не проверены. [Приёмка](LOCAL_R46_INSTALL.md).

- 2026-11-26: найден и локально закрыт unmarked DNS bypass на HUP pause. Backend101/101, оба ucode syntax и OpenWrt nft check-only PASS; живой firewall не менялся. Причинность сообщения региона требует аппаратного воспроизведения. [Evidence](RELOAD_DNS_PAUSE.md).

- 2026-11-26:0046 разделяет stream/client-handshake Debug и диагностируемые connect/outbound-handshake Error с контекстом/подсказкой; REFUSED/SERVFAIL не теряются. [Контракт и приёмка](ACTIONABLE_CONNECTION_LOGS.md).

- 2026-11-26: r45 штатно установлен на локальный роутер, SHA/config/WARP/VLESS HTTPS PASS. Затем подтверждено расхождение single-URL latency н/д и healthy по OR-policy; пользователь открывает новые видео, объяснять их только старой сессией нельзя. Причина probe timeout ещё не доказана. [Evidence](FALLBACK_CONFIRMATION_SUCCESS.md).

- 2026-11-26: по прямому запросу в0045 возвращена OR-семантика health старого fallback, общая для WARP/VLESS. RED→GREEN unit/race и real TLS/data executable PASS. Установка/публикация не выполнялись. [Evidence](FALLBACK_CONFIRMATION_SUCCESS.md).

- 2026-11-26: статически сопоставлены fallback0.2.0/0.2.2 и r44: одинаковая старая стратегия, изменение0042 «primary fail несмотря на confirmation ok» объясняет большую чувствительность. Production/роутер не менялись. [Сравнение](FALLBACK_STRATEGY_HISTORY.md).

- 2026-11-26: r44 собран/упакован и штатно установлен на локальный роутер по прямому запросу; SHA/config/служба и оба HTTPS WARP PASS. [Приёмка](FALLBACK_DIAL_ONLY.md).

- 2026-11-26: append-only r44 отменяет stream observer и общий fallback connection Warn по уточнению пользователя; dial-triggered health сохранён. [Контракт](FALLBACK_DIAL_ONLY.md).

- 2026-11-26: r43 установлен на локальный роутер штатным installer; оба WARP HTTPS smoke PASS. Затем проверен stream Warn: нормальные закрытия отфильтрованы, reset/broken pipe могут запускать health исправного туннеля; причина `request_failed` теряется при категоризации. Узкие race tests PASS; runtime поведение в аудите не менялось. [Evidence](AUTO_ROUTING_R43.md).

- 2026-11-26: локальный r43 согласует5s/8s budgets, добавляет выключенный explicit TCP protocol-risk opt-in и убирает постоянную Applied тревогу от исторического timeout, сохраняя данные/логи. Новых checks для успешных persistent IP нет. [Evidence](AUTO_ROUTING_R43.md).

- 2026-11-26: разобран5s/8s timeout mismatch, добавлен ещё не исполненный delayed-dial TLS/HTTP regression. Две попытки Docker execution остановлены approval-service HTTP403; production исправление не внесено, r42 packages не менялись.

- 2026-11-26: продолжена проверка локального r42; исходники/сборка ещё не установлены и не опубликованы. Подавление при подтверждённом отсутствии WAN оставлено по прямому уточнению пользователя. [Текущий контракт](WARP_RUNTIME_FIX.md).

- 2026-11-25: read-only аудит r41 разделил lifecycle suppression, глобальные уровни, WAN gate, Applied errors и частичный отказ WARP; найдены противоречия прежним гарантиям видимости. Production изменений нет. [Отчёт](WARP_LOGGING_AUDIT.md).

- 2026-11-24: реализована bounded RAM Applied diagnostics, подготовлен публичный 0.2.3/r40 с чистыми текущими файлами и сохранённой историей. [Evidence и статус](RELEASE_023.md).

- 2026-11-24: read-only разбор r39 — потеря Applied failure/domain diagnostics в RAM compact projection, пустой Error и splice timeout; [evidence и границы](AUTO_ROUTING_APPLIED_DIAGNOSTICS.md). Runtime fix не заявляется.

- 2026-11-24: зафиксировано уточнение пользователя о section-wide Applied IP, migration/ownership/storage и удалении uncovered status. Установлен 0.2.9/r39, точные команды и границы — [PREVIEW_029](PREVIEW_029.md), контракт — [AUTO_ROUTING_SECTION_IP](AUTO_ROUTING_SECTION_IP.md).

- 2026-11-24: documented the agreed WARP durable port hint policy, boot write allowance and local r38 verification in [WARP_PORT_HINTS](WARP_PORT_HINTS.md). Preview 0.2.8/r38 is now installed with stock install.sh; HTTPS smoke and resource limits are recorded in [PREVIEW_028](PREVIEW_028.md).

2026-11-24: завершён 0.2.7/r37. Фактические 5/5 restart/HTTPS, сохранность RAM intent при flash applied=0, удалённое TTL поле, backend 97/97, frontend 15/15, package/doc gates и cleanup зафиксированы в PREVIEW_027. Ошибка flash-staged установки, восстановление r36 и успешная повторная штатная установка с LAN mirror описаны без сокрытия; финально занято ~33 МиБ, own mirror/scripts удалены. Многодневный soak и power loss не заявляются.

2026-11-24: реализованы окончательный Pending контракт без протухания/автопроверки и WARP-only cold-start recovery с максимум тремя быстрыми rotations перед прежним backoff. 0.2.6/r36 установлен штатно, restart-серия ещё идёт. Автопроверка запретила удаление migration sidecar: выбран безопасный вариант, копия оставлена, тесты без удаления данных. [Отчёт](PREVIEW_026.md).

2026-11-24: по новому прямому разрешению выполнены два WARP restart-теста; оба воспроизвели начальный отказ второго профиля. PROJECT_STATE исправлен: startup не устранён, self-heal не равен успешному старту. Последний контракт Pending без протухания и draft 0035 ещё не завершены/не установлены.

2026-11-24: root cause Pending найден в cleanup по decision deadline; подготовлен 0.2.5/r34 с отдельным retention диагностики, explicit expired state и regression core/backend/UI. Аппаратные результаты — PREVIEW_025.

2026-11-24: read-only snapshot подтвердил misleading Pending label: proposed с alternative_reachable, но без decision/target превращается LuCI в «альтернатива не найдена». Новый дефект и ограничения повторной диагностики записаны в PROJECT_STATE; исходники/роутер не изменялись.

2026-11-24: подтверждён пропуск fresh-port recovery WireGuard transport; добавлены crypto/UDP regression и контракт каждого нового source failure в Warn. r33 установлен штатно: оба профиля получили HTTPS, второй автоматически восстановился после смены UDP-порта без restart. Длительная приёмка продолжается.

Изменения продукта ведутся в [корневом CHANGELOG](../CHANGELOG.md). Здесь фиксируются изменения структуры знаний и правил работы; версии и доказательства — в [PROJECT_STATE](PROJECT_STATE.md).

## 2026-11-24 — две регрессии исправлены, WARP и META остаются открытыми

- [PREVIEW_024](PREVIEW_024.md): 0.2.4/r31, lifecycle log tests/настоящий loopback HUP, canonical scope RED/GREEN, штатная установка и real API reset без удаления пользовательских записей.
- [WARP_RECOVERY](WARP_RECOVERY.md) теперь явно фиксирует повторный отказ, UDP 259/0, отсутствие доказанной root cause и неэффективность r29 для исходного сбоя. Гипотеза reused profiles не подтверждена пользователем. Параллельную регистрацию и socket recovery ещё нужно проверить.
- [LOGGING](LOGGING.md) отделяет META source-failure visibility от общего refused/no-route и VLESS protocol/TLS/auth. First-source Warn ещё не реализован; blanket изменение уровней отменено до реализации.
- Продолжение контейнерных/live действий заблокировано auto-review usage limit; локальные docs/checks выполнены отдельно. Не выдавать ограничение инструмента за технический диагноз роутера.

## 2026-11-23 — актуальный контекст вместо хронологического входа

- [PREVIEW_023](PREVIEW_023.md): согласованный полный 0.2.3/r29, свежие suites, 10 APK/IPK/payload/checksums, штатная установка на один ARM64 роутер и сохранность данных. Зафиксированы ошибка ручной deployment-обвязки и требование пользоваться штатным installer; пользовательская приёмка/публикация ещё впереди.
- [WARP_RECOVERY](WARP_RECOVERY.md): воспроизведение отказа после reload, r29 regression/race, ручная ARM64 установка core и logging-only защиты, текущие YouTube видеоданные/подтверждение пользователя, reboot с недоказанной причиной. В BUILD_AND_DEPLOY закреплены предварительное предупреждение, автономное восстановление при потере связи ассистента и отказ от большого tmpfs-стейджинга при малой RAM.
- [NETWORK_AVAILABILITY](NETWORK_AVAILABILITY.md) фиксирует согласованную политику WAN two-event suppression, DNS per-question и IPv6 FakeIP/PNA, source references, локальные проверки и границы аппаратного evidence. Предыдущее предложение общего per-server DNS window заменено текущим контрактом.

- Добавлен [контракт журнала и мониторинга](LOGGING.md): конкретные byte/object/RPC лимиты, изменение `/connections`, разбор пользовательских сообщений и synthetic RSS evidence. Подтверждённый механизм расхода отделён от недиагностированного аппаратного OOM.

- AGENTS закрепляет одного ассистента без агентов, `resource budgeting` и обязательное обновление затронутых документов.
- PROJECT_STATE, DEVELOPMENT_INDEX, AI_HANDOFF, архитектура, компоненты, решения, проблемы, проверки и сборка приведены к раздельным ролям. Старые release/permission/manual-only/64-record утверждения не используются как текущий контракт.
- 17 прежних файлов сохранены побайтно с SHA256 в [архиве](archive/README.md), включая прежний длинный TESTING. Продуктовый diff r23/r24 сохранён.
- Добавлены PROJECT_MAP, локальный doc gate, unit tests, read-only CI и PR-шаблон. Source-derived facts обновляются отдельно от содержательных выводов.
- Сайт исключает инженерный архив; [аудит](DOCUMENTATION_AUDIT.md) содержит точные результаты проверки и пределы автоматизации.

Следующая запись должна описывать смысл изменения контекста, не копировать весь статус проекта.
