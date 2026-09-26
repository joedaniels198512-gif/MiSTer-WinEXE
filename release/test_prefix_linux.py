#!/usr/bin/env python3
"""Real ext4 image tests on Linux/root. No SS1/device nodes are used."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from test_release import ROOT, prefix_archive, put, run

if sys.platform != 'linux' or os.geteuid() != 0:
    sys.exit('Requires Linux root with loop-mount support; not a hardware test.')

payload = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else None

with tempfile.TemporaryDirectory(prefix='winexe-prefix-') as tmp:
    root = Path(tmp)
    win = root / 'games/WinEXE'
    mnt = win / 'wineprefix-prebuilt'
    img = win / 'wineprefix-prebuilt.ext4'
    (win / 'bin').mkdir(parents=True)
    shutil.copy(ROOT / 'scripts/ss1-winexe-verify-package.py', win / 'bin')
    if payload:
        shutil.copy(payload / 'games/WinEXE/wineprefix-prebuilt.tar.xz', win)
    else:
        prefix_archive(win / 'wineprefix-prebuilt.tar.xz')
    size_mb = 512 if payload else 256
    env = dict(os.environ, WINEXE_PREFIX_MB=str(size_mb))
    cmd = ['sh', ROOT / 'scripts/ss1-winexe-install-prefix.sh', win, root / 'Windows']
    try:
        result = run(cmd, env=env)
        assert result.returncode == 0, result.stdout
        assert img.stat().st_size == size_mb * 1024 * 1024
        assert subprocess.call(['mountpoint', '-q', str(mnt)]) == 0
        assert (mnt / 'dosdevices/c:').is_symlink()
        assert os.readlink(mnt / 'drive_c/windows/system32/cmd.exe') == '/media/fat/games/WinEXE/wine-installer/opt/wine-devel/lib/wine/i386-windows/cmd.exe'
        put(mnt / 'drive_c/save.dat', b'keep this save')
        (mnt / 'system.reg').write_text('user registry')
        # Both mounted and post-reboot/unmounted reinstall must preserve data.
        for unmount in [False, True]:
            if unmount:
                subprocess.run(['umount', str(mnt)], check=True)
            result = run(cmd, env=env)
            assert result.returncode == 0, result.stdout
            assert (mnt / 'system.reg').read_text() == 'user registry'
            assert (mnt / 'drive_c/save.dat').read_bytes() == b'keep this save'
        subprocess.run(['umount', str(mnt)], check=True)
        # A mount failure on an existing image must not trigger formatting.
        damaged = root / 'damaged'
        damaged.mkdir()
        put(damaged / 'wineprefix-prebuilt.ext4', b'not an ext4 image')
        result = run(['sh', cmd[1], damaged, root / 'Windows'], env=env)
        assert result.returncode != 0
        assert (damaged / 'wineprefix-prebuilt.ext4').read_bytes() == b'not an ext4 image'
        print('EXT4_PREFIX_OK: fresh creation, symlinks, mounted reinstall, remount, invalid-image preservation')
    finally:
        if subprocess.call(['mountpoint', '-q', str(mnt)]) == 0:
            subprocess.run(['umount', str(mnt)], check=True)

if payload:
    # Exercise the actual packaged installer with the actual CI-built prefix.
    with tempfile.TemporaryDirectory(prefix='winexe-install-') as tmp:
        fat = Path(tmp)
        mnt = fat / 'games/WinEXE/wineprefix-prebuilt'
        try:
            command = ['sh', payload / 'Scripts/WinEXE Installer.sh', fat]
            result = run(command)
            assert result.returncode == 0, result.stdout
            put(mnt / 'drive_c/reinstall-save.dat', b'user save')
            result = run(command)
            assert result.returncode == 0, result.stdout
            assert (mnt / 'drive_c/reinstall-save.dat').read_bytes() == b'user save'
            assert (fat / 'MiSTer.ini').read_text().count('[WinEXE]') == 1
            print('PACKAGED_INSTALLER_OK: complete fresh install and preserved save on reinstall')
        finally:
            if subprocess.call(['mountpoint', '-q', str(mnt)]) == 0:
                subprocess.run(['umount', str(mnt)], check=True)
