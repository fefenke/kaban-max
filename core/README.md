# Изменённое ядро

Исходники зафиксированы в [UPSTREAM](UPSTREAM). Изменения и тесты находятся в [patches/0001-stable-fallback.patch](patches/0001-stable-fallback.patch).

Версия ядра: **1.14.4-r3**.

```sh
bash scripts/build-core.sh base aarch64_cortex-a53 dist/release
```

Скрипт получает точный commit, применяет patch и [переименование](../scripts/brand-core.py), затем запускает builder. Нужны Git, Python 3, Bash, GNU tar, curl, zstd, Go с загрузкой toolchain и apk v3 `mkpkg` для APK.

Для тестов получите исходники из UPSTREAM, примените patch, выполните `go test -race ./protocol/group -run Fallback -count=1`. При распространении бинарников сохраняйте соответствующие исходники и GPL-3.0-or-later.
