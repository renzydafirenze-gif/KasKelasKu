# KasKelasKu

Aplikasi kas kelas offline Android/iOS. **Implementasi awal, belum siap produksi.**

APK uji terbaru tersedia di `dist/KasKelasKu-1.0.0-rc2-preview.apk` (sekitar 68 MiB).
Mode release, signing debug untuk evaluasi saja; bukan rilis produksi.
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

1. Buat brankas dengan nama Bendahara dan kata sandi minimal 12 karakter.
2. Tambahkan anggota, tentukan peran dan kata sandi unik. Bagikan ID akun lewat kanal aman.
3. Masuk memakai ID, peran terdaftar, dan kata sandi. Pilihan peran bukan pemberian izin.
4. Bendahara mencatat/menghapus transaksi dan mengelola anggota. Penghapusan tercatat di audit.
5. Ketua menyetujui dan mengunci bulan. Guru Wali memverifikasi setelah penguncian.
6. Seluruh peran membaca saldo, riwayat, dan membuat laporan. Cadangan lengkap hanya Bendahara.
7. Ekspor laporan/cadangan melalui lembar berbagi sistem. Kata sandi ekspor dikirim terpisah.

Bulan kosong menghasilkan laporan saldo awal/akhir, bukan kegagalan.
Duplikat kiriman dicegah token unik; pembayaran serupa memerlukan konfirmasi.
Riwayat dipaginasi 100 baris; saldo dashboard tidak dipengaruhi filter riwayat.
Biometrik hanya membuka **akun terakhir yang sudah diautentikasi dalam proses ini**;
mulai ulang aplikasi tetap memerlukan kata sandi. Kunci database tetap ada di memori
untuk fitur buka ulang ini; Dart tidak menjamin penghapusan memori kriptografi.

## Struktur

- `lib/models.dart`: model dan validasi batas input.
- `lib/data/schema.sql`: constraint, indeks, audit, trigger bulan terkunci.
- `lib/data/vault.dart`: PBKDF2-HMAC-SHA256 600.000 iterasi, salt acak, AES-256-GCM.
- `lib/data/repository.dart`: SQLCipher, autentikasi, izin per transaksi database.
- `lib/data/exports.dart`: snapshot konsisten, PDF multi-halaman, CSV aman formula, ekspor atomik.
- `lib/view_model.dart`: MVVM, Riverpod 1, reactive Streams.
- `lib/main.dart`: layar, mode gelap tersimpan, kunci 3 menit dan saat latar belakang.
- `integration_test/reports_test.dart`: SQLCipher asli, ekspor, penguncian, kueri 10.000 baris.

## Enkripsi dan ancaman

Database memakai kunci acak 256-bit. Kunci ini dibungkus oleh kunci turunan
kata sandi masing-masing akun dan disimpan di flutter_secure_storage, bukan plaintext.
Pergantian kata sandi akun nantinya cukup membungkus ulang kunci database.
Ini sengaja memakai envelope encryption, bukan satu kunci database berbeda tiap peran.
Kata sandi salah dibatasi lima percobaan sebelum jeda 30 detik.

Backup `.kkbackup` dan laporan `.pdf.kkreport` / `.csv.kkreport` berisi envelope JSON
AES-GCM berversi: salt, nonce, ciphertext, tag, metadata KDF. AAD backup
`KasKelasKu/backup/v1`; laporan `KasKelasKu/report/pdf` atau `KasKelasKu/report/csv`.
PDF/CSV plaintext dibuat di memori saat generasi. Menu Setelan menyediakan
pembukaan laporan dan berbagi plaintext dengan peringatan; file sementara dihapus
setelah lembar berbagi selesai. Aplikasi penerima dapat menyimpan salinannya.
Pemulihan hanya diizinkan ke brankas baru kosong: buat brankas dengan kata sandi
baru, pilih backup dan masukkan kata sandi backup. Import skema/data/trigger berada
dalam satu transaksi SQLite; kegagalan menggulung balik seluruh import. Akun dari
backup dinonaktifkan karena kredensial tidak dibawa; Bendahara baru membuat akun
akses baru. Tidak ada penimpaan atau merge ledger lama.
Backup mencakup anggota, transaksi, laporan dan audit; tidak mengekspor kredensial.

Repository memeriksa peran aktif di database untuk tiap akses dan tiap mutasi di
transaksi yang sama. Trigger menjaga invariansi tambahan, **bukan sandbox RBAC**:
SQLite tidak mengenal identitas pengguna aplikasi. Root/jailbreak atau modifikasi
binary yang membaca kunci dapat melewati batas repository. Audit lokal juga tidak
tahan penyerang yang sudah menguasai kunci. Tidak ada server atau sinkronisasi.

## QA dan hambatan rilis

Hasil host terakhir (17 Oktober 2026): analisis statis bersih, 93 tes lulus,
schema checks lulus, coverage 1202/1202 baris (100%). Integrasi native Android
SQLCipher/report/backup/RBAC/10.000 transaksi lulus pada emulator Android 10.
APK release RC2 berhasil dibangun dan ditandatangani untuk preview setelah perbaikan ProGuard SQLCipher.
Bundle Play Store tersedia sebagai `dist/KasKelasKu-1.0.0-rc2-unsigned.aab`.
Bundle preview signed debug hanya untuk uji lokal; bukan artefak publik.
Tes tambahan mencakup
restore rollback, matriks peran, pencabutan akses, rotasi kata sandi, PDF/CSV
terenkripsi, Unicode Latin, otomatisasi laporan, 10.000 transaksi dan formulir
pada layar 360 piksel dengan teks 200%. Ini bukan bukti performa perangkat native.
Tes teks besar menemukan overflow dropdown jenis transaksi; sudah diperbaiki.

Analisis statis dan tes host dapat dijalankan. CI sengaja menolak coverage di bawah
100%; ambang tidak diturunkan atau file dikecualikan untuk menyembunyikan kekurangan.
Tes integrasi/performa memerlukan emulator/perangkat SQLCipher asli, bukan SQLite FFI.
CI menambahkan emulator Android dan build simulator iOS; belum ada klaim hasil CI jarak jauh.

Laporan bulan selesai dibuat otomatis saat login dan pemeriksaan menit berikutnya, termasuk bulan kosong
di antara bulan transaksi pertama dan bulan berjalan. Tidak ada proses latar
belakang OS; digest snapshot mencegah generasi ulang tanpa perubahan. Laporan
otomatis dibuka lewat Setelan memakai kunci brankas. Noto Sans (SIL OFL, lisensi di
`assets/fonts/OFL.txt`) disertakan untuk PDF Unicode Latin; seluruh aksara dunia
dan emoji belum dijamin. Sesi diperiksa ulang setiap dua detik untuk perubahan peran.

Belum selesai: coverage 100%, benchmark scroll perangkat,
uji offline kedua platform, audit aksesibilitas TalkBack/VoiceOver/200% teks,
audit keamanan independen, pengujian disk penuh/corruption/crash injection,
penanganan setup terputus, penghapusan/revokasi sesi biometrik,
serta peninjauan dependensi lama dan persyaratan toko 2026.

Warna gelap, label kontrol dan daftar teks pendamping grafik tersedia; itu **bukan
sertifikasi WCAG 2.1 AA**. Paket SQLCipher 2.2.1 membawa SQLCipher Android 4.5.4;
kompatibilitas perangkat baru dan halaman memori 16 KB harus diaudit sebelum rilis.
