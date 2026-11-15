# Изменённое ядро

## №04Б-ФИНАЛ, 2026-11-16

Добавлен отдельный patch0007 к неизменённому r11/0006: ordinary HTTPS pinned-IP verifier, manual-only evidence, context-bound actual-dial IP и single-address lease guard. Test version остаётся r11, новую сборку отличать по SHA256 в TESTING; audited r11 outputs сохранены. Функция требует все patches0001–0007: старый binary r11 без0007 не поддерживает web mode. [Контракт](../docs/AUTO_ROUTING_IMPLEMENTATION_04B.md).


## Локальное расширение №04Б

`0006-auto-routing.patch` поверх неизменённых patches 0001–0005 добавляет opt-in `route.kabanmax_auto` и authenticated `/kabanmax/auto`. Test package version r11; upstream pin прежний. Default r10 routing/fallback не заменяются. [Контракт verifier/leases и ограничения](../docs/AUTO_ROUTING_IMPLEMENTATION_04B.md). `tests/core/run_auto_routing.sh` проверяет чистое применение patches, race suites и опциональные binary-only сборки. Не использовать scratch `.local` как источник release.


Исходники зафиксированы в [UPSTREAM](UPSTREAM). Изменения и тесты находятся в упорядоченной серии [stable fallback](patches/0001-stable-fallback.patch) и [Chrome 155](patches/0002-chrome155.patch). Источники, отличия профиля и ограничения — в [CHROME155](CHROME155.md).

Версия локального собираемого ядра: **1.14.4-r10** (ещё не выпущено).

ТЗ №03: base binary-only r10 отдельно собран для x86_64/ARM64, r9/dist сохранены. Проверены patches и core race suites, x86_64 executable прошёл mixed DNS/route/fail-closed/FakeIP restart smoke. APK/IPK не собирались, ARM64 не запускался. [Результаты и SHA256](../docs/LIFECYCLE_FALLBACK_03.md).

ТЗ №02 добавляет [изоляцию адресов маршрута](patches/0003-resolved-route-address-isolation.patch), [fail-closed неизвестного provider](patches/0004-unavailable-ruleset-fail-closed.patch) и [границу mixed DNS/FakeIP](patches/0005-mixed-dns-fakeip-boundary.patch). Применять все пять patches по имени к прежнему pinned commit. `response_address_all` — расширение r10; backend отклоняет старый r9. Regression runners: `tests/core/run_startup_dns_devices.sh` и `run_dns_policy.sh`; команды и ограничения — [TESTING](../docs/TESTING.md), архитектура — [ТЗ №02](../docs/STARTUP_DNS_DEVICES_02.md). Релизные пакеты r10 не собирались и не устанавливались.

```sh
bash scripts/build-core.sh base aarch64_cortex-a53 dist/release
```

Скрипт получает точный commit, применяет все patches по имени и [переименование](../scripts/brand-core.py), затем запускает builder. Нужны Git, Python 3, Bash, GNU tar, curl, zstd, Go с загрузкой toolchain и apk v3 `mkpkg` для APK.

Для тестов получите исходники из UPSTREAM, примените серию patches и используйте команду с build tags из [CHROME155](CHROME155.md). При распространении бинарников сохраняйте соответствующие исходники и GPL-3.0-or-later.
