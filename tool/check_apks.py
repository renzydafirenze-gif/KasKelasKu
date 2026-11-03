"""Verify delivered per-ABI APKs against recorded checksums. Run from any cwd."""
import hashlib
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1] / 'dist'
# name -> (sha256, expected ABI)
expected = {
    'KasKelasKu-1.2.4-arm64.apk': (
        '684a40ed69d8847aa4c624566ad2dd9afa94ba356e1ca0063aba757cfaa3273d',
        'arm64-v8a'),
    'KasKelasKu-1.2.4-armeabi-v7a.apk': (
        'c410498976cd7b277ff1a5e8714272ebab092c083925fb6bfd11d94445e4d1de',
        'armeabi-v7a'),
}
for name, (digest, abi) in expected.items():
    file = root / name
    hasher = hashlib.sha256()
    with file.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            hasher.update(block)
    if hasher.hexdigest() != digest:
        raise SystemExit(f'Checksum mismatch: {file}')
    with zipfile.ZipFile(file) as apk:
        bad_entry = apk.testzip()
        if bad_entry is not None:
            raise SystemExit(f'Corrupt APK entry: {bad_entry}')
        names = apk.namelist()
        if f'lib/{abi}/libapp.so' not in names:
            raise SystemExit(f'Missing {abi}/libapp.so: {name}')
        native = {n.split('/')[1] for n in names if n.startswith('lib/')}
        if native != {abi}:
            raise SystemExit(f'Unexpected ABIs {sorted(native)}: {name}')
        if any(n.endswith('libsqlcipher.so') for n in names):
            raise SystemExit(f'Unexpected SQLCipher library: {name}')
    print(f'OK {name}: checksum, ZIP integrity, single ABI {abi}, no SQLCipher')
print('Not a signature, runtime security, or release-readiness audit.')
