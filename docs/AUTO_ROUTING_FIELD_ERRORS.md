# Авторутинг: ошибки №2–4, 2026-11-23

Локальные исправления поверх HEAD `98e5605` (0.2.2/r22). Ошибки №1 и №5 из пользовательского документа исключены из задачи. Работа выполнена без агентов, подключений к роутерам/VPS, установки и публикации. Новый источник ядра — r23, patch 0023 поверх неизменённых 0001–0022. Включённый авторутинг требует r23; общий minimum без автоматики остаётся r10.

## Причины и исправления

**№2, `splice read: resource temporarily unavailable`.** `connectionFailure()` принимал wrapped `syscall.EAGAIN/EWOULDBLOCK` за отказ маршрута. Более того, `syscall.Errno.Timeout()` для EAGAIN возвращает true, поэтому исключение должно находиться перед проверкой `net.Error.Timeout()`. Теперь readiness-ошибки не запускают авторутинг; настоящие deadline/i/o timeout сохранены. Текстовые совпадения не используются. Это фильтрация evidence, а не изменение splice или подавление системного журнала.

**№3, «Найдена рабочая альтернатива: META».** `routeText()` подставлял source вместо отсутствующего target, а `recordStateText()` доверял одному статусу proposed. Теперь пустая цель и цель, равная source, не считаются альтернативой и не допускают Apply. Исходный маршрут не выдаётся за результат проверки; настоящие Direct/WARP отображаются как прежде.

**№4, остановка при включённой галочке.** Подтверждён кодовый путь: `capture()` → ошибка checkpoint/сохранения → компенсационный `registry_withdraw` → ошибка отзыва → `disable` исходной секции. `disable` меняет runtime-флаг ядра, а не UCI: новые ошибки перестают наблюдаться, Apply отвечает `disabled_or_unattributed`, leases исчезают, сохранённые intents остаются со статусом saved.

Исправлены две причины ложного перехода в этот путь:

- Сбой private checkpoint после успешного сохранения разрешений больше не отзывает маршруты и не выключает секцию. Предыдущие private metadata сохраняются; следующая фоновая попытка может повторить запись.
- Отзыв уже отсутствующего lease идемпотентен для существующей исходной секции. Sweep, ошибка соединения или предыдущий отзыв могут удалить lease между snapshot и компенсацией; это уже требуемое состояние, а не повод выключать секцию. Чужой существующий lease и неизвестная секция по-прежнему отвергаются.

Настоящая невозможность сохранить/отозвать несохранённый grant по-прежнему обрабатывается fail-closed. Автоматического включения после такого отказа нет. Runtime disabled теперь виден в странице реестра через существующее сообщение о неактивной автоматике; списки не скрываются.

Удаление исключений проверено отдельно: `registry_reset` не использует разрешающий route guard и работает для выключенной runtime-секции, сохраняя ownership/scope checks. В текущем r22 нет прямого пути от reset к `disabled_or_unattributed`; точная причина исторического отказа удаления на конкретном устройстве не доказана без его версии и runtime-состояния. Исправления выше не следует выдавать за аппаратное воспроизведение всех семи роутеров.

## Свежая проверка

Новые регрессии сначала падали: frontend возвращал META; Go принимал EAGAIN и возвращал lease_not_found; backend после checkpoint timeout вызывал `registry_withdraw`, затем `disable`; страница не сообщала о runtime disabled. После исправлений проверки прошли.

На Windows, из `fe-app-kabanmax`:

```powershell
npx.cmd vitest run
npx.cmd eslint src/kabanmax/tabs/sections/autoRouting.ts src/kabanmax/tabs/sections/tests/autoRouting.test.ts
npm.cmd run build
```

Результат: **176 файлов / 1695 тестов**, целевой lint, TypeScript и LuCI bundle — PASS. `yarn.lock` восстановлен побайтно после автоматического изменения npm; зависимости не обновлялись в исходниках.

В изолированном контейнере `kabanmax-autoroute-tests`, проект подключён read-only как `/work`, ucode `v0.0.20250529`, Go `1.26.10`:

```sh
cd /work
bash tests/run.sh
for f in kabanmax/files/usr/lib/diagnostics/auto_routing.uc kabanmax/files/usr/lib/diagnostics/auto_records.uc kabanmax/files/usr/lib/config/validator.uc; do
  ucode -c -o /dev/null "$f"
  ucode -S -c -o /dev/null "$f"
done
```

Результат: **96/96 backend-файлов**, оба режима syntax — PASS. Временные пути checkpoint/lock изолированы тестом.

В `/tmp/core`: чистый checkout закреплённого `60d96c9`, последовательно применены patches 0001–0023; `tests/core/auto*test.go` скопированы в `common/autoroute`, кроме DNS/FakeIP (в `route`) и JA3/sniff (не включены в этот прогон).

```sh
PATH=/usr/local/go/bin:$PATH go test -count=1 -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./common/autoroute ./route ./experimental/clashapi ./protocol/group ./experimental/cachefile
PATH=/usr/local/go/bin:$PATH go build -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn -o /tmp/autoroute-core ./cmd/sing-box
git diff --check
```

Все пять race suites и компиляция executable — PASS. Это compile check, не релизная branded-сборка или проверка трафика executable. Финальный `git diff --check` проекта — PASS.

Окружение: Docker сначала был выключен, затем пользователь его запустил. Старое Debian security зеркало вернуло 404 для libarchive; ucode собран с доступным `3.4.3-2+deb11u1` только внутри контейнера. Первый frontend-запуск блокировался sandbox/esbuild, повторный разрешённый запуск воспроизвёл именно регрессию.

## Оставшаяся приёмка

На реальном OpenWrt нужно подтвердить длительную работу, reload/Save & Apply и удаление исторических исключений на конкретной установленной версии. Эта задача не разрешает такую установку/подключение. Условия пересмотра: свежий отказ на r23 с доступными runtime disabled/source/error данными или другой причиной невозможности checkpoint/отзыва. Не снимать fail-closed ради автоматического восстановления и не расширять доступ к российским сервисам.
