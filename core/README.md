# Изменённое ядро

Исходники зафиксированы в [UPSTREAM](UPSTREAM). Изменения и тесты находятся в упорядоченной серии [stable fallback](patches/0001-stable-fallback.patch) и [Chrome 155](patches/0002-chrome155.patch). Источники, отличия профиля и ограничения — в [CHROME155](CHROME155.md).

Версия собираемого ядра: **1.14.4-r9**.

```sh
bash scripts/build-core.sh base aarch64_cortex-a53 dist/release
```

Скрипт получает точный commit, применяет все patches по имени и [переименование](../scripts/brand-core.py), затем запускает builder. Нужны Git, Python 3, Bash, GNU tar, curl, zstd, Go с загрузкой toolchain и apk v3 `mkpkg` для APK.

Для тестов получите исходники из UPSTREAM, примените серию patches и используйте команду с build tags из [CHROME155](CHROME155.md). При распространении бинарников сохраняйте соответствующие исходники и GPL-3.0-or-later.
