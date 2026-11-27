import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import zipfile


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('artifact_zip', type=Path)
    parser.add_argument('--commit', required=True)
    args = parser.parse_args()
    script_dir = Path(__file__).resolve().parent
    artifacts_dir = script_dir.parent / 'artifacts'
    staging = artifacts_dir / 'windows-artifact-unpacked'
    final = artifacts_dir / 'GTA6-Test01-Windows'
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)
    with zipfile.ZipFile(args.artifact_zip) as z:
        if z.testzip() is not None:
            raise RuntimeError('Artifact ZIP failed its CRC check')
        for name in z.namelist():
            target = (staging / name).resolve()
            if not target.is_relative_to(staging.resolve()):
                raise RuntimeError('Artifact path escapes staging')
        z.extractall(staging)
    roots = [p.parent for p in staging.rglob('BUILD-RESULT.txt')
             if (p.parent / 'patched/kyty_emulator.exe').is_file()]
    if len(roots) != 1:
        raise RuntimeError('Cannot identify one complete Windows runtime package')
    root = roots[0]
    result = (root / 'BUILD-RESULT.txt').read_text(encoding='utf-8-sig')
    if args.commit not in result:
        raise RuntimeError('Artifact source commit differs from the selected successful build')
    exe = root / 'patched/kyty_emulator.exe'
    with exe.open('rb') as f:
        header = f.read(64)
        if header[:2] != b'MZ':
            raise RuntimeError('Expected a Windows PE executable')
        offset = struct.unpack_from('<I', header, 0x3c)[0]
        f.seek(offset)
        pe = f.read(6)
        if pe[:4] != b'PE\x00\x00' or struct.unpack_from('<H', pe, 4)[0] != 0x8664:
            raise RuntimeError('Expected a Windows x86-64 executable')
    checked = 0
    for line in (root / 'SHA256SUMS.txt').read_text(encoding='utf-8-sig').splitlines():
        checksum, relative = line.split('  ', 1)
        path = root / relative.replace('\\', '/')
        if digest(path).upper() != checksum.upper():
            raise RuntimeError('Runtime SHA-256 mismatch: ' + relative)
        checked += 1
    if checked == 0:
        raise RuntimeError('Runtime checksum manifest is empty')
    if final.exists():
        shutil.rmtree(final)
    final.mkdir()
    for name in ['patched', 'source']:
        shutil.copytree(root / name, final / name)
    for name in ['LICENSE', 'BUILD-RESULT.txt', 'CLI-CHECK.txt']:
        shutil.copy2(root / name, final / name)
    for name in ['START-GTA6.cmd', 'START-GTA6-BASELINE.cmd', 'Launch-Patched.cmd',
                 'START-HERE.txt']:
        content = (script_dir / name).read_text()
        (final / name).write_bytes(content.replace('\r\n', '\n').replace('\n', '\r\n').encode())
    with (final / 'BUILD-RESULT.txt').open('a', encoding='utf-8') as f:
        f.write('\nPackaging verification: ZIP CRC, Windows x86-64 PE header, source commit, '
                f'and {checked} runtime SHA-256 hashes verified.\n')
        f.write('The final interactive CMD launcher flow has not been run here.\n')
    files = sorted(p for p in final.rglob('*') if p.is_file())
    lines = [f'{digest(p)}  {p.relative_to(final).as_posix()}' for p in files]
    (final / 'SHA256SUMS.txt').write_text('\n'.join(lines) + '\n')
    out_zip = artifacts_dir / 'GTA6-Test01-Windows.zip'
    with zipfile.ZipFile(out_zip, 'w', zipfile.ZIP_DEFLATED) as z:
        for p in sorted(final.rglob('*')):
            if p.is_file():
                z.write(p, p.relative_to(artifacts_dir))
    with zipfile.ZipFile(out_zip) as z:
        if z.testzip() is not None:
            raise RuntimeError('Final package ZIP failed its CRC check')
    print(json.dumps({'file': str(out_zip), 'bytes': out_zip.stat().st_size,
                      'sha256': digest(out_zip), 'runtime_files_verified': checked,
                      'commit': args.commit}, indent=2))


if __name__ == '__main__':
    main()
