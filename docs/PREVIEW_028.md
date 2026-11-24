# Preview 0.2.8 / core r38 — установка 2026-11-24

Scope: явный запрос пользователя «установи» после локальной реализации [постоянных WARP-портов](WARP_PORT_HINTS.md). Цель — тот же локальный ARM64 OpenWrt router, штатный base комплект, без публикации и полного reboot устройства.

## Подготовка

- Read-only preflight: `ssh -o BatchMode=yes -o ConnectTimeout=8 root@192.168.1.1 "ubus call system board; df -k /overlay /tmp; /etc/init.d/kabanmax status; sing-box version; cat /proc/meminfo | head -3"` — OpenWrt 25.12.5/ARM64, running r37, flash used 33472/free 58372 KiB, MemAvailable 46636 KiB. Содержимое ключей не выводилось. Точный `/etc/config/kabanmax` сохранён приватно на компьютере, не в релизе/Git.
- `docker exec kabanmax-autoroute-tests sh /work/dist/preview-028-r38/build-core-binaries.sh` — exit 0: clean archive pinned commit, check/apply 38 patches, branding, upstream `build.sh --variant base|tiny --arch aarch64_cortex-a53 --version 1.14.4-r38 --binary-only`; Go 1.26.10, GOPROXY=off. Это ignored build helper, аналог команды из [BUILD_AND_DEPLOY](BUILD_AND_DEPLOY.md).
- SHA256 base binary: `14aec4031deab76ffc00734bec6bba1476c3d16dc6c6bb47c06d798f5edabebb`; tiny: `089cc74fd5f335378bf3f19aef23e4f3c76aca6e1253348e4dc3c9abb1bd56f8`.
- `docker run --rm -e PO2LMO=/usr/local/bin/po2lmo -v PROJECT:/work:ro -v PROJECT/dist/preview-028-r38:/output kabanmax-preview-build bash scripts/build-zapret2-local.sh 0.2.8 /output` — exit 0, backend/LuCI/RU APK/IPK.
- `docker run --rm -v PROJECT:/work:ro -v PROJECT/dist/preview-028-r38:/output kabanmax-preview-build bash /work/dist/preview-028-r38/package-core.sh` — exit 0; upstream core packaging base/tiny, manifests 0.2.8/r38, check-release + inspect-release: **10 APK/IPK payload/source/version/license checks и 13 SHA records PASS**. PROJECT означает абсолютный путь текущего workspace.

## Установка

На компьютере запущен временный скрытый Python LAN HTTP mirror только 14 публичных release assets. Пакеты не складывались во flash роутера и не создавалась дополнительная копия большого binary в RAM.

На роутере tiny staging `/tmp/kabanmax-preview028` содержит stock `install.sh`, bounded installer log и exit marker. Detached команда: `KABANMAX_RELEASE=0.2.8 KABANMAX_DOWNLOAD_URL=http://LAN-MIRROR:18090 sh /tmp/kabanmax-preview028/install.sh --variant base --lang ru --quiet`. Установщик сам остановил и запустил KabanMax; отдельного ручного stop/deployment wrapper нет. Выполнение автономно от соединения ассистента.

Промежуточная проверка после `Запуск KabanMax`: running, flash used 33312/free 58528 KiB. Финальный installer exit **0**, service **running**, database versions backend/LuCI/RU **0.2.8**, core **1.14.4-r38**. `/usr/bin/sing-box` SHA256 совпал с base artifact. HTTPS YouTube 204 через первый/второй WARP и fallback: **36/35/34ms**.

Native read-only `/kabanmax/warp-paths` показывает локальные порты 38071/42987, fresh handshake и полученные IP-data у обоих. `ucode -L /usr/lib/kabanmax` + `diagnostics.warp_ports.capture()` вернул true, два pending в RAM, resolved=0; через 77 секунд стабильность сохранилась, `last_seen_ago=17` подтверждает работу resident minute timer. Постоянные hints пока пусты: реальных десяти минут ещё не прошло. `/etc/config/kabanmax` побайтно совпал с приватным pre-install backup (SHA сравнен); немедленной flash-записи нет. Это не доказывает delayed commit после десяти минут.

Первый ручной diagnostic вызов использовал ошибочный `-L /usr/lib` и не нашёл module; повтор с реальным install path `/usr/lib/kabanmax` успешен. Пакетный query `apk info -v` дал warnings об отсутствующих cached feed indexes; exact versions затем прочитаны из native installed database, feeds не менялись.

Installer evidence сохранён приватно на компьютере. После exit 0 удалены только три собственных small staging файла из `/tmp/kabanmax-preview028` и пустая директория; RAM port checkpoint и autoroute data не тронуты. LAN mirror остановлен после проверки PID/CommandLine. Финально flash **used 33312/free 58528 KiB**, 36%; лишних router flash staging/backup copies нет.

Пределы: полного router reboot/power loss, WAN-loss и многодневной приёмки нет. Результаты r37 не считаются аппаратными тестами r38. GitHub публикация не выполнялась.

После документирования установки 2026-11-24: `python scripts/check-project-docs.py`, `python -m unittest discover -s tests/docs -p 'test_*.py'`, `git diff --check` — PASS, docs 9/9. Это документационные проверки; локальные runtime suites из [WARP_PORT_HINTS](WARP_PORT_HINTS.md) не выдаются за повторные после неизменённого source.
