# Реестр действующих решений

Это текущие решения и условия их пересмотра. Подробная прежняя хронология сохранена в [архиве](archive/README.md). Новый значимый выбор получает устойчивый ID и запись «контекст → решение → последствия → доказательство → условие пересмотра».

| ID | Решение и причина | Доказательство / контракт | Пересмотр |
| --- | --- | --- | --- |
| ADR-001 | Один ассистент без агентов, `resource budgeting`; уменьшать повторные чтения и лишние проверки по прямому требованию пользователя | [AGENTS](../AGENTS.md), [WORKFLOW](WORKFLOW.md) | только новое явное указание пользователя |
| ADR-002 | Один текущий источник фактов, отдельная история; CI проверяет пути/версии и наличие doc update при source change | [WORKFLOW](WORKFLOW.md), [аудит](DOCUMENTATION_AUDIT.md) | измеренный пробел/ложное срабатывание проверки |
| ADR-003 | Ядро: pinned upstream + упорядоченные patches + branding; приватный checkout не источник выпуска | [BUILD_AND_DEPLOY](BUILD_AND_DEPLOY.md), `core/UPSTREAM` | воспроизводимый согласованный переход upstream |
| ADR-004 | Fallback подтверждает сбой/возврат по свежему evidence конкретного outbound; TCP connect недостаточен | [NETWORKING](NETWORKING.md), core tests | воспроизведение нарушения контракта |
| ADR-005 | TLS-параметры и fingerprint относятся к конкретному серверу, каталог вариантов имеет один источник | [FINGERPRINTS](../core/FINGERPRINTS.md), [CHROME155](../core/CHROME155.md) | новая доказанная поддержка ClientHello/parser |
| ADR-006 | DNS/route/nft согласованы: per-address isolation, FakeIP, unknown ruleset fail-closed, сохранение чужих mark | [сеть](NETWORKING.md), [DNS evidence](STARTUP_DNS_DEVICES_02.md) | независимый воспроизводимый конфликт |
| ADR-007 | Регистрация WARP использует core detour; profile API и traffic transport независимы | [сеть](NETWORKING.md), generator WARP tests | timeout с доказанно правильным detour |
| ADR-008 | Авторутинг error-first, source-owned; не глобальные connections/stall/DNS догадки | [№2–4](AUTO_ROUTING_FIELD_ERRORS.md), [storage](AUTO_ROUTING_STORAGE.md) | отдельный доказанный источник атрибуции без расширения доступа |
| ADR-009 | Отзыв отсутствующего grant идемпотентен; private checkpoint не отменяет уже сохранённый intent | [field fixes](AUTO_ROUTING_FIELD_ERRORS.md) | доказанный конфликт ownership/надёжного отзыва |
| ADR-010 | Авторутинг: компактный RAM-реестр, byte budget, очистка диагностики, dirty-only flash `1d`; потеря несохранённого при power loss принята | [storage r24](AUTO_ROUTING_STORAGE.md) | измеренный рост payload, нарушение restore/checkpoint или новый запрос пользователя |
| ADR-011 | JSON reload может закрывать TCP; no-op Save не должен перезапускать core | [архитектура](ARCHITECTURE.md), [lifecycle](LIFECYCLE_FALLBACK_03.md) | отдельная задача частичного reload |
| ADR-012 | Приватный журнал в tmpfs bounded по времени/размеру, не долговечный flash-log | [ARCHITECTURE](ARCHITECTURE.md), journal tests | доказанная потеря между сборами/новое требование хранения |

Статусы здесь — принятые правила, а не разрешения на внешние действия. Исторические D13 с разными значениями не переиспользовать как новые ID.
