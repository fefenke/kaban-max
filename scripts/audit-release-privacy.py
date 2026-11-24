#!/usr/bin/env python3
"""Offline release-tree/payload privacy check. Reports locations, never secret values."""
import argparse
import io
import json
import re
import shlex
import subprocess
import tarfile
from pathlib import Path

MARKERS = [b"co" + b"dex", b"open" + b"ai", b"co-authored" + b"-by"]
EMAIL = re.compile(rb"[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})")
TOKEN = re.compile(rb"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16})")
LOCAL = re.compile(rb"(?i:[A-Z]:[/\\]Users[/\\][A-Za-z0-9_.-]+)|/home/[a-z0-9_.-]+")

def sources(root):
    result = subprocess.check_output(["git", "-c", "safe.directory="+str(root), "-c", "core.quotepath=false", "ls-files", "-c", "-o", "--exclude-standard"], cwd=root, text=True)
    for name in sorted(set(result.splitlines())):
        path = root / name
        if path.is_file():
            yield name, path.read_bytes()

def payloads(directory):
    for package in sorted(directory.glob("*.ipk")):
        with tarfile.open(package) as outer:
            for part in ("control.tar.gz", "data.tar.gz"):
                member = next(m for m in outer if m.name.endswith(part))
                with tarfile.open(fileobj=io.BytesIO(outer.extractfile(member).read())) as inner:
                    for item in inner:
                        if item.isfile():
                            yield f"{package.name}:{item.name}", inner.extractfile(item).read()
    for name in ("release.json", "core-release.json", "install.sh", "SHA256SUMS"):
        path=directory/name
        if path.is_file():yield path.name,path.read_bytes()

def private_needles(paths):
    result=set()
    for path in paths:
        words=shlex.split(path.read_text(encoding="utf-8"),comments=True)
        for i,word in enumerate(words[:-2]):
            if word=="option" and re.search(r"(?:password|auth_token|private_key|uuid|secret|license_key|token)$",words[i+1]) and len(words[i+2])>=16:
                result.add(words[i+2].encode())
    return result

def inspect(name,data,needles,public_test_material,public_email=None):
    findings=[]
    for marker in MARKERS:
        if marker in data.lower():findings.append("unwanted_tool_marker")
    if TOKEN.search(data):findings.append("credential_token")
    for match in LOCAL.finditer(data):
        if match.group().decode().rsplit('/',1)[-1] not in {"u","user","runner","example","test"}:findings.append("local_user_path")
    for match in EMAIL.finditer(data):
        import hashlib
        payload_path=name.partition(':')[2].lstrip('./') if ':' in name else name
        if hashlib.sha256(match[0]).hexdigest() in (public_email or {}).get(payload_path,[]):continue
        domain=match[1].decode().lower()
        if domain in {"example.com","example.org","example.net","github.com","users.noreply.github.com"} or domain.endswith((".test",".invalid",".example",".example.com",".example.org",".example.net")):
            continue
        findings.append("review_email")
    if any(needle in data for needle in needles):findings.append("private_reference_match")
    # Symbolic PEM delimiters used in validation/masking tests are not key material.
    if re.search(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",data):
        normalized=data.replace(b"\r\n",b"\n").replace(b"\\n",b"\n")
        for block in re.findall(rb"-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----",normalized,re.S):
            import hashlib
            if re.search(rb"[A-Za-z0-9+/]{64,}",block) and hashlib.sha256(block).hexdigest() not in public_test_material.get(name,[]):findings.append("private_key_material")
    return [{"path":name,"category":kind} for kind in sorted(set(findings))]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root",type=Path,default=Path.cwd())
    parser.add_argument("--packages",type=Path)
    parser.add_argument("--private-reference",type=Path,action="append",default=[])
    parser.add_argument("--report",type=Path)
    args=parser.parse_args()
    needles=private_needles(args.private_reference)
    allow_path=args.root/'tests/fixtures/public-test-material.json'
    reviewed=json.loads(allow_path.read_text(encoding='utf-8')) if allow_path.is_file() else {}
    public_test_material=reviewed.get('pem_sha256',{})
    findings=[];count=0
    for name,data in sources(args.root.resolve()):
        findings.extend(inspect(name,data,needles,public_test_material));count+=1
    if args.packages:
        for name,data in payloads(args.packages):
            findings.extend(inspect(name,data,needles,{},reviewed.get('public_upstream_email_sha256',{})));count+=1
    result={"checked_files":count,"private_reference_values_checked":len(needles),"findings":findings}
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(result,ensure_ascii=False))
    return bool(findings)

if __name__=="__main__":raise SystemExit(main())
