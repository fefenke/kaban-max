<p align="center"><img src="assets/kaban-max.png" width="300" alt="K.A.B.A.N.-MAX"></p>
<h1 align="center">K.A.B.A.N.-MAX</h1>
<p align="center"><b>When the network says no, the boar says go.</b><br>Keepalive-Assisted Backend Arbitration Node — MAX Edition</p>
<p align="center"><a href="https://fefenke.github.io/kaban-max/">Документация</a> · <a href="https://github.com/fefenke/kaban-max/releases/tag/0.1.1">Скачать 0.1.1</a> · <a href="https://github.com/fefenke/kaban-max/issues">Обратная связь</a></p>

**K.A.B.A.N.-MAX** — управление маршрутами, VPN и Zapret2 на роутере OpenWrt через веб-интерфейс LuCI. Настройте, какие сайты, приложения и устройства используют VPN, Zapret2 или прямое подключение.

## Возможности

- **Маршрутизация по правилам.** Домены, подсети, порты, устройства, встроенные списки сервисов и собственные списки.
- **VPN-подключения.** VLESS/Reality, Shadowsocks, Trojan, Hysteria2, TUIC, WireGuard, OpenVPN и Cloudflare WARP. Импорт ссылок и подписок.
- **Запасные серверы.** Fallback проверяет активное подключение, подтверждает сбой вторым HTTPS-запросом и выбирает доступный резерв по порядку. Возврат — после серии успешных проверок основного.
- **Выбор по задержке.** URLTest выбирает подключение из группы по результатам проверок.
- **Zapret2.** Отдельные стратегии для секций, проверка перед применением, установка и обновление компонента из LuCI.
- **DNS.** Настройка резолверов, DNS по правилам и выбор подключения для DNS-запросов.
- **Панель управления.** Состояние подключений, трафик, диагностика, журналы и обновления компонентов в одном интерфейсе.

## Установка

**0.1.1 · предварительная версия**

| Платформа | Пакеты | Архитектура |
|---|---|---|
| OpenWrt | APK / IPK | `aarch64_cortex-a53` |

Выполните в SSH роутера:

```sh
wget -O /tmp/kabanmax-install.sh https://raw.githubusercontent.com/fefenke/kaban-max/main/install.sh && KABANMAX_RELEASE=0.1.1 sh /tmp/kabanmax-install.sh --variant base --lang ru
```

Установщик подбирает пакеты под роутер и проверяет контрольные суммы. После установки откройте **Службы → K.A.B.A.N.-MAX**.

[Инструкция по установке](docs/guide/install.md) · [Быстрый старт](docs/guide/quick-start.md) · [Скачать пакеты](https://github.com/fefenke/kaban-max/releases/tag/0.1.1)

## Как работает fallback

Пока основной сервер доступен, группа проверяет его и держит резервы в ожидании. При подтверждённом сбое подключения проверяются по порядку до первого доступного.

На резерве основной проверяется с отдельным интервалом — по умолчанию раз в минуту. После трёх последовательных успешных проверок группа возвращается на него. В LuCI видны активное подключение, восстановление и последние переключения.

[Настройка fallback](docs/connections/fallback.md) · [Настройка Zapret2](docs/guide/zapret2.md)

## Разработка

[Сборка и тесты](docs/development.md) · [Изменения](CHANGELOG.md) · [Исходники ядра](core/README.md)

Основано на [Forkop](https://github.com/ushan0v/forkop). Авторы компонентов и лицензии — в [CREDITS.md](CREDITS.md) и [LICENSE](LICENSE).
