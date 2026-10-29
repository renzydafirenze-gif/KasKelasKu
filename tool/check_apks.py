"""Verify the delivered 1.2.2 APK against its recorded checksum. Run from any cwd."""
import hashlib
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1] / 'dist'
expected = {
    'KasKelasKu-1.2.2-production.apk': '774b45f8079f8cecbb2281d0af456a6a8ff8d280a476f2f25c19207c5452382b',
}
for name, digest in expected.items():
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
        for abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']:
            if f'lib/{abi}/libapp.so' not in names:
                raise SystemExit(f'Missing {abi}/libapp.so: {name}')
        if any(n.endswith('libsqlcipher.so') for n in names):
            raise SystemExit(f'Unexpected SQLCipher library: {name}')
    print(f'OK {name}: checksum, ZIP integrity, app libraries, no SQLCipher')
print('Not a signature, runtime security, or release-readiness audit.')
