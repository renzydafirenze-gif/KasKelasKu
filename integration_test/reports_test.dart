import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kaskelasku/data/exports.dart';
import 'package:kaskelasku/data/repository.dart';
import 'package:kaskelasku/data/vault.dart';
import 'package:kaskelasku/models.dart';

// Test credentials isolated in memory; database uses real platform SQLCipher.
class TestVault extends Vault {
  final keys = <String, String>{};
  @override
  Future<List<String>> accounts() async => keys.keys.toList();
  @override
  Future<void> enroll(String id, String password, String databaseKey) async {
    keys[id] = await Vault.seal(utf8.encode(databaseKey), password, id);
  }

  @override
  Future<String> unlock(String id, String password) async =>
      utf8.decode(await Vault.unseal(keys[id]!, password, id));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'Real SQLCipher: reports, locks, permissions, backup, 10k history',
      (tester) async {
    final temporary = await Directory((await getTemporaryDirectory()).path)
        .createTemp('kk-integration-');
    final vault = TestVault();
    final repo = TreasuryRepository(vault,
        pathOverride: '${temporary.path}/treasury.db');
    final files = <File>[];
    const password = 'Integration-KasKelasKu-2026!';
    try {
      final treasurer = await repo.setup('Bendahara uji', password);
      final tx = CashTransaction(
          amount: 10000,
          type: 'IN',
          category: 'Iuran',
          date: '2026-10-15',
          description: 'Kas mingguan');
      await repo.addTransaction(tx, 'submission-1');
      await repo.addTransaction(tx, 'submission-1');
      expect(await repo.balance(), 10000);
      await expectLater(repo.addTransaction(tx, 'submission-2'),
          throwsA(isA<DuplicateTransaction>()));
      final report = await Exports(repo).report('2026-10', password);
      files.addAll([report.pdf, report.csv]);
      final pdf = await Vault.unseal(
          await report.pdf.readAsString(), password, 'KasKelasKu/report/pdf');
      final csv = await Vault.unseal(
          await report.csv.readAsString(), password, 'KasKelasKu/report/csv');
      expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
      expect(utf8.decode(csv), contains('Kas mingguan'));
      final empty = await Exports(repo).report('2026-11', password);
      files.addAll([empty.pdf, empty.csv]);
      expect(
          utf8.decode(await Vault.unseal(await empty.csv.readAsString(),
              password, 'KasKelasKu/report/csv')),
          contains('Saldo awal,10000'));
      final backup = await Exports(repo).backup(password);
      files.add(backup);
      final payload = jsonDecode(utf8.decode(await Vault.unseal(
              await backup.readAsString(), password, 'KasKelasKu/backup/v1')))
          as Map<String, dynamic>;
      expect(payload['transactions'], hasLength(1));
      await repo.addMember('Ketua uji', Role.ketua, password);
      final chair =
          (await repo.members()).firstWhere((m) => m.role == Role.ketua);
      await repo.lock();
      await repo.login(chair.id, password, Role.ketua);
      await expectLater(
          repo.addTransaction(tx, 'no-permission'), throwsA(isA<AppError>()));
      await repo.approve('2026-10');
      await repo.lock();
      await repo.login(treasurer.id, password, Role.bendahara);
      await expectLater(repo.deleteTransaction(1), throwsA(isA<AppError>()));

      // Batch seed measures paginated query, not credential KDF or per-write fsync.
      await repo.db.transaction((txn) async {
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
      // Database is not a plaintext SQLite file.
      final header =
          await File('${temporary.path}/treasury.db').openRead(0, 16).first;
      expect(header, isNot(utf8.encode('SQLite format 3\u0000')));
    } finally {
      await repo.lock();
      for (final file in files) {
        if (await file.exists()) await file.delete();
      }
      // Only this test-created directory; never application/user databases.
      await temporary.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
