import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kaskelasku/data/exports.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late TreasuryRepository repo;
  late Exports exports;
  const paths = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('kk-exports-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => directory.path);
    repo = TreasuryRepository(
        pathOverride: '${directory.path}/test.db', openForTesting: openPlain);
    await repo.createOwner('Budi');
    await repo.addMember('Siti', Role.siswa);
    final student = (await repo.members()).firstWhere((m) => m.name == 'Siti');
    await repo.addTransaction(CashTransaction(
        amount: 5000,
        type: 'IN',
        category: 'Kas',
        date: '2026-09-20',
        description: 'Awal'));
    await repo.addTransaction(CashTransaction(
        amount: 10000,
        type: 'IN',
        category: 'Iuran',
        contributorId: student.id,
        date: '2026-10-15',
        description: 'Iuran José'));
    await repo.addTransaction(CashTransaction(
        amount: 1000,
        type: 'OUT',
        category: 'Alat',
        date: '2026-10-16',
        description: '=formula'));
    await repo.setTotalMonthlyTarget('2026-10', 20000);
    exports = Exports(repo);
  });
  tearDown(() async {
    await repo.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    await directory.delete(recursive: true);
  });

  test('Report writes plain PDF and CSV with contributor and target', () async {
    final report = await exports.report('2026-10');
    expect(report.pdf.path, endsWith('KasKelasKu-2026-10.pdf'));
    expect(report.csv.path, endsWith('KasKelasKu-2026-10.csv'));
    final pdf = await report.pdf.readAsBytes();
    expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
    final csv = await report.csv.readAsString();
    expect(csv, contains('Siti'));
    expect(csv, contains('Iuran José'));
    expect(csv, contains("'=formula"));
    expect(csv, contains('Saldo akhir,14000'));
    expect(csv, contains('Target kas,20000'));
    expect(csv, contains('Terkumpul,10000'));
    expect(csv, contains('Draf'));
    final empty = await exports.report('2026-11');
    expect(await empty.csv.readAsString(), contains('Saldo awal,14000'));
  });

  test('Backup is plain JSON and restore loads it into an empty database',
      () async {
    final file = await exports.backup();
    expect(file.path, endsWith('.json'));
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(decoded['schema'], 1);
    expect(decoded['transactions'], hasLength(3));
    expect(decoded['monthly_total_targets'], hasLength(1));
    expect(await file.readAsString(), isNot(contains('ciphertext')));

    final otherDir = await Directory.systemTemp.createTemp('kk-restore-');
    final other = TreasuryRepository(
        pathOverride: '${otherDir.path}/restore.db', openForTesting: openPlain);
    try {
      await other.createOwner('Baru');
      final restored = await Exports(other).restore(file);
      expect(restored.name, 'Budi');
      expect(await other.history(), hasLength(3));
    } finally {
      await other.close();
      await otherDir.delete(recursive: true);
    }
  });

  test('Restore rejects wrong role, malformed files and oversized files',
      () async {
    final file = await exports.backup();
    final student =
        (await repo.members()).firstWhere((m) => m.role == Role.siswa);
    await repo.switchUser(student.id);
    await expectLater(exports.restore(file), throwsA(isA<AppError>()));
    await repo.switchUser(
        (await repo.members()).firstWhere((m) => m.role == Role.bendahara).id);

    final malformed = File('${directory.path}/bad.json');
    await malformed.writeAsString('not-json');
    await expectLater(exports.restore(malformed), throwsA(anything));
    await malformed.writeAsString('[]');
    await expectLater(exports.restore(malformed), throwsA(isA<AppError>()));
    await malformed.writeAsString('{"schema":2}');
    await expectLater(exports.restore(malformed), throwsA(isA<AppError>()));
    final huge = File('${directory.path}/huge.json');
    final handle = await huge.open(mode: FileMode.write);
    await handle.truncate(64 * 1024 * 1024 + 1);
    await handle.close();
    await expectLater(exports.restore(huge), throwsA(isA<AppError>()));
  });

  test('Write failure leaves no partial backup', () async {
    final exportsDir = Directory('${directory.path}/exports');
    await exportsDir.create(recursive: true);
    await Process.run('chmod', ['0500', exportsDir.path]);
    addTearDown(() => Process.run('chmod', ['0700', exportsDir.path]));
    await expectLater(exports.backup(), throwsA(isA<AppError>()));
    final left = (await exportsDir.list().toList())
        .where((entry) => entry.path.endsWith('.partial'))
        .toList();
    expect(left, isEmpty);
  });

  test('Backup requires a treasurer session', () async {
    final student =
        (await repo.members()).firstWhere((m) => m.role == Role.siswa);
    await repo.switchUser(student.id);
    await expectLater(exports.backup(), throwsA(isA<AppError>()));
  });
}
