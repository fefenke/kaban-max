---
layout: home
title: K.A.B.A.N.-MAX
hero:
  name: K.A.B.A.N.-MAX
  text: Маршруты под контролем.
  tagline: When the network says no, the boar says go.
  image:
    src: /kaban-max.png
    alt: K.A.B.A.N.-MAX
  actions:
    - theme: brand
      text: Установить 2.1.0 preview
      link: /guide/install
    - theme: alt
      text: Скачать пакеты
      link: https://github.com/fefenke/kaban-max/releases
features:
  - title: Тихий резерв
    details: Подтверждение отказа вторым HTTPS-адресом и возврат после серии успехов.
    link: /connections/fallback
  - title: Zapret2 внутри LuCI
    details: Отдельные стратегии для секций, установка и обновление официального компонента.
    link: /guide/zapret2
  - title: APK и IPK
    details: Согласованные пакеты, русский интерфейс и контрольные суммы в одном выпуске.
    link: /guide/install
---

**Keepalive-Assisted Backend Arbitration Node — MAX Edition.** Правила маршрутизации, VPN и Zapret2 для OpenWrt.

Первый выпуск — предварительный, для aarch64_cortex-a53. Аппаратная проверка ещё предстоит. Технические имена пакетов и команд остаются `forkop` для совместимости. Основано на наработках Forkop, sing-box и Zapret2; [авторы и лицензии](https://github.com/fefenke/kaban-max/blob/main/CREDITS.md).
