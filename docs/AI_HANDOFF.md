# Контекст следующего чата

**Последний статус:** опубликован [0.1.7 prerelease](https://github.com/fefenke/kaban-max/releases/tag/0.1.7), tag/source `e5dd33b`, core r12. Пользователь прямо разрешил публикацию и перенос ещё не выпущенного тега после исправления только CI-фикстуры. Все 14 публичных assets скачаны и сверены по SHA256/размеру, manifests/ref проверены. `.local/audit/task017/public-verification.json` — локальное evidence. Backend дополнительно 92/92 без root; аппаратных установок и тестов не было. Сохранённые intents не равны активным маршрутам; ограничения в AUTO_REGISTRY_017 остаются актуальными.

## 0.1.7 / r12 — новое ТЗ заменило ограничения этапа UI v2

Пользователь попросил реализовать `KABANMAX_0.1.7_development_TASK.md`: в нём прямо разрешены необходимый core API и prerelease. Новые исходники — patch 0008, `config/auto_registry.uc`, `diagnostics/auto_registry.uc`, обновлённые records UI/API. [Контракт](AUTO_REGISTRY_017.md). Прежние запреты и блокеры в следующих исторических разделах не описывают этот новый этап. Не считать saved intents активными и не расширять ordinary/IP-only eligibility. Точные gates и публикационный статус — PROJECT_STATE/TESTING.

## UI v2, 2026-11-16: НЕ ПУБЛИКОВАТЬ

Последнее указание пользователя отменяет первоначальное «публикуй»: подготовить локально и показать сделанное/несделанное. Ни commits, ни push/tags/releases в этой задаче не выполнялись. Исходный dirty tree сохранён. Изменения и воспроизведённые границы core — [UI_FIXES_V2](audits/UI_FIXES_V2.md), команды — [TESTING](TESTING.md). Подготовлен reviewable `main.js`; новых release packages нет. Не выдавать paged ограниченный r11 snapshot за полный реестр ядра или работу на роутере.

## Выпуск завершён: 0.1.6, 2026-11-16

Опубликован [prerelease 0.1.6](https://github.com/fefenke/kaban-max/releases/tag/0.1.6): source/tag `4445219fa62eac084143620a35bb58d34b704008`, core r11, 14 assets. Все пять Actions success; все публичные downloads независимо сверены по SHA256/размерам, manifests и 13 checksum records PASS. Повторно создавать релиз/тег не требуется. Публикация не означает установку: OpenWrt/logread/TZ/UI/NFQUEUE/PBR/mwan3/WARP/VPN/egress/ARM64 runtime не проверены. Ниже — результаты локального GO и исторические этапы.

## Финальная QA / публикация 0.1.6 — 2026-11-16

Действует новое разрешение пользователя на commit/push/tag/prerelease после GO; прежние запреты публикации ниже исторические. Один агент; оборудование/VPS не используются. Локальный GO: frontend 175/1682, backend 91/91, tsc/lint/bundle/po2lmo, installer и namespace smoke, clean apply семи patches + пять race suites и свежий executable smoke PASS. 10 ARM64/noarch IPK/APK + manifests/install.sh/SHA256SUMS в ignored `.local/audit/final-qa-publish/release`; x86 smoke packages отдельно и в assets не входят. Полные APK/IPK payload совпадают за исключением штатных APK metadata. Версии: приложение 0.1.6, core r11, default minimum r10, opt-in требует r11.

№07: добавлены повтор после отмены/ошибки и защита служебного имени `infrastructure-direct-out`; прежние mocks уже покрывают reconnect/stop/reload, backend activation rollback и Save & Apply/no-op. Это локальные модели. OpenWrt logread/TZ и настоящий UI остаются UNVERIFIED. Release checker принимает core >= minimum и отвергает недостаточный core; не поднимать глобальный minimum ради равенства. Состояние GitHub проверять перед повторной публикацией, не создавать дубликаты. [Свежие команды](TESTING.md); evidence `.local/audit/final-qa-publish/` не публиковать.

## №07 — продолжение: checkpoint

№07 остаётся незавершённым. Последний полный frontend прогон: 175/175 файлов, 1678/1678 тестов; service backend — 14 файлов passed; tsc, целевой lint, bundle и po2lmo прошли. CLI fallback показывал очищенные строки из системного кольца; неполный ответ проверки обновлений принимался за успех; существующий бинарник Zapret2 без version предлагалось установить — исправлено с RED → GREEN. Mock отдельных функций установщика проверяет один вопрос fresh yes/no и состояние пакета при upgrade, без реальной установки. Следующий шаг: воспроизвести изменение timestamp logread при смене TZ в `service/log_journal.uc` / `service/state_service.uc`, затем проверить полный lifecycle Zapret2, расширить mock установщика и Save & Apply. Core r11 и patches 0001–0007 не изменялись.

Новее: полный frontend 175/1679 passed, но bundle собирался параллельно; перепроверить последовательно. В `install.sh` исправлен приоритет явного `--lang=en` над LuCI auto, shell mock RED → GREEN; защита двойной проверки обновлений RED → GREEN. Backend тест `service/zapret2` — 2/2. Следующий конкретный шаг: проверить timezone на настоящей реализации OpenWrt logread либо совместимом локальном стенде (в доступном offline Docker только BusyBox logread); не заявлять этот сценарий закрытым. Затем расширить mock повторного запуска/отмены и проверить Save & Apply и итоговые gates.

Ещё новее: после финального bundle последовательный frontend 175/1680 passed; диагностика backend 10/10, service 14/14 до последней доработки Zapret2 и сам Zapret2 2/2 после неё. Защищён перезапуск операции до обязательного reload; различаются отсутствующий файл Zapret2 и файл без execute permission. Нужны незакрытые TZ OpenWrt logread, mock повторного запуска/отмены и дополнительные переходы/reconnect; точные команды и ограничения — TESTING.

## №07 — частичная работа 2026-11-16

№07 не завершено. Кнопка очистки логов больше не блокируется фоновым чтением; ответ чтения, начатого до очистки, игнорируется. Zapret2 status сообщает наличие управляемого исполняемого файла; при его отсутствии UI предлагает установку. Устранена гонка старого ответа статуса с запуском новой операции установщика. Проверка на настоящем LuCI/OpenWrt не проводилась. Остальные требования №07, включая полную backend-семантику очистки, все переходы Zapret2, язык установщика и полную проверку статусов и lifecycle, требуют дальнейшей работы. В исходном install.sh найден один вызов `ask_translation`, повторный запрос пока не воспроизведён. Текущий источник ядра: pinned UPSTREAM + patches 0001–0007, тестовая ревизия r11; ядро в этой работе не менялось.

Полный frontend suite обнаружил 7 падений: локализация, контракт полей редактора URI, round-trip Zapret2 и подписи отпечатков. Их происхождение не установлено. Результаты и команды — в TESTING; не считать №07 готовым к приёмке.

## Передача №04Б-ФИНАЛ — 2026-11-16

Текущий источник: pinned UPSTREAM + patches 0001–0007. 0006/audited r11/r9/r10 не изменены; test binaries r11 с web extension в ignored .local/audit/auto-routing-04b-final/build, SHA в TESTING. Scratch final/source не source релиза. Изменения dirty tree сохранять, не восстанавливать remote. Один агент, без commit/push/релизных пакетов/устройств/VPS/реальных внешних проб. №05–10 не начинались; №07 и release — отдельные задачи/чаты.

Прочитать обновлённый AUTO_ROUTING_IMPLEMENTATION_04B и свежий TESTING. Default пустой contract = web GET / порт443 по доверенному flow FQDN. Старый JSON без mode = strict для обратной совместимости. Обычные ресурсы не должны отражать nonce: 2 повторных transport failures + 2 содержательных HTTPS-ответа того же IP/hostname/path дают alternative_reachable с ручным Apply, но web НИКОГДА не auto-apply, включая recheck. verified_for_apply — только прежний strict nonce contract. UI выводит evidence и explicit apply eligibility, две галочки/независимые permissions сохранены; bundle пересобран, русские подписи добавлены.

ReportDial связывает фактический remote IP только с тем же исходным core event; события возвращают stable source ID/mark/domain_known. IP-only = видимая TCP диагностика без lease. Полный failed dial нескольких A/AAAA не угадывается и остаётся actual_destination_ip_unknown; никакого DNS batch для web. Исправлен воспроизведённый дефект: lease не выбирает IP из смешанного списка, нужен единственный точный address исходного matcher. Значит у неоднозначного имени даже ручная lease может не примениться — сохранение sibling IP важнее расширения scope.

Свежие PASS: 31 backend-файл, 121 frontend-тест, tsc/lint/bundle/po2lmo, пять race-пакетов и clean apply семи patches, отдельные amd64/arm64 binary-only builds. На executable ordinary HTTPS/FakeIP/IP-only, domain/CDN/mixed DNS, три pre-routing mode и прежний strict regression smoke; WARP/anti-bot/body-stall/invalid TLS дополнительно controlled mocks. Physical egress=false, реальный NFQUEUE/PBR/WARP/UDP и OpenWrt UX не проверялись. CNAME/opaque subscriptions и малое/защищённое anti-bot содержимое fail closed; не ослаблять ради универсального auto-apply. Дальнейшая аппаратная приёмка только по отдельному разрешению.


## Передача №04Б — 2026-11-15

Финальная проверка: 31 backend-файл, 120 frontend-тестов, пять core race-пакетов и executable smoke PASS; binary-only x86_64/ARM64 собраны, SHA256 в TESTING. При self-review воспроизведён и закрыт DNS Answer owner mismatch; откат соединения атомарно связан с точным lease ID, поэтому поздняя ошибка не снимает замену. Последний patch после этого проверен чистой сборкой. Коммиты не создавались.

Пользователь одобрил реализацию №04Б; работал один агент, без commit/push/публикации/роутеров/VPS. Не повторять завершённые №01–03 и не терять исходный dirty tree. Источник core — UPSTREAM + patches 0001–0006; scratch `.local/audit/auto-routing-04b/source` не источник релиза. Выключенная автоматика сохраняет JSON/minimum r10, opt-in требует r11. Проверенные бинарники и синтетические fixtures находятся в ignored `.local/audit/auto-routing-04b/`; не публиковать каталог.

Сначала прочитать [контракт №04Б](AUTO_ROUTING_IMPLEMENTATION_04B.md) и свежий блок [TESTING](TESTING.md). UI интегрирован в пересобранный main.js, предыдущий bundle сохранён в `before-ui/main.js`. Runtime lease действует только после исходного first-match Zapret2 и при точных domain/IP/source/inbound/port. Persistent suppression хранится отдельным атомарным файлом, а не staged UCI. Probe работает только с nonce-сотрудничающим HTTPS endpoint, timeout/обычный 403 не доказательство отказа. Physical egress флаг false; реальный NFQUEUE/PBR/WARP не проверялся. CNAME, неизвестный client context, opaque endpoints/subscriptions дают fail closed. Следующее продолжение: аппаратная приёмка лишь по отдельному разрешению, проверка UX на LuCI и дальнейшие контракты без ослабления безопасности. Старый read-only №04 не является текущим объёмом реализации.


## ТЗ №04 — безопасная часть, 2026-11-15

Добавлены read-only `diagnostics/route_policy.uc`, CLI `check_route` и прогноз на вкладке диагностики. Block учитывается по первому совпадению и source/port, не глобально. Unknown не разрешает Direct; DNS/пробы/мутации отсутствуют. Свежие целевые проверки — TESTING. **Полное ТЗ не выполнено:** активный probe API r10 не даёт требуемого app/IP/egress evidence и `/delay` влияет на health; narrow domain+IP scope для CDN также требует отдельного решения. Managed-правила, автоматические списки в секциях, TTL/suppression/rollback не реализованы. Пользователь разрешил безопасную часть при препятствии; не запрашивать повторное согласование уже одобренных требований. [Отчёт и продолжение](AUTO_ROUTING_DIAGNOSTICS_04.md), [одобренный design](superpowers/specs/2026-11-15-auto-routing-04-design.md). №01–03 и core r10 сохранены; без субагентов, коммитов, сети к сервисам/VPS, установки и публикации.

## ТЗ №03 — 2026-11-15, локально проверено

Сначала [отчёт №03](LIFECYCLE_FALLBACK_03.md) и свежий раздел [TESTING](TESTING.md). Все пять patches применены к pinned commit, base r10 отдельно собран для x86_64/ARM64 в `.local/audit/r10-03/build`; r9/dist сохранены. Core `-race`, backend 39/39, проверка самого x86_64 executable (mixed DNS/FakeIP, resolved isolation, missing provider, graceful FakeIP restart) passed. Production/patches не менялись. Стандартный `/tmp` cache не переживает reboot; persistent pin и missing/corrupt cache проверены на новых Box. Общий JSON reload закрывает TCP; обычный Fallback сохраняет. Новая настройка selector и отдельное flash-хранилище pins не добавлены. Нужна перечисленная в отчёте аппаратная приёмка. Коммитов, push, установки и публикации не было. Исторические записи ниже читать с учётом №03.

## ТЗ №02, 2026-11-15: локально, не выпущено

См. [разбор №02 и передача №03](STARTUP_DNS_DEVICES_02.md), свежие команды — [TESTING](TESTING.md). Добавлены dnsmasq local/server zones, избирательные mark-маски с сохранением чужих битов, регрессии devices/pause/System. Частичный IP-Bypass даёт FakeIP, необходимый resolve выполняется в позиции Bypass, core ограничивает dial адресами выбранного правила. Для remote set без содержимого добавлены scoped fail-closed в core и nft pending до атомарного sync; замена core повторно включает guards, no-op не меняется.

**Новый локальный minimum/источник — 1.14.4-r10, тот же UPSTREAM commit + пять patches.** r9 отклоняется. Пакеты r10 не собирались; старые dist не являются результатом №02. Один агент, без субагентов, коммитов, публикаций и оборудования. Чату №03: сохранить dirty tree, выполнить отдельные review/сборку и только с разрешением стендовую проверку nft/mwan3/PBR/IPv6/cache/корпоративного VPN. Исторический текст №01 ниже не описывает новое поведение смешанного ответа.

Обновлено 2026-11-15. Начать с AGENTS.md, PROJECT_STATE.md и DEVELOPMENT_INDEX.md. В дереве много прежних незакоммиченных и untracked изменений; они сохранены. Ничего не коммитилось и не публиковалось. Один агент, без субагентов; оборудование и VPS не использовались.

## DNS / UCI / GeoIP: локально реализовано, не выпущено

Исходные [аудит и ТЗ](audits/README.md) сохранены в проекте побайтово. Аудит не перепроверялся по GitHub; исторические 1.0.5-репорты не считаются доказательствами дефектов KABANMAX. Источник ядра — `core/UPSTREAM` (commit `60d96c99815a672712915a5c00114bf0f690ad80`, package `1.14.4-r9`) + два текущих patches. Ядро, patches, версии и frontend этой задачей не изменялись.

- Backend получает config/cache пути через `singbox.constants.config_path(settings)` и `cache_path(settings)`. Отсутствующее/пустое значение означает `/etc/sing-box/config.json` и `/tmp/sing-box/cache.db`. Явные пути сохраняются; runtime, lifecycle, Clash API и диагностика читают один эффективный путь. LuCI вправе не записывать default.
- Общий resolver — основной `dns-server`. При глобальном DNS detour транспортные endpoint получают явный bootstrap, если resolver не задан; `direct-out` остаётся для пользовательских назначений. Новый зарезервированный `infrastructure-direct-out` обслуживает прямые загрузки/регистрацию WARP независимо от DNS через VPN. Настроенные detour не получают прямого fallback.
- Подписки при глобальном DNS detour получают bootstrap через существующий `override.patch.domain_resolver`; явный пользовательский `override_patch.domain_resolver` имеет приоритет. Это managed override импортируемых узлов, а не условное заполнение отсутствующего поля внутри удалённого JSON: для собственного resolver импортируемых узлов задавать его явно в patch подписки. Raw outbound/endpoint resolver не перезаписывается.
- DNS query-правила SRS используют только доменную часть. Bypass без ограничения портов дополнительно выполняет основной DNS `evaluate`, затем `respond` по адресам ответа: inline IPv4/IPv6 либо полный SRS. Несовпадение продолжает нижние секции/FakeIP; source/System и порядок сохранены. Локальные зоны перед IP-проверкой остаются в локальном resolver. Порт назначения из DNS неизвестен, поэтому для port-limited Bypass response-проверки не добавляются.
- nft IPv4/IPv6 sync и маршруты согласованы регрессией Telegram/Discord/Meta, mixed SRS, IPv6-only и IP-literal; production nft не менялся. Facebook/Instagram в текущем каталоге domain-only, WhatsApp содержит подсети.

## Доказательства и продолжение

Свежие проверки: **38 целевых backend-файлов passed**; offline `go test -count=1 -race` на чистом UPSTREAM+patches: `dns` и `cmd/sing-box` passed. DNS walker проверен на synthetic SRS и mock transports; реальные dialer — на loopback DNS/SOCKS для ручного сервера/локальной подписки, endpoint по имени/IPv4/IPv6, detour on/off, отравленного bootstrap и разрыва VPN. Точные команды, результаты и неудачные запуски — [TESTING](TESTING.md), раздел DNS/UCI/GeoIP. Не принимать эти проверки за live Save & Apply или полный сетевой стенд.

Остаются отдельная приёмка на WR3000S/U, реальный провайдер/блокировки UDP:53, TLS/DoH/DoT и протоколы туннелей в полевой среде. Ответ DNS с несколькими адресами возвращается целиком при совпадении хотя бы одного IP по текущей семантике core `match_response`; фильтрация отдельных RR не реализована, смешанный ответ на границе Bypass/защищённой секции требует отдельной проверки маршрута до установки. Явный пользовательский resolver/каскад может сам создать зависимость от своего VPN; произвольные пользовательские циклы здесь не устранялись. Полная финальная приёмка и релиз не проводились.

Прежние задачи Fallback/VPN-редактора/uTLS/WARP описаны в PROJECT_STATE и TESTING; не переделывать их без нового воспроизведения. Реальный reload JSON по-прежнему пересоздаёт core и закрывает старые соединения; это не изменено.
