# Разработка и сборка

Проект содержит TypeScript/LuCI интерфейс, ucode backend и собственные patches sing-box. Версия приложения задаётся сборкой; исходный commit, toolchain и версия ядра закреплены в `core/UPSTREAM`. Не подставляйте старые номера из примеров как актуальный выпуск.

## Локальные проверки

Из корня, в окружении с Bash/ucode:

```sh
bash tests/run.sh
```

Из `fe-app-kabanmax`, Node.js 22+:

```sh
npm ci --ignore-scripts --no-audit --no-fund
npm test -- --run --maxWorkers=2
npm run build
```

Каталоги переводов обновляются `node sync-locales.js`; binary translation собирается официальным LuCI po2lmo. Новые строки должны иметь перевод, generated bundle менять через source build.

## Продолжение разработки

Для нового чата/разработчика откройте [AGENTS в репозитории](https://github.com/fefenke/kaban-max/blob/main/AGENTS.md), затем PROJECT_STATE и DEVELOPMENT_INDEX из `docs/`. Инженерные документы отдельно описывают невыпущенные изменения и границы локальных проверок.

Полная упаковка выполняется по `.github/workflows/build.yml` и `scripts/release.Dockerfile`. Используются pinned upstream + все patches + branding, а не произвольный приватный checkout. Выберите согласованную версию приложения и проверьте packages/manifests/SHA256. Сборка не устанавливает приложение на устройство; установка и публикация требуют отдельного решения.
