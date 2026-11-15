# ТЗ №03: r10 и границы lifecycle

Локальная проверка 2026-11-15. Один агент, без коммитов, push, установки, публикации и обращений к оборудованию. Изменения №01/02 сохранены. Production-код и пять patches в этой задаче не менялись; добавлены проверочные runners и тесты.

## Приоритет: sing-box-kabanmax 1.14.4-r10

Источник: `core/UPSTREAM`, commit `60d96c99815a672712915a5c00114bf0f690ad80`. Все пять patches последовательно проходят `git apply --check` и применяются к `git archive` этого commit. Dirty `.local/core-src` используется только как read-only хранилище Git-объектов. Branding выполняется штатным `scripts/brand-core.py`.

| Patch | Проверка и результат |
| --- | --- |
| 0001 stable fallback | Полный `protocol/group -race`, регрессии сохранения routed TCP/dial context и невозможности отменить новый сбой старым stream — passed |
| 0002 Chrome155 | `common/tls` и `protocol/parser -race`, фактический каталог/Chrome155/REALITY/parser fingerprints — passed |
| 0003 resolved route | Route walker и сам собранный executable ограничивают кандидатов выбранным правилом; отказ выбранного адреса не разрешает нижний Direct — passed |
| 0004 unavailable ruleset | Route/rule scope, retry/cache tests; собранный executable не подключается к доступному Direct при missing remote provider — passed |
| 0005 mixed DNS | Generated walker и настоящий FakeIP; собранный executable возвращает FakeIP для mixed SRS/IP ответа — passed |

0003/0004 последовательно изменяют одну границу сопоставления route: 0004 переносит флаг недоступности из отдельного кандидата и возвращает ошибку до dial. DNS query/response исключены из этого fail-closed matcher. 0005 расширяет DNS matcher отдельно от групп и TCP tracking; backend выдаёт `response_address_all` и требует r10. Патчи 0003–0005 не меняют selector/Fallback connection registry. Пересечение с Fallback проверено поведением, а не только отсутствием пересечения файлов.

Собраны **base, binary-only**, Go 1.26.10, CGO disabled:

| Путь внутри `.local/audit/r10-03/` | Размер | SHA256 |
| --- | ---: | --- |
| `build/amd64/base/sing-box` | 34844798 | `c072d5316e433ac7b6f03f1e97406017eda2cf41a9b982ea47b46624618967b7` |
| `build/arm64/base/sing-box` | 32309374 | `9ee954918394312e991a3d3d48fe8929aa253240d763db25ad9c3d08bafa1c1b` |

`version` x86_64 сообщает `1.14.4-r10` и штатные base tags. ARM64 кросс-собран, на ARM не запускался. APK/IPK, tiny/full и релизный комплект не собирались. `dist` и r9 не монтировались в сборочный контейнер: единственный выход сборки — отдельный каталог выше.

Проверен **сам полученный x86_64 executable**, не только Go test binary: generated mixed DNS → FakeIP; штатный SIGTERM и новый процесс сохраняют FakeIP; mixed resolved DNS допускает только IP выбранного route; missing provider не выпускает соединение в нижний Direct. Положительные контроли подтверждают доступность listener как для IP, так и для разрешённого доменного кандидата. Источник — `tests/core/r10_binary_smoke.py`, только loopback. GeoIP здесь представлен synthetic SRS с теми же CIDR matcher-ами; актуальность внешних GeoIP баз и kernel nft этим не доказаны.

## Холодный старт и сохранение выбора

`TestLifecycleColdCache` создаёт новые Box без переноса reload snapshots и health. Отдельно сохраняются внешний selector (`ut`) и ручной pin вложенного Fallback (`b`). При доступном дисковом кэше оба восстанавливаются. Проверены потеря файла, повреждение базы, удаление выбранного участника и снятие pin: безопасный default/первый допустимый участник, без восстановления отсутствующего pin. Отдельно проверяется `Fixed()`, а не только совпавший текущий участник.

URLTest — автоматическая группа, не ручной selector: собственного `StoreSelected` для автоматического результата у него нет. Fallback сохраняет `fixed` по изменению pin, не каждую автоматическую смену/health tick. Selector также пишет только при реальной смене выбора. Сохранение использует транзакции bbolt; новой периодической записи на flash не добавлено.

**Стандартный cache path `/tmp/sing-box/cache.db` теряется при настоящем reboot.** Поэтому штатный cold boot возвращает defaults, а не обещает прежний ручной выбор. Пользовательский persistent `sing_box_cache_path` позволяет восстановление, если файл доступен; кэш содержит также WARP/subscription данные и не должен молча переноситься на flash ради selector. Отдельное хранилище только ручных pins требует самостоятельного проектирования. Поведение persistent пути при отключении питания, flash износ и восстановление на настоящем OpenWrt остаются полевой проверкой.

## Reload, TCP, interrupt и FakeIP

| Действие | Установленная граница |
| --- | --- |
| Обычная смена Fallback при `interrupt_exist_connections=false` | Старое TCP и исходный dial context сохраняются; свежий отказ health не отменяется старым stream |
| Смена внешнего selector | Generator сохраняет прежнее `interrupt_exist_connections:true`. Новый тест проверяет true/false на зарегистрированном внешнем соединении; опция core работает |
| JSON не изменился при Save | Нет core reload, действующие сессии сохраняются; backend regression passed |
| Невалидный новый JSON | Проверяется до применения; действующий core не сбрасывается, backend regression passed |
| Изменился общий JSON / forced reload | SIGHUP → check в отдельном процессе → Close/Create. Старые TCP закрываются, новое подключение использует новый endpoint, loopback regression passed |
| Штатное завершение и новый core с тем же cache | FakeIP восстанавливается: binary smoke с реальным дисковым cache и полный fakeip/cachefile race suite passed |

Частичный reload произвольного JSON не реализован: проверки SIGHUP и перенос наблюдений не сохраняют старый Box/socket ownership. Безопасная замена отдельных outbounds требует управления зависимостями DNS/providers/endpoints/inbounds и временем жизни старых сессий. В этой задаче нет доказательства безопасного общего улучшения; lifecycle оставлен прежним. Backend ставит capture pause/drop до rebind, ждёт readiness и включает pending guards заново. Сохранение FakeIP не означает сохранение TCP. Дополнительный SIGKILL и чужой `procd term_timeout` не добавлялись.

Новая UI/UCI-опция внешнего selector не добавлена: это опциональная возможность, локального дефекта для её введения нет. Собственные настройки URLTest/Fallback не подменены настройкой внешнего selector. Повторная реализация rename/delete VPN, URI редактора и связей исключена из задачи.

## Direct diagnostics

Текущий Clash `/proxies/<tag>/exit` использует конкретный outbound `DialContext` и IP trace сервера без общего route walker; `route.default_mark` исключает его собственные пакеты из nft capture. Это уже ограниченная диагностическая операция, не domain-wide Direct exception. `experimental/clashapi -race` прошёл loopback TLS/mock-dialer suite. Обычный `diagnostics.checks` запрос `/check` намеренно проверяет путь выбранной секции и не равен запросу Direct. Нельзя исправлять его глобальным исключением домена. Реальный catch-all System + nft/PBR Direct egress необходимо проверить на устройстве; локальные mocks не доказывают kernel путь.

## Что осталось на оборудовании

- WR3000S/U: cold boot с обычным `/tmp` и явно persistent cache, nested Fallback/URLTest, исчезнувший член и отсутствие сохранения устаревшей health.
- Save & Apply: invalid config/no-op/changed JSON, готовность capture, отсутствие Direct утечки во время pause, восстановление pending и FakeIP при реальном SIGHUP/остановке procd.
- Реальные nft/ip-rule/conntrack/flow offload, IPv4/IPv6, source scope, GeoIP/Bypass, unavailable providers и последующее восстановление.
- mwan3/PBR и marks с коллизиями/без них; Direct диагностика при System catch-all; корпоративный VPN/DNS.
- WAN/VPN протоколы и реальные TTL/optimistic/persistent DNS cache, DoH/DoT/TLS/UDP:53. ARM64 runtime и упаковка/установка — отдельная приёмка.

Команды и свежие результаты: [TESTING](TESTING.md). Это локальная техническая проверка, не финальная приёмка и не релиз.
