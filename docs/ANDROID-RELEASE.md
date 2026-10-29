# Artefak Android — 28 Oktober 2026

## 1.2.2 — tahan dobel dan pengamanan disk

- Cek fingerprint + INSERT tetap di satu transaksi tulis (sqflite memakai
  `BEGIN IMMEDIATE`); guard `saving` di tombol Simpan mencegah dobel tap saat
  penulisan masih berjalan.
- `onConfigure` kini menyalakan `busy_timeout=5000`, `journal_mode=WAL`, dan
  `foreign_keys=ON` (per koneksi).
- Manifest tidak lagi meminta `USE_BIOMETRIC`; tidak ada plugin biometrik di APK.
- 72 tes host lulus; coverage 1582/1582 (100%).

## 1.2.1 — pembayaran per murid

- Tab Anggota kini menampilkan status bayar bulan berjalan per murid
  (Lunas beserta nominal atau Belum bayar), ringkasan "x dari y murid sudah bayar",
  total terkumpul, dan filter Belum bayar.
- Tombol Bayar pada baris murid membuka entry transaksi dengan nama penyetor dan
  kategori Kas sudah terisi; nominal langsung bisa diketik.
- Tambah banyak murid sekaligus dari satu kolom teks (satu nama per baris).
- `studentPayments()` di repository menghitung setoran per murid per bulan.
- 71 tes host lulus; coverage 1575/1575 (100%).

## 1.2.0 — tanpa enkripsi

- Enkripsi dihapus sepenuhnya: `sqflite` polos, tanpa `flutter_secure_storage`,
  tanpa `local_auth`, tanpa `cryptography`. `crypto` tersisa hanya untuk fingerprint SHA-256.
- Aplikasi langsung masuk sebagai Bendahara. Tidak ada kata sandi, ID akun, atau biometrik.
  Ganti pengguna lewat chip nama di bilah atas atau kartu Pengguna di Setelan.
- Database lama berformat SQLCipher dipindahkan sekali ke `kaskelasku.db.legacy`
  saat pertama dibuka; versi baru mulai dari data kosong.
- Target kas kini target total kelas per bulan. Fitur target per anggota dihapus.
- Backup berupa `.json` polos; laporan dibagikan sebagai `.pdf`/`.csv` biasa.
- Perbaikan cacat lama: target ikut tercadang, kolom CSV cocok dengan isinya,
  status target di laporan benar, tanggal dipilih lewat date picker.
- `flutter analyze --fatal-infos` bersih; tes host lulus; coverage 100%;
  `python3 tool/check_schema.py` lulus.

Belum ada bukti integrasi perangkat Android untuk 1.2.0 di sesi ini; lihat
`docs/SECURITY.md` untuk batasan yang masih berlaku.

## APK produksi

| Berkas | Ukuran | SHA-256 |
| --- | --- | --- |
| `dist/KasKelasKu-1.2.2-production.apk` | 54.371.122 byte | `774b45f8079f8cecbb2281d0af456a6a8ff8d280a476f2f25c19207c5452382b` |

Mode release, ditandatangani keystore produksi. `apksigner verify` lulus untuk
skema v1 dan v2; sertifikat `CN=KasKelasKu Production`,
SHA-256 `d279ad4139e6b65a2440fa7d966a67c201639928cf3ba266e310df127cb4bd97`
(sama dengan 1.1.1, 1.2.0 dan 1.2.1, jadi pemasangan pembaruan tidak bentrok sertifikat).

Verifikasi checksum:

```sh
python3 tool/check_apks.py
```

Pasang melalui pengelola berkas Android atau Android SDK:

```sh
adb install -r dist/KasKelasKu-1.2.2-production.apk
```

Jangan mengabaikan `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: kemungkinan sertifikat
berbeda. Jangan menghapus aplikasi yang memuat data penting untuk melewati error.
Cadangkan data lewat Setelan → Cadangkan data sebelum mengganti atau menghapus aplikasi.

## Build dengan signing produksi

Sediakan keystore sendiri dan simpan salinan aman terpisah. Jangan kirim kata
sandi atau keystore lewat percakapan dan jangan masukkan ke Git. Konfigurasi Gradle
membaca empat variabel lingkungan berikut dari penyimpanan rahasia CI atau shell:

- `KASKELASKU_KEYSTORE`: path absolut ke keystore.
- `KASKELASKU_STORE_PASSWORD`: kata sandi keystore.
- `KASKELASKU_KEY_ALIAS`: alias sertifikat.
- `KASKELASKU_KEY_PASSWORD`: kata sandi private key.

Tanpa keempat nilai tersebut build release sengaja tetap unsigned. Tidak ada
fallback signing produksi ke kunci debug. Setelah rahasia disediakan:

```sh
flutter pub get
flutter analyze --fatal-infos
flutter test --coverage
python3 tool/check_schema.py
python3 tool/check_coverage.py
flutter build apk --release
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
```

## Riwayat

### 1.1.1

Rilis sebelumnya, masih memakai database terenkripsi SQLCipher dan login berkata sandi.
Data dari versi ini tidak dibaca otomatis oleh 1.2.0.

### 1.0.0 RC2

- 93 tes host lulus; coverage 1202/1202 (100%).
- Preview ditandatangani debug; hanya untuk evaluasi.

### 1.0.0 RC1

- Preview lama crash release SQLCipher JNI akibat R8; diperbaiki di RC1.
