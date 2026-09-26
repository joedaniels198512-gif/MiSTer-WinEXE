#!/usr/bin/env python3
"""Stamp build outputs; refuse missing, stale, mixed-run, or modified inputs."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
# Every release input has one producer and a fixed name. No 'latest' fallback.
SPECS = {
    'WinEXE.rbf': (['WinEXE.rbf'], ['fpga/**', '.github/workflows/build-winexe-core.yml']),
    'MiSTer_WinEXE': (['MiSTer_WinEXE', 'MAIN_MISTER.sha'], ['main/**', '.github/workflows/build-mister-winexe.yml']),
    'ss1-winexe-x11-present': (['ss1-winexe-x11-present'], ['scripts/ss1-winexe-x11-present.c', 'scripts/ss1-pal8.h', '.github/workflows/build-winexe-presenter.yml']),
    'dummy_drv.so': (['dummy_drv.so'], ['.github/workflows/build-winexe-presenter.yml']),
    'ss1-pal8-map.so': (['ss1-pal8-map.so'], ['scripts/ss1-pal8-map.c', 'scripts/ss1-pal8.h', '.github/workflows/build-winexe-core.yml']),
    'ss1-civ2-cdaudio.so': (['ss1-civ2-cdaudio.so'], ['scripts/ss1-civ2-cdaudio.c', '.github/workflows/build-winexe-core.yml']),
    'ss1-cnc-pal8-guest': (['ss1-cnc-pal8.dll', 'ss1-cnc-pal8.exe', 'ss1-cnc-capslie.exe', 'ss1-cnc-cdprobe.exe'], ['scripts/ss1-cnc-pal8*.c', 'scripts/ss1-cnc-capslie.c', 'scripts/ss1-cnc-cdprobe.c', 'scripts/ss1-pal8.h', '.github/workflows/build-winexe-core.yml']),
    'wineprefix-prebuilt': (['wineprefix-prebuilt.tar.xz', 'wine-runtime.tar.xz'], ['scripts/prepare-wine-prefix.sh', 'release/runtime-packages.json', '.github/workflows/prepare-wine-prefix.yml']),
    'x11-runtime': (['x11-runtime.tar.xz'], ['scripts/prepare-x11-runtime.sh', '.github/workflows/prepare-x11-runtime.yml']),
    'host-libs': (['host-libs.tar.xz'], ['scripts/prepare-host-libs.sh', '.github/workflows/prepare-host-libs.yml']),
    'box86-runtime': (['box86-runtime.tar.xz'], ['release/prepare-box86.sh', 'release/runtime-packages.json', '.github/workflows/release.yml']),
}


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def inputs(name):
    # Use tracked source paths only: Quartus-generated files must not affect
    # source identity. Explicit globs also support an uncommitted local edit.
    tracked = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    import fnmatch
    patterns = SPECS[name][1] + ['release/artifacts.py']
    paths = {p for p in tracked if p and any(fnmatch.fnmatch(p, pat) for pat in patterns)}
    for pattern in patterns:
        if not any(c in pattern for c in '*?['):
            paths.add(pattern)
    return {p: sha(ROOT / p) for p in sorted(paths)}


def commit():
    return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()


def stamp(name):
    record = dict(artifact=name, source_commit=commit(), sources=inputs(name),
                  run_id=os.environ.get('GITHUB_RUN_ID'),
                  run_attempt=os.environ.get('GITHUB_RUN_ATTEMPT'),
                  repository=os.environ.get('GITHUB_REPOSITORY'),
                  files={p: sha(Path(p)) for p in SPECS[name][0]})
    Path(name + '.provenance.json').write_text(json.dumps(record, indent=2) + '\n')


def verify(directory):
    records = []
    for name, (files, _) in SPECS.items():
        base = directory / name
        record = json.loads((base / (name + '.provenance.json')).read_text())
        if record['artifact'] != name or record['source_commit'] != commit() or record['sources'] != inputs(name):
            raise ValueError('stale/source-mismatched artifact: ' + name)
        if record['files'] != {p: sha(base / p) for p in files}:
            raise ValueError('modified or incomplete artifact: ' + name)
        records.append(record)
    runs = {(r['repository'], r['run_id'], r['run_attempt']) for r in records}
    if len(runs) != 1:
        raise ValueError('release inputs came from different runs')
    if os.environ.get('GITHUB_ACTIONS') == 'true':
        expected = (os.environ['GITHUB_REPOSITORY'], os.environ['GITHUB_RUN_ID'], os.environ['GITHUB_RUN_ATTEMPT'])
        if runs != {expected}:
            raise ValueError('CI release requires artifacts from this run and attempt')
    json.dump(dict(source_commit=commit(), artifacts=records), sys.stdout, indent=2)
    print()


if __name__ == '__main__':
    try:
        if sys.argv[1] == 'stamp':
            stamp(sys.argv[2])
        elif sys.argv[1] == 'verify':
            verify(Path(sys.argv[2]))
        else:
            raise ValueError('usage: artifacts.py stamp NAME | verify DIRECTORY')
    except (OSError, ValueError, KeyError, IndexError) as exc:
        sys.exit('ARTIFACT_ERROR: ' + str(exc))
