# Late-DNS fix в существующем выпуске 0.2.3

Пользователь разрешил исправление и публикацию под тем же номером. **К роутерам не подключаться, не устанавливать; выдать команды для самостоятельного обновления с ПК.** Один исполнитель, без агентов. История/tag сохраняются; source hotfix commit указывается в release notes.

1. Перенести диагностический RED в regression: domain→исходный resolver→конкретный IP→Applied. Проверить serial/parallel, соседний IP, exclusions, DNS failure и attribution ошибок.
2. Добавить узкий per-call resolver wrapper в pinned patch0041. Сохранить DNS options, timers, interface policy; DNS-transport не должен наследовать observation приложения.
3. Исправить подпись applied_route_bypassed и её сохранение в bounded RAM sidecar; source/target diagnostics различать после restore.
4. Подключить тесты к runners/CI. Executable acceptance проверить без предварительного resolve action. Выполнить подходящие Go race, backend, frontend/build/localization и packaging проверки.
5. Версия приложения остаётся0.2.3; core revision=r41. Собрать base/tiny ARM64, GPL source, backend/LuCI/RU APK/IPK, manifests/SHA256. Сверить payload/source, privacy и точные assets.
6. Обновить текущий контракт/состояние; doc gate. Опубликовать main и файлы существующего release0.2.3, не переписывая tag. Проверить remote digests и CI.
7. Дать PowerShell/SSH команды: свежий main bootstrap, explicit pin0.2.3 + reinstall, несколько роутеров последовательно, штатный restart установщика с независимым launcher и сохранённым exit/log.

Приёмка не включает аппаратный restart/установку, стабильность WARP или утверждение об исправлении исторической WARP задержки.

Все7шагов завершены: local и remote executable PASS, все6CIjobs success,16release assets проверены, raw catalog обновлён до r41. Команды docs/UPDATE_023.md подготовлены и проверены синтаксически; на роутерах не исполнялись. Сохранены tag/history, публичные source/packages проходят privacy gate.
