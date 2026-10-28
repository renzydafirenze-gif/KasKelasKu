import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kaskelasku/data/exports.dart';
import 'package:kaskelasku/data/repository.dart';
import 'package:kaskelasku/models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Real device: reports, permissions, backup and 10k history',
      (tester) async {
    final temporary = await Directory((await getTemporaryDirectory()).path)
        .createTemp('kk-integration-');
    final repo =
        TreasuryRepository(pathOverride: '${temporary.path}/treasury.db');
    final files = <File>[];
    try {
      final treasurer = await repo.createOwner('Bendahara uji');
      final tx = CashTransaction(
          amount: 10000,
          type: 'IN',
          category: 'Iuran',
          date: '2026-10-15',
          description: 'Kas mingguan');
      await repo.addTransaction(tx);
      expect((await repo.overview('2026-10')).balance, 10000);
      await expectLater(
          repo.addTransaction(tx), throwsA(isA<DuplicateTransaction>()));
      final report = await Exports(repo).report('2026-10');
      files.addAll([report.pdf, report.csv]);
      expect(ascii.decode((await report.pdf.readAsBytes()).take(5).toList()),
          '%PDF-');
      expect(await report.csv.readAsString(), contains('Kas mingguan'));
      final empty = await Exports(repo).report('2026-11');
      files.addAll([empty.pdf, empty.csv]);
      expect(await empty.csv.readAsString(), contains('Saldo awal,10000'));
      final backup = await Exports(repo).backup();
      files.add(backup);
      expect(await backup.readAsString(), contains('"transactions"'));

      await repo.addMember('Ketua uji', Role.ketua);
      final chair =
          (await repo.members()).firstWhere((m) => m.role == Role.ketua);
      await repo.switchUser(chair.id);
      await expectLater(
          repo.addTransaction(CashTransaction(
              amount: 1,
              type: 'IN',
              category: 'X',
              date: '2026-10-16',
              description: 'Tidak boleh')),
          throwsA(isA<AppError>()));
      await repo.approve('2026-10');
      await repo.switchUser(treasurer.id);
      await expectLater(repo.deleteTransaction(1), throwsA(isA<AppError>()));

      final db = await repo.database;
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (var i = 0; i < 10000; i++) {
          batch.insert('transactions', {
            'amount': 100,
            'type': 'IN',
            'category': 'Perf',
            'tx_date': '2026-12-01',
            'description': 'Pembayaran $i',
            'created_by': treasurer.id,
            'created_at': '2026-12-01T00:00:00Z',
            'fingerprint': 'perf-$i',
            'submission_id': 'perf-$i'
          });
        }
        await batch.commit(noResult: true);
      });
      final watch = Stopwatch()..start();
      final page = await repo.history(limit: 100);
      watch.stop();
      expect(page, hasLength(100));
      expect(watch.elapsedMilliseconds, lessThan(1000));
      final header =
          await File('${temporary.path}/treasury.db').openRead(0, 16).first;
      expect(utf8.decode(header), 'SQLite format 3\u0000');
    } finally {
      await repo.close();
      for (final file in files) {
        if (await file.exists()) await file.delete();
      }
      await temporary.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
