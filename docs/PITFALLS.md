# Ловушки, которые нельзя повторять

Короткая справка по неочевидным ограничениям. История экспериментов — в [архиве](archive/README.md); правила безопасности — [SECURITY](SECURITY.md).

## Авторутинг

- `syscall.EAGAIN.Timeout()` может вернуть true: EAGAIN/EWOULDBLOCK проверять **до** `net.Error.Timeout()`. Настоящий timeout не отбрасывать.
- Snapshot может устареть до withdrawal. Отсутствующий lease для известной source уже отозван; это не повод выключить source.
- Не смешивать ошибку private checkpoint с потерей сохранённого intent. Не снимать fail-closed при настоящем отказе записи/отзыва grants.
- Запись flash не освобождает действующие маршруты в RAM. Pressure считать по dirty bytes; unchanged/diagnostic-only не должны писать flash.
- Не сериализовать весь retained registry на каждом успешном flow. Учитывать in-flight context, инвалидировать cached accounting при мутации, не скрывать свежую applied-route ошибку из-за возраста grant.
- Страница не должна передавать все private members/selection. Bulk ищет ID за первой сотней с тем же source/filter и повторно проверяет scope.
- Старые лимит 64, manual-only и TTL-утверждения читать в контексте версии, не копировать в r24. [Контракт](AUTO_ROUTING_STORAGE.md).

## UI и конфигурация

- LuCI `disabled="false"` и `hidden="false"` всё равно означают установленные HTML-атрибуты. Для boolean использовать DOM properties.
- Новые default-поля не должны создавать UCI diff при no-op Save. Проверять round-trip, unsaved values и скрытые поля.
- URI-редактор изменяет только затронутые компоненты. Не переписывать неизвестные query/fragment, regex или скрытые виртуальные поля в UCI.
- Точные include/exclude ссылки Fallback/URLTest следуют rename/delete; regex не является ID-ссылкой.
- Генерируемый LuCI bundle и fingerprint `.uc` не править вручную; UI, RU/POT и backend должны совпадать с source.

## Сеть, сборка и проверки

- Domain match одного DNS address не разрешает Direct для siblings. Pending remote ruleset не означает пустой разрешающий список.
- WARP profile API detour не равен traffic detour. Автоматическая регистрация тоже должна получать выбранный API detour.
- Не ставить TLS override на всю группу; поддерживаемый fingerprint доказывается wire/parser тестами.
- `.local/core-src` не заменяет pinned upstream + patches. Для нового patch проверять clean apply и runner/CI, включающие нужные тесты.
- Отсутствие ucode/Go/Docker или отказ доступа — не успешный тест. В Windows использовать `npm.cmd` при блокировке PowerShell script shim; не менять ExecutionPolicy глобально.
- `git` и Docker могут работать под разными identity/permissions. Не исправлять это глобальным safe.directory ради задачи; запускать нужную проверку в подходящем контексте.
- Проверка только serialized bytes не доказывает RSS или отсутствие общего OOM. Локальный compile check не является выпуском или hardware smoke.

Документация тоже может устареть: [WORKFLOW](WORKFLOW.md), [проверка](../scripts/check-project-docs.py).
