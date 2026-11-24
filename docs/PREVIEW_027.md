# Приёмка 0.2.7/core r37 — 2026-11-24

Установлены backend/LuCI/RU **0.2.7**, core **1.14.4-r37 base**, штатным неизменённым `install.sh`, exit **0**. GitHub публикации нет. Источник core — pinned UPSTREAM + 37 patches; прежние пользовательские изменения сохранены, один ассистент. Детали r35–r37 и локальных core tests — [PREVIEW_026](PREVIEW_026.md).

## WARP: фактическая restart-приёмка

r34 воспроизводил отказ в двух из двух restart; r36 тоже не прошёл первый цикл. Они не выдаются за исправление. Финальный r37 сохраняет в существующем WARP cache подтверждённый UDP порт как мягкую подсказку для следующего запуска. Пользовательский listen_port имеет приоритет; занятый hint не блокирует старт. Холодный старт до первого handshake имеет максимум три быстрых rotations, затем прежний 90s backoff. Новая регистрация профиля и переписывание credentials не добавлены.

Пользователь прямо разрешил restart-тесты. Команда автономного теста: `setsid sh /root/kabanmax-warp-restart-test-20261124/run-r37.sh </dev/null >/dev/null 2>&1 &`. После каждого `/etc/init.d/kabanmax restart` — тот же интервал **8s после возврата команды**, что в неудачных r34/r36 тестах, затем по отдельности authenticated HTTPS YouTube204 через каждый профиль и fallback. Timeout API 8000ms. Уровень журнала Warn, без Debug/нагрузочного трафика. Сохранённая запись проверялась по created/status/target.

| Цикл, MSK 2026-11-24 | WARP1 | WARP2 | Fallback | Результат |
| --- | --- | --- | --- | --- |
| Baseline 08:11:07–08 | 34ms | 35ms | 34ms | PASS |
| Restart 1, проверки 08:11:32–33 | 34ms | 36ms | 35ms | PASS |
| Restart 2, проверки 08:11:55–56 | 34ms | 42ms | 34ms | PASS |
| Restart 3, проверки 08:12:18–19 | 34ms | 38ms | 35ms | PASS |
| Restart 4, проверки 08:12:41–42 | 34ms | 42ms | 33ms | PASS |
| Restart 5, проверки 08:13:05 | 44ms | 41ms | 49ms | PASS |

Пять новых core PID подтверждают реальные перезапуски. После первого graceful close cache hints стали ненулевыми и одинаковыми в последующих циклах. Применённая пользователем запись сохраняла исходные created/status/target во всех пяти циклах. На момент теста исходная WhatsApp запись уже была применена пользователем: это проверка RAM intent, а не пяти новых проверок Pending. Ранее r35 проверен regression на checkpoint/restore успешного Pending без повторного probe.

После штатного обновления только app/LuCI/RU до 0.2.7 с тем же r37 финальная дополнительная HTTPS-проба: **33/35ms**, fallback **34ms**, служба running. Это успешная ограниченная restart-серия на одном ARM64 роутере; не многодневный soak, hardware WAN-loss или полный power loss. Внешняя причина молчания некоторых новых UDP flows не объявляется доказанной.

## Авторутинг и интерфейс

- Ошибка и последний успешный результат хранятся в RAM до удаления/применения/исключения записи под общим memory budget. Успех не становится expired, новые ошибки исходного маршрута не стирают результат, автоматический повтор после успеха не запускается. Кнопка перепроверки не добавлена.
- Private checkpoint переносит результат через reload/restart с source/scope validation. Время `checked_at` остаётся временем исходной проверки. Полный power loss runtime-диагностики отдельно не покрыт.
- В 0.2.7 удалено поле «Срок хранения диагностики авторутинга / 1h». Старое UCI значение игнорируется; фиксированный внутренний housekeeping относится к временным счётчикам/истории, не Pending. При заполнении memory budget существующие записи сохраняются, новый admission отклоняется с overflow, физическая RAM не увеличивается.
- Суточный dirty-only flash checkpoint **не изменён**. Проверка на устройстве до и после обновления: два применения в RAM, flash applied JSON содержит **0 записей**, mtime остался **20 ноября**. Старые 14 exclusions не удалялись. Установщик не форсировал суточную запись этих двух правил.

## Проверки 0.2.7

Frontend Windows Node, backend существующий Docker/ucode:

- RED `npx.cmd vitest run src/kabanmax/tabs/settings/tests/autoStorage.test.ts`: старое поле 1h ещё присутствовало. GREEN `npx.cmd vitest run src/kabanmax/tabs/settings/tests/autoStorage.test.ts src/kabanmax/tabs/sections/tests/autoRouting.test.ts` — **15/15**.
- `npm.cmd run build`, целевой `npx.cmd eslint src/kabanmax/tabs/settings/form/autoStorage.ts src/kabanmax/tabs/settings/tests/autoStorage.test.ts` — PASS: TypeScript, fingerprint gate, bundle, lint.
- `docker exec kabanmax-autoroute-tests bash /work/tests/run.sh config/auto_storage`, `... diagnostics/auto_routing`, затем `docker exec kabanmax-autoroute-tests bash /work/tests/run.sh` — PASS, **97/97**. Новая regression проверяет игнорирование старого cleanup option; суточные dirty/pressure ограничения не менялись.
- `docker run --rm -e PO2LMO=/usr/local/bin/po2lmo -v "${taskRoot}:/work:ro" -v "${taskRoot}/dist/preview-027:/output" kabanmax-preview-build bash scripts/build-zapret2-local.sh 0.2.7 /output`, затем тот же run с `bash /output/package-core.sh` — PASS **10 APK/IPK** и 13 SHA records, payload/source/version/license. Core binaries переиспользованы из проверенного r37, повторная компиляция не заявляется.
- Чистые 37 patches, 14 Go race packages, crypto restart-path/pinned-port/busy-hint/cold-budget tests, ARM64 base/tiny и executable HUP — PASS в неизменном core r37; точные команды и SHA — [PREVIEW_026](PREVIEW_026.md). Проверки не выдаются за новый прогон после UI-only изменения.
- Итоговые `python scripts/check-project-docs.py --write-facts`, docs gate, doc unittest и `git diff --check` выполняются после обновления отчёта.

## Flash, авария установки и уборка

Первый flash-staged r37 installer остановился при заполнении flash на 100%; core записался частично, без executable mode, KabanMax был остановлен. Это ошибка оценки peak-space ассистентом. По проверенному SHA восстановлен рабочий r36 hardlink из собственного backup, автономный start вернул running до новых изменений. Не приписывать проблему Tailscale или пользовательским данным.

Убраны старые собственные APK и mirror hardlinks r31/r36/r37, диагностические binaries и дубликаты backup files после сравнения SHA с уже имеющимися компьютерными копиями. Новый широкий config archive не создавался: auto-review запретил sensitive egress, выбрана сверка существующих SHA без передачи содержимого. Ранее auto-review также запретил удаление migration sidecar; файл оставлен в RAM. Usage-limit block до 07:51 не обходился.

Повторная штатная установка использовала поддерживаемый `KABANMAX_DOWNLOAD_URL` на временном LAN HTTP mirror **компьютера**, без APK на flash роутера. Сначала r37 core, затем 0.2.7 app/LuCI/RU; оба installer exit **0**, служба автоматически запущена. Значение адреса LAN mirror в отчёте опущено; это не GitHub публикация и не изменение постоянного download URL в UCI.

После уборки и последнего обновления: `/overlay` used **33872 KiB ≈33 MiB**, available **57972 KiB ≈57 MiB**, **37%**. До уборки лишние APK и backups занимали значительную часть flash. Рабочий core, Tailscale, `/etc` настройки и RAM routing intent не удалялись. Binary/config backups остаются на компьютере в приватном ignored хранилище, не в release.

Финальные результаты теста и два installer logs без keys/config содержимого скопированы в приватный каталог на компьютере. Временный LAN HTTP server остановлен после проверки его PID/command line, проектный тестовый контейнер остановлен; Docker настройки/образы не менялись. Восемь собственных staging/test каталогов и RAM helper удалены после проверки рабочего core SHA и installer exit. Финальный `/overlay` **used 33472 KiB (~33 MiB), free 58372 KiB (~57 MiB), 36%**; running. `/etc`, runtime intents, Tailscale и оставленный migration sidecar не затронуты. Новых restart jobs нет. Итоговые docs gate, doc unittest **9/9** и `git diff --check` PASS.
