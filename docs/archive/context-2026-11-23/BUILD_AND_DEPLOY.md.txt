# Сборка, установка и откат

## Источник
Работать из корня KABANMAX. Node.js 22+, npm, Python 3, Bash/Git; backend tests требуют ucode. Полный packaging: Alpine apk v3/mkpkg, GNU tar/zstd, Go toolchain и официальный LuCI po2lmo. `scripts/release.Dockerfile` закрепляет базовый образ и source po2lmo; Go version/commit ядра — в `core/UPSTREAM`.

```sh
cd fe-app-kabanmax
npm ci --ignore-scripts --no-audit --no-fund
npm run lint
npm test -- --run --maxWorkers=2
npm run build
cd ..
bash tests/run.sh
```

Для документации: `cd docs && npm ci --ignore-scripts && npm run build`. Это локальные сборки; скачивание зависимостей обращается к реестрам, но не к роутерам/VPS.

`release.Dockerfile` предназначен для packaging и не устанавливает интерпретатор ucode: backend-тесты требуют отдельного локального окружения с ucode и его модулями. Не считать отсутствие интерпретатора успешным пропуском тестов. Для Intl-тестов Node необходимы полные ICU-локали (`icu-data-full` в Alpine); текущий Dockerfile их устанавливает, старый кэшированный образ может отличаться.

## Пакеты
```sh
docker build -f scripts/release.Dockerfile -t kabanmax-build .
docker run --rm -e GOFLAGS=-p=2 -v "$PWD:/work" -w /work kabanmax-build   bash scripts/build-release.sh 0.1.4 /work/dist/release
bash scripts/check-release.sh dist/release
```

В PowerShell путь bind передавать отдельным аргументом, например `--mount "type=bind,source=$($PWD.Path),target=/work"`. Не использовать старый контейнер с mount соседнего checkout.

Core build получает точный upstream commit, применяет все `core/patches/*.patch` в порядке имён, затем `brand-core.py`. `CORE_SOURCE` — необязательный локальный Git-источник для объектов, всё равно checkout pinned commit + всю серию patches. Нужен доступ к upstream/Go modules при отсутствии кэша. Пакеты base/tiny, app/LuCI/RU в APK/IPK, manifests, install.sh, SHA256SUMS — содержимое выпуска. Внутренний package version ядра не равен версии приложения. Для r9 добавлен закреплённый uTLS-lx; точная версия/checksums находятся во втором patch, лицензия входит в пакет.

## Подготовка исходников ядра для разработки
```sh
git clone <repository-из-core/UPSTREAM> .local/core-clean
git -C .local/core-clean checkout --detach <commit-из-core/UPSTREAM>
for patch in "$PWD"/core/patches/*.patch; do
  git -C .local/core-clean apply --check "$patch"
  git -C .local/core-clean apply "$patch"
done
```
Угловые значения — обозначения, не готовая команда. Отсчитывать patch относительно `git -C` каталога. Локальный `.local/core-src` сохранён как рабочая история и проверяется отдельно.

## Установка/обновление — только отдельным действием
Пользовательские инструкции: [установка](guide/install.md). На целевом устройстве определить OpenWrt, архитектуру, opkg/apk и свободное место; использовать соответствующие пакеты. Через LuCI «Компоненты» проверить обновление и установить выбранную версию. На 0.1.0 без новой кнопки возможен ручной установщик. Конфигурация устройства не должна копироваться с другого роутера ради обновления приложения.

До изменения сохранить собственную конфигурацию и известные рабочие пакеты; при отказе вернуть согласованный комплект app/UI/core и собственный конфиг. Пакетный downgrade и несовместимость схем требуют отдельной проверки; наличия старого APK недостаточно. Возврат локальной реорганизации описан в [аудите](ISOLATION_AUDIT.md).

Публикация: только по явному запросу; проверить metadata версии, prerelease, checksums и исходники GPL. Не загружать `.local`, весь dist или исследовательский архив. Публикация пакетов не означает установку на оборудование.
