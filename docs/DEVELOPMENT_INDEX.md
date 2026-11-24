# Навигатор разработчика

Старт: [AGENTS](../AGENTS.md) → [PROJECT_STATE](PROJECT_STATE.md). Текущий выпуск и native smoke — [0.2.3/r40](RELEASE_023.md). Затем выбрать **одну тему**, не читать все ссылки подряд. Формальная карта путей — [PROJECT_MAP.json](PROJECT_MAP.json).

| Задача | Сначала читать | Код и проверки |
| --- | --- | --- |
| Авторутинг: память, flash, реестр | [контракт r24](AUTO_ROUTING_STORAGE.md), [ошибки №2–4](AUTO_ROUTING_FIELD_ERRORS.md) | `config/auto_*.uc`, `diagnostics/auto_*.uc`, `autoRecords.ts`, `autoRouting.ts`, `autoStorage.ts`, `tests/core/auto*` |
| Fallback, TLS, статистика | [NETWORKING](NETWORKING.md), [DECISIONS](DECISIONS.md), [fingerprints](../core/FINGERPRINTS.md) | `core/UPSTREAM`, `core/patches/`, `tests/core/`, `shared/tls-fingerprints.json` |
| DNS, устройства, nft | [NETWORKING](NETWORKING.md), [COMPONENTS](COMPONENTS.md) | `singbox/generator.uc`, `config/validator.uc`, `nft/`, `tests/singbox/`, `tests/nft/` |
| WAN-log gate, DNS-повторы, IPv6 FakeIP | [NETWORK_AVAILABILITY](NETWORK_AVAILABILITY.md), [LOGGING](LOGGING.md) | `core/patches/0027*`, `0028*`, `singbox/constants.uc`, `diagnostics/route_policy.uc`, `tests/core/run_network_availability.sh` |
| Запуск, reload, RPC, журналы | [LOGGING](LOGGING.md), [ARCHITECTURE](ARCHITECTURE.md), [KNOWN_ISSUES](KNOWN_ISSUES.md) | `service/lifecycle.uc`, `state_service.uc`, `cli.uc`, `log_journal.uc`, `tests/service/` |
| LuCI, формы, URI, переводы | [COMPONENTS](COMPONENTS.md), [PITFALLS](PITFALLS.md) | `fe-app-kabanmax/src/`, frontend `tests/`, `luci-app-kabanmax/po/` |
| Zapret2, WARP, каскады | [NETWORKING](NETWORKING.md), [текущий WARP outage](WARP_RECOVERY.md), [SECURITY](SECURITY.md) | `zapret2/model.uc`, `singbox/generator.uc`, `tests/singbox/generator_warp_stability.test.uc`, `core/patches/` |
| Сборка, версии, упаковка | [BUILD_AND_DEPLOY](BUILD_AND_DEPLOY.md), [TESTING](TESTING.md) | `scripts/`, `core/UPSTREAM`, `.github/workflows/`, package Makefiles |
| Полевой сбой | [KNOWN_ISSUES](KNOWN_ISSUES.md), [TROUBLESHOOTING](TROUBLESHOOTING.md), [SECURITY](SECURITY.md) | точный компонент и синтетическое воспроизведение; live доступ — отдельно |
| Обновление документов | [WORKFLOW](WORKFLOW.md), [DOCUMENTATION_AUDIT](DOCUMENTATION_AUDIT.md) | `scripts/check-project-docs.py`, `tests/docs/`, `.github/workflows/docs-check.yml` |
| Старый эксперимент | [архив](archive/README.md), затем нужный отчёт | `docs/AUTO_*.md`, `superpowers/`, `audits/`; `.local/` — только под конкретную гипотезу |

Пути `config/`, `service/`, `singbox/`, `nft/`, `zapret2/`, `diagnostics/` относительны `kabanmax/files/usr/lib/`. Точные frontend entrypoints — в COMPONENTS/PROJECT_MAP.

## Иерархия знаний

- Состояние сейчас: PROJECT_STATE; контракт: ARCHITECTURE/NETWORKING/актуальный тематический документ.
- Причины: DECISIONS. Неизвестное: KNOWN_ISSUES. Проверки: TESTING.
- Старые отчёты относятся к своему этапу. r11/r12 manual-only и лимит 64 не описывают локальный r24.
- Пользовательское руководство: [сайт](index.md), `guide/`, `connections/`, `dns/`, `sections/`, `tunnels/`, `servers/`, `settings.md`. Оно не подтверждает выпуск локальных изменений.
- [AI_HANDOFF](AI_HANDOFF.md) — указатель для другого чата, без дублирования состояния.
