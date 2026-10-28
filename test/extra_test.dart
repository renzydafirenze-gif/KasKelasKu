import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kaskelasku/main.dart';
import 'package:kaskelasku/models.dart';
import 'package:kaskelasku/view_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kaskelasku/data/backup.dart';
import 'package:kaskelasku/data/repository.dart';
import 'fakes.dart';

Future<Database> openPlain(String path) => databaseFactoryFfi.openDatabase(path,
    options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          for (final sql in (await rootBundle.loadString('lib/data/schema.sql'))
              .split('-- @statement')) {
            await db.execute(sql);
          }
        }));

void tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<TreasuryViewModel> pumpScreen(
    WidgetTester tester, FakeRepository repo, Widget screen,
    {Member? user}) async {
  tallView(tester);
  final model = TreasuryViewModel(repo);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(model.dispose);
  });
  await tester.pumpWidget(ProviderScope(
      overrides: [
        treasuryProvider.overrideWithValue(model),
        sessionProvider
            .overrideWithValue(StateController<Member?>(user ?? repo.active)),
      ],
      child: MaterialApp(
          home:
              Scaffold(body: KeyedSubtree(key: UniqueKey(), child: screen)))));
  await tester.pumpAndSettle();
  return model;
}

void main() {
  test('Error text and duplicate message', () {
    const error = AppError('Pesan');
    expect(error.toString(), 'Pesan');
    expect(const DuplicateTransaction().toString(),
        'Transaksi serupa sudah ada. Tetap simpan?');
  });

  test('Backup rejects mismatched approval columns', () {
    final base = <String, dynamic>{
      'schema': 1,
      'users': [
        {'id': 'one', 'name': 'Siswa', 'role': 'siswa', 'active': 1}
      ],
      'transactions': <Object?>[],
      'monthly_reports': [
        {
          'period': '2026-10',
          'approved_by': 'one',
          'approved_at': '2026-10-01',
          'verified_by': null,
          'verified_at': '2026-10-01'
        }
      ],
      'monthly_total_targets': <Object?>[],
      'audit_log': <Object?>[]
    };
    expect(() => Backup(base), throwsA(isA<AppError>()));
  });

  testWidgets('Entry date picker applies the chosen date', (tester) async {
    final repo = FakeRepository();
    final model = TreasuryViewModel(repo);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(model.dispose);
    });
    tallView(tester);
    await tester.pumpWidget(ProviderScope(overrides: [
      treasuryProvider.overrideWithValue(model),
    ], child: const MaterialApp(home: Scaffold(body: TransactionEntry()))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tanggal'));
    await tester.tap(find.text(dateLabel(isoDate(DateTime.now()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    expect(find.text('15 ${_short(now.month)} ${now.year}'), findsOneWidget);
  });

  testWidgets('Entry toggles contributor chips back to umum', (tester) async {
    final repo = FakeRepository();
    tallView(tester);
    final model = TreasuryViewModel(repo);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(model.dispose);
    });
    await tester.pumpWidget(ProviderScope(overrides: [
      treasuryProvider.overrideWithValue(model),
      sessionProvider.overrideWithValue(StateController<Member?>(repo.active)),
    ], child: const MaterialApp(home: Scaffold(body: TransactionEntry()))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Siti'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Siti'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Umum'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dashboard quick actions open both entry modes', (tester) async {
    final repo = FakeRepository()..target = 0;
    await pumpScreen(tester, repo, const DashboardScreen());
    await tester.tap(find.text('Uang masuk'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionEntry), findsOneWidget);
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uang keluar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lihat semua'));
    await tester.pumpAndSettle();
  });

  testWidgets('Dashboard shows the paid state and trend chart', (tester) async {
    final repo = FakeRepository()..target = 1000;
    await pumpScreen(tester, repo, const DashboardScreen());
    expect(find.text('Lunas'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('History delete surfaces repository failures', (tester) async {
    final repo = FakeRepository()..failDelete = true;
    await pumpScreen(tester, repo, const HistoryScreen());
    await tester.tap(find.byKey(const Key('delete_tx_btn')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();

    expect(find.text('Hapus'), findsNothing);
    expect(find.text('Operasi ditolak.'), findsOneWidget);
  });

  testWidgets('Members list marks inactive members', (tester) async {
    final repo = FakeRepository()
      ..people = const [
        Member('one', 'Budi', Role.bendahara),
        Member('two', 'Siti', Role.siswa, active: false)
      ];
    await pumpScreen(tester, repo, const MembersScreen());
    expect(find.text('nonaktif'), findsOneWidget);
  });

  testWidgets('Members list error state', (tester) async {
    final repo = FakeRepository()..fail = true;
    await pumpScreen(tester, repo, const MembersScreen());
    expect(find.text('Daftar anggota gagal dimuat.'), findsOneWidget);
  });

  testWidgets('Settings user row opens the switch sheet', (tester) async {
    final repo = FakeRepository();
    await pumpScreen(tester, repo, const SettingsScreen());
    await tester.tap(find.text('Ganti'));
    await tester.pumpAndSettle();
    expect(find.text('Ganti pengguna'), findsOneWidget);
    await tester.tap(find.text('Siti'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['switch:two']);
  });

  test('Legacy database with an existing quarantine name', () async {
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('kk-legacy2-');
    final path = '${directory.path}/old.db';
    try {
      await File(path).writeAsBytes(List.filled(64, 7));
      await File('$path.legacy').writeAsString('lama');
      final repo = TreasuryRepository(pathOverride: path);
      try {
        expect(await repo.open(), isNull);
        final quarantined = directory
            .listSync()
            .where((entry) => entry.path.contains('.legacy-'))
            .toList();
        expect(quarantined, hasLength(1));
      } finally {
        await repo.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('Existing plain database is reopened without quarantine', () async {
    final directory = await Directory.systemTemp.createTemp('kk-plain-');
    final path = '${directory.path}/plain.db';
    try {
      final first =
          TreasuryRepository(pathOverride: path, openForTesting: openPlain);
      await first.createOwner('Budi');
      await first.close();
      final second = TreasuryRepository(pathOverride: path);
      try {
        expect((await second.open())!.name, 'Budi');
      } finally {
        await second.close();
      }
      expect(await File('$path.legacy').exists(), false);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('Switch user rejects missing members', () async {
    final directory = await Directory.systemTemp.createTemp('kk-switch-');
    final repo = TreasuryRepository(
        pathOverride: '${directory.path}/switch.db', openForTesting: openPlain);
    try {
      expect(await repo.open(), isNull);
      await repo.createOwner('Budi');
      await expectLater(repo.switchUser('missing'), throwsA(isA<AppError>()));
    } finally {
      await repo.close();
      await directory.delete(recursive: true);
    }
  });
}

String _short(int month) => const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des'
    ][month - 1];
