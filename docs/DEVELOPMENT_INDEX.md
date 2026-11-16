# Навигатор разработчика

0.1.7/r12: [bounded registry, persistence, exact scope и bulk](AUTO_REGISTRY_017.md); [свежие gates](TESTING.md). Предыдущие UI v2/r11 записи ниже исторические.

№04Б-ФИНАЛ 2026-11-16: ordinary HTTPS без nonce, только manual proposals; актуальные критерии в [контракте](AUTO_ROUTING_IMPLEMENTATION_04B.md), свежие результаты в [TESTING](TESTING.md).


ТЗ №04Б: [active verifier, scoped leases, LuCI и границы](AUTO_ROUTING_IMPLEMENTATION_04B.md); [свежие тесты](TESTING.md), [передача](AI_HANDOFF.md).


ТЗ №04: [read-only прогноз маршрута, ограничения автоматики и продолжение](AUTO_ROUTING_DIAGNOSTICS_04.md).

Актуальная проверка r10 и lifecycle: [ТЗ №03](LIFECYCLE_FALLBACK_03.md), команды — [TESTING](TESTING.md).

Текущий результат и передача №03 после ТЗ №02: [запуск, DNS, устройства и смешанные ответы](STARTUP_DNS_DEVICES_02.md).

Минимальный контекст: [AGENTS](../AGENTS.md) → [PROJECT_STATE](PROJECT_STATE.md). Далее читать только нужную тему.

| Задача | Документы | Код |
| --- | --- | --- |
| Понять устройство | [Архитектура](ARCHITECTURE.md), [компоненты](COMPONENTS.md) | `kabanmax/files/usr/lib/`, frontend `src/kabanmax/` |
| Fallback/TLS/статистика | [Решения](DECISIONS.md), [сеть](NETWORKING.md), [fallback](connections/fallback.md) | `core/patches/`, `.local/core-src/protocol/group/` |
| Запуск, DNS, NFQUEUE | [Диагностика](TROUBLESHOOTING.md), [проблемы](KNOWN_ISSUES.md) | backend `service/`, `nft/`, `zapret2/` |
| Сборка/проверки | [Сборка](BUILD_AND_DEPLOY.md), [тесты](TESTING.md), [ловушки](PITFALLS.md) | `scripts/`, `tests/`, `core/UPSTREAM` |
| Публикация и приватность | [Безопасность](SECURITY.md), [сборка](BUILD_AND_DEPLOY.md) | `install.sh`, release scripts |
| Продолжить разработку | [План](ROADMAP.md), [изменения](CHANGELOG.md) | точечный поиск по компоненту |
| Найти старые исследования | [Аудит переноса](ISOLATION_AUDIT.md) | `.local/research/`, `.local/legacy/` |

Пользовательское руководство остаётся в `guide/`, `connections/`, `dns/`, `sections/`, `tunnels/`, `servers/` и `settings.md`. Не дублировать их содержимое в AGENTS. Подробные приватные материалы читать только под конкретную гипотезу; пути к ним не означают разрешение запускать старые команды.

??????????? ????? ? ?? DNS/UCI/GeoIP: [?????????](audits/README.md). ??????????? ????? ????????? ??????: [AI_HANDOFF](AI_HANDOFF.md).
