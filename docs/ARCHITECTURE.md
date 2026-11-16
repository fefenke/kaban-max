# Архитектура

Локально после r13: patch 0010 сохраняет failed dial IP и выбирает lease на уровне конкретного dial, сохраняя source first-match и здоровые DNS siblings. Альтернатива — configured выход секции без её списков. Журнал собирает bounded tail, обслуживает неизменившийся дамп быстрым путём и передаёт одну revision частями. [Контракт и границы](AUTO_ROUTING_IP_FIX.md).

0.1.9/r13: ошибка конкретного соединения → реально записанный log ID → source-owned candidate → повторная first-match/TLS/content проверка → scoped lease по отдельному opt-in. Нет `/connections`/no-progress или угадывания секции. Patch 0009 добавляет Failure provenance/API3 dismiss и IP-only HTTPS identity; отказ альтернативы отзывает только свою lease, не становится исходной ошибкой. Backend фильтрует по подтверждённой failure, UI сохраняет DOM одинаковых snapshots. [Контракт и проверки](AUTO_ROUTING_019.md).

0.1.7/r12: `config.auto_registry` → saved intents/slot inventory в opt-in JSON → core patch 0008. Никакой прямой загрузки intents в active leases. Write-only `auto_action(op=records)` → scoped batch adapter → exact core operations; read-only `auto_records` → source-filtered pages/selection. Existing first-match/DNS/FakeIP/nft/PBR и transport не переписывались. [Контракт](AUTO_REGISTRY_017.md).

UI v2 добавляет `cbi/formUx.ts` (делегированная справка и scoped layout) и read-only RPC `auto_records` → `diagnostics/auto_records.uc` (серверный paged view существующего snapshot, не новый verifier). Старый write-only `auto_action` остаётся единственным путём мутаций. Core, DNS/nft/PBR и transport не менялись. [Границы реализации](audits/UI_FIXES_V2.md).

## Доработка №04Б-ФИНАЛ, 2026-11-16

Patch 0007 добавляет web verifier и дополнительные facts поверх 0006. Route connection manager передаёт actual dial remote IP в context-bound event исходного Zapret2; DNS siblings не копируются в кандидаты. Lease application требует single exact original DestinationAddress. Server-side decision разделяет evidence/apply_allowed/auto_apply_eligible: web — только manual, strict — прежняя строгая автоматика. [Контракт](AUTO_ROUTING_IMPLEMENTATION_04B.md).


## Расширение №04Б

[Автомаршрутизация](AUTO_ROUTING_IMPLEMENTATION_04B.md): LuCI → отдельные read/write ubus методы → bounded CLI worker → аутентифицированный core API. Route matcher r10 сначала выбирает пользовательский маршрут; опциональный Manager проверяет lease только внутри победившего Zapret2. Probe/detection не записывают пользовательские правила. Apply потребляет server-side evidence; suppression хранится атомарно отдельно от UCI, leases — только RAM текущего Box.


ТЗ №04 добавляет только read-only forecast уже сформированного JSON. Он не является источником сетевой политики; unknown не разрешает дальнейшую автоматизацию. Active probes и managed UCI пока отсутствуют из-за ограничений r10 API и domain/IP scope. [Контракт](AUTO_ROUTING_DIAGNOSTICS_04.md).

ТЗ №03 уточняет существующий lifecycle: общий JSON требует Close/Create и закрывает TCP; FakeIP может восстановиться из того же cache, ручные pins — только если файл пережил boot. Штатный `/tmp` этого не обеспечивает. Частичный reload и отдельное flash-хранилище pins не добавлены. [Архитектурная записка и тесты](LIFECYCLE_FALLBACK_03.md).

ТЗ №02: частичный IP-Bypass DNS остаётся FakeIP; resolve выполняется в позиции секции, терминальный route использует только соответствующие IP-кандидаты. Неизвестный remote set удерживается через nft pending и scoped отказ core до первого содержимого. Snapshot и снятие pending атомарны. Свои mark-биты проверяются масками, чужие сохраняются. Это локальный контракт r10; схема LuCI/UCI и pinned upstream не заменены. [Подробности](STARTUP_DNS_DEVICES_02.md).

WARP API: native generator задаёт `profile.detour` даже автоматической регистрации — секция либо маркированный `direct-out`. API использует dialer ядра независимо от транспортного каскада; raw JSON остаётся явной пользовательской конфигурацией. No-op определяется итоговым JSON, реальные изменения требуют пересоздания всего core. Ограничения RAM-кэша и приёмка — TESTING, раздел WARP.

uTLS IDs/версии/REALITY-ограничения приложения имеют один источник — `shared/tls-fingerprints.json`. Backend получает проверяемый generated `.uc`, не читает JSON с диска на роутере. Новые версии не синтезируются по номеру: контракт каталога проверяется на ClientHello и parser текущего pinned core. В UI отдельные виртуальные поля семейства/варианта разрешаются в прежнее поле `tls_fingerprint`, без миграции UCI.

Ручной VPN-редактор: `connectionUri.ts` читает поддерживаемые URI и меняет только затронутые компоненты; `connectionEditor.ts` строит виртуальные поля LuCI JSONMap. `links.ts` через CBI `prepareSave` проверяет эффективный URI до записи diff в существующий `connection_link`. Виртуальные поля не расширяют UCI. Генератор продолжает выдавать `type: parser` с `link` и отдельными TLS-override; экспорт ссылки применяет приоритет fingerprint без изменения сохранённого URI. Exact-фильтры Fallback/URLTest остаются именованными; редактор синхронизирует их при rename/delete, regex не переписывает.

```text
LuCI (TypeScript bundle)
  → LuCI fs/exec RPC + ACL → /usr/bin/kabanmax (ucode)
  → service.cli → config validator/migration → generator
  → sing-box config + service lifecycle + nftables/routing
  → sing-box outbounds (VLESS/WARP/groups/direct)
  → помеченный Zapret2 outbound → NFQUEUE → nfqws2 на секцию
```

Frontend `src/main.ts` экспортирует KabanMaxView; LuCI-обёртка передаёт его `view.extend()`. Точка входа `/usr/bin/kabanmax` загружает библиотеку из `/usr/lib/kabanmax` или подготовленного bytecode; `KABANMAX_LIB` позволяет указать другую библиотеку. Реальные данные читаются RPC/CLI и Clash API; браузер и роутер могут иметь разную сетевую достижимость API.

`service/lifecycle.uc` сериализует start/stop/reload lock-ом, выполняет миграции/валидацию, проверяет готовность ядра и сохраняет fingerprint применённого nft script. Reload сравнивает сформированные конфиги, а изменение конфигурации во время операции ставит повторное применение в очередь. Ядро/watch и отдельные procd workers не следует подменять внешними одноразовыми shell-командами.

`config/` нормализует UCI, секции, правила и подключения. `singbox/generator.uc` строит outbounds, DNS и routing; `nft/sections.uc` и `nft/apply.uc` строят перехват и приоритетные sets. Это две части одной политики: изменение одной требует проверки другой. Списки IP и доменов не взаимозаменяемы.

`zapret2/model.uc` — общий источник очередей, mark и аргументов worker для sing-box/nft/procd. Реестр слотов сохраняет идентичность секций; удаление реестра без оценки действующих соединений опасно. Runtime проверяет ожидаемый PID каждой очереди; наличия процесса nfqws2 недостаточно.

Go-ядро воспроизводится через `core/UPSTREAM` + patch + branding script. Рабочая копия в `.local/core-src` содержит исходники/тесты изменений, но релизная сборка берёт закреплённый commit и применяет patch заново. Изменять только рабочую копию недостаточно.

Сетевая последовательность и ограничения — [NETWORKING](NETWORKING.md); точные владельцы модулей — [COMPONENTS](COMPONENTS.md).

Резидентный state service собирает подходящие строки `logread` каждые 1.5s независимо от открытой вкладки. Журнал хранится в приватном `/tmp/kabanmax-journal/archive.json`: до 24 часов с момента сбора по монотонным часам и до 2 МиБ вместе с JSON/метаданными, старейшие записи удаляются первыми. Состояние переживает перезапуск процесса, но не перезагрузку роутера. Для дедупликации сохраняются ограниченное окно отпечатков и отпечаток системного снимка, а не удалённый текст. `clear_logs` требует write ACL и успешного свежего чтения, иначе отказывается от очистки. Вкладка и резервный CLI-чтитель используют архив.
