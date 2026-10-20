#!/usr/bin/env python3
"""Run the real installer offline, substituting only platform and network calls."""
import hashlib
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest


class Installer(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / 'home with spaces'
        self.home.mkdir()
        self.archive = self.root / 'package.tar.gz'
        self.checksum = self.root / 'package.sha256'
        self.files = {'dc-auto-quest': b'#!/bin/sh\nexit "${FIXTURE_EXIT:-0}"\n',
                      'README.md': b'readme', 'LICENSE': b'license'}
        self.package()
        self.env = dict(os.environ, HOME=str(self.home), TMPDIR=str(self.root),
                        FIXTURE_ARCHIVE=str(self.archive), FIXTURE_HASH=str(self.checksum),
                        FIXTURE_SCRIPT=str(Path(__file__).resolve().parents[1] / 'install.sh'))

    def tearDown(self):
        self.temp.cleanup()

    def package(self, kind=None):
        with tarfile.open(self.archive, 'w:gz') as tar:
            for name, data in self.files.items():
                info = tarfile.TarInfo(name)
                info.mode, info.size = 0o755, len(data)
                if kind in ('link', 'hardlink') and name == 'dc-auto-quest':
                    info.type = tarfile.SYMTYPE if kind == 'link' else tarfile.LNKTYPE
                    info.linkname, info.size = '/tmp/outside', 0
                tar.addfile(info, io.BytesIO(data) if info.size else None)
                if kind == 'duplicate' and name == 'dc-auto-quest':
                    tar.addfile(info, io.BytesIO(data))
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        self.checksum.write_text(digest + '  dc-auto-quest-linux-x64.tar.gz\n')

    def run_installer(self, success=True):
        code = '''source "$FIXTURE_SCRIPT"
autoquest_platform() { :; }
autoquest_download() {
 case "$1" in *.sha256) cp "$FIXTURE_HASH" "$2";; *.tar.gz) cp "$FIXTURE_ARCHIVE" "$2";; *) return 1;; esac
}
install_autoquest'''
        result = subprocess.run(['bash', '-c', code], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        self.assertFalse(list(self.root.glob('dc-auto-quest-install.*')))
        self.assertFalse(list((self.home / '.local/bin').glob('.dc-auto-quest.*')))
        return result

    def test_install_update_and_remove_command(self):
        self.run_installer()
        cli = self.home / '.local/bin/dc-auto-quest'
        self.assertTrue(cli.is_file())
        self.assertTrue(os.access(cli, os.X_OK))
        self.files['dc-auto-quest'] += b'# updated\n'
        self.package()
        result = self.run_installer()
        self.assertEqual(cli.read_bytes(), self.files['dc-auto-quest'])
        self.assertIn('--remove', result.stdout)
        self.assertEqual(subprocess.run([str(cli), '--remove']).returncode, 0)

    def test_bad_checksum_preserves_existing_command(self):
        self.run_installer()
        cli = self.home / '.local/bin/dc-auto-quest'
        previous = cli.read_bytes()
        for checksum in ['0' * 64 + '  dc-auto-quest-linux-x64.tar.gz\n',
                         self.checksum.read_text() + 'unexpected second line',
                         self.checksum.read_text().replace('dc-auto-quest-linux-x64.tar.gz', '../other')]:
            with self.subTest(checksum=checksum):
                self.checksum.write_text(checksum)
                self.run_installer(False)
                self.assertEqual(cli.read_bytes(), previous)

    def test_failed_integration_preserves_previous_command(self):
        self.run_installer()
        cli = self.home / '.local/bin/dc-auto-quest'
        previous = cli.read_bytes()
        self.files['dc-auto-quest'] += b'# replacement\n'
        self.package()
        self.env['FIXTURE_EXIT'] = '1'
        result = self.run_installer(False)
        self.assertNotIn('Instalação concluída', result.stdout)
        self.assertEqual(cli.read_bytes(), previous)

    def test_rejects_missing_extra_duplicate_links_and_traversal(self):
        for kind in ['missing', 'extra', 'duplicate', 'link', 'hardlink', 'traversal']:
            with self.subTest(kind=kind):
                original = self.files.copy()
                if kind == 'missing':
                    self.files.pop('dc-auto-quest')
                if kind == 'extra':
                    self.files['extra'] = b'bad'
                if kind == 'traversal':
                    self.files['../escaped'] = b'bad'
                self.package(kind)
                self.files = original
                self.run_installer(False)
                self.assertFalse((self.home / '.local/bin/dc-auto-quest').exists())
                self.assertFalse((self.root / 'escaped').exists())

    def test_network_failure_does_not_install(self):
        self.env['FIXTURE_ARCHIVE'] = str(self.root / 'missing')
        self.run_installer(False)
        self.assertFalse((self.home / '.local/bin/dc-auto-quest').exists())


if __name__ == '__main__':
    unittest.main()
