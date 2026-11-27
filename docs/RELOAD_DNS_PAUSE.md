# DNS при Save & Apply: защита окна перезапуска

2026-11-26. Пользователь сообщает: после сохранения YouTube/ChatGPT работают непредсказуемо, ChatGPT иногда сообщает о регионе; переключение другого VPN на компьютере всегда восстанавливает работу KabanMax. Это свидетельство изменения клиентского сетевого состояния, но не доказательство конкретного виновного кэша.

## Диагностика без перезапуска

Read-only SSH к локальному роутеру: r45/running. В21:06/21:08/21:09MSK были реальные HUP reload после изменений, а не no-op. Отдельное сохранение до них отклонено валидатором `Automatic routing target section is unavailable`; это не успешный reload. Native Clash snapshot после пользовательского восстановления: новые ChatGPT flow идут через VLESS, YouTube/media — через WARP; один media flow уже принял более100МБ. Трафик обоих семейств наблюдался в захвате. Выбранные runtime группы/страны проверялись без изменения выбора. Выход VLESS по собственному exit API: IPv4 AT/IPv6 NL; это не доказывает региональную оценку сервиса для конкретного браузерного запроса.

FakeIP cache включён, путь RAM cache.db сохраняется, store_fakeip=true, оба FakeIP ranges прежние. Это проверка текущей конфигурации, не побайтное доказательство сохранения всех mappings в момент прошлого сбоя. OS DNS cache read не дал относящихся к запросу записей; браузерный DNS cache/QUIC/DNS-over-HTTPS отдельно не читались. Client-only IPv6/HTTP3 bypass во время сбоя не исключался измерением. Сбой уже устранён переключением VPN, поэтому исходный плохой flow не перехвачен.

## Подтверждённый дефект в коде

`service.lifecycle.reload_runtime` выключает capture на время HUP и включает после готовности. Старая `capture_pause` отбрасывает помеченный proxy-трафик, но завершает unmarked traffic вердиктом accept. Первый jump в `dns_redirect` тем самым пропускает клиентский DNS к обычному резолверу во время паузы. Клиент может получить реальные адреса вместо FakeIP. Поскольку NAT lookup происходит на первом пакете, unredirected conntrack binding способен пережить включение capture; клиентский DNS/браузерный кэш также может сохранить ответы. Это согласуется с пользовательским переключением VPN, но причинная связь с конкретным сообщением региона пока не доказана.

Основание поведения NAT: [официальная документация Netfilter](https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_%28NAT%29). Не утверждается, что любое сообщение региона вызвано DNS или что country exit API гарантирует разрешение сервиса.

## Исправление backend

В `nft/apply.uc` добавлена пустая `dns_capture_pause`, на которую ссылается filter mangle до `ct status dnat return` и до раннего DNS return: только original TCP/UDP53 с настроенных source interfaces. Исключения устройств IPv4/IPv6 обрабатываются раньше. Во время reload цепочка получает drop, после готовности очищается в той же транзакции, что и общая pause. Поэтому ни новые, ни уже DNATed клиентские DNS-запросы не уходят к обычному резолверу из-за паузы. Задержка реализована потерей пакета на время HUP с клиентской повторной попыткой, не очередью DNS и не искусственным ответом.

Router/core upstream DNS и loopback не подпадают под новый guard; startup разрешение имён не блокируется. Не меняется runtime при no-op save. `add chain` при resume/pause идемпотентно обеспечивает совместимость с таблицей до этой правки. Новая таблица/guard вступают в действие при обычном rebuild; старую активную таблицу текущего роутера в этой задаче не изменяли.

Это профилактика найденного окна, не общий kill switch и не защита стороннего browser DoH/DoT. Stop/uninstall с удалением таблицы и reboot не входят в этот контракт. Ранее загрязнённые клиентские кэши/conntrack entries автоматически не стираются. Глобальной очистки conntrack/DNS, изменения WAN, MTU, профилей, сертификатов, cookies или ОС нет.

## Свежие проверки26ноября

- `bash /work/tests/run.sh nft/apply`: RED2assertions на прежнем backend — отсутствует guard/совместная пауза. После исправления `docker exec kabanmax-autoroute-tests bash /work/tests/run.sh`: PASS101/101, включая исключения, ordering до DNAT, lifecycle/no-op/reload. Unit framework проверяет генерируемые правила/порядок и имитирует lifecycle; это не kernel packet replay.
- `ucode -c -o /dev/null /work/kabanmax/files/usr/lib/nft/apply.uc` и `ucode -S -c ...`: PASS оба режима.
- У существующего контейнера нет nft/ip и NET_ADMIN; не ставились инструменты и не добавлялись capabilities. Вместо этого на локальном OpenWrt через stdin выполнен **только** `tr -d '\015' | nft --check --file -` для изолированной синтетической таблицы: интерфейсные/адресные sets, новый guard, повторный add chain, pause/resume flush. PASS exit0. Дополнительный `nft list table` подтвердил отсутствие тестовой таблицы, service running. Первый запуск с CRLF дал parser error до LF-normalization; не считается PASS.
- `--check` не применяет правила: [официальный nft manual](https://netfilter.org/projects/nftables/manpage.html). На живом роутере не выполнялись Save/Apply/reload, отключение VPN или изменение firewall ради воспроизведения.

App остаётся0.2.3/core r46. Ядро в DNS-правке не менялось: комплект включает ранее проверенное logging исправление0046 и новый backend DNS guard. Позднее по отдельному запросу установлен вместе с UI combobox: [приёмка](LOCAL_R46_INSTALL.md). Не опубликован. Аппаратная проверка нескольких сохранений с непрерывным клиентским DNS и захватом сбоя ещё требуется; текущие tests не дают основания объявить полностью устранённой причину сообщения региона.

Финальная упаковка: existing offline `kabanmax-preview-build`, `--network none`, `bash /work/dist/auto-routing-r46/package-release.sh` — PASS10APK/IPK, payload/source/binary/license agreement и13SHA records после backend-правки. Использованы неизменённые финальные r46 core binaries из предыдущей logging-приёмки; повторный Go build не выдаётся за необходимый или выполненный. Точный комплект `dist/auto-routing-r46/release` обновлён, прежние package hashes больше не актуальны. `python scripts/check-project-docs.py`,9docs tests и `git diff --check` проверены отдельно.
