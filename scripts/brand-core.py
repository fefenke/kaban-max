#!/usr/bin/env python3
"""Brand a pinned, patched source tree before compiling or running its tests."""
from pathlib import Path
import re, sys
root=Path(sys.argv[1]).resolve()
def renamed(s):
    return s.replace('FORKOP','KABANMAX').replace('Forkop','KabanMax').replace('forkop','kabanmax')
for path in sorted(root.rglob('*'),key=lambda p:len(p.parts),reverse=True):
    if '.git' in path.relative_to(root).parts or not path.is_file():
        continue
    data=path.read_bytes()
    if b'\0' not in data:
        try:
            text=data.decode('utf-8')
            saved=[]
            def protect(match):
                saved.append(match.group());return f'@@UPSTREAM{len(saved)-1}@@'
            text=re.sub(r'ushan0v/(?:sing-box-)?forkop(?:-lists)?',protect,text)
            text=renamed(text)
            for i,value in enumerate(saved):text=text.replace(f'@@UPSTREAM{i}@@',value)
            data=text.encode()
        except UnicodeDecodeError:
            pass
    destination=root/renamed(path.relative_to(root).as_posix())
    if not destination.resolve().is_relative_to(root):raise ValueError('Invalid output path')
    destination.parent.mkdir(parents=True,exist_ok=True)
    mode=path.stat().st_mode
    destination.write_bytes(data)
    destination.chmod(mode)
    if destination!=path:path.unlink()
for path in sorted(root.rglob('*'),key=lambda p:len(p.parts),reverse=True):
    if '.git' in path.relative_to(root).parts or not path.is_dir():continue
    try:path.rmdir()
    except OSError:pass
