# Applied обходится при позднем DNS — 2026-11-25

**Исправлено и опубликовано в r41, hotfix приложения0.2.3.** После диагностики пользователь разрешил исправление/публикацию под тем же номером, запретил подключения и установку на роутеры. Запрет соблюдён. [Команды самостоятельного обновления](UPDATE_023.md).

## Текущий контракт r41

Patch0041 добавляет per-call `resolveDialer.DialContextWithWrapper`: исходный resolver/его options, DNS lookup и serial/parallel порядок сохраняются, Applied проверяется отдельно перед dial каждого конкретного IP. DNS transport не наследует application observation; альтернативный маршрут не может присвоить себе соседний IP. Source/exclusion guards остаются.

Persistent target failure выставляет reason=applied_target_failed, заменяя прежний bypass reason. RAM diagnostic sidecar сохраняет строго ограниченную attribution причины. UI различает applied_route_bypassed и ошибку выбранной альтернативы; старым ошибкам без attribution показывает нейтральную подпись, не угадывает маршрут. Исходный технический текст/время сохраняются.

Tracked regression `tests/core/auto_late_dns_test.go` подключён к runner/CI: serial/parallel, сохранение winning route, отсутствие observation в DNS, target failure attribution, sibling/exclusion/DNS error. Получен GREEN; полный профильный Go race suite14packages PASS. Executable acceptance дополнен режимом pre_resolve=false; local и remote PASS. На роутерах новый код не проверялся/не устанавливался.

## Подтверждённая публикация

2026-11-25, source commit `7beabf98d3e452e1e64a7d501c88cc95a1aa2e02`. Обновлён существующий [release0.2.3](https://github.com/fefenke/kaban-max/releases/tag/0.2.3), ID457032455, stable/latest, без переписи tag/history. Проверены digest/size всех16assets: APK/IPK backend/LuCI/RU0.2.3, core r41 base/tiny, manifests/installer/checksums и полный GPL source. Старые r40 core/source assets заменены; новые source references явно указаны в release notes. Raw catalog core-release.json соответствует опубликованному r41.

GitHub Actions source7beabf9: core `45494093551`, frontend `45494093567`, backend `45494093540`, documentation `45494093534`, integrity `45494093608`, ShellCheck `45494093450` — **success**. В core log явно подтверждены pre_resolve=true/false и lifecycle HUP PASS. Job долго находился в setup, поэтому параллельно выполнен локальный equivalent; итоговый remote результат тоже зелёный.

GPL source SHA256=`f68b8ac60682ff0da9e87d39119b70d7ec7c5126a54380e6d4c7e28d40151410`. Privacy: `python scripts/audit-release-privacy.py --packages dist/release-023-r41 --private-reference .local/release023-api-hotfix/kabanmax.before --report dist/release-023-r41/privacy-final.json` —1124source/payload files,4реальных credential values, findings=[]. Обязательные public upstream licenses/test attribution сохранены; operator data и инструментальные метки не найдены. Private staging/logs/backup не опубликованы.

Локальный executable: `docker exec kabanmax-autoroute-tests sh /work/dist/release-023-r41/build-exec.sh`; `docker build -t kabanmax-late-dns-exec:local dist/release-023-r41/exec-context`; `docker run --rm --network none --cap-add NET_ADMIN --sysctl net.ipv4.tcp_syn_retries=1 -v PROJECT:/work:ro kabanmax-late-dns-exec:local sh /work/dist/release-023-r41/exec-smoke.sh` — **exit0/PASS**: kernel TCP DROP/ETIMEDOUT, manual apply/restore, CNAME, disabled logging, неизвестный protocol, automatic HTTPS apply с предварительным/поздним DNS и получение данных, lifecycle HUP. Настройка TCP retry задаётся только namespace контейнера; host/read-only proc не менялись. Первый запуск пытался записать readonly proc/sys и был исправлен на штатный Docker --sysctl.

## Проверки реализации 2026-11-25

- `docker exec kabanmax-autoroute-tests env PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin sh /work/dist/applied-diagnostics/verify-core.sh` — clean apply41patches, **14Go race packages PASS**. Helper соответствует tracked `tests/core/run_auto_routing.sh` с project mounts; новый late-DNS regression включён в оба runner и CI.
- `docker exec kabanmax-autoroute-tests bash /work/tests/run.sh` —100/101, единственный сбой: устаревший packaging assertion r40. Исправлен на r41+наличие0041; `... bash /work/tests/run.sh packaging/core_patch_series` —1/1PASS. Оба syntax режима config/auto_diagnostics —PASS.
- В frontend: `npx.cmd vitest run` —176/177files,1701/1702tests; единственный сбой — две отсутствующие строки POT. После добавления POT/RU `npx.cmd vitest run tests/localization.test.js tests/localeIdentity.test.js src/kabanmax/tabs/sections/tests/autoRouting.test.ts` —21/21PASS. После нейтральной подписи legacy ошибок целевой autoRouting —15/15PASS. `npx.cmd eslint` двух изменённых source/test files, `npm.cmd run build` —PASS. Итоговый полный CI фиксируется после выполнения, эти промежуточные запуски не объявляются полностью зелёными.
- `docker exec kabanmax-autoroute-tests sh /work/dist/release-023-r41/build-core-binaries.sh` — clean branded upstream+41patches, ARM64 base/tiny r41 PASS. SHA base=`3ea6dd004d530872452e503852ef3f8ae8f814daf57185d693ae5be08902e56e`, tiny=`f31bb1c6a4bd17cc7db430b9f98fab6366143cc6e3da0150cfc1bca7fe8faa4b`.
- Existing local image, network=none: `PO2LMO=/usr/local/bin/po2lmo bash /work/scripts/build-zapret2-local.sh 0.2.3 /output`; core packaging helper `/work/dist/release-023-r41/package-core.sh`; `bash /work/scripts/finalize-release.sh /output`; `python3 /work/scripts/inspect-release.py /output` — **10APK/IPK payload/source/license,13SHA records PASS**. После финальной UI правки app/backend/RU packages пересобраны и проверены повторно. GPL source отличается от ранее проверенного r40 только тремя Go файлами patch0041 и provenance JSON; Git metadata отсутствует.
- `python -m unittest discover -s tests/docs -p 'test*.py'` —9/9, security тем же способом —3/3. `python -m py_compile tests/core/auto_error_binary.py`, `python scripts/check-project-docs.py --write-facts`, doc gate и `git diff --check` —PASS.
- Команды ПК: PowerShell AST parser проверил оба блока, извлечённый POSIX launcher прошёл `sh -n`. Подключения/обновления не выполнялись. ExecutionPolicy не менялся; команды предназначены для вставки в консоль, не запуска неподписанного ps1 файла.

Новая аппаратная приёмка и установка **не выполнялись по прямому запрету пользователя**. WARP наблюдение ниже относится к предшествующей диагностике r40.

## Исходное native evidence r40

## Причина повторных ошибок после Apply

Native SHA core совпал с опубликованным ARM64 base r40. Все пять соответствующих leases присутствуют: persistent_ip/all_devices/all_ports=true, status=applied. Сбор включён, disabled_sources/suppressed пусты. Новые события созданы после Apply; это не просто закрытие старых соединений. Leases имеют reason=applied_route_bypassed. Альтернативные HTTPS проверки подтверждают доступность выбранных направлений.

У живых META-соединений destinationIP пуст, host содержит домен. Путь ошибки в исходниках:

1. TCP router выбирает исходную секцию, создаёт observation и передаёт его Direct.
2. `autoroute.WrapDial` расположен снаружи `common/dialer.resolveDialer`.
3. `scopedDialer.dial` получает домен и из-за `!destination.IsIP()` вызывает исходный dialer без выбора Applied.
4. `resolveDialer.DialContext` разрешает DNS внутри и соединяется через raw dialer, уже вне Applied hook.
5. `ReportDial` узнаёт реальный IP после открытия TCP. При последующей ошибке она относится к исходному маршруту, а существующее соединение переключить невозможно.

Это не утрата permissions, не часовой TTL и не доказанный отказ WARP. Выбор Applied требуется выполнять на каждом конкретном адресе после **исходного** DNS resolution, сохраняя resolver, interface strategy, sibling-IP boundaries и exclusions. Перенаправление целого домена или произвольная замена DNS не являются исправлением.

`splice read: connection timed out` — таймаут при пересылке данных открытого соединения. Сам текст не различает сервер, сеть, DPI и клиент. Здесь отдельно доказан обход Applied; скрывать настоящий timeout вместо исправления маршрутизации нельзя.

## Ошибка подписи UI

`recordFailures()` называет любой Applied/new_error «New error on the selected route», включая reason=applied_route_bypassed. В этих событиях ошибся исходный META; до выбранного WARP/Direct соединение не переключилось. Нужны отдельная подпись обхода и сохранение этой причины в diagnostic sidecar.

## Воспроизведение

2026-11-25, local Linux Docker/Go1.26.10, clean pinned upstream +40 patches. Команда: `docker exec kabanmax-autoroute-tests env PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin sh /work/dist/auto-late-dns/reproduce.sh`. Scope — один `TestLateResolvedDomainMustUseAppliedIP` в common/autoroute, synthetic DNSRouter и loopback servers, без внешней сети/роутера.

Тест создаёт Applied IP через прежние manual fixtures, убирает предварительные DestinationAddresses и вызывает WrapDial поверх настоящего NewResolveDialer. **RED/exit1:** original calls=1, alternative calls=0, connection refused на синтетическом исходном сервере. Путь совпадает с native host-only metadata. Предыдущий executable suite выполнял явный resolve action и этот случай не покрывал.

Первоначальный helper/RED находятся в ignored `dist/auto-late-dns/`. На их основе добавлен tracked regression выше; исходный RED не выдаётся за текущий результат r41.

## WARP проверен отдельно

Baseline HTTPS: первый/domain65ms, второй/IP49ms, второй/domain67ms. Один заранее объявленный restart выполнен независимым setsid процессом. Страховка запуска поставлена до остановки и отменена после успешного старта. Наблюдение ограничено90сек/90маленькими snapshots; Debug/packet capture не включались.

После restart оба authenticated handshake появились примерно за секунду после создания endpoint, на прежних сохранённых портах, поколение нового bind=1. HTTPS: первый/domain65ms, второй/IP48ms, второй/domain65ms. Restart exit0, служба running, observer errors=0.

Native команды: `ucode -L /usr/lib/kabanmax observe.uc`, `probe.uc` через `singbox.clash_api.exchange`; GET `/kabanmax/warp-paths` раз в секунду90сек; GET `/proxies/.../delay` с timeout5000ms, HTTPS gstatic generate_204 и HTTPS1.1.1.1/cdn-cgi/trace. Наблюдатель запущен перед `/etc/init.d/kabanmax restart`; не выполняет probe/rebind сам.

**Задержка WARP на этом restart не воспроизвелась.** Исторический startup timeout не закрыт. В прежнем снимке bind/порт не менялись, поэтому объяснение перебором портов не доказано. Для причины нужны данные во время отказа: первый handshake/IP-data и IP-target против domain-target. Один успешный restart не доказывает устойчивость.

Private bounded timeline/probes/logs сохранены только в `.local/warp-startup-delay/remote-restart`. Реальные SSH-ключи, profile IDs, конфиги и адрес роутера в отчёт не включены. Собственный tmp stage удаляется после сохранения evidence; пользовательские checkpoints/настройки не очищаются.
