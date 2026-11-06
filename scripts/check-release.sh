#!/usr/bin/env bash
# Check the actual publishable directory, using the installer's checksum parser.
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:?Release directory required}"
source <(sed -n '/^checksum_of() {/,/^}/p' "$repo/install.sh")
for file in "$output"/*.apk "$output"/*.ipk "$output"/install.sh "$output"/release.json "$output"/core-release.json; do
    test -s "$file"
    expected="$(checksum_of "${file##*/}" "$output/SHA256SUMS")"
    actual="$(sha256sum "$file")"
    test -n "$expected" && test "$expected" = "${actual%% *}"
done
(cd "$output" && sha256sum -c SHA256SUMS)
python3 - "$output" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); app=json.loads((p/'release.json').read_text()); core=json.loads((p/'core-release.json').read_text())
assert app['tag']==core['tag']
assert app['requires']['sing-box-kabanmax']==core['version']
assert core['requires']['kabanmax']==app['version']
for ext in ('apk','ipk'):
 for name in ('kabanmax','luci-app-kabanmax','luci-i18n-kabanmax-ru'):
  assert (p/f"{name}_{app['version']}_all.{ext}").is_file()
 for variant in ('base','tiny'):
  assert (p/f"sing-box-kabanmax_{core['version']}_{variant}_aarch64_cortex-a53.{ext}").is_file()
print('Release manifests, required assets and installer checksum lookup: OK')
PY
