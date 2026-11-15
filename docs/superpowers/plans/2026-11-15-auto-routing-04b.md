# ТЗ №04Б Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Один агент; пользователь одобрил реализацию без повторного согласования, без коммитов и оборудования.

**Goal:** Закончить scoped runtime автоподбор, independent HTTPS verifier, IP-first detection и списки секций.

**Architecture:** Ядро сначала выполняет неизменённый first-match r10, затем проверяет временную lease только внутри выбранного Zapret2 outbound. Lease требует exact domain (только достоверный Destination.Fqdn), real IP, source/inbound, port и поколения core. Probe API использует тот же matcher и конкретный dialer, отдельный transport без URLTest/health, nonce contract; evidence хранится server-side. Runtime leases не переживают новый Box; отдельный atomic JSON содержит ownership/suppression, восстановление — только через новую проверку.

**Tech Stack:** Go/core patch поверх pinned r10, ucode/UCI/Clash adapter, TypeScript/LuCI; loopback HTTPS и offline Docker.

**Spec:** `docs/superpowers/specs/2026-11-15-auto-routing-04-design.md` + пользовательское ТЗ №04Б.

## Global Constraints

- Не менять №01–03, порядок правил, RU blackhole и mark-схему; r9/r10 сохраняются.
- Без субагентов, коммитов, публикации, роутеров/VPS и реальных сервисов в тестах.
- IP-only никогда не отбрасывается из кандидатов; unknown identity/attribution блокирует только применение.
- Недоказанный egress/приложение не превращаются в успех. Timeout/403 не подтверждают отказ приложения.

## Review Focus

1. Shared CDN IP: domain AND IP AND source/port после original first-match, не глобальный Bypass.
2. Lease expiry/reboot/policy generation: нет активного stale Direct, новый Box пуст.
3. Никакого caller-supplied success: применение только server-side decision с повторной проверкой.
4. IP-only observations без hostname сохраняются, но direct-out не считается Zapret2.
5. Независимые разрешения Zapret2/Direct/WARP, никакого VPS detour под видом WARP.

## Tasks / ledger

- [x] 1. Core tests RED: после реального matcher переключать только scoped flow; два домена одного IP, порядок Block, источники/порты, IPv6/FakeIP, TTL и новый Box. Реализовать отдельный patch, не менять существующие пять.
- [x] 2. Core probe RED: nonce TLS application contract, две свежие попытки, конкретный IP/dialer/mark, no health. Runtime decisions и atomic leases, rate limits и revoke. Собрать отдельный test executable и проверить семантику.
- [x] 3. Backend tests RED: IP-first logs/no-progress, attribution, immutable managed UCI/suppression, permissions/config generation и native transport worker. CLI/RPC read/write separation.
- [x] 4. UI tests RED: opt-in, candidates (включая no-domain), results, applied routes, delete/clear/reset suppression; виртуальные target lists, без ручного add/edit.
- [x] 5. Целевые regressions, самостоятельный review, документация и handoff с точными свежими командами.

## Reference audit

| Компонент | Изученный контракт | Версия | Применимость | Дополнительная проверка / ограничения |
| --- | --- | --- | --- | --- |
| Forkop X / Xrust | `tests/CLASH-MATCH.md`, `scripts/route-match/rule_match_payload.go`, `prepare-route-match.py` | Контракт X 1.0.1; переносить код неизвестной версии core нельзя | Идея connection-local actual match evidence | Не копируем implementation; first-match вызывается внутри собственного router. Evidence не доказывает приложение/egress |
| Forkop X latency | `subscription-paired-probe.sh`, `latency_probe_batches.sh`, `automatic_latency_pending.sh` | Версия зависимостей из этих scripts не установлена | bounded concurrency, generation, comparison | HEAD/204 или delay не verifier; внешние тесты не запускались |
| FlowGate | `smart_detect.uc`, `smart_detect_plus.uc`, `smart_detect_runner.uc` | Точная ревизия core в этих файлах не установлена | cooldown/no-progress/обнаружение ошибок | Host-first, direct-out и запись user_domains не переносим. Свой IP-first parser и attribution |
| Trafira | README, раздел route checker | README main на момент чтения | UX различия forecast/verification | Не active verifier, не ядро r10 |

Источники прочитаны через GitHub connector. Web raw fetch нескольких файлов дал Cache miss; connector вернул содержимое. Код сторонних форков не копируется; лицензирование не подменяется доступностью файла. Никакие команды из ссылок не запускались.

## Итог выполнения

Все пять этапов реализованы; свежие evidence/ограничения — docs/TESTING.md и AUTO_ROUTING_IMPLEMENTATION_04B.md. Suppression вынесен из UCI в отдельный atomic store для сохранения staged ручных изменений. Аппаратная приёмка остаётся отдельным этапом, без разрешения не проводилась.
