# Компоненты: где менять и что проверять

Это карта ответственности, а не каталог всех исходников. Формальные glob-правила для контроля изменений — [PROJECT_MAP.json](PROJECT_MAP.json); порядок проверки — [TESTING](TESTING.md).

| Компонент | Entry points | Ближайшие проверки | Документ контракта |
| --- | --- | --- | --- |
| LuCI/bootstrap | `fe-app-kabanmax/src/main.ts`, `luci-app-kabanmax/htdocs/luci-static/resources/view/kabanmax/` | frontend `tests/bundle/`, `tests/pageContract.test.js` | [архитектура](ARCHITECTURE.md) |
| Формы секций/URI | `fe-app-kabanmax/src/kabanmax/tabs/sections/` | соседние `tests/`, bundle round-trip | [ловушки](PITFALLS.md) |
| Авторутинг UI | `tabs/sections/autoRouting.ts`, `autoRecords.ts`, `tabs/settings/form/autoStorage.ts` | sections/settings tests, bundle UI | [storage](AUTO_ROUTING_STORAGE.md) |
| Авторутинг backend | `config/auto_storage.uc`, `auto_registry.uc`, `auto_routing.uc`; `diagnostics/auto_*.uc` | `tests/config/auto*`, `tests/diagnostics/auto*` | [storage](AUTO_ROUTING_STORAGE.md), [ошибки](AUTO_ROUTING_FIELD_ERRORS.md) |
| Applied diagnostic retention | `config/auto_diagnostics.uc`, core patch 0040, `autoRecords.ts` | config auto_diagnostics/auto_registry_diagnostics, core auto_applied_diagnostics, frontend autoRouting | [выпуск 0.2.3/r40](RELEASE_023.md) |
| Applied IP section scope | `core/patches/0039-section-wide-applied-ip.patch`, `diagnostics/auto_records.uc` | `tests/core/auto_section_ip_test.go`, `tests/diagnostics/auto_uncovered_pending.test.uc` | [все устройства секции](AUTO_ROUTING_SECTION_IP.md) |
| UCI/валидация/миграции | `config/validator.uc`, `connections.uc`, `migrations/` | `tests/config/` | [сеть](NETWORKING.md) |
| WARP port hints | `diagnostics/warp_ports.uc`, `config/connections.uc`, core patch `0038-warp-durable-port-hints.patch` | `tests/diagnostics/warp_ports.test.uc`, `tests/core/warp_port_hint_test.go`, `warp_udp_recovery_test.go` | [постоянный порт](WARP_PORT_HINTS.md) |
| sing-box JSON/DNS/outbounds | `singbox/generator.uc`, `constants.uc`, `rulesets.uc` | `tests/singbox/` | [сеть](NETWORKING.md) |
| nft/capture/marks | `nft/sections.uc`, `apply.uc`, `ruleset_sync.uc` | `tests/nft/`, startup DNS fixtures | [сеть](NETWORKING.md) |
| Zapret2 | `zapret2/model.uc`, остальные модули `zapret2/` | `tests/service/zapret2*.test.uc`, generator Zapret tests | [сеть](NETWORKING.md) |
| Lifecycle/procd | `service/lifecycle.uc`, `initd.uc`, `singbox_watch.uc`, `lock.uc` | `tests/service/lifecycle.test.uc`, watcher/initd tests | [архитектура](ARCHITECTURE.md) |
| RPC/CLI/state | `service/cli.uc`, `state_service.uc`, `worker.uc`, `singbox/clash_api.uc` | `tests/service/`, `tests/singbox/clash_api.test.uc` | [архитектура](ARCHITECTURE.md), [безопасность](SECURITY.md) |
| Журнал/диагностика | `service/log_journal.uc`, `health.uc`, `diagnostics/`; `tabs/logs/`, `tabs/monitoring/`; `core/patches/0025-bounded-connection-snapshots.patch` | service journal/state, `tests/core/connections_snapshot_test.go`, monitoring UI | [журнал и память](LOGGING.md), [архитектура](ARCHITECTURE.md), [проблемы](KNOWN_ISSUES.md) |
| Fallback/TLS/core autoroute | `core/UPSTREAM`, `core/patches/` | `tests/core/`, `.github/workflows/core-ci.yml` | [сеть](NETWORKING.md), [решения](DECISIONS.md) |
| TLS fingerprints | `shared/tls-fingerprints.json`, `scripts/generate-fingerprints.mjs` | frontend catalog + backend + Go TLS/parser | [FINGERPRINTS](../core/FINGERPRINTS.md), [CHROME155](../core/CHROME155.md) |
| Переводы/bundle | `fe-app-kabanmax/sync-locales.js`, `luci-app-kabanmax/po/` | frontend localization, locale identity, build | [сборка](BUILD_AND_DEPLOY.md) |
| Установка/релиз | `install.sh`, `scripts/build-release.sh`, `build-core.sh`, `check-release.sh` | installer smoke, `tests/packaging/`, workflows | [сборка](BUILD_AND_DEPLOY.md) |
| Инженерная документация | `AGENTS.md`, `docs/PROJECT_MAP.json`, `scripts/check-project-docs.py` | `tests/docs/`, Documentation integrity CI | [WORKFLOW](WORKFLOW.md) |

Frontend `tabs/` в таблице относительны `fe-app-kabanmax/src/kabanmax/`; backend пути — `kabanmax/files/usr/lib/`. Точные glob-маршруты лежат в PROJECT_MAP; при новом компоненте обновить оба представления.

## Генерируемые файлы

Политика core-логов — `core/patches/0026-actionable-log-levels.patch`; регрессии `tests/core/connection_log_policy_test.go`, `dns_log_policy_test.go`, runner `run_log_policy.sh`. Источник сообщения меняет уровень до logd; frontend не скрывает старые строки. [Точная таблица](LOGGING.md).

WAN monitor/gate — `core/patches/0028-wan-outage-log-gate.patch` (core `common/wanstate`, Router scope, logger output). DNS per-question/FakeIPv6 guard — `0027-fakeip-ipv6-and-domain-dns-logs.patch`, pool — `singbox/constants.uc`, nft consumer — `nft/apply.uc`, route forecast — `diagnostics/route_policy.uc`. Проверки `tests/core/wan_*test.go`, `fakeip_ipv6_*test.go`, `run_network_availability.sh`, backend nft/generator/ip/forecast. [Контракт](NETWORK_AVAILABILITY.md).

- LuCI `main.js`: менять TypeScript, затем `npm run build`. Ручной patch bundle не является источником.
- `singbox/fingerprints.uc`: источник `shared/tls-fingerprints.json`; build проверяет соответствие.
- RU/POT: `node sync-locales.js`, сохранить переводы; не добавлять необоснованные строки.
- Версия приложения подставляется сборкой вместо `__COMPILED_VERSION_VARIABLE__`; это не номер локального core.
- Core: сначала все patches по имени на pinned commit, затем branding. Изменение только `.local/core-src` не входит в стандартную сборку.

## Кого затрагивает изменение

UI → RPC → validator → generator → core/nft образуют цепь. Новое поле должно иметь согласованную валидацию, default, сохранение без лишнего diff и достаточный core minimum. В тестах использовать synthetic данные и подмены системных вызовов; фактическую аппаратную приёмку отмечать отдельно.
