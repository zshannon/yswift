#!/usr/bin/env python3
"""Refresh vendored Yrs, rebasing our local diff with Git's three-way merge."""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import tomllib


def rebase_patch(current, incoming, patch):
    conflicts = []
    with tempfile.TemporaryDirectory() as directory:
        baseline = (Path(directory) / 'baseline').resolve()
        shutil.copytree(current, baseline)
        if patch.read_text():
            subprocess.run(['git', 'apply', '--reverse', '--unsafe-paths',
                            f'--directory={baseline}', str(patch.resolve())], check=True)
        delta = []
        paths = sorted({p.relative_to(current) for p in current.rglob('*') if p.is_file()}
                       | {p.relative_to(baseline) for p in baseline.rglob('*') if p.is_file()})
        for relative in paths:
            ours = (current / relative).read_bytes() if (current / relative).exists() else b''
            base = (baseline / relative).read_bytes() if (baseline / relative).exists() else b''
            if ours == base:
                continue
            target = incoming / relative
            theirs = target.read_bytes() if target.exists() else b''
            inputs = [Path(directory) / name for name in ('ours', 'base', 'theirs')]
            for path, data in zip(inputs, (ours, base, theirs)):
                path.write_bytes(data)
            result = subprocess.run(['git', 'merge-file', '-p', '-L', 'YSwift fix',
                                     '-L', 'previous upstream', '-L', 'new upstream',
                                     *map(str, inputs)], capture_output=True)
            if result.returncode < 0 or result.returncode > 127:
                raise RuntimeError(result.stderr.decode())
            if result.returncode:
                conflicts.append(str(relative))
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(result.stdout)
            delta.extend(difflib.unified_diff(theirs.decode().splitlines(keepends=True),
                                             result.stdout.decode().splitlines(keepends=True),
                                             fromfile=f'a/{relative}', tofile=f'b/{relative}'))
        patch.write_text(''.join(delta))
    return conflicts


def update(source):
    root = Path(__file__).resolve().parent.parent
    state_path = root / '.github/upstream-yrs.json'
    previous = json.loads(state_path.read_text())
    revision = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if revision == previous['revision']:
        print('Yrs is already current.')
        return
    version = tomllib.loads((source / 'yrs/Cargo.toml').read_text())['package']['version']
    with tempfile.TemporaryDirectory() as directory:
        temporary = Path(directory)
        subprocess.run(['cargo', 'package', '--manifest-path', str(source / 'yrs/Cargo.toml'),
                        '--no-verify', '--target-dir', str(temporary / 'target')], check=True)
        archive = temporary / f'target/package/yrs-{version}.crate'
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        with tarfile.open(archive) as package:
            package.extractall(temporary / 'unpacked', filter='data')
        incoming = temporary / f'unpacked/yrs-{version}'
        for name in ('.cargo_vcs_info.json', '.cargo-checksum.json', '.cargo-ok'):
            (incoming / name).unlink(missing_ok=True)
        shutil.copyfile(source / 'LICENSE', incoming / 'LICENSE')
        conflicts = rebase_patch(root / 'lib/vendor/yrs', incoming, root / 'lib/vendor/yrs-undo-drop.patch')
        shutil.rmtree(root / 'lib/vendor/yrs')
        shutil.copytree(incoming, root / 'lib/vendor/yrs')
    state_path.write_text(json.dumps({'revision': revision, 'version': version,
                                     'archive_sha256': digest, 'conflicts': conflicts}, indent=2) + '\n')
    manifest = root / 'lib/Cargo.toml'
    manifest.write_text(re.sub(r'(yrs = \{ version = ")=[^"]+', rf'\g<1>={version}', manifest.read_text(), count=1))
    swift = root / 'Package.swift'
    text = re.sub(r'^let binaryURL: String\? = .*$', 'let binaryURL: String? = nil', swift.read_text(), flags=re.M)
    swift.write_text(re.sub(r'^let binaryChecksum = .*$', 'let binaryChecksum = ""', text, flags=re.M))
    summary = (f'Update vendored Yrs to [{revision[:12]}](https://github.com/y-crdt/y-crdt/commit/{revision}) '
               f'(crate version {version}).\n\n'
               f'[Upstream changes](https://github.com/y-crdt/y-crdt/compare/{previous["revision"]}...{revision}).\n\n'
               'The local undo-manager fix was rebased with Git three-way merge. '
               'The package uses a local framework until a new binary release is cut.\n\n')
    summary += ('Merge conflicts require resolution: ' + ', '.join(conflicts) + '.\n' if conflicts
                else 'No merge conflicts. Native and Swift validation runs below.\n')
    report = Path(os.environ.get('RUNNER_TEMP', tempfile.gettempdir())) / 'yswift-upstream-pr.md'
    report.write_text(summary)
    if output := os.environ.get('GITHUB_OUTPUT'):
        with open(output, 'a') as handle:
            handle.write(f'changed=true\nconflicts={str(bool(conflicts)).lower()}\n')
    print(summary)
    subprocess.run(['cargo', 'update', '--manifest-path', str(manifest), '-p', 'yrs'], check=True)


def check():
    root = Path(__file__).resolve().parent.parent
    state = json.loads((root / '.github/upstream-yrs.json').read_text())
    if state['conflicts']:
        raise RuntimeError('Resolve vendor conflicts, regenerate the local patch, and clear conflict metadata.')
    patch = root / 'lib/vendor/yrs-undo-drop.patch'
    if patch.read_text():
        subprocess.run(['git', 'apply', '--check', '--reverse', '--unsafe-paths',
                        f'--directory={root / "lib/vendor/yrs"}', str(patch)], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--source', type=Path)
    action.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.check:
        check()
    else:
        update(args.source.resolve())
