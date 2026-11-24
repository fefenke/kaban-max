# Preview 0.2.4: lifecycle logs, исключения и WARP recovery

## Продолжение r33 — 2026-11-24

Серия дополнена `0032-wireguard-fresh-port-recovery.patch` и `0033-auto-source-warnings.patch`. r32 включает существующее восстановление WireGuard с новым UDP-портом у single-peer клиентов без listen_port. r33 выводит каждый новый принятый отказ активного источника авторутинга в Warn, включая существующие Pending; TLS/auth Error не дублируются. [WARP evidence](WARP_RECOVERY.md), [журнал](LOGGING.md).

Свежие команды, Linux x86_64 Docker, Go 1.26.10, pinned archive, без внешней сети тестов:

- `docker exec kabanmax-autoroute-tests env PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin sh /work/dist/preview-024-r33/verify-core.sh` — exit 0: clean check/apply 33 patches и race 14 packages (autoroute, route, DNS/FakeIP, WAN, logger, clashapi, fallback, WireGuard transport/protocol, WARP, cache, JA3/sniff). Последнее уточнение source logging после этого проверено повторно command ниже.
- `docker exec kabanmax-autoroute-tests sh -c 'export PATH=/usr/local/go/bin:$PATH; cd /tmp/lifecycle-log.qgN43U; GOPROXY=off go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./common/autoroute ./route'` — exit 0 после уточнения: каждый новый отказ, без дублирования одного события; соседний IP видим; отклонённый admission не логируется; TLS/auth не дублируются, обычная классификация сохранена.
- `docker exec kabanmax-autoroute-tests sh /work/dist/preview-024-r33/build-core-binaries.sh` — exit 0 после уточнения пользователя: clean archive/apply 33, branding, upstream ARM64 base/tiny. Base SHA256 `f57497bf1fd792a6b395278d9d89719268809d1967d0612c5332e4a655ce61ce`, tiny `2df9339c2fc7d97dae2cee942915b8dad7c21065d7cf24022cc99a5442a998e8`.
- `docker run --rm -v "${taskRoot}:/work:ro" -v "${taskRoot}/dist/preview-024-r33:/output" kabanmax-preview-build bash /output/package-core.sh` — exit 0: все 10 APK/IPK, source/payload/license/manifests, 13 SHA records. Прежние неизменённые app/LuCI/RU 0.2.4 packages повторно проверены, не пересобирались.
- `docker exec kabanmax-autoroute-tests sh -c 'export PATH=/usr/local/go/bin:$PATH; cd $(cat /tmp/preview024r33-source-path); GOPROXY=off go build -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn -o /tmp/preview024r33-native ./cmd/sing-box; python3 /work/tests/core/lifecycle_log_binary.py /tmp/preview024r33-native; bash /work/tests/run.sh packaging/core_patch_series'` — exit 0: настоящий executable HUP, ошибка старого поколения Debug, новая ошибка Error; packaging version test PASS.
- `python scripts/check-project-docs.py --write-facts`, `python -m unittest discover -s tests/docs -p 'test_*.py'`, `git diff --check` — PASS (9 doc tests). Финальный docs gate повторяется после аппаратного результата.
- Финальная дополнительная регрессия: `docker exec kabanmax-autoroute-tests sh -c 'export PATH=/usr/local/go/bin:$PATH; cd /tmp/lifecycle-log.qgN43U; GOPROXY=off go test -count=1 -race -p=2 -run TestEveryAcceptedSourceFailureIsVisible -tags=badlinkname,tfogo_checklinkname0,with_wireguard ./common/autoroute'` — exit 0, включая ошибку alternative lease: source Warn не создаётся. Временное имя тестового файла контейнера прежнее; в репозитории — `tests/core/auto_source_failure_test.go`.

Перед установкой: read-only API HTTPS YouTube204 WARP1 Timeout, WARP2 30 мс. Обе предыдущие версии binary r29/r31 сохранены на компьютере и сверены SHA256. Текущий r31 сохранён hardlink во flash; настройки UCI/runtime и `/etc/kabanmax` — private tar во flash и на компьютере. Только старая лишняя r29 hardlink-копия удалена после сверки; tmpfs не использовался для двойного больших binary staging. Пакеты во flash сверены SHA256.

Установка запущена штатным неизменённым `install.sh` после предупреждения о перерыве, detached: `KABANMAX_RELEASE=0.2.4 KABANMAX_DOWNLOAD_URL=http://127.0.0.1:18085 sh /root/kabanmax-preview-0.2.4-r33/install.sh --variant base --lang ru --quiet`. Ручные stop/reload не выполнялись. Installer exit **0**, обновлён только core, служба автоматически запущена. Фактический SHA256 `/usr/bin/sing-box` совпал с base artifact.

Аппаратный итог к **03:28:46 MSK 2026-11-24**: один core PID, running. WARP1 после старта YouTube204 32 мс, WARP2 Timeout. Без дополнительных restart/reload второй автоматически сменил UDP-порт, после нескольких циклов появились ответы и HTTPS: YouTube204 36 мс, главная 190 мс; первый — 32/199 мс. Read-only GET/cache comparison снова подтвердил совпадение client public/private и peer key у обоих профилей. Это фактическое получение HTTPS, не только TCP dial. Внешняя причина отказа flow не объявляется доказанной.

UCI `/etc/config/kabanmax`, persisted suppression/applied JSON после установки побайтно совпали с private backup SHA256. Собственные APK hardlinks и оба собственных loopback mirror процесса удалены/остановлены по сохранённому PID и проверенному cmdline; KabanMax не затронут. Свободная flash около 22 МиБ, MemAvailable около 39 МиБ. Полные новые frontend/backend suites не запускались, поскольку source этих компонентов после r31 не менялся. Каждый новый source Warn проверен Go race tests; намеренные ошибки пользовательского трафика для аппаратного log-теста не создавались. Кнопка Delete, Tiny runtime, hardware WAN-loss/reboot, длительный soak остаются за рамками. GitHub публикации нет.

## Предыдущий этап r31

Финальная read-only повторная HTTPS-проба после cleanup: KabanMax running, уровень Warn, YouTube204 WARP1 **32 мс**, WARP2 **37 мс**. Дополнительного управления службой не было. `python scripts/check-project-docs.py`, doc unittest (9), `git diff --check` — PASS после содержательного обновления отчёта.

Дата: **2026-11-24 MSK** (диагностика lifecycle началась вечером 2026-11-23). База приложения: `98e5605` + сохранённый пользовательский diff; core — pinned `core/UPSTREAM` и все 31 patches. Preview установлен только на согласованный локальный ARM64 роутер, GitHub публикации нет.

## Плановый reload: причина сообщения не важна

В журнале устройства полная строка со скриншота заканчивалась `dns router closed`. Старый код route классифицировал известные errno/тексты и оставлял неизвестные причины на Error. Это не выполняло требование пользователя: после команды планового reload ошибки любого компонента уходящего поколения являются переходным шумом независимо от причины.

Patch `0030-lifecycle-log-severity.patch` меняет общий logger: при отменённом context **самого поколения core** Warn/Error становятся Debug до console/observer/platform output. Run loop отменяет этот context перед закрытием сервисов. Списка текстов/доменов и временного mute-окна нет. Отмена отдельного клиентского запроса не отменяет logger работающего поколения; новое поколение и верхнеуровневые ошибки применения/запуска остаются видимыми. Fatal/Panic не меняются. Обработка потоков и autoroute evidence не удаляется.

RED: `TestStoppedGenerationDowngradesAnyRuntimeFailure` показывал WARN/ERROR для произвольных connection/DNS/fallback/WARP/other-service сообщений, observer получал Error. GREEN: те же console/observer сообщения — Debug; живое поколение сохраняет Error, Panic всё ещё вызывает panic. Проверяется реальный logger output, не mock классификатора.

`tests/core/lifecycle_log_binary.py` запускает настоящий core, loopback mixed inbound и искусственный локальный UDP DNS. Во время зависшего DNS-запроса посылается HUP: ошибка старого потока — Debug; отказ нового DNS-запроса после старта нового поколения — Error. Ни роутер, ни Cloudflare/VPS, ни внешний DNS в этом тесте не используются. В реальном HUP возможны обе причины — `context canceled` и `dns router closed`; тест проверяет фазу/уровень, не требует конкретного победителя этой гонки. REFUSED-ответ не является транспортным exchange failure и в этом сценарии виден через connection Error, поэтому fixture не требует DNS Warn.

## Исключения: JSON-форматирование не является scope

На устройстве было 14 сохранённых исключений; у всех source существовал в runtime config, все scopes имели шесть валидных полей и пробелы JSON-сериализации ucode. Core `registryQuery` сравнивал исходную строку с compact Go JSON посимвольно. Поэтому валидный тот же scope отвергался как `source_or_scope_not_found`; это установленная причина данного полевого отказа, а не отсутствие source.

Patch `0031-canonical-registry-scopes.patch` сохраняет строгий parse/owner/source/IP/device/inbound/port validation, но canonical key создаётся из разобранных полей. Suppress/reset/release используют его для maps; сохранённые suppression/reserved scopes нормализуются и дедуплицируются при загрузке. Старые данные не переписываются ради форматирования. Форматирующие пробелы и эквивалентные JSON escapes не создают другую identity.

В backend `diagnostics/auto_registry.uc` при удалении сравнивает выбранный scope с нормализованным JSON сохранённых записей: compact/spaced дубли одного scope удаляются вместе. UI по-прежнему выбирает видимый IP и его private members; чужой IP/source не присоединяется. Ошибку core нельзя просто игнорировать и удалять deny из файла: прежнее требование успешного reset/rollback сохранено.

RED: `TestRegistryEquivalentScopeEncodingIsCanonical` получал `source_or_scope_not_found`; restored scoped maps содержали разные/нерабочие identities. Backend regression после успешного core reset оставлял compact дубль. GREEN проверяет suppress/reset/release, идемпотентный reset, чужой owner, сохранность соседнего device scope, загрузку/dedup reserved/suppressed и удаление compact/spaced экземпляров с сохранением соседней строки.

## Свежие команды и результаты

Окружение: существующий Linux x86_64 Docker `kabanmax-autoroute-tests`, Go 1.26.10, ucode; packaging image из pinned `scripts/release.Dockerfile`. Без субагентов и нагрузочных проверок.

| Команда | Результат / scope |
| --- | --- |
| `docker exec kabanmax-autoroute-tests env PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin sh /work/tests/core/run_log_policy.sh /tmp/core /work` | PASS clean apply 30 patches на этапе lifecycle: race route/DNS/fallback/logger + cmd compile; позднее runner расширен executable HUP smoke, выполненным в итоговом core runner |
| `docker exec kabanmax-autoroute-tests env PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin sh /work/dist/preview-024/core-verify.sh` | PASS clean archive + 31 check/apply; все autoroute fixtures включая scope encoding; race autoroute, route, DNS, FakeIP, WAN state, logger, clashapi, fallback, cachefile, JA3/sniff, WARP/Cloudflare/WireGuard, cmd; native executable build + HUP smoke PASS |
| `docker exec kabanmax-autoroute-tests bash /work/tests/run.sh diagnostics/auto_registry` | RED до нормализации удаления; GREEN после |
| `docker exec kabanmax-autoroute-tests sh -c 'set -e; ucode -c -o /dev/null /work/kabanmax/files/usr/lib/diagnostics/auto_registry.uc; ucode -S -c -o /dev/null /work/kabanmax/files/usr/lib/diagnostics/auto_registry.uc; bash /work/tests/run.sh diagnostics/auto_registry; bash /work/tests/run.sh'` | PASS оба syntax режима, focused regression и 97/97 backend files |
| `docker exec kabanmax-autoroute-tests sh -c 'set -e; bash /work/tests/run.sh packaging/core_patch_series; sh -n /work/tests/core/run_log_policy.sh; sh -n /work/tests/core/run_auto_routing.sh; sh -n /work/tests/core/run_network_availability.sh'` | Packaging/shell syntax PASS на промежуточном r30; итоговый r31 packaging gate повторён отдельно |

Frontend source не менялся; 177/1701 frontend/TypeScript/lint/build из [предыдущего этапа](PREVIEW_023.md) не выдаются за новый прогон. Версия frontend/RU подставлена упаковкой; payload/source verification повторена для 0.2.4. CI и воспроизводимые runners включают новые Go tests и настоящий HUP smoke.

## Сборка и установка

Локальные artifacts: ignored `dist/preview-024`. Core binary build: `docker exec kabanmax-autoroute-tests sh /work/dist/preview-024/build-core-binaries.sh` — чистый archive/31 patches, branding, Go index/LF prerequisites, upstream binary-only base/tiny ARM64, `SOURCE_DATE_EPOCH=1793880000`. Backend/LuCI/RU: `docker run --rm -e PO2LMO=/usr/local/bin/po2lmo -v "${taskRoot}:/work:ro" -v "${taskRoot}/dist/preview-024:/output" kabanmax-preview-build bash scripts/build-zapret2-local.sh 0.2.4 /output`. Core packaging/inspection: тот же run с `bash /output/package-core.sh`.

PASS 10 APK/IPK и 13 SHA256 records: source/payload/frontend version/license/manifests и равенство APK/IPK. Base binary SHA256: `f3510a535be6b8e09fd86145d88e986ab0b9d92cac47c5b4ad7e380d9128f25d`; tiny: `47269e254658a641ebe2772f8d5fd1aded844dd73eb72ca7bccceb23f1575177`. Промежуточные r30 packages на устройство не ставились.

До установки сохранён согласованный 0.2.3/r29 backup (binary hardlink во flash + приватный архив package/config/autoroute/metadata, копия архива на компьютере). Предыдущая лишняя hardlink-копия исходного ручного ядра удалена только после сверки с сохранённой компьютерной копией; новая рабочая backup не затрагивалась. Пакеты передавались во flash, не двойным большим RAM-стейджингом.

Пользователь предупреждён об одной короткой паузе. Только неизменённый штатный install.sh, detached, с поддерживаемым loopback mirror; никаких ручных stop/reload или своей deployment-обвязки:

```sh
KABANMAX_RELEASE=0.2.4 KABANMAX_DOWNLOAD_URL=http://127.0.0.1:18084 \
 sh /root/kabanmax-preview-0.2.4/install.sh --variant base --lang ru --quiet
```

Installer exit **0**: `KabanMax обновлён до 0.2.4 и запущен`. Около 00:08 MSK `/etc/init.d/kabanmax status` — running, app 0.2.4 / core r31, Warn, один active autoroute source. Через реальный авторизованный API выполнен идемпотентный reset **отсутствующего synthetic scope** с пробелами, TEST-NET IP/device и действующим source ID: PASS, durable suppression JSON побайтно не изменился, все **14 пользовательских исключений сохранены**. Саму пользовательскую кнопку Delete и удаление реальных записей ассистент не выполнял.

Первый HTTPS smoke после установки: WARP1 timeout, WARP2 YouTube 204 30 мс. Это не выдаётся за успех обоих профилей; повторная read-only проверка/выбор fallback фиксируются отдельно. Ради проверки логов дополнительный аппаратный reload не запускался. Длительная приёмка, пользовательское удаление реальных строк, новый hardware WAN-loss/reboot/load soak и Tiny runtime не выполнены. Публикация только после отдельного запроса пользователя.
