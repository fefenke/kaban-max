# Сетевые контракты и инварианты

Текущие границы, которые нельзя менять ради уборки. Архитектура слоёв — [ARCHITECTURE](ARCHITECTURE.md), причины — [DECISIONS](DECISIONS.md), доступ к устройствам — [SECURITY](SECURITY.md).

## Маршруты, DNS и nft

Zapret2 updater при отказе API использует raw `release/zapret2-release.json`: проверенный snapshot официального upstream tag/asset/digest. Он не объявляется свежим upstream latest; UI пишет «Latest verified … (API unavailable)». Archive скачивается по официальному публичному release URL и проверяется прежним SHA256 guard. Snapshot обновлять после проверки upstream, не отключать digest ради fallback.

WARP r38 принимает мягкий локальный `listen_port_hint` из постоянного UCI при пустом RAM cache; серверный `port` и обязательный `listen_port` сохраняют свой смысл. Подошедший старый порт не вызывает flash write; новый сохраняется после десяти здоровых минут один раз на профиль/router boot. [Контракт и границы](WARP_PORT_HINTS.md).

- Порядок секций и first-match сохраняются. Нельзя разрешать Direct для соседнего DNS-IP на основании успеха одного адреса.
- Domain и IP-правила не взаимозаменяемы. DNS query не знает destination port; port-limited bypass не следует расширять DNS-ответом.
- Частичный IP-Bypass сохраняет FakeIP до разрешения в нужной позиции маршрута. Выбранный dial должен использовать адрес, соответствующий выигравшему правилу.
- Недоступный remote ruleset не превращается в Direct: unknown/pending остаётся fail-closed до пригодного содержимого.
- nft-биты KABANMAX проверяются масками с сохранением чужих mark-битов. Не делать глобальный flush и не ломать PBR/mwan3.
- `config_path`/`cache_path` читаются согласованно из настроек. Изменение пути кэша меняет persistence; default `/tmp` не flash.
- IPv6 FakeIP — `2001:2::/112` вне ULA для Chromium/Edge PNA/LNA; размер пула не увеличен. DNS/nft используют одну константу; benchmark `/48` не допускается как публичное autoroute evidence. Старые runtime ranges распознаются диагностикой. [Причина, миграция и проверки](NETWORK_AVAILABILITY.md).

Опорное доказательство этих границ — [startup/DNS/devices](STARTUP_DNS_DEVICES_02.md); отчёт описывает свой этап, не выпуск r24.

## Fallback и TLS

Предварительный fallback suspect и probe-only failure при свежих данных — Debug; confirmed failure сохраняет Warn. Copy/close и routine transport/refused/timeout в Debug не перестают поступать close handler/autoroute evidence. DNS сохраняет FORMATERROR/REFUSED и причины: первый обычный отказ — Warn, повторный summary за 10s относится только к тому же server+domain+type+class. TLS/auth не включены в blanket downgrade. [Политика и границы](LOGGING.md).

На OpenWrt отдельный монитор проверяет прямую доступность без VPN/локального DNS: после двух неуспешных раундов две независимые службы не ответили, логирует наблюдаемые route/carrier/address/netifd facts и включает gate сетевых логов. Восстановление требует проверенного HTTPS-ответа; между двумя событиями сетевые сводки не выводятся. Ошибки конфигурации/аварии не замалчиваются. Проверки имеют тот же outbound mark, ограничены по памяти/времени и не выключают TLS. Это модель контрольной доступности, не доказательство неисправности ISP. [Полный контракт](NETWORK_AVAILABILITY.md).

Список соединений — диагностический снимок, а не реестр маршрутов/источник autoroute evidence. Локальный core ограничивает `/connections` до 200 последних non-DNS строк и возвращает реальный `connectionsTotal`; отсутствие строки при `truncated` не доказывает закрытие соединения. Ограничение не меняет routing, TLS, DELETE all или число живых соединений. [Контракт и совместимость](LOGGING.md).

- Успех TCP dial не равен данным приложения. HTTP/TLS/protocol проверки и пользовательский read — разные виды evidence.
- Подтверждение сбоя/возврата относится к конкретному раунду и outbound. Старая сессия не отменяет новый сбой проверок.
- Не переигрывать пользовательские запросы незаметно ради диагностики. Старые сессии могут жить до их завершения; JSON reload может их закрыть.
- TLS split/fingerprint/classical параметры относятся к конкретному серверу, а не ко всей группе. URI override не должен неожиданно включать TLS.
- Default Chrome и вариант 155 — разные объявленные профили; проверять реальные ClientHello/parser, не подменять поддерживаемые версии произвольной строкой.

Подробнее: [fallback пользователя](connections/fallback.md), [fingerprints](../core/FINGERPRINTS.md), [ограничения Chrome155](../core/CHROME155.md), [lifecycle evidence](LIFECYCLE_FALLBACK_03.md).

## WARP

Текущая локальная серия r36/r37: WARP с не заданным persistent keepalive получает 25s, включая initial handshake standby профиля; explicit 0/диапазон сохраняется. Только до первого успешного handshake и только при динамическом single-peer порте доступны максимум 3 быстрых rotations, затем прежний 90s debounce. r37 сохраняет подтверждённый локальный UDP порт в identity-keyed profile cache и использует как мягкий hint после restart; занятый hint не блокирует старт, explicit listen_port имеет приоритет. Нельзя выдавать сохранённый hint или прошлый успех за доказательство актуальной доступности; требуется реальная restart/HTTPS проверка. [Точный scope](PREVIEW_026.md).

Single-peer WireGuard клиент без явно заданного listen_port включает существующий fresh-port give-up recovery. Здоровая сессия защищена прежними условиями библиотеки; server/multi-peer/pinned-port bind identity сохраняется. Runtime retry/debounce timers не ускорялись. r33 прошёл полевой цикл отказа и восстановления WARP на новом UDP-порту без общего restart; это не доказывает внешнюю причину отсутствия UDP ответов. [Evidence](WARP_RECOVERY.md).

Native generator задаёт `profile.detour` для регистрации API, в том числе без сохранённых credentials. Detour API и detour пользовательского транспорта — разные вещи. Автоматическая регистрация не должна обходить выбранную секцию; raw JSON остаётся явной конфигурацией пользователя. Успешный mock генератора не доказывает доступность Cloudflare API у провайдера.

WARP wrapper передаёт `InterfaceUpdated` вложенному WireGuard: network manager видит только wrapper, поэтому без forwarding сброс сети не обновлял UDP bind WARP. Пока регистрация не завершена, уведомление не блокирует network manager. Правка r29 не меняет выбор fallback, API detour, credentials или TLS. Она устраняет подтверждённый кодом дефект восстановления, но ещё не доказывает причину каждого полевого обрыва после Save & Apply. [Проверки и границы](WARP_RECOVERY.md).

## Авторутинг

- Реальная ошибка принадлежит выигравшей исходной Zapret-секции и конкретному flow; сторонние logs/connections/DNS observations не заменяют атрибуцию.
- Проверяется фактический dial IP. Достоверная identity берётся из допустимого контекста потока; reverse DNS не создаёт разрешение.
- Последовательность кандидатов и разрешённые Direct/WARP выходы задаются source settings. Альтернатива не равна source и не применяет списки целевой секции к исходному flow.
- Ручное направление, verifier evidence и opt-in auto-apply различаются. Голый TCP connect не доказывает работу приложения. Поддержку протокола/порта проверять в текущем core, не предполагать универсальность.
- Применённое persistent web IP-перенаправление r39 действует для всех устройств и портов **выбранной выигравшей секции** (`all_devices`, `all_ports`). Origin device/inbound остаются доказательством исходной ошибки, а не ограничением этого правила. Соседняя секция/IP, first-match и infrastructure protection не расширяются. Strict short-lived decisions и явные исключения сохраняют свои отдельные проверки scope. [Контракт r39](AUTO_ROUTING_SECTION_IP.md).
- Ошибка уже выбранной альтернативы не становится новым отказом исходного Zapret. EAGAIN/EWOULDBLOCK не запускают смену маршрута; реальные timeout сохраняются.
- Routes/denies не удаляются для освобождения места новым данным. Настоящий отказ надёжного сохранения/отзыва остаётся fail-closed; бюджет сам по себе не выключает секцию.

Точный текущий контракт — [storage r24](AUTO_ROUTING_STORAGE.md), предыдущие полевые исправления — [№2–4](AUTO_ROUTING_FIELD_ERRORS.md). Старые тексты r11/r12 с manual-only или 64-record limit не переносить на текущий код.
