# Каталог uTLS

Источник приложения: `shared/tls-fingerprints.json`. Frontend импортирует его напрямую; `scripts/generate-fingerprints.mjs` создаёт `kabanmax/files/usr/lib/singbox/fingerprints.uc`, проверяемый при frontend build. Backend валидирует по этому же каталогу. `tests/core/run_fingerprints.sh` сверяет его с чистым UPSTREAM+patches, настоящими ClientHello, локальным TLS handshake и parser override. Ядро и uTLS ради списка не изменены.

| Выбор | Реальный профиль | REALITY |
| --- | --- | --- |
| Chrome, стандартный | Chrome 133 (`chrome`) | современный key share |
| Chrome, версия 155 | Chrome 155 (`chrome_155`) | современный key share; ограничения ML-DSA/trust anchors из CHROME155.md |
| Firefox | 148 | современный key share |
| Safari | 26.3 | современный key share |
| Edge | 85 | только совместимые старые серверы без обязательного hybrid share |
| iOS | 14 | то же ограничение |
| Android / OkHttp | Android 11 | TLS 1.2, без key share, запрещён для REALITY |
| QQ | 11.1 | только совместимые старые серверы |
| 360 | 7.5 | TLS 1.2, запрещён для REALITY |
| Random | один из Chrome 133 / Firefox 148 / Safari 26.3 на процесс | современный key share |
| Randomized | seeded ClientHello с ALPN, seed на процесс; не номер браузера | современный key share |

`chrome_psk`, `chrome_psk_shuffle`, `chrome_padding_psk_shuffle`, `chrome_pq`, `chrome_pq_psk` в текущем `uTLSClientHelloID` возвращают тот же `HelloChrome_Auto` = 133. Это совместимые старые имена, не пять разных пресетов. Они принимаются при чтении существующих конфигов и не переписываются при no-op, но новым выбором не предлагаются. Список версий появляется только для Chrome, где реально доступны два профиля. Auto/default не выдаётся за произвольную актуальную версию.

Основание: pinned upstream `common/tls/utls_client.go`, `utls_spec.go`, `parser/subscription/tls.go`; patch `0002-chrome155.patch`; закреплённый uTLS-lx `47b8493a47af`, `u_common.go`. Там Edge 106 и 360 11.0 отмечены несовместимыми — их не предлагаем. Другие старые ClientHello библиотека содержит, но текущий sing-box не предоставляет им отдельных runtime-ID. Массовое добавление старых номеров не входит в этот каталог.

## Блокировки

Отпечаток — структура TLS ClientHello, не HTTP User-Agent. Исследования подтверждают фильтрацию по TLS fingerprint/SNI ([USENIX 2023](https://gfw.report/publications/usenixsecurity23/en/)); [OONI по России](https://labs.ooni.io/ru/post/2024-russia-report/) фиксирует в том числе разрыв после ClientHello. Это не сравнительный рейтинг версий Chrome и не доказательство, что 89 проходит там, где не проходит 133. Вывод для проекта: предлагать реально различающиеся проверенные профили, не обещая обход и не выбирая «лучшую» версию без измерений конкретной сети. Возможность отдельных старых версий пересмотреть при воспроизводимом локальном контракте и отдельной полевой задаче с разрешением.
