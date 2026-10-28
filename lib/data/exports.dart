import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models.dart';
import 'repository.dart';
import 'backup.dart';

class ReportFiles {
  const ReportFiles(this.pdf, this.csv);
  final File pdf;
  final File csv;
}

class Exports {
  Exports(this.repository);
  final TreasuryRepository repository;
  static const maxImportBytes = 64 * 1024 * 1024;

  static String safeCell(Object? value) {
    final text = '${value ?? ''}';
    return RegExp(r'^\s*[=+@\-\t\r]').hasMatch(text) ? "'$text" : text;
  }

  Future<ReportFiles> report(String period) async {
    final snapshot = await repository.reportSnapshot(period);
    final summary = await repository.monthSnapshot(period);
    final rows = snapshot['rows']! as List<Map<String, Object?>>;
    final status = snapshot['status']! as Map<String, Object?>;
    final opening = summary['opening']! as int;
    final incoming = summary['income']! as int;
    final outgoing = summary['expense']! as int;
    final target = summary['target']! as int;
    final paid = summary['paid']! as int;
    final state = status['verified_by'] != null
        ? 'Diverifikasi Guru Wali'
        : status['approved_by'] != null
            ? 'Dikunci Ketua'
            : 'Draf';
    final data = [
      for (final row in rows)
        [
          row['tx_date'],
          row['type'] == 'IN' ? 'Masuk' : 'Keluar',
          row['category'],
          row['contributor_name'] ?? '',
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
      ['Target kas', target],
      ['Terkumpul', paid],
      ...data,
    ]);
    final font =
        pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final pdf =
        pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
    pdf.addPage(pw.MultiPage(
        maxPages: 10000,
        build: (_) => [
              pw.Text('KasKelasKu · $period',
                  style: pw.TextStyle(
                      fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(state),
              pw.SizedBox(height: 12),
              pw.Text(
                  'Saldo awal: Rp $opening    Masuk: Rp $incoming    Keluar: Rp $outgoing'),
              pw.Text('Saldo akhir: Rp ${opening + incoming - outgoing}'),
              pw.Text('Target kas: Rp $target · Terkumpul: Rp $paid'),
              pw.SizedBox(height: 16),
              if (rows.isEmpty)
                pw.Text('Tidak ada transaksi pada bulan ini.')
              else
                pw.TableHelper.fromTextArray(
                    cellStyle: const pw.TextStyle(fontSize: 9),
                    headerStyle: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold),
                    headerDecoration:
                        const pw.BoxDecoration(color: PdfColors.grey300),
                    headers: [
                      'Tanggal',
                      'Jenis',
                      'Kategori',
                      'Penyetor',
                      'Rupiah',
                      'Keterangan'
                    ],
                    data: data),
            ]));
    final directory = await Directory((await getTemporaryDirectory()).path)
        .createTemp('kk-report-');
    final pdfFile = File('${directory.path}/KasKelasKu-$period.pdf');
    final csvFile = File('${directory.path}/KasKelasKu-$period.csv');
    await pdfFile.writeAsBytes(await pdf.save(), flush: true);
    await csvFile.writeAsString(csv, flush: true);
    return ReportFiles(pdfFile, csvFile);
  }

  Future<File> backup() async {
    final snapshot = await repository.backupSnapshot();
    final bytes =
        utf8.encode(const JsonEncoder.withIndent('  ').convert(snapshot));
    return _atomicWrite(
        'KasKelasKu-${DateTime.now().microsecondsSinceEpoch}.json', bytes);
  }

  Future<Member> restore(File file) async {
    if ((await repository.currentMember()).role != Role.bendahara) {
      throw const AppError('Hanya Bendahara boleh memulihkan cadangan.');
    }
    if (await file.length() > maxImportBytes) {
      throw const AppError('Berkas melebihi 64 MB.');
    }
    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const AppError('Cadangan tidak valid.');
    }
    return repository.restore(Backup(decoded));
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
}
