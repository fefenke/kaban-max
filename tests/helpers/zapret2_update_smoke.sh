#!/bin/sh
# Container-only smoke test. Real download, SHA-256, extraction, Lua and atomic activation;
# simulate only OpenWrt's unavailable kernel-package manager. No router or host changes.
set -eu
umask 077
[ -f /.dockerenv ] || { echo 'Run this only in a disposable Docker container' >&2; exit 2; }
[ ! -e /opt/kabanmax-zapret2 ] || { echo 'Expected a fresh container' >&2; exit 2; }
rmdir /opt 2>/dev/null || true
mkdir -p /tmp/zapret2-smoke-bin
cat > /tmp/zapret2-smoke-bin/uclient-fetch <<'EOF'
#!/bin/sh
exec wget "$@"
EOF
cat > /tmp/zapret2-smoke-bin/opkg <<'EOF'
#!/bin/sh
echo 'Smoke test: kernel package already supplied by the container host' >&2
exit 0
EOF
chmod +x /tmp/zapret2-smoke-bin/*
export PATH="/tmp/zapret2-smoke-bin:$PATH"
ucode -L tests/fakes -L tests/lib -L kabanmax/files/usr/lib -e '
let common = require("core.common");
let lock = require("service.lock");
let updater = require("zapret2.updater");
require("fixture").seed({ section: [{ ".name": "legacy", action: "zapret2",
    nfqws2_opt: "--filter-udp=443 --blob=fake_quic:@/opt/zapret2/files/fake/quic_initial_www_google_com.bin --lua-desync=fake:blob=fake_quic" }] });
if (!lock.acquire("/var/run/kabanmax-zapret2-update.lock", common.own_pid())) die("lock failed");
let result = updater.run("install");
print(sprintf("%J\n", updater.status()));
exit(result);
'
test -L /opt/kabanmax-zapret2/current
test -x /opt/kabanmax-zapret2/current/nfq2/nfqws2
test -f /opt/kabanmax-zapret2/current/lua/zapret-antidpi.lua
