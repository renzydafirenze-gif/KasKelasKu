import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kaskelasku/data/backup.dart';
import 'package:kaskelasku/data/repository.dart';
import 'package:kaskelasku/models.dart';

Future<Database> openPlain(String path) => databaseFactoryFfi.openDatabase(path,
    options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          for (final sql in (await rootBundle.loadString('lib/data/schema.sql'))
              .split('-- @statement')) {
            await db.execute(sql);
          }
        }));

CashTransaction entry(
        {int amount = 10000,
        String date = '2026-10-15',
        String description = 'Iuran',
        String? contributorId,
        String type = 'IN'}) =>
    CashTransaction(
        amount: amount,
        type: type,
        category: 'Kas',
        contributorId: contributorId,
        date: date,
        description: description);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late TreasuryRepository repo;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('kk-repo-');
    repo = TreasuryRepository(
        pathOverride: '${directory.path}/test.db', openForTesting: openPlain);
  });
  tearDown(() async {
    await repo.close();
    await directory.delete(recursive: true);
  });

  test('Owner, members, transactions and reporting aggregates', () async {
    expect(await repo.open(), isNull);
    await expectLater(repo.currentMember(), throwsA(isA<AppError>()));
    final owner = await repo.createOwner('Budi');
    expect(owner.role, Role.bendahara);
    expect((await repo.open())!.id, owner.id);
    expect((await repo.currentMember()).name, 'Budi');
    await expectLater(repo.createOwner('Lain'), throwsA(isA<AppError>()));
    await expectLater(
        repo.addMember('   ', Role.siswa), throwsA(isA<AppError>()));

    await repo.addMember('Siti', Role.siswa);
    await repo.addMember('Ketua', Role.ketua);
    final members = await repo.members();
    final student = members.firstWhere((m) => m.name == 'Siti');
    final chair = members.firstWhere((m) => m.name == 'Ketua');
    expect(members, hasLength(3));

    await repo.addTransaction(entry(contributorId: student.id));
    await expectLater(
        repo.addTransaction(entry()), throwsA(isA<DuplicateTransaction>()));
    await repo.addTransaction(entry(description: 'Iuran 100%'));
    await repo
        .addTransaction(entry(amount: 3000, type: 'OUT', description: 'Sapu'));
    await expectLater(repo.addTransaction(entry(contributorId: chair.id)),
        throwsA(isA<AppError>()));

    final summary = await repo.overview('2026-10');
    expect(summary.balance, 17000);
    expect(summary.income, 20000);
    expect(summary.expense, 3000);
    expect(summary.recent, hasLength(3));
    expect(summary.recent.first.contributorName, isNull);
    expect(summary.trends.single['net'], 17000);

    final history = await repo.history();
    expect(history, hasLength(3));
    expect(history.where((row) => row.contributorName == 'Siti'), hasLength(1));
    expect(await repo.history(keyword: 'siti'), hasLength(1));
    expect(await repo.history(keyword: '%'), hasLength(1));
    expect(await repo.history(category: 'Kas'), hasLength(3));
    expect(
        await repo.history(
            from: '2026-10-01', to: '2026-10-31', limit: 2, offset: 1),
        hasLength(2));
    expect(await repo.history(from: '2026-11-01'), isEmpty);
    await expectLater(repo.history(from: 'bad'), throwsA(isA<AppError>()));
    await expectLater(repo.history(from: '2026-10-02', to: '2026-10-01'),
        throwsA(isA<AppError>()));
    await expectLater(repo.history(limit: 0), throwsA(isA<AppError>()));
    await expectLater(repo.history(offset: -1), throwsA(isA<AppError>()));

    expect((await repo.reportSnapshot('2026-10'))['rows'], hasLength(3));
    expect(await repo.monthSnapshot('2026-11'), {
      'opening': 17000,
      'income': 0,
      'expense': 0,
      'closing': 17000,
      'target': 0,
      'paid': 0
    });
    await expectLater(repo.monthSnapshot('2026-13'), throwsA(isA<AppError>()));
    await repo.setTotalMonthlyTarget('2026-10', 20000);
    expect((await repo.overview('2026-10')).target, 20000);
    expect((await repo.monthSnapshot('2026-10'))['paid'], 20000);
    await expectLater(
        repo.setTotalMonthlyTarget('2026-10', -1), throwsA(isA<AppError>()));
    await expectLater(
        repo.setTotalMonthlyTarget('x', 1), throwsA(isA<AppError>()));

    final id = history.first.id!;
    await repo.deleteTransaction(id);
    await expectLater(repo.deleteTransaction(9999), throwsA(isA<AppError>()));
  });

  test('Role checks, approvals, locks and member changes', () async {
    final owner = await repo.createOwner('Budi');
    await repo.addMember('Siti', Role.siswa);
    await repo.addMember('Ketua', Role.ketua);
    await repo.addMember('Wali', Role.guruWali);
    final members = await repo.members();
    final student = members.firstWhere((m) => m.name == 'Siti');
    final chair = members.firstWhere((m) => m.name == 'Ketua');
    final guardian = members.firstWhere((m) => m.name == 'Wali');
    await repo.addTransaction(entry());

    await repo.switchUser(student.id);
    await expectLater(repo.addTransaction(entry(description: 'Dua')),
        throwsA(isA<AppError>()));
    await expectLater(repo.approve('2026-10'), throwsA(isA<AppError>()));
    await expectLater(
        repo.setTotalMonthlyTarget('2026-10', 1), throwsA(isA<AppError>()));

    await repo.switchUser(chair.id);
    await expectLater(repo.addTransaction(entry(description: 'Tiga')),
        throwsA(isA<AppError>()));
    await repo.approve('2026-10');
    await expectLater(repo.approve('2026-10'), throwsA(isA<AppError>()));
    await expectLater(repo.verify('2026-10'), throwsA(isA<AppError>()));

    await repo.switchUser(guardian.id);
    await repo.verify('2026-10');
    await expectLater(repo.verify('2026-10'), throwsA(isA<AppError>()));

    await repo.switchUser(owner.id);
    await repo.addMember('Tanpa izin?', Role.siswa);
    await expectLater(repo.deleteTransaction(1), throwsA(isA<AppError>()));
    await expectLater(
        repo.changeMember(owner, Role.siswa, true), throwsA(isA<AppError>()));
    await repo.changeMember(student, Role.ketua, false);
    await expectLater(repo.switchUser(student.id), throwsA(isA<AppError>()));
    await expectLater(
        repo.changeMember(
            const Member('missing', 'Tidak ada', Role.siswa), Role.siswa, true),
        throwsA(isA<AppError>()));
    await repo.changeMember(student, Role.siswa, true);
    expect((await repo.switchUser(student.id)).role, Role.siswa);
  });

  test('Backup snapshot covers every table and restore replaces empty data',
      () async {
    final owner = await repo.createOwner('Budi');
    await repo.addMember('Siti', Role.siswa);
    final student = (await repo.members()).firstWhere((m) => m.name == 'Siti');
    await repo.addTransaction(entry(contributorId: student.id));
    await repo.setTotalMonthlyTarget('2026-10', 50000);
    final snapshot = await repo.backupSnapshot();
    expect(snapshot.keys, containsAll(Backup.columns.keys));
    expect(snapshot['monthly_total_targets'], hasLength(1));
    final backup = Backup(snapshot);

    final otherDir = await Directory.systemTemp.createTemp('kk-restore-');
    final target = TreasuryRepository(
        pathOverride: '${otherDir.path}/restore.db', openForTesting: openPlain);
    try {
      await target.createOwner('Baru');
      final restored = await target.restore(backup);
      expect(restored.name, 'Budi');
      expect(await target.members(), hasLength(2));
      expect(await target.history(), hasLength(1));
      expect((await target.overview('2026-10')).target, 50000);
      await expectLater(target.restore(backup), throwsA(isA<AppError>()));
    } finally {
      await target.close();
      await otherDir.delete(recursive: true);
    }
    expect(owner.id, isNotEmpty);
  });

  test('Restore rejects backups that collide with the current owner', () async {
    final owner = await repo.createOwner('Budi');
    final snapshot = await repo.backupSnapshot();
    expect(snapshot['users'], hasLength(1));
    await expectLater(repo.restore(Backup(snapshot)), throwsA(isA<AppError>()));
    expect((await repo.currentMember()).id, owner.id);
  });
}
