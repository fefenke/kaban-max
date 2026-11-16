# Компоненты и точки изменений

0.1.7/r12: `core/patches/0008-auto-routing-registry.patch`; `config/auto_registry.uc` (atomic intents/budget); `diagnostics/auto_registry.uc` (ACL-guarded batch orchestration через auto_action); `diagnostics/auto_records.uc` (bounded view); state service capture раз в минуту. `tests/core/auto_registry_test.go`, `tests/diagnostics/auto_registry.test.uc`, `tests/installer-upgrade-017.sh` и headless fixture проверяют новые границы. [Контракт](AUTO_REGISTRY_017.md).

UI v2: `cbi/formUx.ts` — help/layout; `components/updateStatus.ts` — boolean-safe status; `diagnostic/renderRouteForecast.ts` — скрытый forecast и существующий LAN cache; `sections/connectionEditor.ts`/`fingerprintOptions.ts` — компактный editor; `sections/autoRecords.ts` → RPC `auto_records` → `diagnostics/auto_records.uc` — source-only страницы. `auto_routing_use_warp` отключает использование, сохраняя выбранный профиль; legacy configs без флага сохраняют прежнюю семантику. [Отчёт](audits/UI_FIXES_V2.md).

Приёмка 0.1.6: `src/constants.ts` резервирует `infrastructure-direct-out` в LuCI; page fixture удерживает frontend/backend вместе. `scripts/check-release.sh` проверяет core >= minimum, regression — `tests/release-manifest-smoke.sh`. [Свежая QA](TESTING.md).

## №04Б-ФИНАЛ

Новый core/patches/0007-auto-routing-web-probes.patch: common/autoroute/web.go, evidence/eligibility, actual-dial hook route/conn.go и narrowing lease.matches. Backend config/auto_routing.uc распознаёт default web и старый strict contract. UI autoRouting.ts показывает confidence/identity/Apply eligibility, позволяет IP-only Check без lease. Новый tests/core/auto_web_test.go и расширенный executable smoke покрывают обычные HTTPS-ответы и запреты.


## Компоненты №04Б

`core/patches/0006-auto-routing.patch` — Manager, HTTPS verifier, scoped lease и hook после original route match. `config/auto_routing.uc` — opt-in контракт и endpoint/DNS guards; `diagnostics/auto_detect.uc` — IP-first observations; `diagnostics/auto_routing.uc` — API и atomic suppression; `service/state_service.uc` — async write-RPC с ACL. `tabs/sections/autoRouting.ts` — source/target списки и операции. Тесты: `tests/core/auto_routing*`, `tests/diagnostics/auto_routing.test.uc`, frontend `sections/tests/autoRouting.test.ts`. [Контракт](AUTO_ROUTING_IMPLEMENTATION_04B.md).


ТЗ №04: `diagnostics/route_policy.uc` — ограниченный read-only forecast JSON и чтение config_path; `service/cli.uc:check_route`; frontend `diagnostic/routeForecast.ts` и `renderRouteForecast.ts`. Тесты — `tests/diagnostics/route_{policy,generated}.test.uc` и frontend `diagnostic/tests/*RouteForecast*` / `routeForecast.test.ts`. Probe/apply отсутствуют: [препятствия](AUTO_ROUTING_DIAGNOSTICS_04.md).

ТЗ №03: `tests/core/run_r10_review.sh` — изолированная base-сборка и полный group/cachefile race suite; `run_lifecycle_cold.sh`/`lifecycle_cold_test.go` — disk-only pins и interrupt; `r10_binary_smoke.py` — фактический executable, FakeIP restart, mixed DNS и route/fail-closed. Production-компоненты не менялись. [Отчёт](LIFECYCLE_FALLBACK_03.md).

ТЗ №02: `singbox/generator.uc` — local zones, response-all/FakeIP и resolve в позиции Bypass; `nft/apply.uc`, `nft/sections.uc`, `nft/ruleset_sync.uc` — marks/pending/provider readiness; `service/lifecycle.uc` — повторное включение guards. Patches 0003–0005 — изоляция resolved-кандидатов, отказ при неизвестном provider и all-address DNS matcher. Нужен r10. [Связи, тесты и ограничения](STARTUP_DNS_DEVICES_02.md).

Каталог uTLS: `shared/tls-fingerprints.json` → TS `services/tlsFingerprints.ts` и generated backend `singbox/fingerprints.uc` через `scripts/generate-fingerprints.mjs`. CBI семейство/версия — `sections/fingerprintOptions.ts`; compatibility — `services/coreFeatures.service.ts` / backend `singbox/features.uc`. Истинность metadata и random/randomized проверяет `tests/core/run_fingerprints.sh` на чистом ядре с текущими patches.

Редактор ручного VPN: `fe-app-kabanmax/src/kabanmax/tabs/sections/connectionUri.ts` — lossless parser/serializer по контракту pinned core; `connectionEditor.ts` — виртуальные поля/импорт/экспорт; `links.ts` — валидация, стабильный ID и ссылки Fallback/URLTest. `cbi/modal.ts` вызывает необязательный `prepareSave` до UCI diff. Проверки: `connectionUri.test.ts`, bundle `connectionLinks.test.js`, `tests/core/editor_reload_test.go` (чистый upstream+patches, runner рядом).

Все backend-пути в таблице относительно `kabanmax/files/usr/lib/`.

| Компонент | Файлы | Ответственность/проверки |
| --- | --- | --- |
| CLI и жизненный цикл | `service/cli.uc`, `lifecycle.uc`, `lock.uc`, `singbox_watch.uc` | команды, сериализация, готовность, reload; `tests/service/` |
| Конфигурация | `config/connections.uc`, `validator.uc`, `migration.uc`, `migrations/` | UCI → внутренняя модель, диапазоны, перенос старых настроек |
| Генератор | `singbox/generator.uc`, `route.uc`, `dns.uc`, `rulesets.uc` | JSON, resolver/route/outbounds, подписки и rule sets |
| Перехват | `nft/apply.uc`, `sections.uc`, `state.uc`, `ruleset_sync.uc` | таблица nft, mark, policy routing, обновление sets |
| Zapret2 | `zapret2/model.uc`, `runtime.uc`, `kernel.uc`, `updater.uc` | аргументы, постоянные слоты, procd/очереди, kmod и staged обновление |
| Обновления | `service/release.uc`, `installer.uc`, `package.uc`, корневой `install.sh` | metadata GitHub, загрузка и установка пакетов |
| Диагностика | `diagnostics/`, `singbox/clash_api.uc` | проверки, отчёты и маскирование; не путать probe failure с пользовательской ошибкой |
| Журнал | `service/log_journal.uc`, `service/state_service.uc` | сбор приложения без открытого UI, 24 часа / 2 МиБ сериализованного архива, write-RPC `clear_logs` |

Frontend: `fe-app-kabanmax/src/kabanmax/tabs/` (sections/settings/dashboard/components), `methods/custom/clashApi.ts` (transport), services/helpers (состояние и представление). Имена уточнять `rg --files` в конкретном подкаталоге. `luci-app-kabanmax` содержит не исходный TS, а LuCI-обёртки/пакетные метаданные и переводы.

Ядро: `protocol/group/fallback*.go` (выбор/наблюдения), `cmd/sing-box/stable_observation_*.go` (перенос статистики reload), `common/tls/reality_client.go`, `common/tlsfragment/` (TLS), `option/group.go` (опции), `experimental/clashapi/proxies.go` (API). Эти пути находятся внутри рабочего checkout ядра или представлены hunks в patch.

Chrome 155: `core/patches/0002-chrome155.patch` меняет `common/tls/utls_client.go`, `option/tls.go`, `parser/subscription/tls.go`, go.mod/go.sum и упаковку BSD-лицензии. Выбор в LuCI и клиентских ссылках — `tabs/servers/constants.ts`. Точные источники/ограничения — `core/CHROME155.md`; версия r9 — в `core/UPSTREAM` и backend minimum.

Отпечаток отдельного подключения: `tabs/sections/links.ts` сохраняет `connection_link.tls_fingerprint`, `services/coreFeatures.service.ts` проверяет применимость TCP/TLS и uTLS; backend `config/validator.uc` повторяет проверку, `singbox/generator.uc` передаёт override parser outbound. Patch ядра применяет его после разбора ссылки. Проверки — frontend `sections/tests/fingerprint.test.ts`, backend `config/validator_fingerprint.test.uc` и `singbox/generator_tls_records.test.uc`.

Результаты проверки обновлений приложения и Zapret2: `tabs/components/initController.ts`, `zapret2.ts`, общий стиль `styles.ts`. Статус над кнопкой остаётся видимым после ответа: успех зелёный, ошибка красная, ожидание нейтральное; успешная проверка приложения не создаёт нижний toast. Повторные проверки и состояния покрывают `updateFeedback.test.ts` и `zapret2Feedback.test.ts`.

Runtime-конфигурация приложения: `/etc/config/kabanmax`; локальные списки: `/etc/kabanmax/lists/`; конфиг ядра определяется настройками, обычно `/etc/sing-box/config.json`; служебное состояние `/var/run/kabanmax/`. Zapret2: `/opt/kabanmax-zapret2/current/`, слоты `/etc/kabanmax/zapret2-slots.json`. Не редактировать генерируемый JSON как постоянный источник настроек.

DNS/UCI (2026-11-15): `singbox.constants.config_path/cache_path` ?????? ????? backend defaults ??? runtime, lifecycle ? ???????????. ??? DNS detour ???????????? endpoint ? ????????? `infrastructure-direct-out` ?????????? bootstrap, ???????????????? resolver ? ???????? DNS. IP Bypass ??? ?????? ????????? DNS evaluate/respond; query SRS ?????????? ???????? ?????. ????? UCI ? ???? ?? ????????. ??????????? ? ?????????????? ? [AI_HANDOFF](AI_HANDOFF.md), [TESTING](TESTING.md).
