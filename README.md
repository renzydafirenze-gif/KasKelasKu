# KasKelasKu

Aplikasi kas kelas offline Android/iOS. Tanpa akun, tanpa sandi, tanpa enkripsi:
buka aplikasi langsung masuk sebagai Bendahara.

APK produksi terbaru: `dist/KasKelasKu-1.2.0-production.apk`.
Petunjuk pemasangan, checksum dan signing: [`docs/ANDROID-RELEASE.md`](docs/ANDROID-RELEASE.md).

## Menjalankan

Flutter **3.24.0 menyertakan Dart 3.5.0**, bukan Dart 3.4. Batas bahasa proyek tetap >=3.4.

```sh
flutter pub get
flutter analyze
flutter test --coverage
python3 tool/check_schema.py
python3 tool/check_coverage.py
flutter run -d <ID-perangkat-dari-flutter-devices>
```

Android memerlukan SDK dan Java 17. iOS memerlukan macOS, Xcode dan CocoaPods.
Android minimum API 23. Konfigurasi signing rilis wajib disediakan sendiri;
build rilis tidak memakai kunci debug.

## Alur

1. Buka aplikasi, isi nama. Pengguna pertama otomatis menjadi Bendahara.
2. Tambah anggota dengan nama dan peran. Tidak ada sandi dan tidak ada ID akun.
3. Ganti pengguna lewat chip nama di bilah atas atau kartu Pengguna di Setelan.
4. Bendahara mencatat/menghapus transaksi, mengatur target kas bulanan, dan mengelola anggota.
5. Ketua menyetujui dan mengunci bulan. Guru Wali memverifikasi setelah penguncian.
6. Semua peran membaca saldo, riwayat, dan laporan. Backend tetap memeriksa peran tiap mutasi.

Entry transaksi: nominal dengan chip tambah cepat, chip penyetor, chip kategori,
dan pemilih tanggal. Keterangan kosong otomatis memakai kategori.
Duplikat fingerprint meminta konfirmasi sebelum disimpan.

Target kas adalah target total kelas per bulan, bukan target per siswa.
Riwayat dipaginasi 100 baris dengan pencarian dan filter bulan.

## Data

- Database SQLite polos di direktori support aplikasi (`kaskelasku.db`).
- Backup berupa JSON polos `.json` berisi anggota, transaksi, laporan dan audit.
- Pemulihan hanya ke data kosong; tidak ada merge atau penimpaan ledger lama.
- Laporan dibagikan sebagai PDF/CSV biasa lewat lembar berbagi sistem.
- Database lama berformat SQLCipher tidak bisa dibuka; saat pertama dibuka berkas
  itu dipindahkan ke `kaskelasku.db.legacy` dan aplikasi mulai dengan data kosong.

**Data tidak dienkripsi.** Siapa pun yang membuka aplikasi atau menyalin berkas
database dapat melihat dan mengubah isi. Backup JSON juga terbaca bebas.
Simpan dan bagikan hanya lewat kanal tepercaya.

## Struktur

- `lib/models.dart`: model, validasi, fingerprint SHA-256.
- `lib/data/schema.sql`: constraint, indeks, audit, trigger bulan terkunci.
- `lib/data/repository.dart`: SQLite, sesi pengguna, izin per peran, backup/restore.
- `lib/data/backup.dart`: validasi cadangan sebelum menyentuh database aktif.
- `lib/data/exports.dart`: PDF multi-halaman, CSV aman formula, backup JSON atomik.
- `lib/view_model.dart`: MVVM, Riverpod 1.
- `lib/main.dart`: layar, tema terang/gelap, sheet entry transaksi.
- `integration_test/reports_test.dart`: database asli, ekspor, penguncian, 10.000 baris.

## QA

- `flutter analyze --fatal-infos` bersih.
- `flutter test --coverage` lulus; gate coverage 100% wajib.
- `python3 tool/check_schema.py` menguji invariansi SQLite asli.
- Tes integrasi memerlukan emulator/perangkat Android; bukan bukti performa perangkat.

Belum dicakup: audit aksesibilitas TalkBack/VoiceOver, uji kedua platform di
perangkat nyata, dan pengujian disk penuh/corruption/crash injection.
