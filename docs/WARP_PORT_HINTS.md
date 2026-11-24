# WARP: порт в постоянном конфиге

Контракт согласован 2026-11-24. Реализация: core r38 (patch 0038) и backend. По новому явному запросу установлен preview 0.2.8/r38, exit 0, running; оба WARP/fallback прошли HTTPS. [Первичная установка](PREVIEW_028.md). Текущий preview 0.2.9/r39 сохраняет этот контракт; native UCI hints 38071/42987 подтвердились после restart — [PREVIEW_029](PREVIEW_029.md). Полного router reboot не было.

## Поведение

- У каждого native WARP tunnel в `/etc/config/kabanmax` сохраняются `warp_local_port_hint` и `warp_local_port_profile` (ID профиля). Это локальный UDP-порт, не серверный `warp_port`.
- После reboot с пустым RAM cache ядро пробует постоянную подсказку. При restart службы более новая RAM-подсказка имеет приоритет. Это не обязательный `listen_port`: занятый порт допускает ephemeral bind, неотвечающий путь — прежнее bounded recovery. Explicit bind и `profile.recreate` не участвуют.
- Подтверждение требует authenticated handshake и полученного валидного IP-пакета; handshake и пустой/padded keepalive недостаточны. Затем нужны 600 секунд здоровых наблюдений одного порта и поколения bind. Handshake не старше 180 секунд, разрыв наблюдений не больше 120 секунд. Пассивный опрос раз в минуту: запись может произойти позднее ровно десяти минут.
- Если сохранённый порт подошёл, окно завершается RAM-маркером: **ноль UCI commits**. Последующие изменения остаются в RAM до нового reboot.
- Если старый порт не подошёл или подсказки ещё нет, новый сохраняется после окна **максимум один раз на профиль за загрузку роутера**. Одновременно готовые профили объединяются в один commit.
- Переключение, reload/restart KabanMax сами по себе не обновляют flash и не сбрасывают лимит. Изменение core/bind, порта, stale handshake, отсутствие IP-data или ошибка API сбрасывают отсчёт. До подтверждения сохраняется прежняя flash-подсказка.
- Без явно заданных ID/token/private key постоянная подсказка не создаётся. Регенерация ID делает старую подсказку неприменимой. Неоднозначные дубликаты credentials автоматически не сохраняются.

## Слои и сохранность

`diagnostics/warp_ports.uc` вызывается из minute timer `service/state_service.uc`. Authenticated GET `/kabanmax/warp-paths` отдаёт tag, profile ID, подтверждённый порт, времена handshake/IP-data и экземпляр bind, без credentials/remote address. API не выполняет пробы и не меняет маршруты.

Под lifecycle lock backend сравнивает credentials текущего UCI с running JSON и profile ID ответа. Отдельный свежий cursor использует приватный RAM delta directory: staged настройки LuCI не коммитятся. Commit подсказки не вызывает reload. Генератор передаёт hint только при совпадении ID.

Окна/лимиты — `/var/run/kabanmax/warp-port-hints.json`: переживают restart, сбрасываются reboot. Allowance атомарно резервируется **до** commit: неоднозначный сбой записи не вызывает повторных flash attempts в этой загрузке. Повреждённый checkpoint запрещает сохранение вместо сброса лимита. Не удалять checkpoint при обычной уборке runtime. Flash schedule авторутинга не меняется.

## Проверки 2026-11-24

Окружение: локальный Linux x86_64 Docker `kabanmax-autoroute-tests`, Go 1.26.10; clean archive pinned `core/UPSTREAM` + 38 patches. Этот раздел описывает локальные проверки до установки; последующая аппаратная проверка отделена в [PREVIEW_028](PREVIEW_028.md).

- RED: `docker exec kabanmax-autoroute-tests bash /work/tests/run.sh diagnostics/warp_ports` — exit 1 до создания модуля. Новый Go test до patch 0038 — exit 1: нет hint/status interfaces.
- `docker exec kabanmax-autoroute-tests env PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin sh /work/tests/core/run_warp_stability.sh /tmp/core /work` — exit 0: clean apply 38 patches; race suites WARP/Cloudflare/WireGuard/Clash API. Покрыты пустой cache, RAM priority, explicit bind/recreate, read-only API, реальные локальные handshakes/IP payload, busy hint/recovery/restart; keepalive не считается данными, rebind сбрасывает health.
- `docker exec kabanmax-autoroute-tests env PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin sh /work/dist/warp-port-hints/verify.sh` — exit 0: cmd compile-only, оба ucode syntax режима для трёх изменённых backend modules, `sh -n tests/core/run_warp_stability.sh`, backend **98/98 файлов PASS**. Ignored helper выполняет в чистой подготовленной r38 базе `GOPROXY=off go test -run '^$' -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./cmd/sing-box`, затем из `/work` — `ucode -c -o /dev/null FILE`, `ucode -S -c -o /dev/null FILE` для `diagnostics/warp_ports.uc`, `config/connections.uc`, `service/state_service.uc`, и `bash tests/run.sh`.
- `python scripts/check-project-docs.py --write-facts`, `python scripts/check-project-docs.py`, `python -m unittest discover -s tests/docs -p 'test_*.py'`, `git diff --check` — PASS, docs unit **9/9**. Число patches/source version актуализировано; установленная версия явно отделена.
- Промежуточный Go test не скомпилировался из-за вызова void `SendKeepalive` как error; исправлен, финальный runner PASS. Backend tests проверяют delayed/unchanged commits, отдельные профили и batching, outage/stale/core-restart reset, profile ownership, fail-closed checkpoint и использование отдельного delta directory. Нативный OpenWrt cursor при этом заменён fake.

Ограничения: timers проверены виртуальными часами. ARM64 base APK штатно установлен; native OpenWrt cursor/capture и resident timer проверены. Фактический delayed commit после десяти минут, полный reboot/power loss и WAN soak ещё не проверены. Прежние 5/5 restart r37 из [PREVIEW_027](PREVIEW_027.md) не являются проверкой r38. Во время отдельной установки KabanMax перезапустил штатный installer; публикации нет.
