# Ошибки соединений с контекстом и направлением диагностики

2026-11-26. По прямому требованию пользователя непонятное сообщение не должно становиться Error лишь из-за слова TLS. App0.2.3/core r46, append-only0046. После локальной приёмки установлен по отдельному запросу вместе с DNS guard и UI: [результат](LOCAL_R46_INSTALL.md). Не опубликован.

## Контракт

Обработчик TCP upload/download после установления соединения сохраняет **любую** ошибку в Debug, включая `remote error: tls: protocol version not supported`. Эта фаза не позволяет надёжно приписать TLS alert прокси или конечному сайту. Исходная ошибка не удаляется и без изменения передаётся close callback/observer. Подробная диагностика доступна при Debug; запись сама не запускает fallback health, как установлено0044.

При открытии TCP/packet-соединения или отложенном handshake Error допустим, только если одновременно известны адрес назначения, маршрут/профиль и распознана причина с предметной проверкой. Формат включает `stage`, `destination`, `route`, `check`, `cause`. TLS/REALITY → совместимость TLS, транспорт и server name; certificate/x509 → срок/цепочка доверия/server name; authentication/credentials → параметры авторизации выбранного прокси; типизированные DNS REFUSED/SERVFAIL → доступность/ответ и политика настроенного DNS. Это направление диагностики, не доказательство конкретной виновной стороны и не обещание единственной готовой команды исправления. Проверку сертификата не отключают.

Неизвестная причина или отсутствующий адрес/профиль → Debug, а не бессодержательный Error с придуманным советом. Прежние routine transport failures также остаются Debug. Ошибка handshake к локальному клиенту получает отдельный `client_handshake` и Debug; отложенный outbound handshake сохраняет диагностируемые Error. Текст домена/профиля из contextual wrapper не используется для угадывания типа причины.

Маршрут захватывается перед dial, включая выбранные звенья группы до8уровней. Это snapshot выбора на старте попытки, не утверждение о неизменности группы при конкурентном переключении. Читаемый metadata route служит fallback при отсутствии outbound-интерфейса. Диагностические labels ограничены256символами, управляющие символы заменяются пробелами. Конфиги, ключи, URI профилей или пароли отдельно не читаются и не добавляются. Исходный error сохраняется как раньше. Новых таймеров, общей истории или карт накопления нет.

Scope — общий ConnectionManager для профилей, не глобальное подавление всех журналов. Startup/config errors, Fatal/Panic, auto-routing source/selected-route Warn, DNS subsystem logs и подтверждённые health Warn не переписываются этой правкой. WAN gate и отмена уходящего поколения сохранены. Stable fallback r45 остаётся с прежней OR-policy: основной либо независимый confirmation успешен → healthy.

## Проверки26ноября

До production: новые assertions на r45 дали RED для позднего TLS Error, TLS без контекста, неизвестного open error и отсутствующих контекстных полей. Затем полный package `route` с `-race` PASS. `NewConnection` проверен с синтетическими outbound kinds vless/warp: известный auth failure сохраняет исходный cause/callback и контекст. Это проверка общего manager, не тест реальных внешних VLESS/WARP серверов. Отдельно проверены outbound/client handshake, TLS copy в обоих направлениях, routine transport, отсутствие классификации по словам certificate/tls в hostname/profile.

Первый executable HUP test обнаружил два отличия: matcher ожидал старый префикс без новых полей; после его корректировки выявлена настоящая потеря DNS REFUSED Error как «неизвестной» причины. Добавлен отдельный RED-test REFUSED и предметная подсказка для типизированных DNS REFUSED/SERVFAIL. Ожидание fresh-generation Error не ослаблялось. Предварительные hashes/PASS не считаются финальной приёмкой.

## Финальная локальная приёмка

- Existing container `kabanmax-autoroute-tests`: `PATH=/usr/local/go/bin:$PATH sh /work/tests/core/run_network_availability.sh /tmp/core /work` — PASS чистое применение46patches;7race packages (`common/autoroute`, `dns`, `dns/transport/fakeip`, `route`, `protocol/group`, `common/wanstate`, `log`), compile-only `cmd/sing-box`. После последней production-правки DNS guidance выполнено заново.
- `sh /work/dist/auto-routing-r46/build-core-binaries.sh` — pinned source+46patches, branding, amd64base/ARM64base+tiny PASS. Финальный ARM64 base SHA `a66dbd8baab8423fa251c71a824d4bcbfffe1d736e93b5aceffc8959f1ef457f`, tiny `da9d2cefb62e4690cd1f618e7b11257154f5655b17e0193657581be10ee55c2e`.
- `python3 /work/tests/core/connection_actionable_binary.py /tmp/auto-routing-r46-core-output/build/amd64/base/sing-box` — PASS настоящий TLS version alert во время соединения с тестовым TLS proxy: одна Error с target/profile/phase/original cause/check. TLS certificate trust задан fixture CA; verification не отключалась.
- `python3 /work/tests/core/lifecycle_log_binary.py` с тем же executable — PASS уходящий HUP flow Debug, fresh DNS REFUSED Error. `python3 /work/tests/core/fallback_partial_binary.py` — PASS independent confirmation quiet/healthy, полный отказ failover, shared outage hold, recovery. Эти три scripts выполнены последовательно с `set -e`; затем `bash /work/tests/run.sh packaging/core_patch_series` — PASS1/1.

На этапе этих core-проверок использовались только synthetic/loopback, без внешних профилей/роутеров. Frontend/backend production в logging-правке не менялись и их прошлые suites не объявляются свежими. Последующая установка и дополнительные DNS/UI изменения отдельно отражены выше.

Existing offline `kabanmax-preview-build`, `--network none`, `bash /work/dist/auto-routing-r46/package-release.sh` — PASS10APK/IPK, payload/source/binary/license consistency и13SHA records. Финальные бинарники перепакованы после DNS guidance fix; игнорируемый комплект `dist/auto-routing-r46/release` готов. Task source/report проверены на credential/email/tool-marker patterns, findings0 (`privacy-task.json`, точный scope внутри ignored artifact directory); package payloads отдельно сверены inspector с исходниками. `python scripts/check-project-docs.py --write-facts`, обычный docs gate,9docs tests и `git diff --check` — PASS.
