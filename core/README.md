# Изменённое ядро

Исходники зафиксированы в [UPSTREAM](UPSTREAM). Изменения и тесты находятся в [patches/0001-stable-fallback.patch](patches/0001-stable-fallback.patch).

Версия **1.14.4-r2**, имя пакета `sing-box-forkop`. Это сборка K.A.B.A.N.-MAX, а не официальный выпуск upstream с таким номером.

```sh
bash scripts/build-core.sh base aarch64_cortex-a53 dist/release
```

Скрипт получает точный commit, проверяет и применяет patch, запускает upstream builder. Нужны Git, Bash, GNU tar, curl, zstd, Go с загрузкой toolchain и apk v3 `mkpkg` для APK. Для full нужны дополнительные инструменты NaiveProxy; готовые full пока не публикуются.

Для тестов получите исходники из UPSTREAM, примените patch, выполните `go test -race ./protocol/group -run Fallback -count=1`. При распространении бинарников сохраняйте соответствующие исходники и GPL-3.0-or-later.
