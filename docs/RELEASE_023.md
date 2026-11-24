# Выпуск 0.2.3 / core r40 — 2026-11-24

## Hotfix GitHub API quota, тот же номер 0.2.3

Запрос пользователя после публикации: при обновлении всё ещё показывается API quota, также Zapret2 получает HTTP403. Причина: raw fallback покрывал только bootstrap script, а shell installer/проверка версии/ядро и Zapret2 продолжали использовать API assets. Исправлены эти пути: raw manifests из `release/`, maintained main bootstrap с прежним pin, public pinned package URLs, curl для длинных redirects (wget остаётся доступным fallback), checksum guards сохранены. Запрошенный номер 0.2.3 и core r40 сохранены. Обновляются ровно backend APK/IPK, install.sh, SHA256SUMS; прочие 12 assets и старый tag не переписываются. Source hotfix находится в отдельном обычном коммите main; ссылка добавляется в release notes.

Zapret2 snapshot v1.0.7/digest `d2799bc8dffc03a21f977d3a0e2d8a8626105db630c03d9b99d5164980d5db16` проверен 2026-11-24 через official `bol-van/zapret2/releases/latest`. При fallback показывается последняя проверенная версия, не обещание свежего upstream lookup. Digest/official-host validation и archive verification не ослаблены. Нет проверки фактического обновления Zapret2 или его restart: это отдельная операция.

Свежие проверки 2026-11-24, Linux Docker, исходники hotfix:

- `docker exec kabanmax-autoroute-tests bash /work/tests/run.sh` — **101/101 PASS**. `ucode -c -o /dev/null FILE` и `ucode -S -c -o /dev/null FILE` для service/release, service/installer, zapret2/updater — PASS; `sh -n /work/install.sh` — PASS.
- `docker exec kabanmax-autoroute-tests bash /work/tests/installer-api-fallback.sh` — PASS: forced API quota, оба raw manifests, explicit pins, public assets, curl HTTP/timeout classification. Новые backend tests сначала RED (без реализации), затем GREEN; async process indices обновлены под фактический manifest download.
- С тем же `docker exec ... bash /work/`: `tests/installer-release-pin.sh`, `tests/installer-recovery-022.sh`, `tests/installer-upgrade-017.sh`, `tests/installer-translation-smoke.sh`, `tests/release-manifest-smoke.sh` — PASS.
- Existing `kabanmax-preview-build` image, сеть отключена: `PO2LMO=/usr/local/bin/po2lmo bash /work/scripts/build-zapret2-local.sh 0.2.3 /output`; в final set взяты только два backend packages/install.sh. `bash /work/scripts/finalize-release.sh /output` и `python3 /work/scripts/inspect-release.py /output` — **10 APK/IPK + 13 SHA records PASS**, original r40 binaries read-only mounted для сверки.
- `python -m unittest discover -s tests/docs -p 'test*.py'` — 9/9; security тем же способом — 3/3. `python scripts/audit-release-privacy.py --packages dist/release-023-r40-hotfix --report dist/release-023-r40-hotfix/privacy.json` — 1119 source/payload files, findings=[]; `python scripts/check-project-docs.py`/`git diff --check` — PASS.

На момент этих проверок hotfix assets ещё не заменены и native CDN/fallback приёмка не выполнена. Публикация/установка фиксируются после фактического завершения. Поддержка длинных redirect через старый uclient-fetch без curl отдельно не подтверждена.

Пользователь поручил исправить исчезновение Applied diagnostics, установить **свежий код под публичным номером 0.2.3** и опубликовать его. Предыдущий публичный выпуск — 0.2.2; более высокие номера использовались только для локальных приёмок. По отдельному ответу пользователя очищаются текущие файлы/новый выпуск; старая опубликованная история и теги не переписываются.

## Исправление

- Compact routing intent и его dirty-only flash schedule сохранены. Исходная ошибка, последующая ошибка выбранного маршрута, error port и наблюдённые domain labels находятся отдельно в bounded RAM sidecar `auto-routing-applied-diagnostics.json`, с точной привязкой к owner/source/lease ID/IP/target.
- Sidecar переживает reload/restart службы, не имеет часового TTL и удаляет сведения только вместе с явным удалением/заменой разрешений. Переполнение сохраняет прежние данные и сообщает warning; оно не отзывает grant и не выключает сбор.
- Core patch 0040 удерживает исходную ошибку отдельно от новой ошибки альтернативы, переносит ранее наблюдённые имена при повторном применении IP. Метаданные не расширяют routing permission. Новый UI показывает понятную причину таймаута, исходный технический текст и валидное время; пустой Error disclosure удалён.
- Устаревшие утраченные сведения не подделываются: если старая версия уже вырезала текст, показывается явное сообщение о его отсутствии. Неизвестному IP не назначается домен по догадке или reverse DNS.
- Чтение diagnostic snapshot/index выполняется один раз на view, не один раз на строку. Regression test проверяет 1000 обращений с одним чтением RAM-файла.

## Проверки 2026-11-24

Go 1.26.10, локальный Linux Docker; Windows Node frontend. Источник ядра — clean archive pinned commit `60d96c99815a672712915a5c00114bf0f690ad80` + 40 patches, не рабочий private checkout.

- RED новые config/auto_diagnostics и Go Applied diagnostics tests падали до реализации. Повторное чтение RAM, ownership/budget, сохранение source/target errors, labels/reapply, compact-only flash и saved-inactive view покрыты regression tests.
- `docker exec kabanmax-autoroute-tests env PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin sh /work/dist/applied-diagnostics/verify-core.sh` — PASS: clean apply 40 patches, **14 Go race packages**. Helper — repository `tests/core/run_auto_routing.sh`, с mounts `/core`→`/work/core`, `/extra-tests`→`/work/tests/core`, `/source`→`/tmp/core`.
- `docker exec kabanmax-autoroute-tests sh /work/dist/applied-diagnostics/verify-backend.sh` — PASS: **101/101 backend files**, оба `ucode -c`/`ucode -S -c` режима для новых/изменённых config и diagnostics modules. В промежуточной проверке обнаружены порядок объявления функций ucode и CRLF у исторического fixture; исправлены, финальная проверка прошла.
- В `fe-app-kabanmax`: `npx.cmd vitest run` — **177 файлов / 1702 теста PASS**; `npm.cmd run build` — TypeScript/fingerprints/bundle PASS; targeted ESLint трёх section files PASS. После правки служебных headers переводов — localeIdentity/localization/autoRouting **21/21 PASS**; все 1180 RU strings переведены.
- `python -m unittest discover -s tests/security -p 'test_*.py'` — **3/3 PASS**. `python scripts/audit-release-privacy.py --packages dist/release-023-r40 --private-reference PRIVATE_CONFIG --report PRIVATE_REPORT` — PASS, findings=[]: source tree и распакованные IPK/control payloads, сопоставленные с APK. PRIVATE_CONFIG — точный приватный pre-install backup; его содержимое не публикуется. Проверены четыре реальных credential values без их вывода.
- Все backend payload files теперь побайтно сверяются с source, а не только три entrypoints. `scripts/finalize-release.sh` + `scripts/inspect-release.py`: **10 APK/IPK, manifests/license/source и 13 SHA records PASS**. APK payload совпадает с проверенным IPK.

## Установка и native smoke

Штатный detached `install.sh`, `KABANMAX_RELEASE=0.2.3`, supported LAN mirror компьютера, `--variant base --lang ru --quiet` — **exit 0**, service **running**. Установленные backend/LuCI/RU версии 0.2.3, core **1.14.4-r40**. Установщик выполнил единственный автоматический restart; ручного stop/deployment wrapper нет. Числовой переход с private preview 0.2.9 прошёл штатно, это не установка старого кода.

Base binary SHA256 `9cab8b0889d801d1baaf45f570ad4b088a14d810bf0c69f1af4a7b713cbaee3e` совпал на роутере. Tiny SHA256 `6d5e7bbbbde756794d38151e2cf2e0384ae3389387bb99bdb250ebfcf29f15b0`.

Два прежних Applied permissions сохранены с all_devices/all_ports; disabled_sources=[], registry_error и diagnostics_error пусты, capture=true. Старые вырезанные тексты исходных ошибок отсутствуют и не были реконструированы без evidence. В изолированном RAM-каталоге synthetic RFC IP, отдельном от реального registry, первый native ucode процесс сохранил ошибку/домен, второй новый процесс восстановил их: **PASS**. Синтетические права в реальный core не добавлялись.

HTTPS через два WARP: **34/48ms**, fallback **42ms**; пользователь затем подтвердил успешную проверку второго туннеля. Flash после установки used **33364/free 58480 KiB**, 36% (~33 MiB). Installer evidence сохранён только приватно, tiny staging/synthetic test files удалены, реальный sidecar/checkpoints сохранены. Точный LAN mirror остановлен после проверки PID/CommandLine. Публикация фиксируется отдельно после remote verification.

## Privacy и публикация

Текущие tool-specific упоминания/имена файлов удалены; три PNG очищены от provenance/text metadata с неизменным IDAT pixel stream. Router-specific coordinates в support prose заменены документационными примерами. Архивные текущие копии явно помечены privacy-redacted, SHA manifests пересчитаны; история Git не изменена.

Публичные synthetic test PKI и обязательные upstream license/trust-anchor attribution проверены и разрешены только по точным fingerprints. Это не реальные ключи/почта оператора; GPL notices не удалялись. Не публикуются `.local`, configs/logs/private reports, mirrors, build staging или credentials. Полный GPL core source archive (1894 checked entries), без `.git`, подготовлен отдельно; source SHA256 `066d3f7b7c5dbf7288f891d82c01b5628345464dc78dda02bf11cd98d42e0d78`.

## Подтверждённая публикация

Обычный latest [release 0.2.3](https://github.com/fefenke/kaban-max/releases/tag/0.2.3), ID `457032455`, draft=false/prerelease=false. Source commit/tag `489c074fd4c55ac82a556f1c5fdf8b8ea18d0b6a` опубликованы через нефорсированный atomic push. Проверены 984 staged blobs и archive hashes; новая commit/tag identity — project contributors/noreply, без инструментального co-author. Старые commits/tags не переписаны по выбору пользователя.

Uploaded 16 explicit allowlisted assets; каждый remote digest/size совпал с локальным. К 10 APK/IPK + manifests/installer/SHA добавлены полный GPL core source и `SOURCE_SHA256SUMS`. Ключи/конфиги/логи/.local/build staging не публиковались. `/releases/latest` подтверждён через независимый GitHub connector read. Роутер скачал опубликованные app/core manifests (с redirects): **0.2.3 / 1.14.4-r40**, service running.

GitHub Actions для release commit: frontend, backend, shellcheck, documentation build и documentation integrity — success. Core run `45437218598` прошёл Go/race/WARP проверки, но executable error-first assertion ожидал транспортную ошибку в журнале с порогом Error: после r33 она выводится на Warn. Тест исправлен на Warn, assertions IP/timeout/отсутствия дубликатов сохранены. Это изменение harness, пакеты и release tag не меняются. Повторная remote проверка фиксируется отдельно; локальные 14 core race packages уже PASS.

Ограничения: RAM diagnostics не переживают полный router power loss. Flash schedule routing intent остаётся суточным. Полный reboot/WAN-loss/многодневный soak не проверены в этом выпуске. Публикация завершена; ограничения аппаратной приёмки сохраняются.

Post-publication harness, 2026-11-24: run `45439214789` подтвердил реальные timeout/Warn/manual-apply/restore сценарии, затем остановился на устаревшем ожидании auto-apply без TLS evidence. SOCKS отказ до handshake корректно даёт `protocol_unconfirmed` после r22. Добавлен отдельный отрицательный executable сценарий; положительный задаёт явный HTTPS body prefix тестового сервера. Runtime guards не изменены. `python -m py_compile tests/core/auto_error_binary.py`, `python -m unittest discover -s tests/docs -p 'test*.py'` (9/9), `python -m unittest discover -s tests/security -p 'test*.py'` (3/3), `python scripts/audit-release-privacy.py --report dist/release-023-r40/final-source-privacy.json` (984 files/findings=[]), `python scripts/check-project-docs.py` и `git diff --check` — PASS.

Окончательная remote приёмка main `a4873d0`, 2026-11-24: [core run 45440290714](https://github.com/fefenke/kaban-max/actions/runs/45440290714) — **success**, включая все Go race, WARP и executable steps. Команды последнего шага: `CGO_ENABLED=0 go build -trimpath -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn -o /tmp/auto-core ./cmd/sing-box`; `sudo unshare --net sh -c 'ip link set lo up; sysctl -w net.ipv4.tcp_syn_retries=1 >/dev/null; export KERNEL_TIMEOUT=1; exec python3 "$1" /tmp/auto-core /tmp/auto-fixtures system' sh "$GITHUB_WORKSPACE/tests/core/auto_error_binary.py"`; `python3 "$GITHUB_WORKSPACE/tests/core/lifecycle_log_binary.py" /tmp/auto-core`. Изолированный Linux namespace: TCP DROP/kernel timeout, видимый Warn, manual apply, disabled collection restore, отсутствие ложного кандидата, неизвестный протокол без auto-apply, проверенный HTTPS body с auto-apply/получением данных — PASS. Backend `45440290959`, documentation `45440290627`, integrity `45440290759` — success. Это проверка test harness поверх неизменного release runtime; tag `0.2.3`/16 assets сохранены. Hardware reboot/soak ограничения выше остаются.
