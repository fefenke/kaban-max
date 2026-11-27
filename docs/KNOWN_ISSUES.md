# Известные проблемы и границы доказательств

## Save & Apply и клиентское DNS-состояние

Найден DNS bypass в старой HUP pause; новый backend закрывает его filter guard до DNAT.101backend и nft dry-run PASS, guard установлен. Это согласуется с восстановлением после переключения VPN на компьютере, но конкретный сбой региона не перехвачен; повторные Save с клиентским capture после установки ещё не проверены. [Диагностика/границы](RELOAD_DNS_PAUSE.md).

**Web probe deadline,2026-11-26:** исправлен локально в r43: configured TCP budget +5s TLS/HTTP, bounded выбранная цепочка групп, прежний60s parent limit. Добавлены явный TCP-risk opt-in и честный Applied status с сохранением ошибок. Affected race/backend/frontend PASS; final artifacts и hardware status — [r43](AUTO_ROUTING_R43.md).

**Локальный r42:** исправлены global copy downgrade, видимость fallback/Applied failures, потеря partial primary failure и отсутствие late-stream wake. WAN gate оставлен прежним по прямому уточнению пользователя. Тесты и binaries готовы; hardware acceptance/внешняя причина частичного Google outage ещё не установлены. [Evidence](WARP_RUNTIME_FIX.md).

**WARP partial failure на r41,2026-11-25:** первый не проходил Google при доступном Cloudflare; второй проходил Google. Потеря primary failure исправлена локально в r42, на устройстве исправление не проверено. [Исходная матрица](WARP_PARTIAL_FAILURE.md).

**Auto Apply/r41,2026-11-25:** auto включён; после mixed WARP проверки и5мин cooldown новая проверка автоматически применила IP к WARP, all_devices/all_ports=true. Обнаружено5сек web probe против8сек fallback attempt; mixed evidence показывается общим no_working_alternative. Runtime fix не выполнялся. [Точные наблюдения и ограничения](AUTO_ROUTING_AUTO_APPLY_DELAY.md).

**2026-11-25: Applied late-DNS bypass r40 исправлен и опубликован в r41/0.2.3.** RED→GREEN,14Go race packages, local executable, все6GitHub jobs PASS. Hardware/установка не проводились по запрету пользователя. Исправлена подпись обхода/атрибуция старых ошибок. [Доказательства и границы](AUTO_ROUTING_LATE_DNS.md). Предыдущий r40 restart дал WARP HTTPS65/65ms; задержка WARP остаётся отдельной открытой проблемой.

WARP: после штатной установки API quota hotfix 0.2.3/r40 первый профиль прошёл HTTPS за 35ms, второй дважды вернул HTTP504 без дополнительных restart. Startup/recovery второго профиля снова открыт; причина не установлена, ядро в hotfix не менялось. [Текущая приёмка](RELEASE_023.md). Прежний r37 проходил 5/5 restart/HTTPS с cache hints — это исторический результат, не доказательство текущей устойчивости.

Pending «не найдена → очередь → не найдена»: промежуточный r34 разделял TTL и retention, но не соответствовал окончательному запросу пользователя. Установленный 0.2.7/r37 сохраняет неразобранную ошибку и успешный результат до удаления/применения/исключения, без протухания и повторного probe; поле 1h удалено, ограничение — memory budget. Checkpoint/restore/new-error/Sweep regressions PASS; прежний результат перенесён без новой пробы, позднее запись применена пользователем и сохранилась через 5 restart. Полный power loss RAM Pending не покрыт. [Точная приёмка](PREVIEW_027.md).

Версии и актуальные результаты — [PROJECT_STATE](PROJECT_STATE.md). Закрывать проблему только новым доказательством для её условий, а не совпадением текста сообщения.

| ID / статус | Что известно | Что требуется для закрытия |
| --- | --- | --- |
| KI-001 · не диагностировано | OOM выбранного процесса sing-box наблюдался при выключенном авторутинге. На устройствах заявлены OpenWrt/KABANMAX/Tailscale; источник расхода RAM не установлен | kernel OOM context и динамика памяти с известной моделью/настройками; synthetic reproduction, затем отдельно разрешённая полевая приёмка |
| KI-002 · локальное исправление, поле не подтверждено | r23/r24 исправляют EAGAIN, ложную source-альтернативу, checkpoint/withdraw disable paths. Исторический отказ удаления исключений конкретного роутера полностью не воспроизведён | свежий отказ на согласованном комплекте app/core с runtime/source/scope данными; не расширять права ради cleanup |
| KI-003 · не проверено на устройстве | Длительная работа r24, power loss, ARM64 RSS, аппаратная LuCI/theme/Save & Apply и реальные WARP/VPN/NFQUEUE/PBR/mwan3 | отдельное разрешение и зафиксированная аппаратная матрица |
| KI-004 · техническое ограничение | Значимое изменение runtime JSON пересоздаёт core и может закрыть TCP | отдельная реализация/проверка частичного reload; no-op уже обязан оставаться no-op |
| KI-005 · окружение/граница persistence | Default cache и private metadata в `/tmp`/`/var/run` не переживают reboot; периодический flash snapshot может быть старее RAM | не обещать cold restore того, что не сохранялось; [storage](AUTO_ROUTING_STORAGE.md) |
| KI-006 · видимость изменена, сеть не диагностирована | По новому запросу routine `no route to host`/`endpoint not connected` в ConnectionManager и copy/close сообщения понижены до Debug. Первопричины старых потоков по строкам не установлены | изменение уровня не считать исправлением сети; [точный scope](LOGGING.md) |
| KI-007 · отложено | Анимация и TLS ClientHello в трёх записях не реализованы | отдельное согласованное ТЗ и соответствующие проверки |
| KI-008 · не доказано универсальное поведение | Успех контрольного endpoint/протокола не гарантирует работу любого приложения/порта/провайдера; причины всех исторических TLS timeout неизвестны | воспроизведение конкретного flow/protocol и проверка реального evidence |
| KI-009 · документационный предел | Gate проверяет структуру/факты/наличие обновления, не истинность каждого утверждения и не секреты во всей истории | ревью изменяемого кода и подтверждение выводов; [WORKFLOW](WORKFLOW.md) |
| KI-010 · исправлено локально, аппаратно не подтверждено | Info/Trace journal и полный `/connections` усиливали диагностические аллокации. Введены byte/object/input/RPC лимиты и bounded core snapshot; replay VmHWM 26776 → 6064 kB | новый core + backend/LuCI, аппаратная приёмка на 256 МБ и RSS/oom context; прежний KI-001 остаётся открытым. [Замеры и пределы](LOGGING.md) |
| KI-011 · исправлено локально, аппаратно не подтверждено | ULA IPv6 FakeIP классифицируется Chromium как local; пул перенесён в benchmark `2001:2::/112`, согласованы перехват/guards/migration | Edge/Chromium и OpenWrt IPv6 hardware smoke; клиентские cached AAAA могут требовать повторного разрешения. [Контракт](NETWORK_AVAILABILITY.md) |
| KI-012 · operational limit | WAN-log gate использует независимые прямые HTTPS-проверки. Одновременная блокировка обеих контрольных служб может выглядеть как outage при доступности других сайтов; это не доказанный диагноз ISP | аппаратная WAN-loss/PPPoE/DHCP/PBR/mwan3/IPv6-only приёмка; unknown TLS/permission не считать outage. [Проверки и пределы](NETWORK_AVAILABILITY.md) |

Неудачные эксперименты записывать с условиями, командами, результатом и условием пересмотра в тематический отчёт. Не превращать гипотезу DPI/MTU/VPS/Tailscale/OOM в доказанный диагноз.

WARP: исходный отказ r31 подтверждён; в r32 исправлен пропуск включения существующего fresh-port recovery WireGuard. Установленный r33 восстановил второй профиль после отказа без общего restart: новый UDP-порт, ответы и HTTPS YouTube у обоих профилей. Внешняя причина молчания прежнего flow не установлена; многодневная устойчивость и hardware WAN-loss/reboot остаются открыты. Регенерация профиля не требуется. [Текущий разбор](WARP_RECOVERY.md).

Удаление исключений: подтверждённый случай `source_or_scope_not_found` при существующем source вызван посимвольным сравнением spaced ucode JSON с compact Go JSON. Исправлено r31 + backend 0.2.4; real API synthetic reset PASS, все 14 пользовательских записей сохранены. Реальную кнопку Delete пользователь ещё не подтвердил. Это не доказательство обработки любого отсутствующего/выключенного source. [Scope regression](PREVIEW_024.md).

META visibility: принятые source failures получают отдельный Warn с0033; общий refused/no-route остаётся Debug. Локальный0046 уточняет полезность connection Error по контексту/этапу/подсказке, а не одному слову TLS. [Текущий контракт](LOGGING.md).
