"""Check release payloads against source and each other without installing them."""
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tarfile
import tempfile

root = Path(sys.argv[1]).resolve()
repo = Path(__file__).resolve().parent.parent
app = json.loads((root / 'release.json').read_text())
core = json.loads((root / 'core-release.json').read_text())
version = app['version']
assert app['tag'] == core['tag'] == version
assert core['requires']['kabanmax'] == version
assert len(list(root.glob('*.ipk'))) == 5
assert len(list(root.glob('*.apk'))) == 5


def unpack_ipk(path):
    with tarfile.open(path) as archive:
        control = next(m for m in archive if m.name.endswith('control.tar.gz'))
        payload = next(m for m in archive if m.name.endswith('data.tar.gz'))
        with tarfile.open(fileobj=io.BytesIO(archive.extractfile(control).read())) as controls:
            item = next(m for m in controls if m.name.lstrip('./') == 'control')
            metadata = controls.extractfile(item).read().decode()
        with tarfile.open(fileobj=io.BytesIO(archive.extractfile(payload).read())) as files:
            content = {}
            for member in files:
                name = member.name.removeprefix('./')
                parts = PurePosixPath(name).parts
                assert not member.name.startswith('/') and '..' not in parts, name
                assert not any(part in ('.local', '.git', '.env', 'node_modules') for part in parts), name
                assert not name.endswith(('.log', '.pem', '.key')), name
                if member.isfile():
                    content[name] = files.extractfile(member).read()
    return metadata, content


for package in sorted(root.glob('*.ipk')):
    metadata, files = unpack_ipk(package)
    package_name = package.name.split('_')[0]
    is_core = package_name == 'sing-box-kabanmax'
    expected_version = core['version'] if is_core else version
    assert f'Version: {expected_version}\n' in metadata, package.name
    assert f'Architecture: {"aarch64_cortex-a53" if is_core else "all"}\n' in metadata
    if package_name == 'luci-app-kabanmax':
        name = 'www/luci-static/resources/view/kabanmax/main.js'
        source = repo / 'luci-app-kabanmax/htdocs/luci-static/resources/view/kabanmax/main.js'
        expected = source.read_bytes().replace(b'__COMPILED_VERSION_VARIABLE__', version.encode())
        assert files[name] == expected, 'Frontend package differs from source'
    if package_name == 'kabanmax':
        assert 'usr/lib/kabanmax/diagnostics/auto_routing.uc' in files
        assert 'usr/lib/kabanmax/diagnostics/auto_records.uc' in files
        assert 'usr/lib/kabanmax/singbox/fingerprints.uc' in files
    if is_core:
        variant = 'tiny' if '_tiny_' in package.name else 'base'
        binary = root / f'build/arm64/{variant}/sing-box'
        assert files['usr/bin/sing-box'] == binary.read_bytes(), 'Core differs from freshly built binary'
        assert any('license' in name.lower() or 'copying' in name.lower() for name in files)
    with tempfile.TemporaryDirectory() as temp:
        subprocess.run(['apk', 'extract', '--allow-untrusted', '--no-chown', '--destination', temp,
                        str(package.with_suffix('.apk'))], check=True, capture_output=True)
        extracted = {p.relative_to(temp).as_posix(): p.read_bytes() for p in Path(temp).rglob('*')
                     if p.is_file() and not p.is_symlink()}
        for name in list(extracted):
            if name.startswith('lib/apk/packages/'):
                assert name in {f'lib/apk/packages/{package_name}.{suffix}'
                                for suffix in ('list', 'conffiles', 'conffiles_static')}
                del extracted[name]
        assert extracted == files, 'APK/IPK payload mismatch: ' + package.name
    print(package.name + ': payload/source/version/license OK')

records = (root / 'SHA256SUMS').read_text().splitlines()
assert len(records) == 13
for line in records:
    digest, name = line.split('  ', 1)
    assert '/' not in name and '\\' not in name
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
print('All 10 APK/IPK payloads, source substitution, core binaries and 13 SHA256 records: PASS')
