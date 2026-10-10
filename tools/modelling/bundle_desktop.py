#!/usr/bin/env python3
"""Bundle the exact headless engine beside a Windows/Linux app, never at runtime.

Downloads are SHA256-locked. The archive's notices, resources and dependency
DLLs travel with the engine. Use --cache to reuse verified build downloads.
"""
import argparse
import hashlib
import json
import shutil
import re
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / 'tools/modelling/desktop-runtime-lock.json'


def linux_libraries(stage):
    """Keep the engine's closure separate from Flutter/Qt's library versions."""
    result = subprocess.run(['ldd', str(stage / 'chrome-headless-shell')],
                            check=True, text=True, capture_output=True)
    if 'not found' in result.stdout:
        raise ValueError('Missing desktop CAD engine library: ' + result.stdout)
    libraries = stage / 'lib'
    libraries.mkdir()
    notices = stage / 'linux-library-notices'
    notices.mkdir()
    for name, source in re.findall(r'^\s*(\S+)\s+=>\s+(/\S+)\s+\(', result.stdout, re.M):
        # glibc and the C/C++ runtime remain owned by the supported OS, like
        # Flutter itself. Every other dynamically linked dependency ships.
        if re.match(r'^(lib(c|m|dl|pthread|rt|resolv|gcc_s|stdc\+\+)\.so|ld-linux)', name):
            continue
        shutil.copyfile(source, libraries / name)
        paths = [source, str(Path(source).resolve())]
        if source.startswith('/lib/'):
            paths.append('/usr' + source)
        package = None
        for candidate in paths:
            query = subprocess.run(['dpkg-query', '-S', candidate], text=True, capture_output=True)
            if query.returncode == 0:
                package = query.stdout.split(': ')[0].split(':')[0]
                break
        if not package or not (Path('/usr/share/doc') / package / 'copyright').is_file():
            raise ValueError('Missing redistribution notice for ' + name)
        shutil.copyfile(Path('/usr/share/doc') / package / 'copyright', notices / (package + '.txt'))


def bundle(platform, destination, cache, bundle_linux_libs=False):
    lock = json.loads(LOCK.read_text())
    item = lock['platforms'][platform]
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / f'{platform}.zip'
    if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != item['sha256']:
        temporary = archive.with_suffix('.download')
        print('Bundling offline desktop CAD engine', platform, lock['version'], flush=True)
        urllib.request.urlretrieve(item['url'], temporary)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != item['sha256']:
            temporary.unlink()
            raise ValueError('Desktop CAD engine SHA256 mismatch')
        temporary.replace(archive)
    stage = destination.with_name(destination.name + '.staging')
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    with zipfile.ZipFile(archive) as z:
        for entry in z.infolist():
            parts = Path(entry.filename).parts
            if not parts or parts[0] != item['archiveRoot'] or '..' in parts:
                raise ValueError('Unexpected runtime archive path: ' + entry.filename)
            target = stage.joinpath(*parts[1:])
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with z.open(entry) as source, target.open('wb') as output:
                shutil.copyfileobj(source, output)
            target.chmod(0o755 if target.name == item['executable'] else 0o644)
    for name in [item['executable'], 'LICENSE.headless_shell', 'ABOUT']:
        if not (stage / name).is_file():
            raise ValueError('Missing desktop runtime member: ' + name)
    if bundle_linux_libs:
        if platform != 'linux64' or sys.platform != 'linux':
            raise ValueError('Linux library collection requires a Linux build host')
        linux_libraries(stage)
    (stage / 'runtime-version.json').write_text(json.dumps({
        'version': lock['version'], 'platform': platform, 'sha256': item['sha256'],
    }, indent=2) + '\n')
    if destination.exists():
        shutil.rmtree(destination)
    stage.replace(destination)
    print('Offline desktop CAD engine ready:', destination, flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--platform', choices=['linux64', 'win64'], required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--cache', type=Path, default=ROOT / 'build/desktop-cad-downloads')
    parser.add_argument('--bundle-linux-libs', action='store_true')
    args = parser.parse_args()
    bundle(args.platform, args.destination, args.cache, args.bundle_linux_libs)
