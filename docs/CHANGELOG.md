# Изменения разработческого контекста

## 2026-11-16 — 0.1.8: восстановление оформления

Утверждённый стиль перенесён в общий CBI-адаптер и настройки: синие help у подписей, единая колонка полей, компактные страницы справа. Исправлено снятие сохранённого auto-apply без контракта; добавлено массовое удаление applied текущего фильтра через существующий `forget`. Удалены постоянная техническая справка и временная stop-кнопка. Frontend 176/1686, backend 92/92, browser matrix и payload 10 пакетов PASS; ядро r12 побайтно из 0.1.7, hardware UNVERIFIED. [Отчёт](audits/UI_STYLE_PROPOSAL.md).

## 0.1.6 — локальная QA, 2026-11-16

Frontend 175/1682, backend 91/91, core race/executable smoke, 10 IPK/APK и manifests/SHA256 PASS. Устранены reserved tag LuCI и ошибочное требование minimum==package. [Продуктовый changelog](../CHANGELOG.md), [команды и UNVERIFIED](TESTING.md). Новое разрешение пользователя допускает публикацию prerelease после GO; оборудование не используется.

## 2026-11-16 — №04Б-ФИНАЛ, локально

Ordinary HTTPS mode без nonce, explicit evidence/Apply eligibility, context-bound actual destination IP и IP-only TCP diagnostic. Исправлены mixed-DNS lease pinning и web recheck auto-apply, классифицирован body stall. Patch0007 отдельно от audited 0006, version test r11 сохранена; новый binary-only build изолирован. [Результаты](TESTING.md).


## Локально 2026-11-15 — №04Б, не опубликовано

Добавлены opt-in independent HTTPS verifier, точные runtime leases после исходного first-match Zapret2, ограниченные IP-first observations, TTL/повторная проверка/откат, persistent suppression и автоматические source/target LuCI-списки с русскими подписями. Отдельный patch 0006 и test core r11; механизмы №01–03 сохранены. [Контракт и ограничения](AUTO_ROUTING_IMPLEMENTATION_04B.md).


## 2026-11-15 — ТЗ №04, безопасная часть

Добавлены read-only прогноз маршрута в диагностике и CLI `check_route`, tri-state matcher generated JSON и синтетические проверки порядка Block/Bypass/Zapret2, source/port/IPv6/unknown/FakeIP/лимитов. Active probe/apply и автоматические списки секций не реализованы: API r10 недостаточен для app/IP/egress evidence; narrow CDN scope не доказан. Требования одобрены без повторного согласования; [продолжение](AUTO_ROUTING_DIAGNOSTICS_04.md). №01–03/core сохранены, без оборудования и публикации.

## 2026-11-15 — ТЗ №03, локально

Проверены пять patches, отдельно собраны r10 base x86_64/ARM64; core race suites, backend 39/39 и фактический executable прошли локальные проверки. Добавлены disk-only cold-cache/pin/interrupt и binary smoke tests. Зафиксированы ограничения reboot `/tmp`, общего JSON reload и полевая матрица. Production/patches не менялись; r9 не заменён, установки/публикации не было. [Отчёт](LIFECYCLE_FALLBACK_03.md).

## 2026-11-15 — ТЗ №02, локально

Добавлены local/server zones dnsmasq, mark-маски с сохранением чужих битов, проверки devices/pause/System и смешанного DNS. Исправлены mixed-response граница FakeIP, список dial-кандидатов и fail-open неизвестного remote set через scoped nft/core guards. Требуется локальный r10 на прежнем upstream + пять patches. Обновлены handoff, состояние, решения, архитектура и инструкции проверок; ограничения вынесены в [ТЗ №02](STARTUP_DNS_DEVICES_02.md). Без релизной сборки, установки и публикации.

## ???????? 2026-11-15 ? DNS / UCI / GeoIP (?? ????????)

- Backend defaults config/cache path ?????????? ???????? UCI defaults; runtime, lifecycle, Clash API ? ??????????? ?????????? ???? ????.
- ???????? resolver ??????? ?? ????????????????? bootstrap ??? DNS detour; ????????? ????????/WARP API ?? ??????? ?? DNS ????? ???? VPN.
- DNS SRS query-??????? ?????????? ????????; IP Bypass ??? ?????? ?????????? evaluate/respond ?? ??????? FakeIP. nft IPv4/IPv6 ???????? ?????????? ??? ????????? ?????????.
- ????????? ???????? ?????/??, ?????? AI_HANDOFF. 38 ??????? backend-?????? ? ??? core-?????? race-?????? passed. ???????/????????? ??????? ?? ???????????; ??????????? ??????? ? AI_HANDOFF/TESTING.

## 2026-11-14 — опубликована 0.1.5
Опубликованы r9, отдельный Chrome155, per-ID отпечатки соединений и единое оформление статусов обновлений. Добавлены D10/D11, pin uTLS-lx, patch, описание источников/wire-отличий/ограничений и свежие проверки в TESTING. Все четыре GitHub CI и сверка 14 публичных assets прошли. Устройства не использовались.

## 2026-11-13 — резолв, журнал и интерфейс (0.1.4)
Добавлены документация режимов резолва до правил всех секций, решения D8/D9 о DNS и RAM-журнале, границы polling и свежие команды/результаты проверок. Исправлены оформление fallback/конфигурации и обратная связь проверки обновлений. Подробности продукта — в корневом CHANGELOG, проверки — в TESTING.

## 2026-11-13 — локальная изоляция
Текущий checkout перенесён в KABANMAX с Git-историей. Исторический репозиторий/worktree, dirty core checkout и исследования сохранены в исключённой `.local/`. Добавлены AGENTS и тематические документы для продолжения работы без полного чтения архива. Состав/контрольные суммы/удаления и тесты — в ISOLATION_AUDIT/TESTING. Сетевые алгоритмы и установленное оборудование не изменяются; публикации не выполняются.

Изменения продукта: [корневой CHANGELOG](../CHANGELOG.md). Git остаётся источником детальной истории.
