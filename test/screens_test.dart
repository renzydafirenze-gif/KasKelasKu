import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kaskelasku/main.dart';
import 'package:kaskelasku/models.dart';
import 'package:kaskelasku/view_model.dart';
import 'fakes.dart';

void useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<TreasuryViewModel> pumpApp(
    WidgetTester tester, FakeRepository repo) async {
  useTallView(tester);
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
  useTallView(tester);
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
  testWidgets('First launch creates the treasurer without a password',
      (tester) async {
    final repo = FakeRepository(active: null);
    await pumpApp(tester, repo);
    expect(find.text('KasKelasKu'), findsOneWidget);
    await tester.tap(find.byKey(const Key('start_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Nama harus 1–80 karakter.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('owner_name_input')), 'Budi');
    await tester.tap(find.byKey(const Key('start_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Halo, Budi'), findsOneWidget);
    expect(repo.calls, ['owner:Budi']);
  });

  testWidgets('Database failure shows retry and can recover', (tester) async {
    final repo = FakeRepository(active: null)..failOpen = true;
    await pumpApp(tester, repo);
    expect(find.text('Data tidak bisa dibuka.'), findsOneWidget);
    repo.failOpen = false;
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('owner_name_input')), findsOneWidget);
  });

  testWidgets('Dashboard, history, reports, members and settings are reachable',
      (tester) async {
    final repo = FakeRepository();
    await pumpApp(tester, repo);
    expect(find.text('Halo, Budi'), findsOneWidget);
    expect(find.text('Rp 12.000'), findsOneWidget);
    expect(find.text('Target ${monthLabel(periodOf(DateTime.now()))}'),
        findsOneWidget);
    expect(find.textContaining('dari target'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    expect(find.textContaining('Iuran kelas'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.summarize_outlined));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('share_pdf_btn')));
    expect(find.byKey(const Key('share_pdf_btn')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.group_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Siti'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Mode gelap'));
    expect(find.text('Mode gelap'), findsOneWidget);
    final before = Theme.of(tester.element(find.text('Mode gelap'))).brightness;
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final after = Theme.of(tester.element(find.text('Mode gelap'))).brightness;
    expect(after, isNot(before));
    expect(find.text('KasKelasKu $appVersion'), findsOneWidget);
  });

  testWidgets('Dashboard error can be retried', (tester) async {
    final repo = FakeRepository()..fail = true;
    await pumpScreen(tester, repo, const DashboardScreen());
    expect(find.text('Ringkasan gagal dimuat.'), findsOneWidget);
    await tester.tap(find.text('Muat ulang'));
    await tester.pumpAndSettle();
    expect(find.text('Ringkasan gagal dimuat.'), findsOneWidget);
  });

  testWidgets('Dashboard target sheet validates and saves', (tester) async {
    final repo = FakeRepository()..target = 0;
    await pumpScreen(tester, repo, const DashboardScreen());
    expect(find.text('Belum ada target bulan ini'), findsOneWidget);
    await tester.tap(find.text('Tentukan target'));
    await tester.pumpAndSettle();
    expect(find.byType(TargetSheet), findsOneWidget);
    await tester.tap(find.byKey(const Key('save_target_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Target tidak valid.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('target_input')), '50000');
    await tester.tap(find.byKey(const Key('save_target_btn')));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('target:${periodOf(DateTime.now())}:50000'));
  });

  testWidgets('Dashboard empty state and see-all callback', (tester) async {
    final repo = FakeRepository()..entries = [];
    var seen = 0;
    await pumpScreen(tester, repo, DashboardScreen(onSeeAll: () => seen++));
    expect(find.text('Belum ada transaksi'), findsOneWidget);
    await tester.tap(find.text('Lihat semua'));
    await tester.pumpAndSettle();
    expect(seen, 1);
    await tester.ensureVisible(find.text('Catat transaksi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Catat transaksi'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionEntry), findsOneWidget);
    await tester.tap(find.byTooltip('Tutup'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionEntry), findsNothing);
  });

  testWidgets('History searches, filters, paginates and deletes',
      (tester) async {
    final repo = FakeRepository();
    await pumpScreen(tester, repo, const HistoryScreen());
    expect(find.textContaining('Iuran kelas'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('history_search')), 'Sapu');
    await tester.pumpAndSettle();
    expect(repo.historyCalls.last.$1, 'Sapu');
    expect(find.textContaining('Sapu'), findsWidgets);
    await tester.tap(find.byTooltip('Hapus pencarian'));
    await tester.pumpAndSettle();
    expect(repo.historyCalls.last.$1, '');
    final previous =
        periodOf(DateTime(DateTime.now().year, DateTime.now().month - 1, 1));
    await tester.tap(find.text(shortMonthLabel(previous)));
    await tester.pumpAndSettle();
    expect(repo.historyCalls.last.$2, '$previous-01');

    repo.entries = List.generate(
        100, (i) => sampleEntry(id: i + 1, description: 'Kas $i'));
    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester, repo, const HistoryScreen());
    await tester.scrollUntilVisible(find.text('Muat lebih banyak'), 300,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Muat lebih banyak'));
    await tester.pumpAndSettle();
    expect(repo.historyCalls.last.$3, 200);

    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester, FakeRepository(), const HistoryScreen());
    await tester.tap(find.byKey(const Key('delete_tx_btn')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(find.text('Batal'), findsNothing);
    await tester.tap(find.byKey(const Key('delete_tx_btn')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();
    expect(find.text('Hapus'), findsNothing);
  });

  testWidgets('History shows empty and error states', (tester) async {
    final repo = FakeRepository()..entries = [];
    await pumpScreen(tester, repo, const HistoryScreen());
    expect(find.text('Tidak ada transaksi.'), findsOneWidget);

    final failing = FakeRepository()..failHistory = true;
    await pumpScreen(tester, failing, const HistoryScreen());
    expect(
        find.text('Riwayat gagal dimuat. Periksa pencarian.'), findsOneWidget);
  });

  testWidgets('Member sheet adds and edits members', (tester) async {
    final repo = FakeRepository();
    await pumpScreen(tester, repo, const MembersScreen());
    await tester.tap(find.byKey(const Key('add_member_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_member_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Nama harus 1–80 karakter.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('member_name_input')), 'Wali');
    await tester.tap(find.byType(DropdownButtonFormField<Role>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guru Wali').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_member_btn')));
    await tester.pumpAndSettle();
    expect(repo.calls, ['member:Wali:guruWali']);

    await tester.tap(find.text('Siti'));
    await tester.pumpAndSettle();
    expect(find.text('Ubah anggota'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_member_btn')));
    await tester.pumpAndSettle();
    expect(repo.calls.last, 'change:two:siswa:false');
  });

  testWidgets('Members are read-only for non-treasurers', (tester) async {
    final repo = FakeRepository();
    await pumpScreen(tester, repo, const MembersScreen(),
        user: const Member('two', 'Siti', Role.siswa));
    expect(find.byKey(const Key('add_member_btn')), findsNothing);
    await tester.tap(find.text('Budi'));
    await tester.pumpAndSettle();
    expect(find.text('Ubah anggota'), findsNothing);
  });

  testWidgets('Report approvals follow role and surface failures',
      (tester) async {
    final repo = FakeRepository();
    await pumpScreen(tester, repo, const ReportsScreen(),
        user: const Member('three', 'Ketua', Role.ketua));
    await tester.tap(find.text('Setujui dan kunci'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Setujui dan kunci'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Setujui'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['approve:${periodOf(DateTime.now())}']);

    await tester.pumpWidget(const SizedBox());
    final failing = FakeRepository()..fail = true;
    await pumpScreen(tester, failing, const ReportsScreen(),
        user: const Member('four', 'Wali', Role.guruWali));
    await tester.ensureVisible(find.text('Verifikasi sebagai Guru Wali'));
    await tester.tap(find.text('Verifikasi sebagai Guru Wali'));
    await tester.pumpAndSettle();
    expect(find.text('Operasi ditolak.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await pumpScreen(tester, FakeRepository(), const ReportsScreen(),
        user: const Member('two', 'Siti', Role.siswa));
    expect(find.text('Setujui dan kunci'), findsNothing);
    expect(find.text('Verifikasi sebagai Guru Wali'), findsNothing);
  });

  testWidgets('Report month navigation and target editing', (tester) async {
    final repo = FakeRepository();
    await pumpScreen(tester, repo, const ReportsScreen());
    final current = periodOf(DateTime.now());
    await tester.tap(find.byTooltip('Bulan berikutnya'));
    await tester.pumpAndSettle();
    expect(
        find.text(monthLabel(periodOf(
            DateTime(DateTime.now().year, DateTime.now().month + 1, 1)))),
        findsOneWidget);
    await tester.tap(find.byTooltip('Bulan sebelumnya'));
    await tester.pumpAndSettle();
    expect(find.text(monthLabel(current)), findsOneWidget);
    await tester.ensureVisible(find.text('Atur'));
    await tester.tap(find.text('Atur'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('target_input')), '30000');
    await tester.tap(find.byKey(const Key('save_target_btn')));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('target:$current:30000'));
  });

  testWidgets('User switch sheet changes session and hides treasurer actions',
      (tester) async {
    final repo = FakeRepository();
    await pumpApp(tester, repo);
    expect(find.byKey(const Key('add_transaction_btn')), findsOneWidget);
    await tester.tap(find.text('Budi · Bendahara'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Siti'));
    await tester.pumpAndSettle();
    expect(find.text('Siti · Siswa'), findsOneWidget);
    expect(find.byKey(const Key('add_transaction_btn')), findsNothing);
  });

  testWidgets('Settings shows the no-encryption notice', (tester) async {
    await pumpApp(tester, FakeRepository());
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('tanpa enkripsi'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('tanpa enkripsi'), findsOneWidget);
  });
}
