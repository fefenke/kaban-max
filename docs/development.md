# Разработка и сборка

## Backend и интерфейс

Нужны Bash, ucode, Node.js 22+, npm. Проверки:

```sh
bash tests/run.sh
cd fe-app-kabanmax
npm ci --ignore-scripts
npm test -- --run --maxWorkers=2
npm run build
```

Каталоги переводов обновляются `node sync-locales.js`, пакет перевода собирается официальным LuCI po2lmo. Не заменяйте конвертер самодельным генератором.

## Полный выпуск

См. `.github/workflows/build.yml` и `scripts/release.Dockerfile`. Сборка выполняется в Alpine с apk v3, GNU tar, Go toolchain и официальным po2lmo.

```sh
docker build -f scripts/release.Dockerfile -t kabanmax-build .
docker run --rm -v "$PWD:/work" -w /work kabanmax-build bash scripts/build-release.sh 0.1.4 /work/dist/release
```

В `dist/release` создаются пакеты backend, LuCI, RU и ядра base/tiny для aarch64_cortex-a53 в форматах IPK/APK, два манифеста, установщик и SHA256SUMS.

Исходный commit ядра закреплён в `core/UPSTREAM`, изменения — в `core/patches/`. Номер `1.14.4-r8` принадлежит этой сборке. Проверка ядра: `go test -race ./protocol/group -run Fallback -count=1` в исходниках с применённым patch.
