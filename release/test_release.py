#!/usr/bin/env python3
"""Release regression tests. Synthetic payloads, no Wine or device access."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('artifacts', ROOT / 'release/artifacts.py')
artifacts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifacts)
VERIFY = ROOT / 'scripts/ss1-winexe-verify-package.py'
INSTALL = ROOT / 'scripts/WinEXE Installer.sh'


def run(args, **kw):
    return subprocess.run([str(a) for a in args], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kw)


def put(path, data=b'fixture\n'):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def elf(machine):
    data = bytearray(128)
    data[:6] = b'\x7fELF\x01\x01'
    struct.pack_into('<H', data, 18, machine)
    return bytes(data)


def pe():
    data = bytearray(128)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 60, 64)
    data[64:70] = b'PE\0\0\x4c\x01'
    return bytes(data)


def prefix_archive(path):
    with tempfile.TemporaryDirectory() as tmp:
        prefix = Path(tmp) / 'wineprefix-prebuilt'
        for name in ['system.reg', 'user.reg', 'drive_c/windows/system32/fixture.dll']:
            put(prefix / name)
        (prefix / 'dosdevices').mkdir()
        (prefix / 'dosdevices/c:').symlink_to('../drive_c')
        (prefix / 'dosdevices/z:').symlink_to('/')
        (prefix / 'drive_c/windows/system32/cmd.exe').symlink_to('/media/fat/Windows/wine-installer/opt/wine-devel/lib/wine/i386-windows/cmd.exe')
        with tarfile.open(path, 'w:xz') as tar:
            tar.add(prefix, arcname='wineprefix-prebuilt')


def fixture(root):
    """Sufficiently structured to exercise checks; binaries are NOT executable."""
    win = root / 'games/WinEXE'
    doc = root / 'docs/WinEXE'
    doc.mkdir(parents=True)
    for name in ['runtime-files.list', 'package-files.list']:
        shutil.copy(ROOT / 'release' / name, doc / name)
    for name in (ROOT / 'release/package-files.list').read_text().splitlines():
        if name and not name.startswith('#'):
            put(root / name)
    for name in (ROOT / 'release/runtime-files.list').read_text().splitlines():
        if name and not name.startswith('#'):
            shutil.copy(ROOT / 'scripts' / name, win / 'bin' / name)
    shutil.copy(INSTALL, root / 'Scripts/WinEXE Installer.sh')
    shutil.copy(ROOT / 'mister/WinEXE.ini', doc / 'WinEXE.ini')
    shutil.copytree(ROOT / 'profiles', win / 'profiles')
    for wex in (ROOT / 'wex').glob('*.wex'):
        shutil.copy(wex, win / wex.name)
    put(root / '_Computer/WinEXE_20260918.rbf')
    put(root / 'MiSTer_WinEXE', elf(40) + b'/media/fat/games/WinEXE/bin/ss1-winexe-launch.sh')
    for name in ['bin/ss1-winexe-x11-present', 'bin/ss1-pal8-map.so', 'bin/ss1-civ2-cdaudio.so', 'box86-ss1/box86', 'x11/lib/xorg/Xorg']:
        put(win / name, elf(40))
    for name in ['wine', 'wineserver']:
        put(win / 'wine-installer/opt/wine-devel/bin' / name, elf(3))
    for p in (win / 'apps/diag').iterdir():
        p.write_bytes(pe())
    put(win / 'wine-installer/opt/wine-devel/lib/wine/i386-windows/cmd.exe', pe())
    prefix_archive(win / 'wineprefix-prebuilt.tar.xz')
    result = run([sys.executable, VERIFY, root, '--write-manifest'])
    if result.returncode:
        raise AssertionError(result.stdout)
    return win


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='winexe release test ')
        self.root = Path(self.tmp.name) / 'fat'
        self.win = fixture(self.root)

    def tearDown(self):
        self.tmp.cleanup()

    def test_complete_payload_and_corruption(self):
        self.assertEqual(run([sys.executable, VERIFY, self.root]).returncode, 0)
        (self.win / 'bin/ss1-civ2-cdaudio.so').unlink()
        result = run([sys.executable, VERIFY, self.root])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ss1-civ2-cdaudio.so', result.stdout)

    def test_checksum_and_no_user_payload(self):
        with (self.root / 'MiSTer_WinEXE').open('ab') as f:
            f.write(b'corrupt')
        self.assertIn('checksum mismatch', run([sys.executable, VERIFY, self.root]).stdout)
        put(self.win / 'apps/notepad.exe', pe())
        self.assertIn('unexpected application payload', run([sys.executable, VERIFY, self.root, '--write-manifest']).stdout)

    def test_old_install_aborts_before_writes(self):
        for marker in ['bin/marker', 'apps/user.exe', 'wineprefix-prebuilt/system.reg', 'wineprefix-prebuilt.ext4', 'wineprefix/system.reg']:
            with self.subTest(marker=marker):
                old = self.root / 'Windows'
                put(old / marker, b'user data')
                before = {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
                result = run(['sh', self.root / 'Scripts/WinEXE Installer.sh', self.root])
                after = {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Automatic migration is not currently performed', result.stdout)
                self.assertEqual(before, after)
                shutil.rmtree(old)

    def test_in_place_and_separate_install_preserve_existing_prefix(self):
        # Mount operations are covered separately by test_prefix_linux.py.
        # Here only mountpoint is faked to exercise complete installer copies.
        fake = Path(self.tmp.name) / 'tools'
        fake.mkdir()
        for name, body in [('mountpoint', '#!/bin/sh\nexit 0\n'), ('pidof', '#!/bin/sh\nexit 1\n'), ('gdb', '#!/bin/sh\nexit 0\n'), ('taskset', '#!/bin/sh\nexit 0\n'), ('setsid', '#!/bin/sh\nexit 0\n')]:
            p = fake / name
            p.write_text(body)
            p.chmod(0o755)
        env = dict(os.environ, PATH=str(fake) + os.pathsep + os.environ['PATH'])
        for separate in [False, True]:
            with self.subTest(separate=separate):
                target = Path(self.tmp.name) / 'other' if separate else self.root
                prefix = target / 'games/WinEXE/wineprefix-prebuilt'
                for f in ['system.reg', 'user.reg', 'drive_c/save.dat']:
                    put(prefix / f, b'preserve me')
                (prefix / 'dosdevices').mkdir(exist_ok=True)
                original_ini = b'bootcore=last\n[OtherCore]\nfoo=bar\n'
                if separate:
                    original_ini += b'[WinEXE]\nmain=MiSTer_WinEXE\ncustom=keep\n[WinEXE_Test]\nmain=MiSTer_WinEXE'
                put(target / 'MiSTer.ini', original_ini)
                put(target / 'MiSTer', b'stock Main')
                put(target / 'games/WinEXE/apps/user.exe', b'user app')
                put(target / 'games/WinEXE/apps/diag/user-notes.txt', b'user notes')
                for _ in range(2):
                    result = run(['sh', self.root / 'Scripts/WinEXE Installer.sh', target], env=env)
                    self.assertEqual(result.returncode, 0, result.stdout)
                    self.assertEqual((prefix / 'system.reg').read_bytes(), b'preserve me')
                    self.assertEqual((prefix / 'drive_c/save.dat').read_bytes(), b'preserve me')
                self.assertEqual((target / 'MiSTer').read_bytes(), b'stock Main')
                self.assertEqual((target / 'games/WinEXE/apps/user.exe').read_bytes(), b'user app')
                self.assertEqual((target / 'games/WinEXE/apps/diag/user-notes.txt').read_bytes(), b'user notes')
                self.assertEqual((target / 'MiSTer.ini').read_text().count('[WinEXE]\n'), 1)
                self.assertEqual((target / 'MiSTer.ini').read_text().count('[WinEXE_Test]\n'), 1)
                if separate:
                    self.assertEqual((target / 'MiSTer.ini').read_bytes(), original_ini)
                # Both core names reject conflicts before runtime/config writes.
                for section in ['WinEXE', 'WinEXE_Test']:
                    put(target / 'MiSTer.ini', ('[' + section + ']\nmain=OtherMain\n').encode())
                    before = (target / 'MiSTer.ini').read_bytes()
                    result = run(['sh', self.root / 'Scripts/WinEXE Installer.sh', target], env=env)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('conflicts', result.stdout)
                    self.assertEqual((target / 'MiSTer.ini').read_bytes(), before)

    def test_prefix_failure_never_extracts_on_exfat(self):
        fake = Path(self.tmp.name) / 'prefix-tools'
        fake.mkdir()
        # mkfs fails before any mount/extraction; dd is stubbed to avoid a GiB write.
        for name, body in [('mountpoint', 'exit 1'), ('dd', 'exit 0'), ('mkfs.ext4', 'exit 1')]:
            p = fake / name
            p.write_text('#!/bin/sh\n' + body + '\n')
            p.chmod(0o755)
        env = dict(os.environ, PATH=str(fake) + os.pathsep + os.environ['PATH'])
        result = run(['sh', ROOT / 'scripts/ss1-winexe-install-prefix.sh', self.win, self.root / 'Windows'], env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.win / 'wineprefix-prebuilt.ext4').exists())
        self.assertFalse((self.win / 'wineprefix-prebuilt/system.reg').exists())
        self.assertFalse(list(self.win.glob('.wineprefix-new.*')))

    def test_prefix_space_preflight(self):
        from unittest.mock import patch
        import types
        spec = importlib.util.spec_from_file_location('verify', VERIFY)
        verify = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(verify)
        args = ['verify', str(self.win / 'wineprefix-prebuilt.tar.xz'), '--prefix-only', '--image-mb', '512', '--space-dir', str(self.win)]
        with patch.object(sys, 'argv', args), patch.object(verify.os, 'statvfs', return_value=types.SimpleNamespace(f_bavail=1, f_frsize=4096)):
            with self.assertRaisesRegex(ValueError, 'insufficient free space'):
                verify.main()
        with patch.object(sys, 'argv', args), patch.object(verify, 'prefix_members', return_value=[types.SimpleNamespace(size=1024**3, isfile=lambda: True)]):
            with self.assertRaisesRegex(ValueError, 'headroom'):
                verify.main()

    def test_prefix_failure_cleanup_and_retry_guard(self):
        # Fault injection only: no real mounts, formatting, or large allocation.
        tools = Path(self.tmp.name) / 'fault-tools'
        tools.mkdir()
        driver = tools / 'driver'
        driver.write_text('#!' + sys.executable + '\n' + """
import os, pathlib, signal, sys
op = pathlib.Path(sys.argv[0]).name
state = pathlib.Path(os.environ['FAULT_STATE'])
mode = os.environ['FAULT_MODE']
if op == 'mountpoint':
    sys.exit(0 if state.exists() else 1)
if op == 'mount':
    state.touch()
    if mode == 'mount': sys.exit(1)
if op == 'umount':
    if mode == 'umount': sys.exit(1)
    state.unlink(missing_ok=True)
if op == 'tar':
    if mode == 'term': os.kill(os.getppid(), signal.SIGTERM)
    sys.exit(1)
if op == 'mkfs.ext4' and mode == 'mkfs': sys.exit(1)
""")
        driver.chmod(0o755)
        for name in ['mountpoint', 'mount', 'umount', 'dd', 'mkfs.ext4', 'tar']:
            (tools / name).symlink_to(driver)
        for mode in ['mkfs', 'mount', 'tar', 'term', 'umount', 'existing-invalid']:
            with self.subTest(mode=mode):
                win = Path(self.tmp.name) / mode
                (win / 'bin').mkdir(parents=True)
                shutil.copy(VERIFY, win / 'bin')
                prefix_archive(win / 'wineprefix-prebuilt.tar.xz')
                if mode == 'existing-invalid':
                    put(win / 'wineprefix-prebuilt.ext4', b'preserve image')
                state = win / 'mounted-state'
                env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'], FAULT_STATE=str(state), FAULT_MODE=mode)
                command = ['sh', ROOT / 'scripts/ss1-winexe-install-prefix.sh', win, self.root / 'Windows']
                result = run(command, env=env)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                pending = list(win.glob('.wineprefix-new.*'))
                if mode == 'umount':
                    self.assertTrue(state.exists())
                    self.assertEqual(len(pending), 1)
                    self.assertIn('retained', result.stdout)
                    retry = run(command, env=env)
                    self.assertIn('Interrupted installation image retained', retry.stdout)
                    self.assertEqual(pending, list(win.glob('.wineprefix-new.*')))
                else:
                    self.assertFalse(state.exists(), result.stdout)
                    self.assertFalse(pending)
                if mode == 'existing-invalid':
                    self.assertEqual((win / 'wineprefix-prebuilt.ext4').read_bytes(), b'preserve image')

    def test_zip_assembly_and_missing_input_preserves_output(self):
        import zipfile
        art = Path(self.tmp.name) / 'artifacts'
        copies = {
            'WinEXE.rbf': self.root / '_Computer/WinEXE_20260918.rbf',
            'MiSTer_WinEXE': self.root / 'MiSTer_WinEXE',
            'dummy_drv.so': self.win / 'x11/lib/xorg/modules/drivers/dummy_drv.so',
            'wineprefix-prebuilt.tar.xz': self.win / 'wineprefix-prebuilt.tar.xz',
        }
        bundles = {
            'wine-runtime.tar.xz': ['wine-installer'],
            'box86-runtime.tar.xz': ['box86-ss1', 'box86-extracted'],
            'x11-runtime.tar.xz': ['x11'],
            'host-libs.tar.xz': ['host-libs'],
        }
        for name, (files, _) in artifacts.SPECS.items():
            base = art / name
            base.mkdir(parents=True)
            for f in files:
                if f in copies:
                    shutil.copy(copies[f], base / f)
                elif f in bundles:
                    with tarfile.open(base / f, 'w:xz') as tar:
                        for directory in bundles[f]:
                            tar.add(self.win / directory, arcname=directory)
                elif f.endswith(('.exe', '.dll')):
                    shutil.copy(self.win / 'apps/diag' / f, base / f)
                elif f == 'MAIN_MISTER.sha':
                    put(base / f, b'4145f1dba9127a8935a3071a0650166ba5d699c3\n')
                else:
                    shutil.copy(self.win / 'bin' / f, base / f)
            result = run([sys.executable, ROOT / 'release/artifacts.py', 'stamp', name], cwd=base)
            self.assertEqual(result.returncode, 0, result.stdout)
        out = Path(self.tmp.name) / 'release.zip'
        env = dict(os.environ, ARTIFACT_DIR=str(art))
        command = ['sh', ROOT / 'scripts/ss1-winexe-package-release.sh', ROOT, out]
        result = run(command, env=env)
        self.assertEqual(result.returncode, 0, result.stdout)
        with zipfile.ZipFile(out) as z:
            self.assertIsNone(z.testzip())
            for name in ['ss1-cnc-capslie.exe', 'ss1-cnc-cdprobe.exe', 'ss1-cnc-pal8.exe', 'ss1-cnc-pal8.dll']:
                self.assertIn('games/WinEXE/apps/diag/' + name, z.namelist())
            self.assertIn('games/WinEXE/bin/ss1-civ2-cdaudio.so', z.namelist())
            extract = Path(self.tmp.name) / 'unzipped'
            z.extractall(extract)
        result = run([sys.executable, VERIFY, extract])
        self.assertEqual(result.returncode, 0, result.stdout)
        old = out.read_bytes()
        (art / 'dummy_drv.so/dummy_drv.so').unlink()
        self.assertNotEqual(run(command, env=env).returncode, 0)
        self.assertEqual(old, out.read_bytes())

    def test_artifact_provenance_rejects_stale_and_tampered(self):
        art = Path(self.tmp.name) / 'artifacts'
        for name, (files, _) in artifacts.SPECS.items():
            base = art / name
            for f in files:
                put(base / f)
            result = run([sys.executable, ROOT / 'release/artifacts.py', 'stamp', name], cwd=base)
            self.assertEqual(result.returncode, 0, result.stdout)
        command = [sys.executable, ROOT / 'release/artifacts.py', 'verify', art]
        self.assertEqual(run(command).returncode, 0)
        meta = art / 'MiSTer_WinEXE/MiSTer_WinEXE.provenance.json'
        original = meta.read_text()
        record = json.loads(original)
        record['source_commit'] = '0' * 40
        meta.write_text(json.dumps(record))
        self.assertIn('stale/source-mismatched', run(command).stdout)
        meta.write_text(original)
        record = json.loads(original)
        record['run_id'] = 'different-run'
        meta.write_text(json.dumps(record))
        self.assertIn('different runs', run(command).stdout)
        meta.write_text(original)
        (art / 'MiSTer_WinEXE/MiSTer_WinEXE').write_bytes(b'changed')
        self.assertIn('modified or incomplete', run(command).stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
