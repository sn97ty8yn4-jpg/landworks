#!/usr/bin/env python3
"""Download pinned MIT Godot vehicle addons; standalone Windows Python 3.9+.

No downloads are performed simply by opening the Godot project.
This script is run explicitly by the user and does not overwrite existing addons.
"""
from __future__ import annotations
import argparse
from pathlib import Path, PurePosixPath
from urllib.request import Request, urlopen
import io
import zipfile
import hashlib
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
VENDORS = {
    'gevp': {
        'repository': 'DAShoe1/Godot-Easy-Vehicle-Physics',
        'commit': 'c392257f54f6ca537dc10bc5badad0c060f18982',
        'addon': 'gevp',
        'license': 'LICENSE',
    },
    'kv': {
        'repository': 'Kurtzmusch/kv-vehicle',
        'commit': 'e37b7ea335a45a2f6d220a4fea3603a248aaac08',
        'addon': 'kv-vehicle',
        'license': 'LICENSE.txt',
    },
}

def safe_extract_selection(zf: zipfile.ZipFile, inside: str, destination: Path) -> int:
    """Extract only the named addon tree from a pinned GitHub archive."""
    files = []
    for item in zf.infolist():
        # GitHub zip root always has one named folder; match selected dir below it.
        parts = PurePosixPath(item.filename).parts
        if len(parts) < 4 or parts[1:3] != ('addons', inside):
            continue
        rel = PurePosixPath(*parts[3:])
        if not rel.parts or rel.is_absolute() or '..' in rel.parts:
            raise ValueError('Unsafe vendor archive path: ' + item.filename)
        if item.is_dir():
            continue
        files.append((item, rel))
    if not files:
        raise ValueError('Expected addons/%s missing from GitHub archive' % inside)
    destination.mkdir(parents=True, exist_ok=True)
    for item, rel in files:
        out = destination.joinpath(*rel.parts)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(zf.read(item))
    return len(files)

def install_one(key: str) -> None:
    v = VENDORS[key]
    target = ROOT / 'addons' / v['addon']
    if target.exists():
        print('SKIP (existing, not overwritten):', target)
        return
    url = 'https://github.com/%s/archive/%s.zip' % (v['repository'], v['commit'])
    print('Fetching pinned source:', v['repository'], v['commit'])
    req = Request(url, headers={'User-Agent': 'Landworks-physics-v0.4'})
    with urlopen(req, timeout=75) as response:
        data = response.read(30 * 1024 * 1024 + 1)
    if len(data) > 30 * 1024 * 1024:
        raise ValueError('Vendor archive exceeded size limit')
    print('Archive SHA256:', hashlib.sha256(data).hexdigest())
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        items = archive.namelist()
        matches = [n for n in items if PurePosixPath(n).parts[1:] == (v['license'],)]
        if len(matches) != 1:
            raise ValueError('Vendor license file missing or ambiguous')
        license_data = archive.read(matches[0])
        with tempfile.TemporaryDirectory(dir=ROOT / 'addons') as td:
            staging = Path(td) / v['addon']
            count = safe_extract_selection(archive, v['addon'], staging)
            shutil.move(str(staging), str(target))
        license_path = ROOT / 'vendor' / 'licenses' / (key + '-LICENSE.txt')
        license_path.write_bytes(license_data)
        manifest = ROOT / 'vendor' / 'licenses' / (key + '-SOURCE.txt')
        manifest.write_text('Repository: %s\nCommit: %s\nArchive: %s\nArchive SHA256: %s\nInstalled files: %d\n' % (v['repository'], v['commit'], url, hashlib.sha256(data).hexdigest(), count), encoding='utf-8')
        print('Installed',count,'files into',target)

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--vendor', choices=['gevp', 'kv', 'all'], default='all')
    args = ap.parse_args()
    for key in VENDORS if args.vendor == 'all' else [args.vendor]:
        install_one(key)
    print('NOTICE: libraries installed, but not yet wired into the Kubota machines.')
    print('For first trial, open addons/gevp/scenes/demo_simcade.tscn after configuring input actions.')
