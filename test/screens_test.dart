import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kaskelasku/data/repository.dart';
import 'package:kaskelasku/data/vault.dart';
import 'package:kaskelasku/main.dart';
import 'package:kaskelasku/models.dart';
import 'package:kaskelasku/view_model.dart';
import 'package:kaskelasku/main.dart' as app;
import 'repository_test.dart' show MemoryVault;
import 'secure_storage_mock.dart';

class ScreenRepository extends TreasuryRepository {
  ScreenRepository() : super(MemoryVault());
  final user = const Member('one', 'Budi', Role.bendahara);
  @override
  Future<int> balance() async => 10000;
  @override
  Future<List<Map<String, Object?>>> trends() async => [
        {'period': '2026-09', 'net': 15000},
        {'period': '2026-10', 'net': -5000}
      ];
  @override
  Future<List<Member>> members() async =>
      [user, const Member('two', 'Siti', Role.siswa)];
  @override
  Future<List<CashTransaction>> history(
          {String category = '',
          String keyword = '',
          String? from,
          String? to,
          int limit = 100,
          int offset = 0}) async =>
      [
        CashTransaction(
            id: 1,
            amount: 10000,
            type: 'IN',
            category: 'Kas',
            date: '2026-10-01',
            description: 'Iuran kelas')
      ];
}

class SessionScreenRepository extends ScreenRepository {
  bool reject = false;
  bool changedRole = false;
  bool biometrics = false;
  bool biometricFails = false;
  int locks = 0;
  @override
  Future<Member> setup(String name, String password) async {
    if (name.trim().isEmpty) throw const AppError('Nama wajib diisi.');
    await vault.enroll(user.id, password, 'test-key');
    return user;
  }

  @override
  Future<Member> login(String id, String password, Role selectedRole) async {
    await vault.unlock(id, password);
    if (selectedRole != user.role) throw const AppError('Peran tidak sesuai.');
    return user;
  }

  @override
  Future<Member> currentMember() async {
    if (reject) throw const AppError('Akun dinonaktifkan.');
    if (changedRole) return const Member('one', 'Budi', Role.siswa);
    return user;
  }

  @override
  bool get canResumeBiometric => biometrics;
  @override
  Future<Member> resumeBiometric() async {
    if (biometricFails) throw const AppError('Biometrik gagal.');
    return user;
  }

  @override
  Future<List<String>> completedMonths(DateTime now) async => [];
  @override
  Future<void> lock({bool forgetBiometric = false}) async {
    locks++;
  }
}

void main() {
  testWidgets('App entry point starts and reports secure-storage failure',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => throw PlatformException(code: 'storage_failure'));
    app.main();
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Penyimpanan kunci gagal dibuka. Jangan hapus data aplikasi.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final failure in [false, true]) {
    testWidgets('Biometric login UI failure=$failure', (tester) async {
      mockSecureStorage();
      await Vault.storage.write(key: 'setting:dark', value: 'false');
      final repo = SessionScreenRepository()
        ..biometrics = true
        ..biometricFails = failure;
      await repo.vault.enroll('one', 'Password-kelas-2026', 'test-key');
      final model = TreasuryViewModel(repo);
      await tester.pumpWidget(ProviderScope(
          overrides: [treasuryProvider.overrideWithValue(model)],
          child: const KasKelasKuApp()));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<Role>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Siswa').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Buka akun terakhir dengan biometrik'));
      await tester.pumpAndSettle();
      if (failure) {
        expect(find.text('Biometrik gagal.'), findsOneWidget);
      } else {
        expect(find.byType(HomeScreen), findsOneWidget);
        repo.changedRole = true;
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(model.dispose);
    });
  }
  testWidgets(
      'Setup validates fields, opens vault and manual lock returns to login',
      (tester) async {
    mockSecureStorage();
    final repo = SessionScreenRepository();
    final model = TreasuryViewModel(repo);
    await tester.pumpWidget(ProviderScope(overrides: [
      treasuryProvider.overrideWithValue(model),
    ], child: const KasKelasKuApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Buat brankas'));
    await tester.pumpAndSettle();
    expect(find.text('Nama wajib diisi.'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Nama Bendahara'), 'Budi');
    await tester.enterText(
        find.widgetWithText(TextField, 'Kata sandi'), 'KelasSepuluh-2026!');
    await tester.tap(find.text('Buat brankas'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    final gesture = await tester.startGesture(const Offset(300, 300));
    await gesture.moveBy(const Offset(0, 20));
    await gesture.up();
    await tester.tap(find.byTooltip('Kunci aplikasi'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(repo.locks, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(model.dispose);
  });

  for (final reason in ['background', 'idle', 'revoked']) {
    testWidgets('Session locks and closes sensitive dialogs: $reason',
        (tester) async {
      mockSecureStorage();
      final repo = SessionScreenRepository();
      await repo.vault.enroll('one', 'KelasSepuluh-2026!', 'test-key');
      final model = TreasuryViewModel(repo);
      await tester.pumpWidget(ProviderScope(overrides: [
        treasuryProvider.overrideWithValue(model),
      ], child: const KasKelasKuApp()));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, 'Kata sandi'), 'wrong');
      await tester.tap(find.text('Masuk'));
      await tester.pumpAndSettle();
      expect(find.text('Kata sandi salah.'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField, 'Kata sandi'), 'KelasSepuluh-2026!');
      await tester.tap(find.text('Masuk'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transaksi'));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionEntry), findsOneWidget);
      if (reason == 'background') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      } else if (reason == 'idle') {
        await tester.pump(const Duration(minutes: 3));
      } else {
        repo.reject = true;
        await tester.pump(const Duration(seconds: 2));
      }
      await tester.pumpAndSettle();
      expect(find.byType(TransactionEntry), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(repo.locks, greaterThan(0));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(model.dispose);
    });
  }

  testWidgets(
      'Treasurer navigates dashboard, history, reports, members and settings',
      (tester) async {
    mockSecureStorage();
    final repo = ScreenRepository();
    final model = TreasuryViewModel(repo);
    await tester.pumpWidget(ProviderScope(overrides: [
      treasuryProvider.overrideWithValue(model),
      sessionProvider.overrideWithValue(StateController<Member?>(repo.user)),
    ], child: const MaterialApp(home: HomeScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Rp 10.000'), findsOneWidget);
    expect(find.text('Arus kas bersih per bulan'), findsOneWidget);
    await tester.tap(find.text('Riwayat'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Iuran kelas'), findsOneWidget);
    await tester.tap(find.text('Filter riwayat'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Kata kunci keterangan'), 'Iuran');
    await tester.tap(find.text('Terapkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Laporan'));
    await tester.pumpAndSettle();
    expect(find.text('Laporan bulanan'), findsOneWidget);
    expect(find.text('Setujui dan kunci'), findsNothing);
    await tester.tap(find.text('Anggota'));
    await tester.pumpAndSettle();
    expect(find.text('Budi'), findsOneWidget);
    await tester.tap(find.text('Tambah anggota'));
    await tester.pumpAndSettle();
    expect(find.byType(AddMemberDialog), findsOneWidget);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Setelan'));
    await tester.pumpAndSettle();
    expect(find.text('Mode gelap'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ganti kata sandi'));
    await tester.pumpAndSettle();
    expect(find.byType(ChangePasswordDialog), findsOneWidget);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(model.dispose);
  });

  for (final role in [Role.ketua, Role.guruWali, Role.siswa]) {
    testWidgets('${role.label} report actions follow role', (tester) async {
      final model = TreasuryViewModel(ScreenRepository());
      await tester.pumpWidget(ProviderScope(overrides: [
        treasuryProvider.overrideWithValue(model),
        sessionProvider.overrideWithValue(
            StateController<Member?>(Member('one', 'User', role))),
      ], child: const MaterialApp(home: Scaffold(body: ReportsScreen()))));
      await tester.pumpAndSettle();
      expect(find.text('Setujui dan kunci'),
          role == Role.ketua ? findsOneWidget : findsNothing);
      expect(find.text('Verifikasi sebagai Guru Wali'),
          role == Role.guruWali ? findsOneWidget : findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(model.dispose);
    });
  }
}
