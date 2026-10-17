import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models.dart';
import 'repository.dart';
import 'vault.dart';
import 'backup.dart';

class ReportFiles {
  const ReportFiles(this.pdf, this.csv);
  final File pdf;
  final File csv;
}

class Exports {
  Exports(this.repository);
  final TreasuryRepository repository;
  bool _generatingAutomatic = false;
  static const maxImportBytes = 64 * 1024 * 1024;
  static Future<void> cleanupPlaintext() async {
    final directory = await getTemporaryDirectory();
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is Directory &&
          entry.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last
              .startsWith('kk-share-')) {
        await entry.delete(recursive: true);
      }
    }
  }

  static Future<String> readEnvelope(File file) async {
    if (await file.length() > maxImportBytes) {
      throw const AppError('Berkas melebihi 64 MB.');
    }
    return file.readAsString();
  }

  Future<void> restore(File file, String password) async {
    if ((await repository.currentMember()).role != Role.bendahara) {
      throw const AppError('Hanya Bendahara boleh memulihkan cadangan.');
    }
    final bytes = await Vault.unseal(
        await readEnvelope(file), password, 'KasKelasKu/backup/v1');
    final Object? decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const AppError('Cadangan tidak valid.');
    }
    await repository.restore(Backup(decoded));
  }

  Future<File> decryptReport(File file, String password) async {
    await repository.currentMember();
    final type = file.path.endsWith('.pdf.kkreport')
        ? 'pdf'
        : file.path.endsWith('.csv.kkreport')
            ? 'csv'
            : null;
    if (type == null) {
      throw const AppError('Pilih laporan .pdf.kkreport atau .csv.kkreport.');
    }
    final envelope = await readEnvelope(file);
    final bytes =
        await Vault.unseal(envelope, password, 'KasKelasKu/report/$type');
    await repository.currentMember();
    final directory = await Directory((await getTemporaryDirectory()).path)
        .createTemp('kk-share-');
    final result = File('${directory.path}/KasKelasKu.$type');
    try {
      return await result.writeAsBytes(bytes, flush: true);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> automaticReports(DateTime now) async {
    if (_generatingAutomatic) return;
    _generatingAutomatic = true;
    try {
      // No OS background task or stored export password: generate at foreground
      // catch-up and protect generated files with database key-derived secret.
      for (final period in await repository.completedMonths(now)) {
        final snapshot = await repository.reportSnapshot(period);
        final digest =
            sha256.convert(utf8.encode(jsonEncode(snapshot))).toString();
        final dir = Directory(
            '${(await getApplicationSupportDirectory()).path}/exports');
        final key = 'auto-report:$period';
        final previous = await Vault.storage.read(key: key);
        if (previous != null) {
          final saved = jsonDecode(previous) as Map<String, dynamic>;
          if (saved['digest'] == digest &&
              await File('${dir.path}/${saved['pdf']}').exists() &&
              await File('${dir.path}/${saved['csv']}').exists()) continue;
        }
        final secret = await repository.automaticReportPassword();
        final files = await report(period, secret);
        await Vault.storage.write(
            key: key,
            value: jsonEncode({
              'digest': digest,
              'pdf': files.pdf.uri.pathSegments.last,
              'csv': files.csv.uri.pathSegments.last
            }));
      }
    } finally {
      _generatingAutomatic = false;
    }
  }

  Future<List<File>> automaticFiles() async {
    await repository.currentMember();
    final dir =
        Directory('${(await getApplicationSupportDirectory()).path}/exports');
    final entries = await Vault.storage.readAll();
    final files = <File>[];
    for (final entry
        in entries.entries.where((e) => e.key.startsWith('auto-report:'))) {
      final saved = jsonDecode(entry.value) as Map<String, dynamic>;
      for (final type in ['pdf', 'csv']) {
        final name = saved[type];
        if (name is String && !name.contains('/') && !name.contains('\\')) {
          final file = File('${dir.path}/$name');
          if (await file.exists()) files.add(file);
        }
      }
    }
    return files;
  }

  static String safeCell(Object? value) {
    final text = '${value ?? ''}';
    return RegExp(r'^\s*[=+@\-\t\r]').hasMatch(text) ? "'$text" : text;
  }

  Future<File> _atomicWrite(String name, List<int> bytes) async {
    final dir =
        Directory('${(await getApplicationSupportDirectory()).path}/exports');
    await dir.create(recursive: true);
    final file = File('${dir.path}/$name');
    final temp = File('${file.path}.partial');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      return await temp.rename(file.path);
    } on FileSystemException {
      if (await temp.exists()) await temp.delete();
      throw const AppError(
          'Ekspor gagal. Periksa ruang penyimpanan. Data asli tetap utuh.');
    }
  }

  Future<File> backup(String password) async {
    final snapshot = await repository.backupSnapshot();
    final envelope = await Vault.seal(
        utf8.encode(jsonEncode(snapshot)), password, 'KasKelasKu/backup/v1');
    // Check authorization again after expensive encryption.
    if ((await repository.currentMember()).role != Role.bendahara) {
      throw const AppError('Izin cadangan dicabut.');
    }
    return _atomicWrite(
        'KasKelasKu-${DateTime.now().microsecondsSinceEpoch}.kkbackup',
        utf8.encode(envelope));
  }

  Future<ReportFiles> report(String period, String password) async {
    Vault.validatePassword(password);
    final snapshot = await repository.reportSnapshot(period);
    final rows = snapshot['rows']! as List<Map<String, Object?>>;
    final opening = snapshot['opening']! as int;
    final status = snapshot['status']! as Map<String, Object?>;
    var incoming = 0;
    var outgoing = 0;
    for (final row in rows) {
      if (row['type'] == 'IN') {
        incoming += row['amount']! as int;
      } else {
        outgoing += row['amount']! as int;
      }
    }
    final state = status['verified_by'] != null
        ? 'Diverifikasi Guru Wali'
        : status['approved_by'] != null
            ? 'Dikunci Ketua'
            : 'Draf';
    final table = <List<String>>[
      ['Tanggal', 'Jenis', 'Kategori', 'Rupiah', 'Keterangan'],
      for (final row in rows)
        [
          row['tx_date'],
          row['type'],
          row['contributor_id'] ?? '',
          row['category'],
          row['amount'],
          row['description']
        ].map(safeCell).toList(),
    ];
    final csv = const ListToCsvConverter().convert([
      ['KasKelasKu', period, state],
      ['Saldo awal', opening],
      ['Masuk', incoming],
      ['Keluar', outgoing],
      ['Saldo akhir', opening + incoming - outgoing],
      ...table,
    ]);
    final font =
        pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final pdf =
        pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
    pdf.addPage(pw.MultiPage(
        maxPages: 10000,
        build: (_) => [
              pw.Text('KasKelasKu - $period',
                  style: pw.TextStyle(
                      fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.Text(state),
              pw.Text(
                  'Saldo awal: Rp $opening | Masuk: Rp $incoming | Keluar: Rp $outgoing'),
              pw.Text('Saldo akhir: Rp ${opening + incoming - outgoing}'),
              if (rows.isEmpty) pw.Text('Tidak ada transaksi pada bulan ini.'),
              pw.SizedBox(height: 16),
              pw.TableHelper.fromTextArray(data: table),
            ]));
    // Reports remain encrypted at rest. Plain PDF/CSV require explicit user
    // decryption outside app; exports must never silently persist plaintext.
    final base = 'KasKelasKu-$period-${DateTime.now().microsecondsSinceEpoch}';
    final pdfEnvelope =
        await Vault.seal(await pdf.save(), password, 'KasKelasKu/report/pdf');
    final csvEnvelope =
        await Vault.seal(utf8.encode(csv), password, 'KasKelasKu/report/csv');
    await repository.currentMember();
    final pdfFile =
        await _atomicWrite('$base.pdf.kkreport', utf8.encode(pdfEnvelope));
    final csvFile =
        await _atomicWrite('$base.csv.kkreport', utf8.encode(csvEnvelope));
    return ReportFiles(pdfFile, csvFile);
  }
}
