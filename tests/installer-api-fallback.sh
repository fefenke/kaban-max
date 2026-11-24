#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
test_repo=$repo
for fn in release_url asset_url fetch_release read_manifest; do
 source <(sed -n "/^$fn() {/,/^}/p" "$repo/install.sh")
done
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
KABANMAX_REPO=fefenke/kaban-max CORE_REPO=fefenke/kaban-max
API_URL=https://api.github.com MIRROR='' TARGET_TAG='' F_TAG='' C_TAG=''
log(){ :; }; t(){ printf '%s' "$1"; }; fail(){ echo "unexpected failure: $*" >&2; exit 1; }
jsonfilter(){ python3 - "$@" <<'PY'
import json,sys
a=sys.argv; v=json.load(open(a[a.index('-i')+1])); expr=a[a.index('-e')+1]
for k in expr.removeprefix('@.').replace('["','.').replace('"]','').split('.'):
 v=v.get(k) if isinstance(v,dict) else None
if v is not None: print(v)
PY
}
download(){
 case "$1" in
 https://api.github.com/*) return 3;;
 https://raw.githubusercontent.com/fefenke/kaban-max/main/release/*)
  cp "$test_repo/release/${1##*/}" "$2";;
 https://github.com/fefenke/kaban-max/releases/download/0.2.3/*)
  cp "$test_repo/release/${1##*/}" "$2";;
 *) echo "unexpected API fallback URL: $1" >&2; return 1;;
 esac
}
fetch_release kabanmax || exit 1
fetch_release core || exit 1
expected_core=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$test_repo/release/core-release.json")
test "$F_VERSION/$F_TAG/$C_VERSION/$C_TAG" = "0.2.3/0.2.3/$expected_core/0.2.3"
test "$(asset_url core sing-box.apk)" = 'https://github.com/fefenke/kaban-max/releases/download/0.2.3/sing-box.apk'
test "$(asset_url kabanmax SHA256SUMS)" = 'https://github.com/fefenke/kaban-max/releases/download/0.2.3/SHA256SUMS'
TARGET_TAG=0.2.3
fetch_release kabanmax || exit 1
fetch_release core || exit 1
test "$F_TAG/$C_TAG" = '0.2.3/0.2.3'
MIRROR=http://127.0.0.1:18090
test "$(asset_url core sing-box.apk)" = "$MIRROR/fefenke/kaban-max/releases/download/0.2.3/sing-box.apk"
echo 'API quota fallback resolves both raw manifests and pinned public package URLs: PASS'

# Public release redirects bypass the API and use curl when available. Its HTTP
# errors must remain errors, never accept a nonempty error page as a package.
source <(sed -n '/^fetch() {/,/^}/p' "$test_repo/install.sh")
LOG="$WORK/fetch-test.log"
curl(){ printf 'synthetic package' > "$WORK/package"; return "$curl_status"; }
curl_status=0
fetch https://github.com/fefenke/kaban-max/releases/download/0.2.3/test "$WORK/package"
curl_status=22
status=0; fetch https://github.com/fefenke/kaban-max/releases/download/0.2.3/test "$WORK/package" || status=$?
test "$status" = 2
curl_status=28
status=0; fetch https://github.com/fefenke/kaban-max/releases/download/0.2.3/test "$WORK/package" || status=$?
test "$status" = 1
echo 'Public asset transport preserves success, HTTP failure and timeout classification: PASS'
