# WAN, DNS-повторы и IPv6 FakeIP

Текущий локальный контракт, 2026-11-23. Версия и статус установки — [PROJECT_STATE](PROJECT_STATE.md). Логи до logd меняют patches `0027-fakeip-ipv6-and-domain-dns-logs.patch` и `0028-wan-outage-log-gate.patch`; предыдущая очистка шума сохраняется.

Контракт включён в установленный на одном роутере preview 0.2.3/r29; runtime generator выдаёт `2001:2::/112`, текущие WARP/YouTube HTTPS smoke успешны. Свежие suites и package/install evidence — [PREVIEW_023](PREVIEW_023.md). WAN-loss/Chromium/IPv6-only/PBR soak это не заменяет.

## WAN: два события вместо сетевого шума

На OpenWrt core запускает один монитор после Router PostStart и останавливает его через lifecycle scope. На других системах он автоматически не запускается. Наблюдение не приостанавливает маршрутизацию, fallback или авторутинг — меняется только вывод журнала.

1. При двух последовательных неуспешных раундах появляется один Warn `WAN unavailable`: наблюдаемые default routes, состояние интерфейса/carrier, наличие адреса, доступные netifd status/error codes и причины отказов внешних проверок.
2. После этого связанные сетевые Warn/Error DNS, VLESS/WireGuard/WARP, fallback и типовые transport errors отбрасываются до вывода в console/logd, Clash observer и platform writer. Повторных outage-сообщений и промежуточных DNS-сводок нет. Счётчик хранится в RAM, без списка ошибок/доменов.
3. Первая подтверждённая доступность даёт один Warn `WAN restored`: что ответило, длительность и число подавленных **сообщений**, не число потерянных DNS-запросов. Только после записи recovery gate открывается. Переходы и gate сериализованы mutex: сетевой поток не может проскочить между recovery event и снятием флага.

Это suppression сетевых событий и сообщений transport/connection logger, не запрет всех записей приложения. Runtime TLS/auth ошибки VLESS тоже подавляются до восстановления; при рабочем WAN их прежние уровни сохраняются. Ошибки локальной конфигурации/парсинга/чтения сертификатов, сохранения, permission, OOM/panic/fatal и независимые сообщения KABANMAX остаются диагностируемыми. Неизвестные новые сообщения зависимостей вне сетевых logger не объявляются автоматически сетевыми.

### Что считается доступностью

Две независимые службы: [Cloudflare DoH JSON](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/dns-json/) и [Google DoH JSON](https://developers.google.com/speed/public-dns/docs/doh/json). Монитор делает только запрос `example.com`/A. Он подключается к фиксированным IPv4/IPv6 адресам служб, сохраняя HTTPS hostname/SNI и обычную проверку сертификата. Системный DNS, VPN, HTTP proxy environment и KABANMAX capture не используются: на Linux ставится тот же SO_MARK `0x08000000`, что исключён из nft-перехвата собственного трафика.

Успех требует HTTP 200 и реально прочитанного валидного DNS JSON с `Status`, а не TCP dial. Любой корректный DNS rcode доказывает получение ответа, не наличие конкретной DNS-записи. Redirect, пустой/невалидный/слишком большой ответ успехом не являются. Достаточно одной ответившей службы/семейства; отказ одного VPN или DNS-настройки приложения не выключает журнал.

Один раунд: максимум две provider goroutines; каждая пробует IPv4 и IPv6 последовательно, до 2s на попытку; общий deadline 5s. У каждого transport закрываются соединения. Ответ ограничен 4096 байт, заголовки 8192. При доступности проверки раз в 30s; при подозрении/отключении раз в 5s. Новая сетевая ошибка, включая Debug opening/copy failure, может разбудить монитор раньше, но между началами раундов не менее 5s. Канал ранней проверки имеет ёмкость 1; нет goroutine/request на каждую ошибку.

До подтверждения outage gate открыт: физический обрыв не распознаётся мгновенно. Неудача проверки доверия TLS или прав socket — Unknown, а не доказанный WAN-loss: один раз сообщается непригодность мониторинга, ошибки не подавляются. Unknown во время уже подтверждённого outage не выдаётся за восстановление и не создаёт третье событие.

### Причина падения: наблюдение, не догадка

Маршруты берутся из ограниченных `/proc/net/route` и `/proc/net/ipv6_route`; reject/loopback default не считаются действующими. Из `/sys/class/net/DEVICE/carrier` и net.Interface читаются flags/наличие адреса. Факт отсутствия default в main table не равен отсутствию маршрута в PBR/mwan3: окончательное состояние зависит от внешних ответов, а этот факт только входит в причину.

`ubus call network.interface dump` (timeout 700ms, stdout максимум 64 КиБ) добавляет только up/pending/available/device/l3_device и до четырёх subsystem/code для WAN/интерфейсов default route. Например, `ppp:AUTH_FAILED` — реальный код netifd. Raw data, параметры ошибок, логины/пароли и адреса интерфейсов не выводятся. Неподдерживаемая схема/недоступный ubus не превращаются в выдуманный диагноз.

Если интерфейс поднят, адрес/маршрут есть, но обе контрольные службы недоступны, сообщение так и говорит и не объявляет установленной вину ISP. Одновременная блокировка обеих контрольных служб при рабочем остальном интернете может дать ложное outage; это предел этой модели, не доказательство глобальной недоступности. Внешние firewall/PBR и аппаратный WAN-loss требуют отдельной приёмки. Пробы не отключают TLS/firewall и не меняют конфигурацию сети.

## DNS: разные домены не смешиваются

Ключ окна — **DNS-server tag + имя (lowercase/FQDN) + тип + класс**. Поэтому ошибки разных доменов, A/AAAA и серверов видны отдельно. Первый обычный отказ сразу Warn с именем сервера, вопросом и причиной; дополнительные отказы того же ключа за 10s — одна сводка с числом и последней причиной. Успешные ответы/причины отказов приложения не изменены. Служебный CHAOS/TXT REFUSED известных version/hostname/id запросов остаётся Debug.

Не более 256 активных окон; сохранённая диагностическая причина не длиннее 1024 байт. При превышении — одно явное предупреждение о лимите и подробности дополнительных вопросов в Debug. Во время outage и это предупреждение подавляется. Ограничение защищает 256-МБ устройства от роста map/timers по произвольному числу доменов. Возвращаемый error сохраняет исходную причину и IsLoggedFailure; ограничение текста относится только к накопленной сводке.

По дополнительному прямому указанию пользователя `connection refused`, настоящие deadline/timeout в ConnectionManager также Debug. `no route to host`, not-connected/reset/broken-pipe/copy-close остаются Debug. TLS/auth ошибки не включены в blanket downgrade; текущая матрица — [LOGGING](LOGGING.md).

## IPv6 FakeIP и Chromium/Edge

[Upstream issue #4473](https://github.com/SagerNet/sing-box/issues/4473) описывает конфликт ULA FakeIP с PNA/LNA Chromium. [Код Chromium](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/services/network/public/cpp/ip_address_space_util.cc) относит `fc00::/7` к local. [Актуальный пример sing-box](https://sing-box.sagernet.org/configuration/dns/server/fakeip/) использует `2001:2::/48`.

KABANMAX использует **`2001:2::/112`**: часть того же benchmark prefix, но прежние 16 host bits/65536 адресов вместо расширения пула. DNS generator и nft берут одну константу; перехват LAN/System, bypass exclusions и local guards согласованы. IPv4 `198.18.0.0/16` не меняется. Локальные ULA пользователей не перенумеровываются.

`2001:2::/48` не считается реальным публичным адресом в backend public-IP validator и core autoroute protected guard. Offline route forecast требует core mapping для текущего FakeIP и также понимает диапазон из реально анализируемого runtime JSON, включая старый `fc00::/112`. Новый synthetic IPv6 не становится основанием для автоматического внешнего probe/маршрута.

Существующий FakeIP store умеет отфильтровывать записи вне новых пулов: тест миграции сохраняет IPv4, удаляет старое IPv6-соответствие, выдаёт новый IPv6 и сохраняет его через следующий restart. Общий cache.db не удаляется. Клиенты могут временно держать старые AAAA: после будущего обновления может потребоваться повторное разрешение имени/истечение DNS-cache клиента. Установку/очистку клиентских кэшей эта задача не выполняла.

## Проверки — 2026-11-23

Linux x86_64, существующий локальный Docker `kabanmax-autoroute-tests`, `/work` read-only, Go 1.26.10 и ucode v0.0.20250529. Все новые WAN tests — синтетические; они не запускают внешние проверки и не подключаются к роутерам/VPS. Source inspection внешних Chromium/sing-box/DoH документов выполнен 2026-11-23; это не браузерная/аппаратная приёмка.

До реализации были RED: старый generator/nft prefix, public-IP/route forecast нового IPv6, per-domain DNS separation, first-failure Warn и Debug refused/deadline. Store migration уже поддерживалась pinned core и проверена новым тестом. WAN integration test до появления модуля не собирался; после реализации проверяет реальные две строки logger, а не подменяет output.

| Команда | Результат / scope |
| --- | --- |
| `docker exec kabanmax-autoroute-tests env PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin sh /work/tests/core/run_network_availability.sh /tmp/core /work` | PASS: clean archive pinned commit + 28 patches; 7 race packages common/autoroute, DNS, FakeIP store, route, fallback, WAN state и logger; compile-only cmd |
| `docker exec kabanmax-autoroute-tests bash /work/tests/run.sh` | PASS 97/97 backend test files после смены prefix/guard/forecast |
| `docker exec kabanmax-autoroute-tests bash /work/tests/run.sh packaging/core_patch_series` | PASS 1/1 file после фиксации версии текущей patch-серии |
| `docker exec kabanmax-autoroute-tests sh -c 'cd /work && ucode -c -o /dev/null kabanmax/files/usr/lib/singbox/constants.uc && ucode -S -c -o /dev/null kabanmax/files/usr/lib/singbox/constants.uc && ucode -c -o /dev/null kabanmax/files/usr/lib/core/ip.uc && ucode -S -c -o /dev/null kabanmax/files/usr/lib/core/ip.uc && ucode -c -o /dev/null kabanmax/files/usr/lib/diagnostics/route_policy.uc && ucode -S -c -o /dev/null kabanmax/files/usr/lib/diagnostics/route_policy.uc && sh -n tests/core/run_network_availability.sh && sh -n tests/core/run_auto_routing.sh'` | PASS оба ucode syntax режима трёх файлов и shell syntax двух runners |
| `python -m unittest discover -s tests/docs -p 'test_*.py'` | PASS 9 tests |
| `python scripts/check-project-docs.py --write-facts`, `python scripts/check-project-docs.py`, `git diff --check` | Финальный gate после актуализации source facts и документов |

Новые проверки: два WAN события и suppression между ними; Unknown не выдаётся за recovery; критические ошибки не скрываются; название домена не обходит gate; netifd error codes без private params; reject/loopback route parsing; валидные/пустые/redirect/oversize HTTP ответы; split DNS keys и bounded map/error; FakeIP family-preserving migration и protected range. Предыдущие frontend/RSS тесты не выдаются за свежие. Нет аппаратного OpenWrt WAN-loss/PPPoE/DHCP/mwan3/PBR/IPv6-only/captive-portal smoke, запуска Chromium и новых APK/IPK/установки/публикации.
