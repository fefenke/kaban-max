# Текущее состояние проекта

**2026-11-27: опубликован 0.2.3 / core r47, установлен на всех семи заданных устройствах.** FakeIP-refusal — Debug. DNS transition-защита полной установки проверена локально и установлена7/7; exit0, running, SHA/core/UI/module и UCI hashes подтверждены. [Приёмка](FAKEIP_LOG_R47.md).

## Выпуск и локальная приёмка

- **27 ноября, отдельная диагностика двух удалённых устройств:** read-only проверка подтвердила 0.2.3/r46, совпадение SHA ядра/LuCI/DNS guard и running. Больших копий APK/IPK/старого ядра не найдено; различие занятого места связано с составом установленных файлов. Адреса, команды и численные результаты — только в приватном `.local/router-diagnostics-20261127/report.json`. Службы не перезапускались, пакеты не удалялись.
- **SSH-доступ:** перед авторизованной диагностикой читать приватный `.local/router-access.json` и повторно использовать указанный ключ с явным `-i` / `IdentitiesOnly=yes`. Не генерировать новый ключ автоматически при отказе авторизации. Указатель, ключи и адреса не добавлять в Git или release.
- **Последующая отдельная просьба удалить nmap:** штатный `apk del --no-network nmap` после simulate удалил nmap и две неиспользуемые зависимости на одном из проверенных устройств. Освобождено 4968 KiB; пакет, binary и базы отсутствуют, KabanMax running, PID sing-box/Tailscale прежние. Точные before/after и адрес — в том же приватном отчёте. Второе устройство не изменялось.

- Release0.2.3:10APK/IPK приложения/LuCI/RU0.2.3 и base/tiny r47, всего18assets с исходниками r41/r46/r47 и SHA256. Все18 скачаны без авторизации и совпали побайтно; main/tag/release/raw согласованы. Прежние privacy-cleanup теги и выпуски не изменялись.
- Локальный r46 ранее установлен по отдельному запросу: logging, DNS guard, выбираемый confirmation URL. Установка/SHA/UCI/HTTPS прошли; длительная проверка региона и переменчивых WARP timeout остаётся открыта. [Аппаратный scope](LOCAL_R46_INSTALL.md).
- Последняя установка7/7 выполнена по новому прямому разрешению; на одном OPKG target повторена после исправления BusyBox tar. Старые отказы не выдаются за успех. Адреса и сырые данные только в `.local/fakeip-log-r47/`.
- Проверки r47:102backend файла,4Go race packages + executable thresholds,10APK/IPK,9docs tests, BusyBox IPK обоих форматов, failure/recovery/early RAM cleanup. Все6GitHub workflows исходного r47 source af1226d PASS; последующие изменения — installer marker cleanup и документация, без изменения core/UI bytes.

## Факты из исходников

<!-- BEGIN GENERATED PROJECT FACTS -->
| Факт из исходников | Значение |
| --- | --- |
| Upstream | `https://github.com/ushan0v/sing-box-forkop.git` |
| Закреплённый commit | `60d96c99815a672712915a5c00114bf0f690ad80` |
| Версия локального ядра | `1.14.4-r47` |
| Go toolchain | `1.26.10` |
| Количество core patches | 47 |
| Общий minimum core | `1.14.4-r10` |
| Minimum core авторутинга | `1.14.4-r24` |
<!-- END GENERATED PROJECT FACTS -->

## Действующие контракты

- Fallback: успех основного или независимого confirmation URL означает доступность. Два отказа запускают подтверждение и поиск резерва; возврат после серии свежих успехов. Stream-close не запускает health; новый dial/handshake может запустить ограниченную проверку. [Контракт](connections/fallback.md), [история стратегии](FALLBACK_STRATEGY_HISTORY.md).
- WARP: отдельный port hint на профиль, сохранение максимум раз за boot после 10 минут стабильной работы, совпавший порт не перезаписывается. [Контракт](WARP_PORT_HINTS.md).
- Логи: stream/client-handshake — Debug; диагностируемый connect/outbound-handshake — Error с маршрутом, стадией и подсказкой. Warn включает Error и выше. WAN/lifecycle suppression сохраняются. [Контракт](LOGGING.md), [контекст](ACTIONABLE_CONNECTION_LOGS.md).
- Авторутинг: section-wide IP approvals для всех устройств/портов; успешные результаты сохраняются без периодической перепроверки. Protocol-unverified auto-apply — отдельное явное согласие. [Хранение](AUTO_ROUTING_STORAGE.md), [r43](AUTO_ROUTING_R43.md).
- DNS guard удерживает перехватываемые DNS-запросы во время HUP; глобальные DNS/conntrack кэши не очищаются. [Контракт](RELOAD_DNS_PAUSE.md).

Все шесть GitHub workflows r47 source `af1226d` завершились успешно. Core/UI SHA неизменны после финального уточнения installer recovery marker. [Актуальная приёмка](FAKEIP_LOG_R47.md).

## Открыто и ограничения

1. Переменные WARP timeout и региональные отказы требуют длительной проверки на конкретном провайдере; причина не доказана. Успех отдельной HTTPS-пробы не гарантирует доступность любого сайта.
2. Не завершены многодневная приёмка, полное отключение питания, hardware WAN-loss/PBR/IPv6-only и клиентские browser/DNS captures после HUP.
3. Исторический общий OOM при выключенном авторутинге не объяснён. Не приписывать его компоненту без данных. [KNOWN_ISSUES](KNOWN_ISSUES.md).
4. Историческое UI-удаление исключений не воспроизведено на всех устройствах. Локальные regression tests не заменяют этот scope.
5. Перепись истории не удаляет сторонние копии и кэши. Старые clone требуют согласования с обновлённой историей; приватные backups не публикуются.

Навигация: [AGENTS](../AGENTS.md) → [DEVELOPMENT_INDEX](DEVELOPMENT_INDEX.md), текущие команды — [TESTING](TESTING.md), сборка — [BUILD_AND_DEPLOY](BUILD_AND_DEPLOY.md). Исторические отчёты описывают только свой этап и не дают разрешения на новые внешние действия.
