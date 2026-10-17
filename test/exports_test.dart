import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'secure_storage_mock.dart';
import 'package:kaskelasku/data/exports.dart';
import 'package:kaskelasku/data/backup.dart';
import 'package:kaskelasku/data/repository.dart';
import 'package:kaskelasku/data/vault.dart';
import 'package:kaskelasku/models.dart';

class SnapshotRepository extends TreasuryRepository {
  SnapshotRepository() : super(Vault());
  Role role = Role.bendahara;
  Backup? restored;
  @override
  Future<void> restore(Backup backup) async {
    restored = backup;
  }

  @override
  Future<Member> currentMember() async => Member('one', 'Bendahara', role);
  @override
  Future<Map<String, Object?>> reportSnapshot(String period) async => {
        'period': period,
        'opening': 5000,
        'status': <String, Object?>{},
        'rows': <Map<String, Object?>>[
          {
            'tx_date': '$period-15',
            'type': 'IN',
            'category': 'Iuran',
            'amount': 10000,
            'description': 'Iuran José'
          },
          {
            'tx_date': '$period-16',
            'type': 'OUT',
            'category': 'Alat',
            'amount': 1000,
            'description': '=formula'
          },
        ],
      };
  @override
  Future<Map<String, Object?>> backupSnapshot() async => {
        'schema': 1,
        'users': [],
        'transactions': [],
        'monthly_reports': [],
        'audit_log': [],
      };
  @override
  Future<List<String>> completedMonths(DateTime now) async => ['2026-09'];
  @override
  Future<String> automaticReportPassword() async => 'auto-report-secret-2026';
}

class FailingExportFile implements File {
  FailingExportFile(this.file, {required this.failWrite});
  final File file;
  final bool failWrite;
  @override
  String get path => file.path;
  @override
  Future<File> writeAsBytes(List<int> bytes,
      {FileMode mode = FileMode.write, bool flush = false}) async {
    if (failWrite) throw FileSystemException('test write failure', path);
    await file.writeAsBytes(bytes, mode: mode, flush: flush);
    return this;
  }

  @override
  Future<File> rename(String newPath) async =>
      throw FileSystemException('test rename failure', path);
  @override
  Future<bool> exists() => file.exists();
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      file.delete(recursive: recursive);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const password = 'Laporan-kelas-2026';
  setUp(() async {
    mockSecureStorage();
    directory = await Directory.systemTemp.createTemp('kk-exports-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => directory.path);
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  test(
      'PDF/CSV encrypted roundtrip, Unicode, formula safety and temporary cleanup',
      () async {
    final exports = Exports(SnapshotRepository());
    final report = await exports.report('2026-10', password);
    final pdf = await exports.decryptReport(report.pdf, password);
    expect(ascii.decode((await pdf.readAsBytes()).take(5).toList()), '%PDF-');
    await pdf.parent.delete(recursive: true);
    final csv = await exports.decryptReport(report.csv, password);
    expect(await csv.readAsString(), contains('Iuran José'));
    expect(await csv.readAsString(), contains("'=formula"));
    expect(await csv.readAsString(), contains('Saldo akhir,14000'));
    await csv.parent.delete(recursive: true);
    await expectLater(exports.decryptReport(report.pdf, 'wrong-password'),
        throwsA(isA<AppError>()));
    await expectLater(
        exports.decryptReport(File('${directory.path}/other'), password),
        throwsA(isA<AppError>()));
  }, timeout: const Timeout(Duration(minutes: 3)));
  test('Plaintext crash remnants cleaned without deleting unrelated files',
      () async {
    final leftover = Directory('${directory.path}/kk-share-stale');
    await leftover.create();
    await File('${leftover.path}/report.pdf').writeAsString('sensitive');
    final unrelated = File('${directory.path}/keep.txt');
    await unrelated.writeAsString('keep');
    await Exports.cleanupPlaintext();
    expect(await leftover.exists(), false);
    expect(await unrelated.readAsString(), 'keep');
  });

  test('Backup authenticated, wrong role rejected after encryption', () async {
    final repo = SnapshotRepository();
    final exports = Exports(repo);
    final file = await exports.backup(password);
    final decoded = jsonDecode(utf8.decode(await Vault.unseal(
        await file.readAsString(), password, 'KasKelasKu/backup/v1')));
    expect(decoded['schema'], 1);
    repo.role = Role.siswa;
    await expectLater(exports.backup(password), throwsA(isA<AppError>()));
    await expectLater(
        exports.restore(file, password), throwsA(isA<AppError>()));
  }, timeout: const Timeout(Duration(minutes: 3)));
  test('Write failures remove plaintext directory and partial encrypted backup',
      () async {
    final exports = Exports(SnapshotRepository());
    final report = await exports.report('2026-10', password);
    final parent = Zone.current;
    File intercept(String path) {
      final file = parent.run(() => File(path));
      if (path.endsWith('/KasKelasKu.csv'))
        return FailingExportFile(file, failWrite: true);
      if (path.endsWith('.partial'))
        return FailingExportFile(file, failWrite: false);
      return file;
    }

    await IOOverrides.runZoned(() async {
      await expectLater(exports.decryptReport(report.csv, password),
          throwsA(isA<FileSystemException>()));
      await expectLater(exports.backup(password), throwsA(isA<AppError>()));
    }, createFile: intercept);
    final remaining = await directory.list(recursive: true).toList();
    expect(remaining.where((f) => f.path.contains('kk-share-')), isEmpty);
    expect(remaining.where((f) => f.path.endsWith('.partial')), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 3)));
  test('Encrypted restore validates authentication, JSON shape and schema',
      () async {
    final repo = SnapshotRepository();
    final exports = Exports(repo);
    final file = await exports.backup(password);
    await expectLater(
        exports.restore(file, 'wrong-password'), throwsA(isA<AppError>()));
    expect(repo.restored, isNull);
    await exports.restore(file, password);
    expect(repo.restored!.tables['users'], isEmpty);
    for (final payload in ['[]', '{"schema":2}', 'not-json']) {
      repo.restored = null;
      await file.writeAsString(await Vault.seal(
          utf8.encode(payload), password, 'KasKelasKu/backup/v1'));
      await expectLater(exports.restore(file, password), throwsA(anything));
      expect(repo.restored, isNull);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
  test(
      'Automatic reports skip unchanged snapshots and regenerate missing artifacts',
      () async {
    final exports = Exports(SnapshotRepository());
    await exports.automaticReports(DateTime(2026, 10));
    final first = await exports.automaticFiles();
    expect(first, hasLength(2));
    await exports.automaticReports(DateTime(2026, 10));
    expect((await exports.automaticFiles()).map((f) => f.path),
        first.map((f) => f.path));
    await first.first.delete();
    await exports.automaticReports(DateTime(2026, 10));
    expect(await exports.automaticFiles(), hasLength(2));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
