import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'secure_storage_mock.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kaskelasku/data/backup.dart';
import 'package:kaskelasku/data/repository.dart';
import 'package:kaskelasku/data/vault.dart';
import 'package:kaskelasku/models.dart';
import 'package:kaskelasku/view_model.dart';

class MemoryVault extends Vault {
  final credentials = <String, (String, String)>{};
  @override
  Future<List<String>> accounts() async => credentials.keys.toList();
  @override
  Future<void> enroll(String id, String password, String databaseKey) async {
    credentials[id] = (password, databaseKey);
  }

  @override
  Future<String> unlock(String id, String password) async {
    final entry = credentials[id];
    if (entry == null || entry.$1 != password) {
      throw const AppError('Kata sandi salah.');
    }
    return entry.$2;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late TreasuryRepository repo;
  late MemoryVault vault;
  const password = 'Aman-untuk-kelas-2026';
  Future<Database> open(String path, String key, bool create) async =>
      databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
              version: 1,
              onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
              onCreate: (db, _) async {
                for (final sql
                    in (await rootBundle.loadString('lib/data/schema.sql'))
                        .split('-- @statement')) {
                  await db.execute(sql);
                }
              }));
  CashTransaction entry(
          {int amount = 10000,
          String date = '2026-10-15',
          String description = 'Iuran'}) =>
      CashTransaction(
          amount: amount,
          type: 'IN',
          category: 'Kas',
          date: date,
          description: description);

  setUp(() async {
    mockSecureStorage();
    directory = await Directory.systemTemp.createTemp('kk-repository-test-');
    vault = MemoryVault();
    repo = TreasuryRepository(vault,
        pathOverride: '${directory.path}/test.db', openForTesting: open);
  });
  tearDown(() async {
    await repo.lock(forgetBiometric: true);
    await directory.delete(recursive: true);
  });

  test('Transactions, filters, pagination, balance and literal keyword',
      () async {
    await repo.setup('Bendahara', password);
    await repo.addTransaction(entry(), 'one');
    await repo.addTransaction(entry(), 'one');
    await expectLater(repo.addTransaction(entry(), 'two'),
        throwsA(isA<DuplicateTransaction>()));
    await repo.addTransaction(entry(description: 'Iuran 100%'), 'two',
        confirmDuplicate: true);
    expect(await repo.balance(), 20000);
    expect(await repo.history(keyword: '%'), hasLength(1));
    expect(
        await repo.history(
            category: 'Kas', from: '2026-10-01', to: '2026-10-31'),
        hasLength(2));
    expect(await repo.history(limit: 1, offset: 1), hasLength(1));
    expect(await repo.trends(), [
      {'period': '2026-10', 'net': 20000}
    ]);
    expect(await repo.completedMonths(DateTime(2027, 1)),
        ['2026-10', '2026-11', '2026-12']);
    await expectLater(repo.history(from: 'bad'), throwsA(isA<AppError>()));
    await repo.deleteTransaction(1);
    expect(await repo.balance(), 10000);
    await expectLater(repo.deleteTransaction(99), throwsA(isA<AppError>()));
    await expectLater(
        repo.addTransaction(entry(), ''), throwsA(isA<AppError>()));
    expect((await repo.reportSnapshot('2026-11'))['opening'], 10000);
  });

  test('Monthly targets calculate paid status without carry-over', () async {
    await repo.setup('Bendahara', password);
    await repo.addMember('Siswa Target', Role.siswa, password);
    final student =
        (await repo.members()).firstWhere((m) => m.name == 'Siswa Target');
    await repo.setMonthlyTarget('2026-10', student.id, 10000);
    await repo.addTransaction(
        CashTransaction(
            amount: 15000,
            type: 'IN',
            category: 'Kas',
            contributorId: student.id,
            date: '2026-10-15',
            description: 'Iuran'),
        'one');
    final october = await repo.monthlyTargetStatus('2026-10');
    expect(october.single['paid'], 15000);
    expect(october.single['target'], 10000);
    final november = await repo.monthlyTargetStatus('2026-11');
    expect(november.single['paid'], 0);
    expect(november.single['target'], 0);
    await expectLater(repo.setMonthlyTarget('2026-10', student.id, -1),
        throwsA(isA<AppError>()));
    await repo.setTotalMonthlyTarget('2026-10', 20000);
    expect(await repo.totalMonthlyTargetStatus('2026-10'),
        {'target': 20000, 'paid': 15000});
    await expectLater(
        repo.setTotalMonthlyTarget('2026-10', -1), throwsA(isA<AppError>()));
  });

  test('Role matrix, report locks, verification and mid-session revocation',
      () async {
    final treasurer = await repo.setup('Bendahara', password);
    for (final role in [Role.ketua, Role.guruWali, Role.siswa]) {
      await repo.addMember(role.label, role, password);
    }
    final members = await repo.members();
    await expectLater(repo.changeMember(treasurer, Role.siswa, true),
        throwsA(isA<AppError>()));
    await repo.addTransaction(entry(), 'one');
    final chair = members.firstWhere((m) => m.role == Role.ketua);
    await repo.lock();
    await expectLater(
        repo.login(chair.id, password, Role.siswa), throwsA(isA<AppError>()));
    await repo.login(chair.id, password, Role.ketua);
    await expectLater(
        repo.addTransaction(entry(), 'forbidden'), throwsA(isA<AppError>()));
    await expectLater(repo.deleteTransaction(1), throwsA(isA<AppError>()));
    await expectLater(repo.addMember('Forbidden', Role.siswa, password),
        throwsA(isA<AppError>()));
    await expectLater(repo.backupSnapshot(), throwsA(isA<AppError>()));
    await repo.approve('2026-10');
    await expectLater(repo.approve('2026-10'), throwsA(isA<AppError>()));
    final teacher = members.firstWhere((m) => m.role == Role.guruWali);
    await repo.lock();
    await repo.login(teacher.id, password, Role.guruWali);
    await expectLater(repo.verify('2026-11'), throwsA(isA<AppError>()));
    await repo.verify('2026-10');
    await expectLater(repo.verify('2026-10'), throwsA(isA<AppError>()));
    await repo.lock();
    await repo.login(treasurer.id, password, Role.bendahara);
    await expectLater(repo.deleteTransaction(1), throwsA(isA<AppError>()));
    await expectLater(repo.addTransaction(entry(description: 'Khác'), 'locked'),
        throwsA(isA<AppError>()));
    final student = members.firstWhere((m) => m.role == Role.siswa);
    await repo.changeMember(student, Role.siswa, false);
    await repo.db.update('users', {'active': 0},
        where: 'id=?', whereArgs: [treasurer.id]);
    await expectLater(repo.balance(), throwsA(isA<AppError>()));
    await expectLater(
        repo.addTransaction(entry(), 'revoked'), throwsA(isA<AppError>()));
  });

  test(
      'Restore retains history/locks, disables imported users, rejects overwrite',
      () async {
    await repo.setup('Original', password);
    await repo.addTransaction(entry(), 'one');
    await repo.addMember('Ketua', Role.ketua, password);
    final chair =
        (await repo.members()).firstWhere((m) => m.role == Role.ketua);
    final original =
        (await repo.members()).firstWhere((m) => m.role == Role.bendahara);
    await repo.lock();
    await repo.login(chair.id, password, Role.ketua);
    await repo.approve('2026-10');
    await repo.lock();
    await repo.login(original.id, password, Role.bendahara);
    final backup = Backup(await repo.backupSnapshot());
    final restored = TreasuryRepository(MemoryVault(),
        pathOverride: '${directory.path}/restore.db', openForTesting: open);
    try {
      await restored.setup('Recovery', password);
      await restored.restore(backup);
      expect(await restored.balance(), 10000);
      expect(
          (await restored.members())
              .where((m) => m.id == original.id)
              .single
              .active,
          false);
      await expectLater(
          restored.deleteTransaction(1), throwsA(isA<AppError>()));
      await expectLater(restored.restore(backup), throwsA(isA<AppError>()));
      expect(await restored.balance(), 10000);
    } finally {
      await restored.lock();
    }
  });

  test('Invalid foreign key backup rolls back all imported data and triggers',
      () async {
    final actor = await repo.setup('Bendahara', password);
    final source = await repo.backupSnapshot();
    final broken = Map<String, dynamic>.from(source);
    broken['users'] = [
      {'id': 'other', 'name': 'Other', 'role': 'siswa', 'active': 0}
    ];
    broken['monthly_reports'] = [
      {
        'period': '2026-10',
        'approved_by': 'other',
        'approved_at': '2026-10-31',
        'verified_by': 'other',
        'verified_at': null
      }
    ];
    expect(() => Backup(broken), throwsA(isA<AppError>()));
    expect((await repo.members()).single.id, actor.id);
    await repo.addTransaction(entry(), 'still-works');
  });

  test('Login throttles failed attempts and lock forgets biometric cache',
      () async {
    final actor = await repo.setup('Bendahara', password);
    await repo.lock(forgetBiometric: true);
    expect(repo.canResumeBiometric, false);
    await expectLater(repo.resumeBiometric(), throwsA(isA<AppError>()));
    for (var i = 0; i < 5; i++) {
      await expectLater(repo.login(actor.id, 'wrong', Role.bendahara),
          throwsA(isA<AppError>()));
    }
    await expectLater(repo.login(actor.id, password, Role.bendahara),
        throwsA(isA<AppError>()));
    await expectLater(repo.balance(), throwsA(isA<AppError>()));
  });

  test('Password rotation keeps ledger and rejects previous password',
      () async {
    final actor = await repo.setup('Bendahara', password);
    await repo.addTransaction(entry(), 'one');
    await expectLater(repo.changePassword('wrong', 'new-password-2026'),
        throwsA(isA<AppError>()));
    await repo.changePassword(password, 'new-password-2026');
    expect(repo.canResumeBiometric, false);
    await repo.lock();
    await expectLater(repo.login(actor.id, password, Role.bendahara),
        throwsA(isA<AppError>()));
    await repo.login(actor.id, 'new-password-2026', Role.bendahara);
    expect(await repo.balance(), 10000);
  });

  test('Promotion mid-session requires fresh login', () async {
    await repo.setup('Bendahara', password);
    await repo.addMember('Siswa', Role.siswa, password);
    final student =
        (await repo.members()).firstWhere((m) => m.role == Role.siswa);
    await repo.lock();
    await repo.login(student.id, password, Role.siswa);
    await repo.db.update('users', {'role': 'bendahara'},
        where: 'id=?', whereArgs: [student.id]);
    await expectLater(
        repo.addTransaction(entry(), 'promotion'), throwsA(isA<AppError>()));
    expect(repo.canResumeBiometric, false);
  });

  test('Authenticated pending setup resumes missing database', () async {
    const id = 'pending-account';
    await vault.enroll(id, password, 'test-only-database-key');
    await Vault.storage.write(key: 'setup:$id', value: 'Bendahara pending');
    final member = await repo.login(id, password, Role.bendahara);
    expect(member.name, 'Bendahara pending');
    expect(await Vault.storage.read(key: 'setup:$id'), isNull);
    expect(await repo.balance(), 0);
  });

  test('SQL constraint failure rolls back restore, including dropped triggers',
      () async {
    await repo.setup('Recovery', password);
    final row = {
      'id': 1,
      'amount': 100,
      'type': 'IN',
      'category': 'Kas',
      'tx_date': '2026-10-01',
      'description': 'Iuran',
      'created_by': 'old',
      'created_at': '2026-10-01T00:00:00Z',
      'fingerprint': 'hash',
      'submission_id': 'same'
    };
    final backup = Backup({
      'schema': 1,
      'users': [
        {'id': 'old', 'name': 'Old', 'role': 'bendahara', 'active': 1}
      ],
      'transactions': [
        row,
        {...row, 'id': 2}
      ],
      'monthly_reports': <Object?>[],
      'audit_log': <Object?>[]
    });
    await expectLater(repo.restore(backup), throwsA(isA<DatabaseException>()));
    expect(await repo.balance(), 0);
    expect(await repo.members(), hasLength(1));
    final triggers = await repo.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger' AND name='tx_no_update'");
    expect(triggers, hasLength(1));
    await repo.addTransaction(entry(), 'after-rollback');
  });

  test('Setup rejects when vault already has accounts', () async {
    await repo.setup('First', password);
    final second = TreasuryRepository(vault,
        pathOverride: '${directory.path}/second.db', openForTesting: open);
    await expectLater(
        second.setup('Second', password), throwsA(isA<AppError>()));
  });

  test('Setup and addMember reject invalid names', () async {
    await expectLater(repo.setup('', password), throwsA(isA<AppError>()));
    await expectLater(repo.setup('x' * 81, password), throwsA(isA<AppError>()));
    await repo.setup('Valid', password);
    await expectLater(
        repo.addMember('', Role.siswa, password), throwsA(isA<AppError>()));
    await expectLater(repo.addMember('x' * 81, Role.siswa, password),
        throwsA(isA<AppError>()));
  });

  test('History rejects invalid filter parameters', () async {
    await repo.setup('Bendahara', password);
    await expectLater(repo.history(limit: 0), throwsA(isA<AppError>()));
    await expectLater(repo.history(limit: 501), throwsA(isA<AppError>()));
    await expectLater(repo.history(offset: -1), throwsA(isA<AppError>()));
    await expectLater(
        repo.history(keyword: 'x' * 101), throwsA(isA<AppError>()));
    await expectLater(repo.history(from: '2026-10-31', to: '2026-10-01'),
        throwsA(isA<AppError>()));
    await expectLater(repo.history(to: 'not-a-date'), throwsA(isA<AppError>()));
  });

  test('Change password rejects credential mismatch', () async {
    await repo.setup('Bendahara', password);
    // Tamper the vault so unlock returns a different key than _key
    final actor = (await repo.members()).first;
    vault.credentials[actor.id] = (password, 'tampered-key-different-from-db');
    await expectLater(repo.changePassword(password, 'New-password-2026!'),
        throwsA(isA<AppError>()));
  });

  test('Completed months returns empty when no transactions', () async {
    await repo.setup('Bendahara', password);
    expect(await repo.completedMonths(DateTime(2026, 10)), isEmpty);
  });

  test('Restore rejects non-empty vault', () async {
    await repo.setup('Bendahara', password);
    await repo.addTransaction(entry(), 'one');
    final backup = Backup(await repo.backupSnapshot());
    await expectLater(repo.restore(backup), throwsA(isA<AppError>()));
  });

  test('Add member removes credential when user insertion fails', () async {
    await repo.setup('Bendahara', password);
    await repo.db
        .execute('''CREATE TRIGGER reject_test_member BEFORE INSERT ON users
      BEGIN SELECT RAISE(ABORT, 'test insertion failure'); END''');
    await expectLater(repo.addMember('Test', Role.siswa, password),
        throwsA(isA<DatabaseException>()));
    expect(await repo.members(), hasLength(1));
  });

  test('Open rejects missing database without create flag', () async {
    await vault.enroll('any', password, 'test-key');
    final missing = TreasuryRepository(vault,
        pathOverride: '${directory.path}/nonexistent.db', openForTesting: open);
    await expectLater(missing.login('any', password, Role.bendahara),
        throwsA(isA<AppError>()));
  });

  test('Login with pending setup skips insert when users already exist',
      () async {
    await repo.setup('Existing', password);
    await repo.lock();
    final vault2 = MemoryVault();
    const id = 'pending-existing';
    await vault2.enroll(id, password, 'test-key-pending');
    await Vault.storage.write(key: 'setup:$id', value: 'Pending Name');
    final repo2 = TreasuryRepository(vault2,
        pathOverride: '${directory.path}/test.db', openForTesting: open);
    try {
      // Pre-insert user so login finds active row with matching role
      final db =
          await open('${directory.path}/test.db', 'test-key-pending', false);
      await db.insert('users',
          {'id': id, 'name': 'Pending Name', 'role': 'bendahara', 'active': 1});
      await db.close();
      final member = await repo2.login(id, password, Role.bendahara);
      expect(member.name, 'Pending Name');
    } finally {
      await repo2.lock();
    }
  });

  test('Db getter throws when locked', () async {
    await repo.setup('Bendahara', password);
    await repo.lock();
    expect(() => repo.db, throwsA(isA<AppError>()));
  });

  test('Current member throws when locked', () async {
    await repo.setup('Bendahara', password);
    await repo.lock();
    expect(() => repo.currentMember(), throwsA(isA<AppError>()));
  });

  test('Automatic report password requires authorization', () async {
    final actor = await repo.setup('Bendahara', password);
    expect(
        await repo.automaticReportPassword(), vault.credentials[actor.id]!.$2);
    await repo.lock();
    await expectLater(repo.automaticReportPassword(), throwsA(isA<AppError>()));
  });

  test('Backup snapshot requires bendahara role', () async {
    await repo.setup('Bendahara', password);
    await repo.addMember('Siswa', Role.siswa, password);
    final student =
        (await repo.members()).firstWhere((m) => m.role == Role.siswa);
    await repo.lock();
    await repo.login(student.id, password, Role.siswa);
    await expectLater(repo.backupSnapshot(), throwsA(isA<AppError>()));
  });

  test('Self-deactivation as bendahara is rejected', () async {
    final me = await repo.setup('Bendahara', password);
    await expectLater(
        repo.changeMember(me, Role.bendahara, false), throwsA(isA<AppError>()));
  });

  test('Self-role-change away from bendahara is rejected', () async {
    final me = await repo.setup('Bendahara', password);
    await expectLater(
        repo.changeMember(me, Role.siswa, true), throwsA(isA<AppError>()));
  });

  test('Report snapshot validates month format', () async {
    await repo.setup('Bendahara', password);
    await expectLater(repo.reportSnapshot('invalid'), throwsA(isA<AppError>()));
  });

  test('Approve and verify validate month format', () async {
    await repo.setup('Bendahara', password);
    expect(() => repo.approve('bad'), throwsA(isA<AppError>()));
    expect(() => repo.verify('bad'), throwsA(isA<AppError>()));
  });

  test('Verify rejects unapproved period', () async {
    await repo.setup('Bendahara', password);
    await repo.addMember('Guru', Role.guruWali, password);
    final guru =
        (await repo.members()).firstWhere((m) => m.role == Role.guruWali);
    await repo.lock();
    await repo.login(guru.id, password, Role.guruWali);
    await expectLater(repo.verify('2026-10'), throwsA(isA<AppError>()));
  });

  test('Changes stream emits on write operations', () async {
    await repo.setup('Bendahara', password);
    final model = TreasuryViewModel(repo);
    try {
      final revision = model.revisions.first;
      await repo.addTransaction(entry(), 'stream-test');
      expect(await revision, 1);
    } finally {
      await model.dispose();
    }
  });

  for (final change in ['none', 'role', 'inactive', 'cancel', 'unavailable']) {
    test('Biometric resume checks account state: $change', () async {
      final actor = await repo.setup('Bendahara', password);
      if (change == 'role') {
        await repo.db.update('users', {'role': 'siswa'},
            where: 'id=?', whereArgs: [actor.id]);
      } else if (change == 'inactive') {
        await repo.db.update('users', {'active': 0},
            where: 'id=?', whereArgs: [actor.id]);
      }
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('plugins.flutter.io/local_auth');
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getAvailableBiometrics') {
          return change == 'unavailable' ? <String>[] : ['fingerprint'];
        }
        if (call.method == 'authenticate') return change != 'cancel';
        throw MissingPluginException(call.method);
      });
      try {
        await repo.lock();
        if (change == 'none') {
          expect((await repo.resumeBiometric()).id, actor.id);
          expect(await repo.balance(), 0);
        } else {
          await expectLater(repo.resumeBiometric(), throwsA(isA<AppError>()));
          expect(repo.unlocked, false);
          if (change == 'role' || change == 'inactive') {
            expect(repo.canResumeBiometric, false);
          }
        }
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
  }

  test('Unlocked returns false after lock', () async {
    await repo.setup('Bendahara', password);
    expect(repo.unlocked, true);
    await repo.lock();
    expect(repo.unlocked, false);
  });

  test('Delete nonexistent transaction throws', () async {
    await repo.setup('Bendahara', password);
    await expectLater(repo.deleteTransaction(999), throwsA(isA<AppError>()));
  });

  test('Change member for nonexistent user throws', () async {
    await repo.setup('Bendahara', password);
    const fake = Member('nonexistent', 'Fake', Role.siswa);
    await expectLater(
        repo.changeMember(fake, Role.ketua, true), throwsA(isA<AppError>()));
  });
}
