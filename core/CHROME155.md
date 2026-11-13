# Chrome 155: источник и перенос

В ядре `1.14.4-r9` добавлен отдельный отпечаток `chrome_155`. Обычный `chrome`, пустое значение и прежние chrome aliases остаются Chrome 133. Автоматической смены существующих подключений нет.

## Закреплённые источники

- Интеграция sing-box-lx: [b506e48883d02e2f8d1d8b25e28707853378da21](https://github.com/Leadaxe/sing-box-lx/commit/b506e48883d02e2f8d1d8b25e28707853378da21).
- Реализация Chrome 155 в uTLS: [c3e674648d81fada5ba497e807c07f53543507a1](https://github.com/Leadaxe/utls-lx/commit/c3e674648d81fada5ba497e807c07f53543507a1), перенесённая из refraction-networking/utls.
- Выбранное состояние uTLS-lx: [47b8493a47afa6d884701a0205950524f5c8ed87](https://github.com/Leadaxe/utls-lx/tree/47b8493a47afa6d884701a0205950524f5c8ed87). В нём восстановлен Chrome 133 для `HelloChrome_Auto`; последующие изменения API освобождения handshake state не включены.
- Точная версия, разрешённая Go: `github.com/Leadaxe/utls-lx v1.8.8-0.20261008181611-47b8493a47af`. Контрольные суммы записаны в patch `go.sum`.
- [Исходный профиль и таблицы](https://github.com/Leadaxe/utls-lx/blob/47b8493a47afa6d884701a0205950524f5c8ed87/u_parrots.go), [тесты захваченного ClientHello](https://github.com/Leadaxe/utls-lx/blob/47b8493a47afa6d884701a0205950524f5c8ed87/u_chrome155_test.go), [происхождение эталонного захвата](https://github.com/Leadaxe/utls-lx/blob/47b8493a47afa6d884701a0205950524f5c8ed87/testdata/chrome155_clienthello.md).

Наш sing-box upstream остаётся прежним, `60d96c99815a672712915a5c00114bf0f690ad80`. Полный sing-box-lx не подменяет ядро. Изменения оформлены отдельным [0002-chrome155.patch](patches/0002-chrome155.patch), следующим за stable-fallback patch. В зависимости также присутствуют изменения Firefox/Safari из этой ревизии; собственные пресеты ядра и существующие регрессии этих браузеров сохранены и проверены.

## Что меняется в ClientHello

| Поле | Chrome 133 → Chrome 155 |
| --- | --- |
| Signature algorithms | перед прежними алгоритмами добавлены GREASE и MLDSA44/65/87, коды `0904`, `0905`, `0906` |
| Trust anchors | новое расширение `ca34`, 28 упорядоченных идентификаторов Chrome Root Store |
| Генерация GREASE | отдельный seed для signature algorithms; одного переименования ClientHelloID недостаточно |
| Cipher suites и версии | сохранены; TLS 1.3 / TLS 1.2 |
| ALPN / ALPS | сохранены `h2`, `http/1.1`; ALPS `17613` для `h2` |
| ECH и сжатие сертификатов | прежний GREASE-ECH и Brotli |
| Groups / key shares | GREASE, X25519MLKEM768 перед X25519; размеры ключей 1216 и 32 байта |
| Порядок extensions | Chrome shuffle сохраняется, новое расширение участвует в перемешивании |

Это исходящий TLS ClientHello. Профили AWG `ib=chrome` / `chrome-full` — отдельный генератор ложного QUIC-пакета, здесь не переносились. HTTP User-Agent и полный стек Chrome эта настройка не подменяет.

## Использование

В параметрах клиента сервера можно выбрать `chrome_155`; при экспорте ссылки сохранится `fp=chrome_155`. Парсер ссылок/подписок понимает это значение и не заменяет его на обычный Chrome.

В JSON outbound:

```json
"tls": {
  "enabled": true,
  "utls": { "enabled": true, "fingerprint": "chrome_155" }
}
```

Нужно ядро r9: r8 не знает этого идентификатора. Минимальная версия в backend и manifests согласована с `core/UPSTREAM`. По умолчанию в интерфейсе по-прежнему выбирается `chrome`.

## Ограничения и совместимость

Профиль объявляет ML-DSA, но закреплённая реализация uTLS не поддерживает проверку ML-DSA CertificateVerify. Если сервер выберет такую подпись, handshake завершится ошибкой. Сборка Go 1.26.10 это не исправляет; полная поддержка требует дополнительных изменений TLS-реализации, связанных с Go 1.27. Проверка сертификатов не отключается.

Trust-anchor hints не меняют системные RootCAs. Сервер, понимающий эти подсказки, может выбрать цепочку, которой нет в доверенных корнях клиента. ClientHello также немного больше, чем у 133; улучшение доступности или прохождения DPI не гарантируется.

REALITY сохраняет hybrid key share по умолчанию. Явный классический режим удаляет его из supported groups и key shares и тем самым меняет отпечаток; новые серверы REALITY могут отказать. Разбиение ClientHello на две TLS-записи также остаётся отдельной настройкой. Локальный тест захватывает настоящий ClientHello REALITY через `net.Pipe`, проверяет новый профиль, key shares и количество записей; это не проверка успешной аутентификации с живым Xray.

В исходном LX [SPEC 118](https://github.com/Leadaxe/sing-box-lx/blob/4cd72d95f95bfe41e518ea5ee1512a6bff8f7130/SPECS/TASKS/118-UTLS_CHROME_155/SPEC.md) отдельно указано отсутствие полевой проверки этого профиля с REALITY и обычным TLS. Проверки на живых роутерах/VPS в этой задаче также не выполнялись.

## Проверки переноса

Новые тесты сначала воспроизвели отсутствие идентификатора и потерю значения в subscription parser. После переноса прошли:

- uTLS: Chrome 155 против браузерного эталона, сохранение 133, trust anchors, GREASE seed, ML-DSA codes и совместимость публичного GREASE API.
- Go race: 13 пакетов TLS, парсеров, fallback/reload и fragmentation; `parser/xhttp` не содержит тестов.
- Реальный ClientHello через собственный `newUClient`: signature prefix, trust anchors, один hybrid перед одним X25519; REALITY и record-fragment варианты через локальный pipe.
- Frontend 170 файлов / 1616 тестов, lint и TypeScript/tsup; backend 84/84.
- Чистая сборка из публичного pinned upstream + оба patches: ARM64 base/tiny, по APK и IPK. В build-info подтверждена именно закреплённая uTLS-lx; IPK payload совпал с собранным бинарником, версия r9 и BSD-лицензия присутствуют.

uTLS имеет BSD-лицензию; её исходный текст добавлен в patch и устанавливается в `/usr/share/licenses/sing-box/utls-lx.LICENSE`. Ядро по-прежнему GPL-3.0-or-later. Пакеты ARM64 base/tiny поставляются в APK/IPK; проверки на действующем оборудовании не выполнялись.

После применения серии patches локальные Go-проверки выполняются командой:

```sh
go test -race -p=2 -tags=badlinkname,tfogo_checklinkname0,with_utls,with_clash_api,with_quic,with_wireguard,with_openvpn ./cmd/sing-box ./parser/... ./protocol/parser ./protocol/group ./common/tls ./common/tlsfragment
```

Поле `tls_fingerprint` отдельной записи подключения применяется после разбора URI к TLS/uTLS outbound. Пустое поле наследует значение URI; неподдерживаемые значения, соединения без TLS и QUIC отклоняются. Привязка использует постоянный ID записи, а не имя сервера.
