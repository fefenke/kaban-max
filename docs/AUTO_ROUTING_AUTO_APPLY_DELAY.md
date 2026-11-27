# Автоприменение: неудачная проба и cooldown — 2026-11-25

Историческая диагностика r41. Отсутствие повторной попытки после неуспешного transport check исправлено локально в r42; успешные результаты не повторяются. [Свежий разбор](AUTO_ROUTING_PENDING_RETRY.md).

По новому прямому запросу подключён только локальный роутер. Прочитаны безопасные поля config/API; выполнены ограниченные HTTPS delay checks. Не выполнялись restart, изменение конфигурации, manual Apply, POST к routing API или установка. Текущий core сообщает1.14.4-r41.

## Что произошло

- auto_apply=true, collect_disabled=false, disabled_sources=[]; первая выборка:1candidate/1decision/0leases.
- У записи Instagram первоначально status=inconclusive, reason=no_working_alternative, apply_allowed=false, auto_apply_eligible=false. Direct дал два transport failures; WARP дал HTTP200/проверенныйTLS/4096bytes, затем transport failure после установления TCP (reachable=true, tls_verified=false).
- Первая проверка стартовала15:45:33UTC. Её WARP attempts начались15:45:43.693 и15:45:48.361: успешная первая попытка заняла примерно4.67сек. Точное внутреннее TLS/HTTP исключение второй проверки в Attempt не сохраняется; единственную сетевую причину по этим полям установить нельзя.
- Следующая исходная ошибка зарегистрирована15:50:22UTC; после5минутного cooldown новая проверка началась15:50:38UTC. Без ручной команды Apply появился persistent lease: target=WARP, status=applied, evidence=alternative_reachable, all_devices/all_ports=true, new_error отсутствует. Итог:0candidates/0decisions/1lease/1history.
- Поэтому текущая запись не доказывает отключение автоприменения: оно выполнилось после следующей успешной проверки. Нельзя обещать повтор каждые5минуты без нового error: Sweep также проверяет attempted, а свежая исходная ошибка снова ставит запись в очередь.

## Несогласованность таймаутов

`common/autoroute/web.go:webAttempt` задаёт5сек на весь TCP/TLS/HTTP запрос. В прочитанном рабочем WARP fallback timeout=8s и attempt_timeout=8s. Внешняя5сек проба может завершиться раньше, чем fallback использует свой8сек бюджет и переключится. Это подтверждённая несогласованность, но без сохранённой внутренней ошибки нельзя назвать её единственной причиной конкретного отказа.

`probe.go` требует два verified ответа; одна удача не разрешает automatic Apply. После mixed результата используется общий no_working_alternative, скрывающий частично успешную проверку. Требуется отдельно рассмотреть согласование bounded probe/fallback budgets, retry нестабильного подтверждения и точный статус mixed evidence. Защиту двух независимых HTTPS подтверждений, cooldown/часовые бюджеты и сохранение успешных результатов нельзя просто отключать.

Сравнение web.go/probe.go из опубликованного r40 GPL archive со staged r41 — побайтно одинаковы. Эта конкретная проверка/5сек лимит не изменены patch0041. Это не исключает сетевой эффект обновления/перезапуска; нет оснований обвинять настройки пользователя.

## Команды и ограничения проверки

2026-11-25: native `ucode -L /usr/lib/kabanmax` через SSH; GET `/kabanmax/auto`, `/kabanmax/warp-paths`, `/proxies/WARP`, `/proxies/WARP%2FFallback%20WARP`. Прямые HTTPS checks GET `/proxies/WARP%2FTunnel%20%23N/delay?url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204&timeout=5000` —31/44ms. Два GET group WARP delay с HTTPS www.instagram.com и timeout10000 —1234/1128ms. Domain-target checks могли разрешить иной IP и разогреть транспорт; они не выдаются за повтор точного четырёхшагового auto job. Выбор выбранной группы/профиля не менялся.

Сравнение исходников: Python tarfile.extractfile для common/autoroute/web.go и probe.go из старого public source archive против staged r41 —обаTrue. Docker Desktop в момент проверки не работал; новые Go tests не запускались, production source не изменялся. Секреты/profile IDs/приватный адрес устройства и raw configs/logs в отчёт не включены.

Состояние: на проверенной записи auto Apply подтверждён; согласование таймаутов/mixed-evidence reporting остаётся открытым. Это диагностический отчёт, не опубликованный runtime fix.
