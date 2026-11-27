# FakeIP и DNS установки: 0.2.3 / r47

Дата: 2026-11-27. Причина Warn: patch0042 отменил прежнее понижение0026 и изменил upstream test expectation. Новый0047 восстанавливает Debug, не меняя отказ TCP/UDP. Project regression независим от upstream expectation.

## Проверки

- Новый TestMissingFakeIPRefusalRemainsDebug: RED на r46, GREEN с race на r47, IPv4/IPv6. Полезные DNS/source проверки сохранены.
- Чистое применение47patches, go test -count=1 -race -p=2 с release tags для route/dns/protocol/group/log: PASS. Собраны amd64 base и ARM64 base/tiny.
- python3 tests/core/fakeip_log_binary.py BINARY: RED r46, PASS r47 для Warn/Error/Debug. Проверяется закрытие транспорта после CONNECT ACK, а не один ответ200. Внешних запросов нет.
- Offline release packaging:10APK/IPK, source/payload/license/version и13SHA records PASS. App/LuCI/RU0.2.3, core r47. Base SHA d2ee01f6a4d87f59577e99048e2e5b6864954139754c568e4416922a4d4f0de3; tiny SHA52a553cf781330e2f44be91d0d724495249252c09eeab13afc3d3fb223c698a2.
- Полный исходный архив r47:1669файлов, privacy0находок; только служебный комментарий prune.list убран, mandatory upstream notices сохранены.
- bash tests/run.sh:102/102 backend файлов PASS. bash tests/dns-transition-installer.sh: порядок guard/stop/start/unguard, early RAM pause и cleanup при guard/transaction/start failures PASS.
- Installer release-pin/upgrade/recovery/API-fallback/translation/manifest/namespace shell suites PASS.
- Синтетический JSON guard с IPv4/IPv6 исключениями принят OpenWrt nft -j --check -f -; правила не применялись.

## Отдельный дефект установки

Прежняя dns_capture_pause защищала HUP внутри основной таблицы, но installer stop удалял всю эту таблицу. Это окно DNS в обход политики. Само по себе оно не доказывает причину каждого сообщения региона или состояние браузерного кэша.

Новый nft.dns_transition делает снимок только capture-интерфейсов и exclusion sets. Независимая таблица блокирует original TCP/UDP53 захваченных клиентов, переживает удаление основной таблицы и снимается после подтверждённого запуска. Исключённые устройства, output/router/core DNS и остальные порты не меняются. Никакой глобальной очистки DNS/conntrack нет.

Backend скачивается/извлекается до большого RAM preflight. На первой миграции нужны8MiB RAM без остановки работающего core; при недостатке подготовка завершается до stop. Последующие ранние RAM-паузы используют установленный guard. Same-owner guard идемпотентен, чужой transition не перезаписывается. Failure cleanup и RAM recovery снимают собственную таблицу.

## Устройства и публикация

По прямому запросу обновлены семь заданных устройств штатным installer через автономный LF runner с setsid. Первая r47 серия:7exit0/running, SHA ядра/UI совпадают, UCI hashes сохранены, временных APK нет. Адреса, ключи и сырые результаты находятся только в .local/fakeip-log-r47/.

Для версии с DNS transition выполняются отдельные живая проверка DNS и публикационная приёмка. Результат фиксируется после завершения. Обычный разрыв уже открытых соединений при полном stop/start не обещается устранённым.

????????? protected ?????????: exit0/r47/running, UCI hash ????????, guard ????, ????????? APK ???. ??????????? DNS-???????? ? ??????????:237????????,227FakeIP,10????????? ?? ????? ?????,0??????? ? ????? ????????. ??? ???????? DNS, ?? ?????????????? ?????????????? ?????????? ?????? ??? ???????.

BusyBox tar regression: IPK ? data.tar.gz ? ./data.tar.gz. ?? ??????? ?????????? RED, ????? fallback GREEN ? release-??????. ?? ????? OPKG-?????????? ?????? ??????? ??????????? ?? stop; ?????? ?????? ????? ?????????? ???????. Watchdog guard cleanup ????? ?????? installer-owner ????? ????????. ????:7/7 protected installs exit0, running, module/hash/config PASS, guard ???????????.

## Публикация и итог

0.2.3/core r47 опубликован:18remote assets, размеры/SHA и все18анонимных скачиваний PASS; main/tag/release/raw согласованы. Семь устройств:installer0/running/core47, module/UI/core SHA совпадают, все UCI hashes сохранены, guard и staged APK/IPK отсутствуют. Только OPKG target потребовал повтор после BusyBox fallback.

Финальная marker-cleanup проверка: при сбросе WORK после recovery failure удаляется исходный marker, не путь от пустого WORK. Regression RED/GREEN; watchdog owner-exit и оба IPK member names PASS. Это изменение только installer, core/UI binaries прежние.

GitHub core/frontend/backend/docs/ShellCheck/Pages для source af1226d — success; core/FE unchanged после marker refinement.

- [Frontend CI](https://github.com/fefenke/kaban-max/actions/runs/46010335684): success
- [Documentation integrity](https://github.com/fefenke/kaban-max/actions/runs/46010268265): success
- [Differential ShellCheck](https://github.com/fefenke/kaban-max/actions/runs/46010268134): success
- [Documentation](https://github.com/fefenke/kaban-max/actions/runs/46010268018): success
- [Backend CI](https://github.com/fefenke/kaban-max/actions/runs/46010268037): success
- [Patched core fallback](https://github.com/fefenke/kaban-max/actions/runs/46010268225): success

Реакция браузерной сессии и все возможные причины региона отдельно не доказаны. При полном stop/start уже открытые соединения кратко прерываются; проверено восстановление DNS без подмены политики, а не бесшовность TCP. Старые Warn в24hжурнале не удалялись.
