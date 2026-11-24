# Applied diagnostics — исследование 2026-11-24

Текущая установленная версия: preview 0.2.9/r39. Задача — разобрать неизвестный домен, пустые ошибки Applied и `splice read` в Pending. Только чтение: конфиг/маршруты/пакеты не менялись, служба не перезапускалась.

## Evidence

SSH, native `ucode -L /usr/lib/kabanmax`: `diagnostics.auto_routing.state()`, `diagnostics.auto_records.page({source_section:SOURCE,status:STATUS,page:1,page_size:25})` для applied/pending, `config.auto_registry.load().entries`. SOURCE — существующая секция. Credentials не выводились. Runtime disabled_sources=[], registry_error пуст; Applied=2, три candidate events группируются в два видимых Pending IP.

- Applied 31.13.72.52 повторно применён в 16:20:31 MSK как IP-only: domain пуст, domain_known=false, ip_only=true, domains пуст. Имя в этой исходной записи не распознано. Ранее IP встречался с WhatsApp именами, но это не доказывает один постоянный домен для IP.
- Applied 31.13.72.174 сохраняет `www.instagram.com`. Оба lease имеют all_devices/all_ports=true, new_error=false. Их failure содержит пустые id/message и zero time. В intent store у failure есть **только source_id**, domains отсутствует.
- Причина в коде: `config.auto_storage.compact()` удаляет failure id/message/time и domains; `config.auto_registry.save()` применяет projection **до RAM branch**. После restore ядро получает лишь компактное разрешение. UI создаёт Error details по наличию объекта failure, даже если текста нет. Это дефект сохранения/отображения диагностики, не доказательство отсутствия исходной ошибки.
- Pending 31.13.72.53: имена CDN и `i.instagram.com`, проверка выполнялась для `i.instagram.com`. Исходная ошибка `splice read: connection timed out`, последнее событие 18:10:05 MSK. Direct дважды открыл TCP, но не подтвердил TLS. WARP дважды подтвердил TLS и получил HTML HTTP 404, 4096 байт. Это подтверждает HTTPS transport до имени/IP, не полную работу Instagram.
- Pending 31.13.72.5, `edge-mqtt.facebook.com`: та же ошибка, 17:38:15 MSK. Direct TLS дважды не подтверждён, WARP TLS и HTTP 200 подтверждены дважды. HTTPS GET не доказывает работу MQTT/push-сессии.

`splice` — kernel-assisted перенос данных Linux, `read` — стадия чтения; существенная причина здесь `connection timed out`. По одной строке нельзя установить сторону сбоя или причину DPI/server/network. Это не EAGAIN/EWOULDBLOCK (`resource temporarily unavailable`), уже исключённый patch 0023. [Linux splice(2)](https://man7.org/linux/man-pages/man2/splice.2.html).

## Исправление в 0.2.3/r40

Результат последующей работы: отдельный bounded RAM sidecar, original/target errors, domain labels и отсутствие пустой раскрывашки. Установлен 0.2.3/r40; [проверки и ограничения](RELEASE_023.md). Ниже сохранена исходная постановка до исправления.

Сохранять исходный failure text/time и наблюдённые доменные подписи в bounded RAM diagnostics отдельно от compact routing intent. Не менять flash schedule и не подставлять угаданный reverse-DNS домен. Статус Applied «новых ошибок нет» относится к новым отказам альтернативного маршрута; исходная ошибка должна оставаться доступной отдельно. Не рисовать пустую Error disclosure. Утраченный текст нельзя восстановить из compact record — нужен другой retained checkpoint/log.

Границы: новых сетевых проб не было; причина DPI и полная работоспособность Instagram/MQTT не доказаны. Исправление/установка по этому исследованию не заявляются. Последующая проверка — только docs gates; прежние runtime suites не выдаются за новые.

2026-11-24, локально: `python scripts/check-project-docs.py`, `python -m unittest discover -s tests/docs -p 'test_*.py'`, `git diff --check` — PASS, docs 9/9. Scope: документация, без повторных runtime suites.
