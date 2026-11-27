# WARP: Google не проходит, fallback удерживает первый — 2026-11-25

Снимок r41 до исправления. Потеря primary failure и поздних stream failures исправлена локально в [r42](WARP_RUNTIME_FIX.md); на роутере ещё не проверено. Внешняя причина частичного отказа не объявляется установленной.

Диагностика только локального роутера по новому прямому запросу пользователя. Core r41; конфиг, selector, профили и служба не изменялись/не перезапускались. Production fix не внесён. Предыдущий запрет на самостоятельную массовую установку сохраняется.

## Подтверждённые результаты

Native Clash HTTPS delay,8сек: первый WARP→gstatic generate_204 —HTTP504/Timeout; второй→тот жеGoogleURL —38ms. Повторная матрица: первый→Google снова504; первый→cp.cloudflare.com generate_204 —33ms; второй→Google —37ms.

GET fallback state: stable=true, selected=первый, fixed пуст; switches_total=0, connection_errors=0, failed_checks=0, events=null. Последняя проверка первого считалась успешной. Рабочие параметры: url=gstatic, confirm_url=Cloudflare, interval5m, timeout/attempt_timeout8s, failure_retry_interval8s, recovery_interval5s. Общий log level=warn.

WARP path API показывает свежие authenticated handshake/IP-data первого и неизменное поколение bind. Следовательно, не доказан полный отказ UDP/WireGuard. Точная внешняя причина недоступности Google через первый выход (маршрут/egress/TLS/MTU и прочее) не установлена; профиль/провайдер причиной по догадке не объявляются. Регенерация/смена порта не выполнялись.

## Почему не восстанавливается и не переключается

WireGuard self-heal работает для отсутствующей/просроченной сессии и не видит Google-specific отказ: через тот же первый туннель успешно проходит HTTPS Cloudflare. Сам по себе свежий handshake не доказывает YouTube, но успешный Cloudflare объясняет, почему механизм полного UDP-outage не срабатывает.

В `protocol/group/fallback_stable.go` результат primary сохраняется в primaryError, затем при ошибке выполняется confirmURL. Успех Cloudflare заменяет err на nil; дальше текущий участник считается healthy, несмотря на отказ основного GoogleURL. Поскольку active healthy, резерв не проверяется для сравнительного подтверждения того же GoogleURL. Это объясняет удержание первого при работающем Google на втором.

Для будущего исправления нужно отдельно сохранять частичный отказ основного URL и сравнивать **тот же** URL на активном и резерве с bounded подтверждением. Успех независимого сервиса не должен незаметно отменять отказ выбранной пользователем контрольной службы. Одновременно нельзя отключать safeguards от общего outage контрольной службы, повторные подтверждения и ограничения частоты; один timeout не должен вызывать бесконечные переключения.

Текущая выборка `/connections`:38YouTube-family TCP connections через WARP fallback, snapshot не усечён. Источник/адреса устройств/URL видео не сохранялись. Это не доказательство успеха видео. Счётчик connection_errors отражает прежде всего ошибки dial; ноль не означает, что весь TLS/HTTP путь исправен.

## Почему журнал пуст и были ли Warn раньше

Да. В patch0001 fallback suspect/probe-only failures были Warn. Patch0026 явно переводит эти три warning sites в Debug; confirmed failure остаётся Warn. Это шире исходного требования подавлять ошибки в lifecycle window. Patch0033 возвращает Warn только принятым source failures авторутинга, не всем ошибкам WARP.

Сейчас при warn level скрыты suspect/probe-only Debug, а обычные fallback dial failure/switch сообщения находятся на Info. Дополнительно конкретный primary Google failure после успешного Cloudflare вообще не доходит до confirmed/suspect failure ветки: err уже nil. Поэтому простое увеличение verbosity не исправляет отсутствие события частичного отказа.

Нужны ограниченные Warn для существенного отказа активного участника/его подтверждения/переключения и отдельное событие primary-failed/confirmation-passed. Lifecycle suppression следует применять только в своём окне. Глобальный Debug, печать каждого пакета и неограниченные повторы не предлагались/не включались.

## Проверки и ограничения

2026-11-25, native `ucode -L /usr/lib/kabanmax` через SSH, GET `/proxies/WARP`, `/proxies/WARP%2FFallback%20WARP`, `/kabanmax/warp-paths`, `/connections`; HTTPS GET `/proxies/WARP%2FTunnel%20%23N/delay?url=ENCODED_URL&timeout=8000` для двух generate_204 URL выше. Прочитан ограниченный `logread -e sing-box | grep -E 'WARP|fallback|Fallback|WARN|ERROR' | tail -n 25`. Персональные адреса, ключи, profiles и raw журналы не опубликованы.

Исходники проверены из staged полного public r41 source и pinned patches0001/0026/0033. Docker в этой диагностической сессии не работает; новых Go/runtime changes/tests нет. Это подтверждённый разбор, не установленное исправление и не доказательство причины внешнего Google outage.
