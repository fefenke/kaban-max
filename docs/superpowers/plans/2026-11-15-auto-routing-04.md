# Auto routing 04 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Один агент, без коммитов и повторного согласования по явному указанию пользователя.

**Goal:** Реализовать безопасную часть №04 и документировать препятствия к включению автоматики.

**Architecture:** Read-only прогноз использует уже сформированные route rules, а не второй генератор UCI. Трёхзначное сопоставление останавливается при неизвестном условии. Активные проверки и мутации недоступны без transport evidence.

**Tech Stack:** ucode, существующий CLI, TypeScript/LuCI, offline Docker tests.

**Spec:** `docs/superpowers/specs/2026-11-15-auto-routing-04-design.md`.

## Global Constraints

- Текущий dirty tree сохраняется; №01–03 и r10 не переделываются.
- Один агент, без оборудования, сетевых проб, коммитов и публикации.
- Block — первое совпадение, не глобальный поиск IP во всех Block.
- Никакого неподтверждённого Direct и искусственного verified.

## Review Focus

- Более ранний неизвестный SRS не пропускается ради нижнего Direct.
- Unknown source при device rules не становится общим правилом.
- FakeIP/resolve не превращаются в реальный IP.
- Поздний Block не переопределяет раннюю Zapret2-секцию.
- Успешный прогноз не выдаётся за фактический egress/verified.

## Tasks

1. [x] Сначала `tests/diagnostics/route_policy.test.uc`: ordered Block/Bypass/Zapret2, source/port, logical AND/OR, unknown SRS/resolve, FakeIP, v6, invalid input. Запустить до реализации и подтвердить отсутствие модуля.
2. [x] `diagnostics/route_policy.uc`: `predict(config, query)` по snapshot JSON, bounded tri-state matcher, no DNS/network/write. `inspect(destination, source, port)` читает эффективный config path, CLI `check_route`. Проверить текущий generator синтетическими fixtures.
3. [x] Read-only frontend в диагностике через существующий shell transport. Явно показать unsupported automation, predicted/observed/verified и отсутствие проб. Проверить typecheck и целевые тесты.
4. [x] Записать свежие команды и результаты, обновить handoff/state и затронутую документацию. Самостоятельный review вместо запрещённого субагента.

## Rulings / препятствия

Самостоятельный review выполнен: найденные combined SRS/domain и System-source неоднозначности воспроизведены assertions, исправлены; финальные 11 backend-файлов, 10 frontend-тестов, tsc, lint и PO compilation passed. Независимого reviewer нет по прямому запрету субагентов. Точные команды и неудачные запуски — TESTING. Выполнены задачи безопасного среза этого плана, но НЕ полное ТЗ №04; отложенные требования перечислены в отчёте.

`getProxyDelay` в r10 возвращает только `delay`, вызывает URLTest без ожидаемого результата приложения и обновляет health history/URLTest groups. `urltest` делает HEAD, закрывает body, не отдаёт remote IP/TLS identity/nonce evidence. `/exit` использует фиксированный trace endpoint. Не годятся для независимого активного checker. Существующие generated domain/IP условия объединены OR: наивное добавление домена к IP-правилу расширит область. Поэтому предложения/managed apply/TTL/suppression и активные автоматические списки НЕ реализуются без необходимых предпосылок. Это разрешённая пользователем безопасная часть, не завершённое ТЗ №04.
