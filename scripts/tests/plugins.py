#!/usr/bin/env python3
"""Pinned package integrity, cache independence, native installation and health."""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'agents/plugins'))
import package_store as packages

CATALOG = json.loads((ROOT / 'agents/plugins/catalog.json').read_text())


class PluginInstallation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        for name in ('claude', 'codex', 'node', 'npm', 'pnpm', 'pyright-langserver'):
            (self.bin / name).symlink_to(ROOT / 'scripts/tests/plugin-cli.py')
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin) + os.pathsep + os.environ['PATH'])
        self.env.pop('CODEX_HOME', None)
        subprocess.run([sys.executable, str(ROOT / 'scripts/tests/plugin-cli.py'), 'seed'], env=self.env, check=True)

    def run_command(self, args, expected=0, **extra):
        result = subprocess.run(args, env=dict(self.env, **extra), capture_output=True, text=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def install(self, expected=0, **extra):
        return self.run_command(['bash', str(ROOT / 'agents/plugins/install.sh')], expected, **extra)

    def manage(self, action, expected=0):
        return self.run_command([sys.executable, str(ROOT / 'agents/plugins/manage.py'), action], expected)

    def release(self):
        return self.home / '.local/share/agent-plugins/releases' / packages.digest(CATALOG)

    def snapshot(self):
        return {str(p.relative_to(self.home)): (p.lstat().st_mtime_ns, p.readlink().as_posix() if p.is_symlink() else hashlib.sha256(p.read_bytes()).hexdigest()) for p in self.home.rglob('*') if p.is_file() or p.is_symlink()}

    def test_install_rerun_all_homes_and_cache_independence(self):
        custom = self.home / 'custom-codex'
        orca = self.home / 'Library/Application Support/orca/codex-runtime-home/home'
        orca.mkdir(parents=True)
        self.install(CODEX_HOME=str(custom))
        before = (self.home / 'plugin-calls').read_text()
        self.install(CODEX_HOME=str(custom))
        self.assertEqual(before, (self.home / 'plugin-calls').read_text())
        for directory in (self.home / '.codex', custom, orca):
            rows = json.loads((directory / 'mock-plugins.json').read_text())['plugins']
            self.assertEqual({p['pluginId'] for p in rows}, {p['id'] for p in CATALOG['plugins'] if p['codex']})
        shutil.rmtree(self.home / '.codex/plugins/cache')
        shutil.rmtree(self.home / '.claude/plugins/cache')
        self.manage('export')
        for plugin in CATALOG['plugins']:
            for skill in plugin['skills']:
                a = self.home / '.agents/skills' / skill
                b = self.home / '.claude/skills' / skill
                self.assertTrue((a / 'SKILL.md').is_file())
                self.assertEqual(a.resolve(), b.resolve())
                self.assertIn(self.release().resolve(), a.resolve().parents)

    def test_disabled_pinned_plugin_enabled_without_reinstallation(self):
        self.install()
        path = self.home / '.codex/mock-plugins.json'
        data = json.loads(path.read_text())
        data['plugins'][0]['enabled'] = False
        version = data['plugins'][0]['version']
        path.write_text(json.dumps(data))
        before = (self.home / 'plugin-calls').read_text()
        self.manage('codex')
        after = json.loads(path.read_text())['plugins'][0]
        self.assertTrue(after['enabled'])
        self.assertEqual(after['version'], version)
        self.assertEqual((self.home / 'plugin-calls').read_text()[len(before):], 'codex app-server --stdio\n')

    def test_native_failure_propagates(self):
        output = self.install(expected=42, TEST_PLUGIN_EXIT='42')
        self.assertIn('exit 42', output)
        self.assertFalse((self.home / '.codex/mock-plugins.json').exists())

    def test_conflicting_marketplace_is_preserved(self):
        self.install()
        path = self.home / '.claude/plugins/known_marketplaces.json'
        data = json.loads(path.read_text())
        data['dotfiles']['source']['path'] = str(self.home / 'unrelated')
        path.write_text(json.dumps(data))
        before = (self.home / 'plugin-calls').read_text()
        output = self.install(expected=1)
        self.assertIn('points elsewhere', output)
        self.assertEqual(before, (self.home / 'plugin-calls').read_text())

    def test_codex_canonicalized_old_release_moves_to_stable_pointer(self):
        self.install()
        previous = self.release().with_name('previous-release')
        previous.mkdir()
        (previous / 'receipt.json').write_text('{}')
        path = self.home / '.codex/mock-plugins.json'
        state = json.loads(path.read_text())
        state['marketplaces']['dotfiles'] = str(previous)
        path.write_text(json.dumps(state))
        self.manage('codex')
        self.assertEqual(json.loads(path.read_text())['marketplaces']['dotfiles'], str(self.home / '.local/share/agent-plugins/marketplace'))

    def test_local_skill_collision_preflights_all_exports(self):
        path = self.home / '.agents/skills/frontend-design'
        path.mkdir()
        (path / 'SKILL.md').write_text('my local skill')
        self.assertIn('Refusing to replace local content', self.manage('export', expected=1))
        self.assertEqual((path / 'SKILL.md').read_text(), 'my local skill')
        self.assertFalse((self.home / '.agents/skills/understand').exists())

    def test_doctor_detects_damage_without_writing_or_running_clients(self):
        self.install()
        before = self.snapshot()
        self.manage('doctor')
        self.assertEqual(before, self.snapshot())
        (self.home / '.agents/skills/understand').unlink()
        before = self.snapshot()
        self.assertIn('[FAIL] .agents understand', self.manage('doctor', expected=1))
        self.assertEqual(before, self.snapshot())

    def test_modified_package_rejected_before_export(self):
        target = self.release() / 'plugins/understand-anything/skills/understand/SKILL.md'
        target.write_text('changed upstream instructions')
        self.assertIn('missing or modified', self.manage('export', expected=1))
        self.assertFalse((self.home / '.agents/skills/understand').exists())

    def test_doctor_detects_modified_native_cache(self):
        self.install()
        for client in ('.claude', '.codex'):
            version = packages.plugin_version(CATALOG, CATALOG['plugins'][0])
            cache = self.home / client / 'plugins/cache/dotfiles/understand-anything' / version
            (cache / 'skills/understand/SKILL.md').write_text('modified instructions')
        output = self.manage('doctor', expected=1)
        self.assertIn('[FAIL] claude understand-anything@dotfiles', output)
        self.assertIn('[FAIL] ' + str(self.home / '.codex') + ' understand-anything', output)


class ArchiveIntegrity(unittest.TestCase):
    def test_all_native_manifests_have_the_same_pinned_version(self):
        catalog = {'marketplace': 'dotfiles', 'plugins': [{'id': 'demo@dotfiles', 'version': '1.2.3', 'skills': []}]}
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in ('plugin.json', '.codex-plugin/plugin.json', '.claude-plugin/plugin.json'):
                path = root / 'plugins/demo' / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('{"name":"demo","version":"old"}')
            packages.finish_release(catalog, root)
            versions = {json.loads((root / 'plugins/demo' / name).read_text())['version'] for name in ('plugin.json', '.codex-plugin/plugin.json', '.claude-plugin/plugin.json')}
            self.assertEqual(len(versions), 1)
            self.assertTrue(versions.pop().startswith('1.2.3+dotfiles.'))

    def test_download_checks_digest_and_preserves_complete_archive(self):
        content = b'archive fixture'
        source = {'repo': 'owner/repo', 'revision': 'a' * 40, 'sha256': hashlib.sha256(content).hexdigest()}
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp) / 'source.tgz'
            with patch('urllib.request.urlopen', return_value=io.BytesIO(content)):
                packages.download(source, target)
            self.assertEqual(target.read_bytes(), content)
            with patch('urllib.request.urlopen', return_value=io.BytesIO(b'corrupt')):
                with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                    packages.download(source, target)

    def test_archive_subtree_retains_support_files_and_rejects_escape(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive = root / 'source.tgz'
            with tarfile.open(archive, 'w:gz') as tar:
                for name, content in [('repo/plugin/skills/demo/SKILL.md', b'instructions'), ('repo/plugin/scripts/run.js', b'helper'), ('repo/other.txt', b'outside')]:
                    item = tarfile.TarInfo(name)
                    item.size = len(content)
                    tar.addfile(item, io.BytesIO(content))
            packages.unpack_package(archive, 'plugin', root / 'package')
            self.assertEqual((root / 'package/scripts/run.js').read_bytes(), b'helper')
            self.assertFalse((root / 'package/other.txt').exists())
            with tarfile.open(archive, 'w:gz') as tar:
                item = tarfile.TarInfo('repo/plugin/../../escape')
                tar.addfile(item, io.BytesIO(b''))
            with self.assertRaisesRegex(ValueError, 'Unsafe archive path'):
                packages.unpack_package(archive, 'plugin', root / 'package')
            self.assertFalse((root / 'escape').exists())


if __name__ == '__main__':
    unittest.main()
