#!/usr/bin/env python3
"""Native CLI fixture with real local package copies; no network or model calls."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'agents/plugins'))
import package_store as packages

agent = Path(sys.argv[0]).name
args = sys.argv[1:]
home = Path.home()
codex_home = Path(os.environ.get('CODEX_HOME', str(home / '.codex')))
catalog = json.loads((ROOT / 'agents/plugins/catalog.json').read_text())
state_path = (codex_home if agent == 'codex' else home / '.claude') / 'mock-plugins.json'
state = json.loads(state_path.read_text()) if state_path.exists() else {'marketplaces': {}, 'plugins': []}


def output(value):
    print(json.dumps(value), flush=True)


def save():
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(state))
    if agent == 'codex':
        text = ''
        for name, source in state['marketplaces'].items():
            text += '[marketplaces.' + name + ']\nsource_type = "local"\nsource = ' + json.dumps(source) + '\n\n'
        for plugin in state['plugins']:
            text += '[plugins.' + json.dumps(plugin['pluginId']) + ']\nenabled = ' + str(plugin['enabled']).lower() + '\n\n'
        (codex_home / 'config.toml').write_text(text)
    else:
        directory = home / '.claude/plugins'
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'known_marketplaces.json').write_text(json.dumps({name: {'source': {'source': 'directory', 'path': source}} for name, source in state['marketplaces'].items()}))
        (directory / 'installed_plugins.json').write_text(json.dumps({'version': 2, 'plugins': {p['id']: [p] for p in state['plugins']}}))
        settings_path = home / '.claude/settings.json'
        if not settings_path.is_symlink():
            settings = json.loads(settings_path.read_text()) if settings_path.exists() else {}
            settings['enabledPlugins'] = {p['id']: p['enabled'] for p in state['plugins']}
            settings_path.write_text(json.dumps(settings))


def mutation():
    with (home / 'plugin-calls').open('a') as stream:
        stream.write(agent + ' ' + ' '.join(args) + '\n')
    if os.environ.get('TEST_PLUGIN_EXIT') and args[:2] in (['plugin', 'install'], ['plugin', 'add']):
        sys.exit(int(os.environ['TEST_PLUGIN_EXIT']))


if args == ['seed']:
    release = packages.release_path(catalog)
    release.mkdir(parents=True)
    for plugin in catalog['plugins']:
        package = packages.package_path(catalog, plugin)
        package.mkdir(parents=True)
        for skill in plugin['skills']:
            path = package / 'skills' / skill / 'SKILL.md'
            path.parent.mkdir(parents=True)
            path.write_text('---\nname: ' + skill + '\ndescription: Fixture\n---\n')
        if plugin.get('mcp'):
            (package / '.mcp.json').write_text('{"mcpServers":{"fixture":{"command":"node"}}}')
    for plugin in catalog['plugins']:
        if plugin.get('pnpm_empty_importers'):
            (release / 'plugins' / plugin['id'].split('@')[0] / 'pnpm-lock.yaml').write_text('lockfileVersion: \'9.0\'\n\nimporters:\n\n  .: {}\n\npackages:\n')
    packages.finish_release(catalog, release)
    for skill in (ROOT / 'agents/skills').iterdir():
        if (skill / 'SKILL.md').is_file():
            for directory in ('.agents', '.claude'):
                subprocess.run([str(ROOT / 'scripts/link-file'), str(skill), str(home / directory / 'skills' / skill.name)], check=True, stdout=subprocess.DEVNULL)
elif args == ['--version']:
    print('2.1.294 (Claude Code)' if agent == 'claude' else 'codex-cli 0.157.0')
elif args[:3] == ['plugin', 'marketplace', 'add']:
    mutation()
    path = Path(args[3])
    manifest = json.loads((path / '.claude-plugin/marketplace.json').read_text())
    state['marketplaces'][manifest['name']] = str(path)
    save()
elif args[:2] == ['plugin', 'list']:
    output(state['plugins'] if agent == 'claude' else {'installed': state['plugins'], 'available': []})
elif args[:2] in (['plugin', 'install'], ['plugin', 'add'], ['plugin', 'update']):
    mutation()
    plugin_id = args[2]
    name, market = plugin_id.split('@')
    source = Path(state['marketplaces'][market]) / 'plugins' / name
    version = json.loads((source / '.claude-plugin/plugin.json').read_text())['version']
    target_home = codex_home if agent == 'codex' else home / '.claude'
    target = target_home / 'plugins/cache' / market / name / version
    if not target.exists():
        shutil.copytree(source, target)
    key = 'pluginId' if agent == 'codex' else 'id'
    state['plugins'] = [p for p in state['plugins'] if p[key] != plugin_id]
    state['plugins'].append({key: plugin_id, 'scope': 'user', 'installed': True, 'enabled': True, 'version': version, 'installPath': str(target)})
    save()
elif args[:2] in (['plugin', 'enable'], ['plugin', 'disable']):
    row = next(p for p in state['plugins'] if p['id'] == args[2])
    wanted = args[1] == 'enable'
    if row['enabled'] == wanted:
        print('Plugin already has that enabled state', file=sys.stderr)
        sys.exit(1)
    mutation()
    row['enabled'] = wanted
    save()
elif agent == 'codex' and args == ['app-server', '--stdio']:
    for line in sys.stdin:
        request = json.loads(line)
        if request['method'] == 'initialize':
            output({'id': request['id'], 'result': {}})
        elif request['method'] == 'config/read':
            entries = {name: {'source_type': 'local', 'source': path} for name, path in state['marketplaces'].items()}
            output({'id': request['id'], 'result': {'config': {'marketplaces': entries, 'plugins': {p['pluginId']: {'enabled': p['enabled']} for p in state['plugins']}}}})
        elif request['method'] == 'config/value/write':
            mutation()
            if request['params']['keyPath'] == 'marketplaces.dotfiles.source':
                state['marketplaces']['dotfiles'] = request['params']['value']
            else:
                plugin_id = re.fullmatch(r'plugins\."([^"]+)"\.enabled', request['params']['keyPath']).group(1)
                next(p for p in state['plugins'] if p['pluginId'] == plugin_id)['enabled'] = request['params']['value']
            save()
            print(json.dumps({'method': 'config/changed', 'params': {}}) + '\n' + json.dumps({'id': request['id'], 'result': {}}), flush=True)
        else:
            sys.exit(93)
else:
    print('Unexpected fixture call: ' + agent + ' ' + ' '.join(args), file=sys.stderr)
    sys.exit(92)
