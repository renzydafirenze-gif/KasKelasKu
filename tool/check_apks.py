"""Verify delivered preview artifacts, not release readiness. Run from any cwd."""
import hashlib
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1] / 'dist'
expected = {
    'KasKelasKu-1.0.0-rc2-preview.apk': '52568d0427603cf3a945eddd8b90b52c646397dd5e4c0cc11b6f615f8d11ddf0',
    'KasKelasKu-1.0.0-rc2-unsigned.apk': 'f5055629093bcc9e4665c1662d4e46426908024648498bdab16300232fbcaf61',
    'KasKelasKu-1.0.0-rc1-preview.apk': '638ba5cc58fa8ec16a7f60b4c9154c5b78303ea10a59ab96fb6448828ca1ae2c',
    'KasKelasKu-1.0.0-rc1-unsigned.apk': '4ed5a9706426bc67166e2e99f584915eeefe421b95debf2962fc205dbb6f2899',
    'KasKelasKu-1.0.0-preview.apk': '52568d0427603cf3a945eddd8b90b52c646397dd5e4c0cc11b6f615f8d11ddf0',
    'KasKelasKu-1.0.0-release-unsigned.apk': 'f5055629093bcc9e4665c1662d4e46426908024648498bdab16300232fbcaf61',
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
        for abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']:
            for library in ['libapp.so', 'libsqlcipher.so']:
                if f'lib/{abi}/{library}' not in apk.namelist():
                    raise SystemExit(f'Missing {abi}/{library}: {name}')
    print(f'OK {name}: checksum, ZIP integrity, app and SQLCipher libraries')
print('Not a signature, runtime security, or release-readiness audit.')
