import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kaskelasku/main.dart';
import 'package:kaskelasku/models.dart';
import 'package:kaskelasku/view_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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

Future<TreasuryViewModel> pumpApp(
    WidgetTester tester, FakeRepository repo) async {
  tallView(tester);
  final model = TreasuryViewModel(repo);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(model.dispose);
  });
  await tester.pumpWidget(ProviderScope(
      overrides: [treasuryProvider.overrideWithValue(model)],
      child: const KasKelasKuApp()));
  await tester.pumpAndSettle();
  return model;
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
  await tester.pumpWidget(ProviderScope(overrides: [
    treasuryProvider.overrideWithValue(model),
    sessionProvider
        .overrideWithValue(StateController<Member?>(user ?? repo.active)),
  ], child: MaterialApp(home: Scaffold(body: screen))));
  await tester.pumpAndSettle();
  return model;
}

void main() {
  testWidgets('Onboarding submits with the keyboard action', (tester) async {
    final repo = FakeRepository(active: null);
    await pumpApp(tester, repo);
    await tester.enterText(find.byKey(const Key('owner_name_input')), 'Budi');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.calls, ['owner:Budi']);
  });

  testWidgets('User switch failures keep the sheet open', (tester) async {
    final repo = FakeRepository();
    await pumpApp(tester, repo);
    await tester.tap(find.text('Budi · Bendahara'));
    await tester.pumpAndSettle();
    repo.fail = true;
    await tester.tap(find.text('Siti'));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    expect(find.text('Operasi ditolak.'), findsOneWidget);
    expect(find.text('Ganti pengguna'), findsOneWidget);
  });

  testWidgets('Dashboard floating button opens the entry sheet',
      (tester) async {
    await pumpApp(tester, FakeRepository());
    await tester.tap(find.byKey(const Key('add_transaction_btn')));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionEntry), findsOneWidget);
  });

  testWidgets('Dashboard target action opens the sheet for non-empty targets',
      (tester) async {
    await pumpScreen(tester, FakeRepository(), const DashboardScreen());
    await tester.tap(find.byKey(const Key('edit_target_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(rupiah(100000)));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save_target_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Target ${monthLabel(periodOf(DateTime.now()))}'),
        findsWidgets);
  });

  testWidgets('Contributor names appear on the dashboard and history',
      (tester) async {
    final repo = FakeRepository()
      ..entries = [
        sampleEntry(contributorId: 'two', contributorName: 'Siti'),
        sampleEntry(id: 2, type: 'OUT', category: 'Alat', description: 'Sapu'),
      ];
    await pumpScreen(tester, repo, const DashboardScreen());
    expect(find.textContaining('Siti'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester, repo, const HistoryScreen());
    expect(find.textContaining('Siti'), findsOneWidget);
  });

  testWidgets('Members screen shows payment status and quick pay',
      (tester) async {
    final repo = FakeRepository()
      ..entries = [
        sampleEntry(contributorId: 'two', contributorName: 'Siti'),
      ];
    await pumpScreen(tester, repo, const MembersScreen());
    expect(find.text('1 dari 1 murid sudah bayar'), findsOneWidget);
    expect(find.textContaining('Lunas'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pay_two')));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionEntry), findsOneWidget);
    final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).where(
        (chip) => chip.label is Text && (chip.label as Text).data == 'Siti');
    expect(chips.single.selected, isTrue);
    expect(find.text('Kas'), findsWidgets);
  });

  testWidgets('Unpaid filter narrows the list and shows the empty state',
      (tester) async {
    final repo = FakeRepository()
      ..people = const [
        Member('one', 'Budi', Role.bendahara),
        Member('two', 'Siti', Role.siswa)
      ]
      ..entries = [
        sampleEntry(contributorId: 'two', contributorName: 'Siti'),
      ];
    await pumpScreen(tester, repo, const MembersScreen());
    await tester.tap(find.byKey(const Key('filter_unpaid_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Siti'), findsNothing);
    expect(find.text('Semua murid sudah bayar.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('filter_all_members')));
    await tester.pumpAndSettle();
    expect(find.text('Siti'), findsOneWidget);
  });

  testWidgets('Member sheet adds many students at once', (tester) async {
    final repo = FakeRepository();
    await pumpScreen(tester, repo, const MembersScreen());
    await tester.tap(find.byKey(const Key('add_member_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('toggle_bulk_member_btn')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('member_names_input')), 'Adi\nBudi, Citra');
    await tester.tap(find.byKey(const Key('save_member_btn')));
    await tester.pumpAndSettle();
    expect(repo.calls, ['students:Adi|Budi|Citra']);
  });

  testWidgets('Double tap on Simpan only stores one transaction',
      (tester) async {
    // Simpan lambat supaya tap kedua mendarat saat penulisan masih berjalan.
    final repo = FakeRepository()
      ..writeDelay = const Duration(milliseconds: 200);
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
    await tester.enterText(find.byKey(const Key('amount_input')), '10000');
    await tester.enterText(find.byKey(const Key('category_input')), 'Kas');
    final button = find.byKey(const Key('submit_tx_btn'));
    await tester.tap(button);
    await tester.tap(button, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(repo.calls.where((call) => call.startsWith('transaction:')),
        hasLength(1));
  });

  testWidgets('Dashboard pull to refresh reloads the overview', (tester) async {
    await pumpScreen(tester, FakeRepository(), const DashboardScreen());
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.text('Halo, Budi'), findsOneWidget);
  });

  testWidgets('Switch sheet reports member load failures without opening',
      (tester) async {
    final repo = FakeRepository();
    await pumpApp(tester, repo);
    repo.fail = true;
    await tester.tap(find.text('Budi · Bendahara'));
    await tester.pumpAndSettle();
    expect(find.text('Ganti pengguna'), findsNothing);
    expect(find.text('Operasi ditolak.'), findsOneWidget);
  });

  testWidgets('Expense transactions show their description', (tester) async {
    await pumpScreen(tester, FakeRepository(), const HistoryScreen());
    expect(find.textContaining('Sapu'), findsWidgets);
  });

  testWidgets('Entry supports a custom category', (tester) async {
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
    await tester.enterText(find.byKey(const Key('amount_input')), '6000');
    await tester.enterText(find.byKey(const Key('category_input')), 'Studi');
    await tester.tap(find.byKey(const Key('submit_tx_btn')));
    await tester.pumpAndSettle();
    expect(repo.calls.single, startsWith('transaction:IN:6000:Studi:'));
  });

  test('Treasurer falls back when the owner is not a treasurer', () async {
    final directory = await Directory.systemTemp.createTemp('kk-fallback-');
    final repo = TreasuryRepository(
        pathOverride: '${directory.path}/fallback.db',
        openForTesting: openPlain);
    try {
      final db = await repo.database;
      await db.insert('users', {'id': 's', 'name': 'Siswa', 'role': 'siswa'});
      expect((await repo.open())!.name, 'Siswa');
    } finally {
      await repo.close();
      await directory.delete(recursive: true);
    }
  });

  test('ViewModel closes the repository on dispose', () async {
    final repo = FakeRepository();
    final model = TreasuryViewModel(repo);
    await model.dispose();
    expect(repo.closed, true);
  });
}
