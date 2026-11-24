# Preview 0.2.9 / core r39 — section-wide IP, 2026-11-24

Scope: пользователь сообщил о странном статусе и ошибках Applied IP, затем явно уточнил: правило должно действовать на все устройства выбранной секции, статус uncovered не нужен. Выполнено одним ассистентом, без публикации. [Контракт, причина, локальные regression tests](AUTO_ROUTING_SECTION_IP.md).

## Сборка

- `docker exec kabanmax-autoroute-tests sh /work/dist/preview-029-r39/build-core-binaries.sh` — exit 0; clean archive pinned `core/UPSTREAM`, 39 patches, branding, Go 1.26.10/offline ARM64 base/tiny upstream binary build. Helper аналогичен [предыдущей сборке](PREVIEW_028.md), версия 1.14.4-r39.
- Base SHA256: `505c83db83a447cad7c4ac9f5312a8cb209ec2b78c3c76d3fa67103050ca32a9`; tiny: `7d72dd5e14e198b1c96f443f7b97b810b0ac177ae5e8653d4fd78fe7219e3671`.
- `docker run --rm -e PO2LMO=/usr/local/bin/po2lmo -v PROJECT:/work:ro -v PROJECT/dist/preview-029-r39:/output kabanmax-preview-build bash scripts/build-zapret2-local.sh 0.2.9 /output` — exit 0; backend/LuCI/RU APK/IPK. PROJECT — абсолютный путь текущего workspace.
- `docker run --rm -v PROJECT:/work:ro -v PROJECT/dist/preview-029-r39:/output kabanmax-preview-build bash /work/dist/preview-029-r39/package-core.sh` — exit 0; upstream core packaging + manifests/check-release/inspect-release. **10 APK/IPK payload/source/version/license checks, 13 SHA records PASS**.

## Штатная установка

Перед обновлением: running r38, flash used 33312/free 58528 KiB. Точный config и RAM applied-intent JSON сохранены приватно на компьютере; содержимое не выводилось и не включалось в release. Публичные 14 release assets раздавались LAN mirror компьютера, без большого staging/backup во flash или дополнительного binary в RAM роутера.

Пользователь предупреждён о кратком restart. Detached stock `install.sh` с `KABANMAX_RELEASE=0.2.9 KABANMAX_DOWNLOAD_URL=http://LAN-MIRROR:18090`, `--variant base --lang ru --quiet` — **exit 0**, KabanMax running. Installer сам остановил/запустил службу. Отдельной ручной stop/deployment обвязки нет. Native installed DB: backend/LuCI/RU 0.2.9, sing-box-kabanmax 1.14.4-r39. Установленный `/usr/bin/sing-box` SHA совпал с base artifact.

## Проверка на роутере

Дата: 2026-11-24, тот же ARM64 OpenWrt 25.12.5 router.

- Два прежних Approved IP восстановились без нового Apply: **`all_devices=true`, `all_ports=true`, target WARP, status applied**. Origin metadata сохранилась, новые разрешения на соседний IP не выдавались.
- UI projection: Applied=2, Pending=1, Excluded=0; у двух Applied `uncovered_connections=0`. Оставшаяся Pending относится к отдельному ещё не применённому IP; она не была автоматически одобрена.
- UCI collection flag=1, running `collect_disabled=false`, `disabled_sources=[]`, registry_error empty, memory_pressure=false. Это текущая проверка включённого сбора, не доказательство отсутствия любого исторического отключения.
- `diagnostics.auto_routing.capture()` с native module path `/usr/lib/kabanmax` — true. RAM intent store содержит обе записи с `all_devices=true`. Flash applied registry mtime **1795207423** (старый checkpoint) сохранён: принудительного flash flush ради миграции не было.
- HTTPS YouTube 204 через оба WARP и fallback: **35/38/34ms**. Bounded `/connections` snapshot в момент проверки не содержал flows двух Applied IP: фактический новый пользовательский flow с другого LAN device в этом снимке не наблюдался. Cross-device route selection подтверждён локальными regression tests и активными section-wide grants, а не вымышленным packet trace.
- Сохранённые WARP port hints 38071/42987 пережили обновление. Этот запрос их не перезаписывал и не сбрасывал per-boot allowance.
- Installer log/exit сохранены приватно. Удалены только собственные три tiny staging файла из `/tmp/kabanmax-preview029` и пустая директория. RAM autoroute/checkpoints не удалялись. LAN mirror остановлен после проверки PID/CommandLine. Финально running, flash **used 33352/free 58492 KiB**, 36% (~33 MiB).

## Финальные проверки и ограничения

`docker exec kabanmax-autoroute-tests sh /work/dist/auto-section-ip/verify-backend.sh` — exit 0, оба `ucode -c` / `ucode -S -c` режима для config auto_storage/auto_registry и diagnostics auto_registry/auto_records, backend **99/99 файлов PASS**. Helper выполняет эти syntax-команды и `bash tests/run.sh` из `/work`.

14 Go race packages, frontend 14/14 + TypeScript/build/lint — [локальные команды](AUTO_ROUTING_SECTION_IP.md). Runtime source после их проверки не менялся. После обновления состояния 2026-11-24 `python scripts/check-project-docs.py --write-facts`, `python scripts/check-project-docs.py`, `python -m unittest discover -s tests/docs -p 'test_*.py'`, `git diff --check` — PASS, docs 9/9. Полный router reboot, WAN-loss и многодневный soak не выполнялись. GitHub push/release нет.
