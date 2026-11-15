# №04Б-ФИНАЛ Implementation Plan

> Выполняется одним агентом через superpowers:executing-plans. ТЗ прямо разрешает продолжение без повторного согласования; без commit/push/релиза/устройств/внешних проб.

**Goal:** практические HTTPS-проверки точного IP обычного ресурса с безопасными предложениями поверх r11.

**Architecture:** отдельный patch 0007 поверх неизменённого 0006. Strict nonce сохраняется как режим. Web GET по pinned IP с подтверждённым flow FQDN и TLS/hostname: два transport failures исходного и два содержательных ответа альтернативы дают alternative_reachable с ручным Apply, никогда automatic apply. Строгий режим даёт verified_for_apply только по прежнему nonce-контракту. IP-only TCP diagnostic не создаёт lease. Existing exact first-match/source/port/domain/DNS/TTL/generation/suppression guards неизменны.

**Tech Stack:** Go r11 test core, ucode, TypeScript/LuCI, network-none Docker.

**Spec:** пользовательский KABANMAX_CODEX_04B_FINISH_REAL_IP_CHECKS.md и дополнение к design №04.

## Constraints / review focus

- Сохранить audited r11 binaries/patch0006, r9/r10 и исходный dirty tree. Новые outputs — `.local/audit/auto-routing-04b-final`.
- Не доказывать DPI/полный сервис из TLS/HTTP/таймаута; web никогда не auto-apply. Generic HTML не равен application contract.
- Не делать batch других A/AAAA для web: только адрес реального потока; unresolved multi-address error остаётся наблюдением unknown IP.
- Не выводить trusted identity из reverse DNS или логов. Настоящий connection remote IP дополняет только то же событие.
- Пределы запросов/сроков прежние. Forbidden outbounds zero-dials, нет reload/ручных списков.

## Ledger

- [x] 1. RED core tests: web без nonce, TLS/HTTP/content outcome matrix, two attempts и no auto apply; IP-only visible diagnostic, pinned IP из multi-address flow. Реализовать отдельные web verifier/decision fields, context-bound dial evidence и patch0007.
- [x] 2. RED backend/frontend: default web mode без domain contract, preserved strict mode, candidate identity/confidence/manual eligibility; существующие две галочки и write ACL. Реализовать минимальные поля/сообщения и русские подписи.
- [x] 3. Clean patch apply + race, отдельный r11 binary-only test build, smoke обычного HTTPS/CDN/FakeIP/A+AAAA/порядка/TTL/suppression, no forbidden dials. Targeted backend/frontend/tsc/lint/bundle.
- [x] 4. Самостоятельный review и docs/handoff: точные свежие результаты отдельно от старых, границы OpenWrt/UDP/anti-bot/свежести.

## Референс FlowGate (прочитан 2026-11-16 через GitHub connector)

`smart_detect.uc` — confirmation window 120s / 2 failures, parsing и protection; `smart_detect_plus.uc` — per-connection progress, queue/cooldown; `smart_detect_runner.uc` — bounded iteration/worker. Версия зависимого ядра не установлена. Код не копируется: собственные per-connection/IP-first primitives уже есть. Не переносим direct-out attribution, PSL expansion, curl exit=успех, user_domains/reload. Сетевые проверки чужого проекта не запускались.

## Decisions

Web default: bounded GET `/`, status 200, type HTML/text/JSON и ≥32 содержательных байт; optional expected prefix задаёт более точный контракт. Captcha/anti-bot, redirect/auth/rate-limit/5xx/cache/TLS error дают отдельную диагностику без разрешения применения. Даже корректный web ответ не доказывает freshness как nonce: только ручное scoped предложение. Нет безопасного универсального автоматического критерия для произвольного приложения; auto-apply strict-only.

## Итог

План выполнен и проверен одним агентом. Дополнительно воспроизведены mixed-address lease pinning, web recheck auto-apply и body stall; минимальные исправления в0007. Свежие команды/результаты/SHA — TESTING. Ни 0006, ни audited r11/r9/r10 не изменены. Аппаратная приёмка, universal app contracts/CNAME и другие номера задач не выполнялись.
