# Applied ошибки и оставшийся Pending — 2026-11-26

Дополнительная диагностика локального r41 по прямому запросу пользователя. Source/device context не выводился и не сохранялся; ниже записи обозначены по роли.

Две записи уже были Applied, `reason=applied_target_failed`: одна через Direct, другая через WARP. Их последние ошибки — `splice read: connection timed out` и `raw read: connection timed out`. Это тайм-аут чтения конкретного соединения, не доказательство полного отказа маршрута или обхода правила. OriginalFailure и последняя Failure сохранены отдельно. Маркер означает зарегистрированный сбой после применения, а не непрерывную неисправность сейчас.

Единственный Pending был inconclusive/no_working_alternative: две попытки Direct и две WARP установили TCP, но не получили требуемый TLS/HTTP результат за5s; AutoApplyEligible=false. Поле tls_verified присваивается после получения HTTP response, поэтому false здесь **не определяет фазу сбоя**. Disabled sources пусты, memory_pressure=false, counts candidates1/decisions1/leases8; других Pending не было.

В00:20МСК26ноября native POST `{"op":"probe","query":EXISTING_CANDIDATE}` повторил проверку в том же сохранённом scope. Direct снова дал два transport failures; WARP получил два TLS-verified HTTP200. Включённый AutoApply сам применил WARP: applied/repeated_transport_failure_alternative_reachable, evidence=alternative_reachable. Ручного Apply, изменения selector или перезапуска не было. После этого native counts candidates0/decisions0/leases9; LuCI projection `diagnostics.auto_records.page` также pending0/applied9.

Пока шла диагностика, native core compact snapshot убрал старый NewError одной Applied записи. RAM diagnostics sidecar вернул его в той же UI projection, которую читает LuCI: обе прежние ошибки по-прежнему видны. Пропажу из core snapshot нельзя выдавать за потерю UI истории.

## Почему не повторилось автоматически

R41 Sweep требует `!attempted`; завершённый неуспешный job оставляет attempted=true. Новый исходный сбой может сбросить флаг, но время само по себе не гарантирует повтор. Поэтому временно неработавшая альтернатива оставляла неподвижный Pending после своего восстановления.

Локальный r42 повторяет **неуспешный web transport check** после прежних5мин: нужны inconclusive/no_working_alternative и transport_failure в последнем решении той же Failure/scope. Сохраняются hourly budget, job lock, source/policy/admission/generation guards. Успешный proposed не повторяется; protocol/policy отказы не включены в новый retry. Прежнее доказательство не очищается ради проверки, ручная кнопка не добавлялась.

UI теперь различает applied_target_failed («Ошибка выбранного маршрута на порту») и generic ошибку без attribution. Для unchanged/zapret_verified: «Исходный маршрут работает; изменение не требуется». Это не меняет routing permissions.

## Границы и проверки

Обычный curl с тем же SNI/IP получил HTTP200, но его router route не выдан за точный Direct outbound. Native DNS API использует Exchange с allowFakeIP=true, WireGuard Lookup — allowFakeIP=false. Один FakeIP ответ DNS API не доказывает FakeIP внутри WARP dial. Native HEAD по имени и exact-IP GET auto probe имеют разные context; расхождение не объявляется установленной причиной WARP outage. Имя MQTT не доказывает отсутствия HTTPS: конкретный повторный WARP probe получил TLS-verified HTTP200.

2026-11-26: `ssh -o BatchMode=yes -o ConnectTimeout=12 root@LOCAL_ROUTER`, `ucode -L /usr/lib/kabanmax -`: GET `/kabanmax/auto`, POST probe только существующего Pending, затем `diagnostics.auto_records.page` для той же source section. Вывод — проекция без source IP/секретов/конфигов. Один результат применился штатным AutoApply во время recheck; служба/профили вручную не менялись, install/reload не было.

`go test -count=1 -tags=badlinkname,tfogo_checklinkname0,with_clash_api,with_utls,with_quic,with_wireguard,with_openvpn ./common/autoroute -run TestFailedTransportCheckRetries` — RED: leases0/calls0 после восстановления альтернативы. После fix full autoroute+group race PASS, затем clean42patches full14packages PASS. Проверяются cooldown, две свежие проверки, отсутствие нового source failure и persistent AllDevices/AllPorts.

Frontend targeted `npx.cmd vitest run src/kabanmax/tabs/sections/tests/autoRouting.test.ts --maxWorkers=2 --reporter=dot`: RED на healthy original label, затем PASS16/16; ESLint/TypeScript/bundle PASS. Полная финальная проверка и установочный статус — [r42](WARP_RUNTIME_FIX.md).
