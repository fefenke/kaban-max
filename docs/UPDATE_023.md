# Повторное обновление 0.2.3 с компьютера

Hotfix сохраняет номер приложения0.2.3, ядро обновляется до1.14.4-r41. Нужны SSH root-доступ, Windows OpenSSH (`ssh`, `scp`) и PowerShell. Примеры адресов ниже заменить своими. Установщик сохраняет настройки и использует прежний вариант ядра; `KABANMAX_REINSTALL=1` вместе с pin0.2.3 обновляет backend/LuCI/перевод того же номера. Не отключать проверку SSH host key.

Команды вставляются **в окно PowerShell**; изменение ExecutionPolicy не требуется. Скрипт установщика скачивается на ПК, передаётся legacy SCP (`-O`, без требования sftp-server) и запускается через setsid независимо от SSH-сеанса. Установщик сам перезапускает KabanMax. Во время этого связь может прерваться; не запускать параллельно другую установку на том же роутере.

```powershell
$routers = @('192.0.2.1', '198.51.100.1') # адреса ваших роутеров
$id = [Guid]::NewGuid().ToString('N')
$file = Join-Path ([IO.Path]::GetTempPath()) "kabanmax-$id.sh"
$prefix = "/tmp/kabanmax-pc-$id"
Invoke-WebRequest -UseBasicParsing 'https://raw.githubusercontent.com/fefenke/kaban-max/main/install.sh' -OutFile $file
$launch = 'command -v setsid >/dev/null 2>&1 || exit 1; setsid sh -c ''KABANMAX_RELEASE=0.2.3 KABANMAX_REINSTALL=1 sh __P__.sh --lang ru --quiet >__P__.log 2>&1; result=$?; echo $result >__P__.exit; rm -f __P__.sh'' </dev/null >/dev/null 2>&1 &'
try {
    foreach ($router in $routers) {
        scp -O -o ConnectTimeout=15 $file "root@${router}:$prefix.sh"
        if ($LASTEXITCODE -ne 0) { Write-Warning "Не загружен установщик: $router"; continue }
        ssh -o ConnectTimeout=15 "root@$router" ($launch.Replace('__P__', $prefix))
        if ($LASTEXITCODE -ne 0) { Write-Warning "Проверьте запуск: $router" }
    }
} finally {
    Remove-Item -LiteralPath $file -Force
}
```

Через1–2минуты в **том же окне** проверить каждый роутер:

```powershell
foreach ($router in $routers) {
    Write-Host "=== $router ==="
    ssh -o ConnectTimeout=15 "root@$router" "if test -f $prefix.exit; then cat $prefix.exit; else echo RUNNING_OR_NOT_STARTED; fi; tail -n 15 $prefix.log"
}
```

Код0 и сообщение об успешном запуске означают завершённую установку. Если exit ещё нет, посмотреть журнал и повторить проверку позже. При ненулевом коде сохранить журнал и выяснить ошибку перед повторным запуском. Отсутствие SSH-связи само по себе не доказывает провал установки.

После завершения можно проверить `ssh root@АДРЕС '/usr/bin/sing-box version; /etc/init.d/kabanmax status'`: ядро должно быть1.14.4-r41, служба running. Небольшие `.log`/`.exit` находятся только в `/tmp`; после проверки их можно удалить по точному сохранённому `$prefix`. Конфиг и checkpoints не удалять.

Эти команды подготовлены и проверяются локально. Автор исправления не запускал их на роутерах после запрета пользователя; аппаратная приёмка нового r41 выполняется пользователем.
