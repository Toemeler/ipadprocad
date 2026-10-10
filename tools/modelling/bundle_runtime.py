#!/usr/bin/env python3
"""Resolve once, then fetch the exact hash-locked offline Pyodide CAD bundle.

Normal builds only download runtime-lock.json; --resolve explicitly updates it.
All downloads keep TLS verification. Nothing is downloaded by the iPad runtime.
"""
import argparse
import hashlib
import json
import shutil
import urllib.request
import zipfile
from collections import deque
from pathlib import Path

from packaging.markers import default_environment
from packaging.requirements import Requirement
from packaging.utils import canonicalize_name
from packaging.version import Version

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / 'tools/modelling/runtime-lock.json'
DEST = ROOT / 'frontend/assets/modelling'
BASE = 'https://cdn.jsdelivr.net/pyodide/v0.29.5/full/'


def fetch(url):
    with urllib.request.urlopen(url, timeout=90) as response:
        return response.read()


def metadata(name, version=None):
    return json.loads(fetch('https://pypi.org/pypi/' + name +
                            ('/' + version if version else '') + '/json'))


def resolve():
    lock_bytes = fetch(BASE + 'pyodide-lock.json')
    pyodide = json.loads(lock_bytes)
    files = []
    def add(filename, url, digest, kind):
        if not any(f['file'] == filename for f in files):
            files.append({'file': filename, 'url': url, 'sha256': digest, 'kind': kind})
    for filename in ['pyodide.js', 'pyodide.asm.js', 'pyodide.asm.wasm', 'python_stdlib.zip', 'pyodide-lock.json']:
        data = lock_bytes if filename == 'pyodide-lock.json' else fetch(BASE + filename)
        add(filename, BASE + filename, hashlib.sha256(data).hexdigest(), 'runtime')
    env = default_environment() | {'python_version': '3.13', 'python_full_version': '3.13.2',
          'sys_platform': 'emscripten', 'platform_system': 'Emscripten',
          'platform_machine': 'wasm32', 'extra': ''}
    queue = deque(['build123d==0.11.1', 'micropip'])
    chosen = {}
    pyodide_names = []
    pure_wheels = []
    aliases = {'cadquery-ocp-novtk': ('cadquery-ocp-novtk-ocp-wasm', '7.9.3.1.post202605200208'),
               'lib3mf': ('lib3mf-ocp-wasm', '2.5.0.post202605200051')}
    while queue:
        req = Requirement(queue.popleft())
        if req.marker and not req.marker.evaluate(env): continue
        name = canonicalize_name(req.name)
        if name in chosen:
            if Version(chosen[name]) not in req.specifier:
                raise ValueError(f'conflicting requirement: {req}, selected {chosen[name]}')
            continue
        if name in aliases:
            package, version = aliases[name]
            info = metadata(package, version)
            selected = next(f for f in info['urls'] if 'cp313-cp313-pyemscripten_2025_0_wasm32' in f['filename'])
            chosen[name] = version
            add(selected['filename'], selected['url'], selected['digests']['sha256'], 'wheel')
            pure_wheels.append(selected['filename'])
            continue
        bundled = pyodide['packages'].get(name)
        if bundled:
            version = bundled['version']
            if Version(version) not in req.specifier:
                raise ValueError(f'Pyodide package {name}=={version} does not satisfy {req}')
            chosen[name] = version
            add(bundled['file_name'], BASE + bundled['file_name'], bundled['sha256'], 'package')
            pyodide_names.append(name)
            queue.extend(bundled['depends'])
            continue
        info = metadata(name)
        versions = sorted((Version(v) for v in info['releases'] if not Version(v).is_prerelease
                           and Version(v) in req.specifier), reverse=True)
        for version in versions:
            record = metadata(name, str(version))
            candidates = [f for f in record['urls'] if f['filename'].endswith('none-any.whl') and not f.get('yanked')]
            requires_python = record['info'].get('requires_python')
            if requires_python and Version('3.13.2') not in Requirement('python'+requires_python).specifier:
                continue
            if candidates:
                selected = candidates[0]
                break
        else:
            raise ValueError(f'No portable wheel for {req}; cannot silently substitute a native wheel')
        chosen[name] = str(version)
        add(selected['filename'], selected['url'], selected['digests']['sha256'], 'wheel')
        pure_wheels.append(selected['filename'])
        queue.extend(record['info'].get('requires_dist') or [])
    result = {'pyodide': '0.29.5', 'build123d': '0.11.1', 'packages': sorted(pyodide_names),
              'wheels': pure_wheels, 'versions': chosen, 'files': files}
    LOCK.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    return result


def install(lock):
    DEST.mkdir(parents=True, exist_ok=True)
    for item in lock['files']:
        path = DEST / item['file']
        if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256']:
            continue
        print('Bundling', item['file'], flush=True)
        data = fetch(item['url'])
        if hashlib.sha256(data).hexdigest() != item['sha256']:
            raise ValueError('hash mismatch: ' + item['file'])
        path.write_bytes(data)
    (DEST / 'manifest.json').write_text(json.dumps({k: lock[k] for k in ['pyodide','build123d','packages','wheels']}), encoding='utf-8')
    # Bundle redistribution notices for every wheel, including OCP/OCCT and
    # their dependency licenses. Preserve the notices already inside wheels.
    notices = []
    for item in lock['files']:
        path = DEST / item['file']
        if zipfile.is_zipfile(path) and item['file'].endswith('.whl'):
            with zipfile.ZipFile(path) as wheel:
                for entry in wheel.namelist():
                    if any(word in entry.lower().split('/')[-1] for word in ['license', 'copying', 'notice']):
                        try:
                            notices.append(f'\n--- {item["file"]}: {entry} ---\n' + wheel.read(entry).decode())
                        except UnicodeDecodeError: pass
    (DEST / 'THIRD_PARTY_NOTICES.txt').write_text('\n'.join(notices), encoding='utf-8')
    shutil.copyfile(ROOT / 'modelling/runner.py', DEST / 'runner.py')
    shutil.copyfile(ROOT / 'modelling/history.py', DEST / 'history.py')
    shutil.copyfile(ROOT / 'frontend/assets/fonts/Inter-Regular.ttf', DEST / 'Inter-Regular.ttf')
    shutil.copyfile(ROOT / 'frontend/assets/fonts/Inter-LICENSE.txt', DEST / 'Inter-LICENSE.txt')
    for asset in DEST.iterdir():
        if asset.is_file(): asset.chmod(0o644)
    print('Runtime bundle bytes:', sum(p.stat().st_size for p in DEST.iterdir() if p.is_file()))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--resolve', action='store_true')
    args = parser.parse_args()
    install(resolve() if args.resolve else json.loads(LOCK.read_text(encoding='utf-8')))
