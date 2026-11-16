# Предложение восстановления оформления — 2026-11-16

Статус: пользователь утвердил макет, попросил уменьшить стрелки и распространить стиль на настройки/общие формы; уточнил удаление только выбранного списка/фильтра и затем разрешил публикацию по готовности. Реализация опубликована в 0.1.8; ядро r12 не меняется. Исходный макет и его скриншоты не являются снимками установленной LuCI-темы.

## Причины претензий

- `fe-app-kabanmax/src/kabanmax/cbi/formUx.ts`: общий Grid заменяет штатную геометрию LuCI; `.km-flag` с `minmax(0,1fr) auto` прижимает контрол к правому краю. `km-nested` и `km-nested-deep` добавляют разные горизонтальные отступы. `attachHelp` удаляет исходные tooltip-контейнеры и создаёт новую монохромную кнопку.
- Там же `auto_routing_apply && !strict` блокирует checkbox независимо от его текущего значения. Уже сохранённое включение нельзя снять без контракта. Вывод основан на чтении кода; воспроизведение и регрессионный тест рабочего адаптера ещё нужны.
- `tabs/sections/autoRecords.ts` постоянно показывает техническую справку о 64 записях и добавляет временную остановку `autoAction('disable', sectionId)`. Эта операция отличается от сохранённого выключения через UCI/Save & Apply.

Проверены локальный tag 0.1.7 и публичные метаданные [релиза](https://github.com/fefenke/kaban-max/releases/tag/0.1.7): опубликован, prerelease, source `e5dd33bb7f1f3dada87af6672e815f89b54308e3`. Рабочее дерево до макета чистое, HEAD `c86cca0523b67b6e796995dc53baf754d76f304f`.

## Предлагаемый вариант

Восстановить прежнюю геометрию штатной темы, оставив выравнивание по вертикали и help справа от подписи. Для согласования на desktop макет использует одну колонку контролов около x=368 px при ширине 895 px; это предложение расстояния, а не доказанная точная копия прежнего экрана. Вернуть синие вопросики, убрать дополнительные вложенные отступы, в том числе у IP без домена. Страницы прижать вправо; постоянную справку перенести под вопросик «Найденные IP»; кнопку временной остановки убрать. Ошибки RPC, предупреждения переполнения и результаты операций должны остаться видимыми.

Снимать «Автоматически применять» должно быть возможно и при отсутствии strict-контракта. Повторное включение без необходимых условий не должно обходить проверки. Макет показывает только внешний вид и клик, не реализует production-валидацию и сохранение. IP-only остаётся недоступным по действующему контракту безопасности.

Глобальную замену формы новым дизайном отклоняем: она повторит проблему. Полный откат релизного коммита также не подходит, поскольку удалит независимые функциональные изменения. Предлагается точечное восстановление оформления адаптера и списка. При реализации проверить остальные CBI-формы, где применяется общий адаптер.

Просмотрены [рекомендации GOV.UK по чекбоксам](https://design-system.service.gov.uk/components/checkboxes/): короткие подсказки, понятные подписи и компактное размещение в насыщенных интерфейсах. Расположение колонок сохраняется по запросу пользователя и структуре LuCI, без переноса всего GOV.UK-дизайна.

## Артефакты и свежие проверки

Ignored `.local/audit/ui-style-proposal/`: `proposal.html`, `capture.mjs`, `proposal-desktop.png`, `proposal-mobile.png`.

Команда из корня: `node .local/audit/ui-style-proposal/capture.mjs` — PASS. Headless Edge/CDP: desktop viewport/content 895/895 px, mobile 375/375 px; checkbox доступен в viewport, программный click снимает и возвращает значение в макете. Скриншоты сохранены. Это проверка макета, не приложения. `git diff --check` — PASS.

Первый запуск Edge через Start-Process не создал скриншот (GPU sandbox/кодировка Unicode-пути); повтор с относительным профилем завершился ошибкой ProcessSingleton. Рабочий вариант использует отдельный ASCII-путь во временной папке, headless-процесс и CDP с точным viewport. Одного `--window-size=375,...` оказалось недостаточно: Edge рендерил более широкий viewport и обрезал снимок. Геометрия проверяется через CDP перед сохранением. Эти неудачи не являются дефектами приложения.

## Реализация и финальные проверки

`formUx.ts`: общая desktop-колонка 26em для полей/галочек, синие help, без вложенных отступов; адаптер применяется к общему map, включая настройки и CBI-модалки. На ≤600px поля переносятся. Стрелки списка 1.8em с нулевым padding, справа. Description «Найденные IP» содержит справку для popover; ошибки/overflow/results остаются видимыми. Временная stop-кнопка удалена.

Checked auto-apply можно снять без контракта и при выключенной главной настройке; после снятия повторное включение требует prerequisites. Исходный readonly сохраняется. Backend/verifier/ACL/IP-only guards не изменялись. «Удалить все» в «Применены» использует `forget` для активных leases и сохранённых разрешений, в «Исключены» — `remove`. Действия охватывают все страницы текущего source/status/search с подтверждением; другие списки не очищаются.

Из frontend: `npm.cmd run build`, `npm.cmd run lint`, `npm.cmd test -- --run` — PASS **176 файлов / 1686 тестов**. Первый полный прогон выявил HTMLInputElement global в bundle и неиспользуемые stop-строки PO/POT; исправлены без ослабления тестов, полный повтор PASS. `npm.ps1` заблокирован execution policy; использован `npm.cmd`, политика не менялась.

Из frontend: `node node_modules/esbuild/bin/esbuild ./tests/browser/formUx.browser.ts --bundle --outfile=../.local/audit/ui-style-proposal/formUx.browser.js`; затем из корня `node .local/audit/ui-style-proposal/check-browser.mjs` — PASS **320/375/768/1280 + dark 375**, точный viewport CDP. Проверены click/strict/main gating, help lifecycle, server pagination, массовые операции всех 64 с source/status/search, отмена подтверждения, textarea и зависимости. RED сохранены в `regression-red.html` (checked невозможно снять) и `bulk-red.html` (нет applied delete), GREEN и матрица — рядом в ignored audit.

Docker, без сети, checkout readonly: `forkop-zapret2-test-tools:local bash tests/run.sh` — **92/92 PASS**. Новый тест `auto_registry.test.uc` проверяет mixed live/saved/foreign/failed, точный withdraw и сохранение соседей/exclusions, partial result 2 done / 1 failed / 1 skipped. Независимое ревью не обнаружило production-регрессий; его замечание об отсутствии этого backend-теста закрыто.

Docker `kabanmax-release:2.1.0`, без сети, `PO2LMO=/usr/local/bin/po2lmo`: `bash scripts/build-zapret2-local.sh 0.1.8 /output`, `bash scripts/finalize-release.sh /output`, `bash tests/installer-release-pin.sh`, `bash tests/release-manifest-smoke.sh`, `python3 /work/.local/audit/ui-style-proposal/inspect_packages.py` — PASS. **10 APK/IPK, 13 SHA256, 14 assets**: payload APK/IPK совпадает, bundle соответствует исходнику с 0.1.8, private paths не включены, ядро и лицензии совпадают с 0.1.7. Четыре core-пакета используются без пересборки, Go/race/ARM64 runtime заново не проверялись. `git diff --check` — PASS.

PROJECT_STATE, DECISIONS, KNOWN_ISSUES, PITFALLS, ARCHITECTURE/COMPONENTS, ROADMAP и CHANGELOG просмотрены; затронутые статус, решения, ловушки и история обновлены. Аппаратная LuCI/theme/Save & Apply проверка не проводилась; подключений к роутерам/VPS нет.

Перед выпуском просмотрены `implemented-desktop.png`, `implemented-mobile.png`, `implemented-settings.png`: реальный CBI-адаптер и renderer реестра на тестовой разметке, настройки представлены примером общих CBI-полей (это не полный renderer вкладки). `node .local/audit/ui-style-proposal/live-capture.mjs` — отсутствие горизонтального overflow при 895/375 px PASS, положение checkbox справа ≤379/361 px, стрелки компактные. Screenshot-fixture сначала завершился из-за stale DevToolsActivePort, затем из-за inline-script до появления body; исправлены только ignored harness: отдельный профиль и script внутри body. Эти ошибки не затрагивали приложение.

Документация: `npm.cmd run build` из `docs` — PASS. Пакеты 0.1.8 сохраняют прежние source minimum и core package r12; изменения установщика не требуются.

## Публикация

[0.1.8 prerelease](https://github.com/fefenke/kaban-max/releases/tag/0.1.8) опубликован с source/tag `1d0dd86d36119d651c589aad8d840113773eda90`. GitHub [Frontend CI](https://github.com/fefenke/kaban-max/actions/runs/43820687281), [Backend CI](https://github.com/fefenke/kaban-max/actions/runs/43820687330), [Documentation](https://github.com/fefenke/kaban-max/actions/runs/43820687646) — success. Ignored helpers `github-release.ps1 -Action draft/upload/publish`, `verify-public.ps1` проверили 14 assets по API/local/public download SHA256 и размеру, 13 SHA256SUMS, manifests, точный tag ref и draft=false/prerelease=true. Evidence: `.local/audit/ui-style-proposal/public-verification.json`. История сохранена, старые releases не менялись; на устройства ничего не устанавливалось.
