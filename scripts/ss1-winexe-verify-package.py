#!/usr/bin/env python3
"""Validate a complete release payload; never launch Wine or touch hardware."""
import argparse
import configparser
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import struct
import sys
import tarfile


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def lines(path):
    return [s.strip() for s in path.read_text().splitlines() if s.strip() and not s.startswith('#')]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def prefix_members(path):
    with tarfile.open(path, 'r:xz') as archive:
        members = archive.getmembers()
        names = {m.name.rstrip('/') for m in members}
        for m in members:
            p = PurePosixPath(m.name)
            require(not p.is_absolute() and '..' not in p.parts and p.parts[0] == 'wineprefix-prebuilt',
                    'unsafe prefix member: ' + m.name)
            require(m.isfile() or m.isdir() or m.issym(), 'unsupported prefix member: ' + m.name)
        for name in ['system.reg', 'user.reg', 'dosdevices', 'drive_c/windows/system32']:
            require('wineprefix-prebuilt/' + name in names, 'prefix missing ' + name)
        # No member may be extracted through a symlink ancestor.
        links = {m.name.rstrip('/') for m in members if m.issym()}
        for m in members:
            require(not any(str(p) in links for p in PurePosixPath(m.name).parents),
                    'prefix member beneath symlink: ' + m.name)
        return members


def check(root, release=True):
    win = root / 'games/WinEXE'
    doc = root / 'docs/WinEXE'
    required = lines(doc / 'package-files.list')
    required += ['games/WinEXE/bin/' + n for n in lines(doc / 'runtime-files.list')]
    for name in required:
        require((root / name).is_file() and (root / name).stat().st_size > 0, 'missing/empty: ' + name)
    rbfs = list((root / '_Computer').glob('WinEXE*.rbf'))
    require(bool(rbfs) and all(p.stat().st_size > 0 for p in rbfs), 'missing/empty WinEXE RBF')
    require(b'/media/fat/games/WinEXE/bin/ss1-winexe-launch.sh' in (root / 'MiSTer_WinEXE').read_bytes(), 'Main has wrong launcher path')
    require(b'/media/fat/Windows/bin/ss1-winexe-launch.sh' not in (root / 'MiSTer_WinEXE').read_bytes(), 'Main still uses legacy launcher')
    shortcuts = list(win.glob('*.wex'))
    require(bool(shortcuts), 'no WEX shortcuts')
    for shortcut in shortcuts:
        cfg = configparser.ConfigParser(interpolation=None)
        cfg.read(shortcut)
        profile = cfg.get('winexe', 'profile')
        require('/' not in profile and '..' not in profile, 'invalid WEX profile')
        ini = win / 'profiles' / (profile + '.ini')
        require(ini.is_file(), 'missing profile: ' + profile)
        cfg = configparser.ConfigParser(interpolation=None)
        cfg.read(ini)
        for key in ['pre', 'post', 'background', 'cleanup']:
            for command in cfg.get('helpers', key, fallback='').split(';'):
                if command.strip():
                    require((win / 'bin' / command.split()[0]).is_file(), 'missing profile helper: ' + command)
    for member in prefix_members(win / 'wineprefix-prebuilt.tar.xz'):
        if member.issym() and member.linkname.startswith(('/media/fat/Windows/', '/media/fat/games/WinEXE/')):
            suffix = member.linkname.split('Windows/', 1)[1] if member.linkname.startswith('/media/fat/Windows/') else member.linkname.split('games/WinEXE/', 1)[1]
            # Links back into the prefix (e.g. c:) resolve after extraction.
            if suffix != 'wineprefix-prebuilt' and not suffix.startswith('wineprefix-prebuilt/'):
                require((win / suffix).is_file(), 'prefix target absent from runtime: ' + member.linkname)
    for p in (root.rglob('*') if release else []):
        require(not p.is_symlink(), 'exFAT payload contains symlink: ' + str(p))
        if p.is_file():
            require(p.suffix.lower() not in {'.iso', '.cue', '.rom', '.avi', '.wav', '.mp3', '.wma', '.sav', '.raw', '.ppm', '.bgra', '.ext4'}, 'unexpected user/image payload: ' + str(p))
    allowed = {'README.md', 'diag/ss1-cnc-pal8.exe', 'diag/ss1-cnc-pal8.dll', 'diag/ss1-cnc-capslie.exe', 'diag/ss1-cnc-cdprobe.exe'}
    for p in ((win / 'apps').rglob('*') if release else []):
        if p.is_file():
            require(p.relative_to(win / 'apps').as_posix() in allowed, 'unexpected application payload: ' + str(p))
    # Catch wrong-architecture or placeholder helper binaries.
    arm = [root / 'MiSTer_WinEXE', win / 'box86-ss1/box86', win / 'x11/lib/xorg/Xorg']
    arm += [win / 'bin' / n for n in ['ss1-winexe-x11-present', 'ss1-pal8-map.so', 'ss1-civ2-cdaudio.so']]
    x86 = [win / 'wine-installer/opt/wine-devel/bin' / n for n in ['wine', 'wineserver']]
    for p, machine in [(p, 40) for p in arm] + [(p, 3) for p in x86]:
        data = p.read_bytes()[:20]
        require(len(data) == 20 and data[:6] == b'\x7fELF\x01\x01' and struct.unpack_from('<H', data, 18)[0] == machine, 'wrong ELF architecture: ' + str(p))
    for name in ['ss1-cnc-pal8.exe', 'ss1-cnc-pal8.dll', 'ss1-cnc-capslie.exe', 'ss1-cnc-cdprobe.exe']:
        p = win / 'apps/diag' / name
        data = p.read_bytes()
        require(data[:2] == b'MZ' and len(data) >= 64, 'invalid PE: ' + str(p))
        off = struct.unpack_from('<I', data, 60)[0]
        require(data[off:off + 6] == b'PE\0\0\x4c\x01', 'not PE32 i386: ' + str(p))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    parser.add_argument('--write-manifest', action='store_true')
    parser.add_argument('--prefix-only', action='store_true')
    parser.add_argument('--image-mb', type=int)
    parser.add_argument('--space-dir', type=Path)
    args = parser.parse_args()
    if args.prefix_only:
        members = prefix_members(args.root)
        if args.image_mb is not None:
            image_bytes = args.image_mb * 1024 * 1024
            # Round each entry to a block; reserve 25% for ext4 metadata,
            # reserved blocks and growth rather than comparing compressed size.
            occupied = sum(((m.size + 4095) // 4096 * 4096) if m.isfile() else 4096 for m in members)
            require(occupied <= image_bytes * 3 // 4, 'prepared prefix exceeds image headroom allowance')
            if args.space_dir:
                fs = os.statvfs(args.space_dir)
                require(fs.f_bavail * fs.f_frsize >= image_bytes + 16 * 1024 * 1024,
                        'insufficient free space: image plus 16 MiB margin required')
            print('PREFIX_SPACE_OK estimated_bytes=%d image_bytes=%d' % (occupied, image_bytes))
        print('PREFIX_ARCHIVE_OK')
        return
    root = args.root.resolve()
    check(root, release=args.write_manifest)
    manifest = root / 'docs/WinEXE/PACKAGE_SHA256.json'
    if args.write_manifest:
        hashes = {p.relative_to(root).as_posix(): sha(p) for p in sorted(root.rglob('*')) if p.is_file() and p != manifest}
        manifest.write_text(json.dumps(hashes, indent=2) + '\n')
    else:
        hashes = json.loads(manifest.read_text())
        require(bool(hashes), 'empty package manifest')
        for name, expected in hashes.items():
            p = PurePosixPath(name)
            require(not p.is_absolute() and '..' not in p.parts, 'unsafe manifest path')
            require(sha(root / name) == expected, 'checksum mismatch: ' + name)
    print('PACKAGE_OK')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, configparser.Error, tarfile.TarError, struct.error) as exc:
        sys.exit('PACKAGE_FAIL: ' + str(exc))
