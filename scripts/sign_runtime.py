#!/usr/bin/env python3
"""Re-sign an existing qualified runtime without changing its unsigned code.

This records a signing derivation, not a fresh source build or release approval.
The pinned Apple library is preserved. Requires Python 3.11 with tar data filter.
"""
import argparse
import copy
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import subprocess
import tarfile
import tempfile

from derive_runtime import sha, tree, unsigned_identical, write_archive

APPLE = 'lib/external/libd3dshared.dylib'
APPLE_SHA = '5131e631eee8b542eadf48f4df9fd662d9aeeb59139137e0e6e14047dc434995'
MAGICS = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xce\xfa\xed\xfe'}


def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True)


def signature(path):
    info = run('codesign', '-dvv', path).stderr.decode()
    identifier = re.search(r'^Identifier=(.+)$', info, re.M)
    if not identifier:
        raise ValueError(f'Missing signing identifier: {path.name}')
    xml = run('codesign', '-d', '--xml', '--entitlements', '-', path).stdout
    return identifier.group(1), plistlib.loads(xml) if xml.strip() else None


def extract_verified(archive, dest):
    with tarfile.open(archive) as tar:
        members = tar.getmembers()
        names = [m.name for m in members]
        if len(names) != len(set(names)):
            raise ValueError('Duplicate archive entries')
        for member in members:
            name = PurePosixPath(member.name)
            if name.is_absolute() or '..' in name.parts or str(name) != member.name:
                raise ValueError('Unsafe archive path: ' + member.name)
            if not (member.isfile() or member.isdir() or member.issym()):
                raise ValueError('Unsupported archive entry: ' + member.name)
            tarfile.data_filter(member, str(dest))
        manifest = json.load(tar.extractfile('runtime.json'))
        if {m.name for m in members if not m.isdir()} != set(manifest['files']) | {'runtime.json'}:
            raise ValueError('Archive differs from its file list')
        tar.extractall(dest, filter='data')
    for name, entry in manifest['files'].items():
        path = dest / name
        if 'symlink' in entry:
            valid = path.is_symlink() and os.readlink(path) == entry['symlink']
        else:
            valid = not path.is_symlink() and sha(path) == entry['sha256'] and path.stat().st_size == entry['bytes']
        if not valid:
            raise ValueError('Manifest mismatch: ' + name)
    return manifest


def sign_runtime(archive, output, version, identity):
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,63}', version):
        raise ValueError('Invalid version')
    if output.exists() or Path(str(output) + '.tar.gz').exists():
        raise ValueError('Use a new output path')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as temporary:
        base = Path(temporary) / 'base'
        base.mkdir()
        manifest = extract_verified(archive, base)
        before = tree(base)
        run('/bin/cp', '-Rc', base, output)
        if sha(base / APPLE) != APPLE_SHA:
            raise ValueError('Unexpected Apple component')
        run('codesign', '--verify', '--strict', '-R=anchor apple', base / APPLE)
        native = []
        for name, entry in manifest['files'].items():
            if 'symlink' not in entry:
                with (base / name).open('rb') as f:
                    if f.read(4) in MAGICS and name != APPLE:
                        native.append(name)
        bundles = sorted({str(p.relative_to(output)) for p in output.rglob('*.app')}, key=lambda s: -s.count('/'))
        for name in [*sorted(native), *bundles]:
            identifier, entitlements = signature(base / name)
            args = ['codesign', '--force', '--options', 'runtime', '--timestamp', '--sign', identity, '--identifier', identifier]
            if entitlements is not None:
                plist = Path(temporary) / 'entitlements.plist'
                plist.write_bytes(plistlib.dumps(entitlements))
                args += ['--entitlements', plist]
            run(*args, output / name)
            run('codesign', '--verify', '--strict', output / name)
            if signature(output / name) != (identifier, entitlements):
                raise ValueError('Signing metadata changed: ' + name)
            info = run('codesign', '-dvv', output / name).stderr.decode()
            if 'Authority=Developer ID Application:' not in info or '(runtime)' not in info:
                raise ValueError('Missing Developer ID or hardened runtime: ' + name)
            print('Signed ' + name, flush=True)
        for name in native:
            if not unsigned_identical(base / name, output / name):
                raise ValueError('Unsigned code changed: ' + name)
        after = tree(output)
        changed = {k for k in before.keys() | after.keys() if before.get(k) != after.get(k)}
        allowed = set(native) | {b + '/Contents/_CodeSignature/CodeResources' for b in bundles}
        if not changed <= allowed or before[APPLE] != after[APPLE]:
            raise ValueError('Unexpected runtime changes: ' + str(sorted(changed - allowed)))
        original = copy.deepcopy(manifest)
        for name in changed:
            path = output / name
            manifest['files'][name] = {'sha256': sha(path), 'bytes': path.stat().st_size}
        manifest['version'] = version
        manifest['signing_derivation'] = {'base_version': original['version'], 'base_archive_sha256': sha(archive),
            'identity': identity, 'changed': sorted(changed), 'unsigned_code_identical': True,
            'apple_component_unmodified': True}
        (output / 'runtime.json').write_text(json.dumps(manifest, indent=2) + '\n')
        result = write_archive(output)
        proof = {'version': version, 'archive_sha256': sha(result), 'archive_bytes': result.stat().st_size,
                 'signed_native_components': len(native), **manifest['signing_derivation']}
        result.with_suffix('.json').write_text(json.dumps(proof, indent=2) + '\n')
        print(json.dumps(proof, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--identity', required=True)
    args = parser.parse_args()
    sign_runtime(args.archive.resolve(), args.output.resolve(), args.version, args.identity)
