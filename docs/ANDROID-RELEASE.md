# Artefak Android — 16 Oktober 2026

## Verifikasi kode setelah RC1

- 61 tes host lulus; analisis statis dan pemeriksaan skema lulus.
- Coverage mentah 995/1202 baris (82,78%); gate 100% tetap memblokir rilis.
- Tidak ada pengecualian coverage untuk kode native atau penyimpanan kunci.
- Tes tambahan: kredensial Vault asli melalui kanal penyimpanan tiruan,
  rotasi kata sandi, biometrik dibatalkan/tidak tersedia, perubahan peran dan
  akun nonaktif sebelum resume, penguncian UI serta penutupan dialog, pemulihan
  terenkripsi dengan autentikasi dan validasi bentuk JSON.
- APK RC1 di bawah belum dibangun ulang dari perubahan kode terbaru ini.

## RC2

- 93 tes host lulus; coverage 1202/1202 (100%); analisis statis dan schema checks lulus.
- `dist/KasKelasKu-1.0.0-rc2-unsigned.apk` dibangun dari kode terbaru.
- `dist/KasKelasKu-1.0.0-rc2-preview.apk` ditandatangani debug untuk evaluasi saja.
- Preview RC2 lulus verifikasi APK v1/v2/v3.
- SHA-256 preview: `52568d0427603cf3a945eddd8b90b52c646397dd5e4c0cc11b6f615f8d11ddf0`.
- SHA-256 unsigned: `f5055629093bcc9e4665c1662d4e46426908024648498bdab16300232fbcaf61`.
- `dist/KasKelasKu-1.0.0-rc2-unsigned.aab` dibangun untuk Play Console.
- SHA-256 unsigned AAB: `4bb24050202f807ae387630d4a8af96f51819a205fb01e5c140550dd242531d9`.
- `dist/KasKelasKu-1.0.0-rc2-preview.aab` memakai debug keystore hanya untuk
  evaluasi lokal; jangan upload ke Play Console.
- SHA-256 preview AAB: `a2b690d16cd4952b2a4197b6fd83d3cb87f7c3f84aba23087fa3d99c71d58348`.
- Signing produksi belum dilakukan; set `KASKELASKU_KEYSTORE`,
  `KASKELASKU_STORE_PASSWORD`, `KASKELASKU_KEY_ALIAS`, dan
  `KASKELASKU_KEY_PASSWORD` saat build.

## Pembaruan RC1

Gunakan `dist/KasKelasKu-1.0.0-rc1-preview.apk`, bukan preview lama.
Preview lama mengalami crash release SQLCipher JNI akibat R8. RC1 memperbaiki
aturan ProGuard, lalu berhasil dipasang dan cold-launch pada emulator Android 10
x86_64 (activity tetap foreground, proses tetap hidup).

- 28 tes host lulus, analisis statis bersih; coverage 811/1190 (68,15%).
- Integrasi native Android lulus: SQLCipher, PDF/CSV, backup, RBAC, penguncian,
  dan kueri 10.000 transaksi. Tes ini memakai mode debug; smoke launch RC1
  dilakukan terpisah memakai APK release.
- Penanganan pending setup, perubahan peran wajib login ulang, penutupan dialog
  saat lock, screenshot protection dan pembersihan plaintext ditambahkan.
- RC1 tetap memakai signing debug untuk evaluasi, bukan signing produksi.
- Coverage 100%, uji iOS, audit aksesibilitas/keamanan independen dan peninjauan
  native 16 KB/target toko masih memblokir rilis publik.

```text
638ba5cc58fa8ec16a7f60b4c9154c5b78303ea10a59ab96fb6448828ca1ae2c  KasKelasKu-1.0.0-rc1-preview.apk
4ed5a9706426bc67166e2e99f584915eeefe421b95debf2962fc205dbb6f2899  KasKelasKu-1.0.0-rc1-unsigned.apk
```

## APK tersedia

| Berkas | Status |
| --- | --- |
| `dist/KasKelasKu-1.0.0-preview.apk` | Mode release, ditandatangani kunci debug Android untuk uji pemasangan saja |
| `dist/KasKelasKu-1.0.0-release-unsigned.apk` | Mode release tanpa tanda tangan; tidak bisa langsung dipasang |

Preview bukan build produksi meskipun memakai kompilasi release. Jangan gunakan
untuk kas nyata atau distribusi publik. Setelah rilis memakai kunci produksi,
Android tidak mengizinkan pembaruan dari preview karena sertifikat berbeda.
Ekspor cadangan dan verifikasi pemulihannya sebelum menghapus aplikasi uji.
Menghapus aplikasi menghapus database dan dapat menghapus kunci lokal.

APK universal membawa kode aplikasi ARMv7, ARM64 dan x86_64. Minimum Android 6
(API 23), target API 34. Target ini bukan pernyataan kepatuhan Play Store 2026.
SQLCipher native tersedia, tetapi keberadaan library bukan bukti uji enkripsi
runtime. Library lama masih memerlukan peninjauan kompatibilitas halaman 16 KB.

SHA-256:

```text
37eb2114cfe6bb96db5ebe1a03941ddbc80e7f14e00efe89b63d9e06fefc018a  KasKelasKu-1.0.0-preview.apk
2f5bce9a4e76df0015f1e7e4f6281ecbc084f21ed8719d29b8ff624915855666  KasKelasKu-1.0.0-release-unsigned.apk
```

Verifikasi checksum lokal:

```sh
python3 tool/check_apks.py
```

Pasang preview melalui pengelola berkas Android atau Android SDK:

```sh
adb install -r dist/KasKelasKu-1.0.0-preview.apk
```

Jangan mengabaikan `INSTALL_FAILED_UPDATE_INCOMPATIBLE`: kemungkinan sertifikat
berbeda. Jangan menghapus aplikasi yang memuat data penting untuk melewati error.

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
flutter analyze
flutter test --coverage
python3 tool/check_schema.py
python3 tool/check_coverage.py
flutter build apk --release
apksigner verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk
```

`check_coverage.py` saat ini gagal karena coverage belum 100%; jangan melewati
gate ini untuk menyebut aplikasi siap produksi. APK preview dibangun untuk
evaluasi teknik, bukan hasil lolos gate rilis.

## Bukti dan penghambat

- Build debug dan release berhasil pada Flutter 3.24.0, Java 17, Android SDK 34.
- Kotlin Gradle plugin diperbarui ke 1.9.24; lifecycle dipatok ke 2.0.19 agar
  cocok dengan AGP 7.3 dan Flutter 3.24.
- Verifikasi tanda tangan preview saat build: APK signature v1/v2/v3 valid.
- Arsip kedua APK dan checksum diperiksa ulang setelah sesi terputus.
- 21 tes host terakhir lulus sebelum perubahan pemulihan setup. Tambahan jalur
  pending setup belum diuji ulang dengan SDK pada sesi lanjutan.
- Coverage terakhir 51,03%, bukan 100%.
- Instalasi emulator terputus; belum ada bukti pemasangan, launch atau integrasi
  native Android. Belum ada hasil uji iOS, audit aksesibilitas atau audit independen.
- Build release mencetak warning metadata Kotlin dari dependensi meskipun
  menghasilkan APK; perlu peninjauan toolchain sebelum distribusi produksi.

Ikuti juga `docs/SECURITY.md`. APK yang berhasil dibangun tidak otomatis aman
atau siap dirilis.
