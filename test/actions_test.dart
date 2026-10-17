import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kaskelasku/main.dart';
import 'package:kaskelasku/models.dart';
import 'package:kaskelasku/view_model.dart';
import 'dart:ui' as ui;
import 'screens_test.dart' show ScreenRepository;
import 'secure_storage_mock.dart';

class ActionRepository extends ScreenRepository {
  bool fail = false;
  bool duplicate = false;
  final calls = <String>[];
  void record(String value) {
    if (fail) throw const AppError('Operasi ditolak.');
    calls.add(value);
  }

  @override
  Future<void> addMember(String name, Role role, String password) async =>
      record('member:$name:${role.name}:$password');
  @override
  Future<void> changePassword(String old, String next) async =>
      record('password:$old:$next');
  @override
  Future<void> changeMember(Member member, Role role, bool active) async =>
      record('change:${member.id}:${role.name}:$active');
  @override
  Future<void> deleteTransaction(int id) async => record('delete:$id');
  @override
  Future<void> approve(String period) async => record('approve:$period');
  @override
  Future<void> verify(String period) async => record('verify:$period');
  @override
  Future<void> addTransaction(CashTransaction entry, String submissionId,
      {bool confirmDuplicate = false}) async {
    entry.validate();
    if (duplicate && !confirmDuplicate) throw DuplicateTransaction();
    record('transaction:${entry.type}:$confirmDuplicate');
  }
}

class EmptyActionRepository extends ActionRepository {
  @override
  Future<List<CashTransaction>> history(
      {String category = '',
      String keyword = '',
      String? from,
      String? to,
      int limit = 100,
      int offset = 0}) async {
    if (this.fail) throw const AppError('Filter ditolak.');
    return [];
  }

  @override
  Future<List<Map<String, Object?>>> trends() async => [];
}

void main() {
  test('Trend painter supports empty and single points and repaint changes',
      () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    TrendPainter([], Colors.blue).paint(canvas, const Size(100, 100));
    final painter = TrendPainter([1], Colors.blue);
    painter.paint(canvas, const Size(100, 100));
    expect(painter.shouldRepaint(TrendPainter([2], Colors.red)), true);
    recorder.endRecording().dispose();
  });
  Future<TreasuryViewModel> mount(
      WidgetTester tester, ActionRepository repo, Widget screen,
      {Role role = Role.bendahara}) async {
    mockSecureStorage();
    final model = TreasuryViewModel(repo);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(model.dispose);
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [
          treasuryProvider.overrideWithValue(model),
          sessionProvider.overrideWithValue(
              StateController<Member?>(Member('one', 'Budi', role))),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => Material(child: screen)),
                        child: const Text('Buka')))))));
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    return model;
  }

  for (final fail in [false, true]) {
    if (!fail) {
      testWidgets('Dashboard explains empty ledger', (tester) async {
        await mount(tester, EmptyActionRepository(), const DashboardScreen());
        expect(find.text('Belum ada transaksi.'), findsOneWidget);
      });
    }
    testWidgets('Empty history and invalid filter failure=$fail',
        (tester) async {
      final repo = EmptyActionRepository()..fail = fail;
      await mount(tester, repo, const HistoryScreen());
      expect(
          find.text(fail
              ? 'Riwayat gagal dimuat. Periksa filter atau masuk kembali.'
              : 'Tidak ada transaksi.'),
          findsOneWidget);
    });

    testWidgets('Add member submit, role selection and failure=$fail',
        (tester) async {
      final repo = ActionRepository()..fail = fail;
      await mount(tester, repo, const AddMemberDialog());
      await tester.enterText(find.widgetWithText(TextField, 'Nama'), 'Siti');
      await tester.tap(find.byType(DropdownButtonFormField<Role>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ketua').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      if (fail) {
        expect(find.text('Operasi ditolak.'), findsOneWidget);
        expect(find.byType(AddMemberDialog), findsOneWidget);
        expect(repo.calls, isEmpty);
      } else {
        expect(repo.calls, ['member:Siti:ketua:']);
        expect(find.byType(AddMemberDialog), findsNothing);
      }
    });

    testWidgets('Password change submit and failure=$fail', (tester) async {
      final repo = ActionRepository()..fail = fail;
      await mount(tester, repo, const ChangePasswordDialog());
      await tester.enterText(
          find.widgetWithText(TextField, 'Kata sandi sekarang'),
          'old-password');
      await tester.enterText(
          find.widgetWithText(TextField, 'Kata sandi baru minimal 12 karakter'),
          'new-password-2026');
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      if (fail) {
        expect(find.text('Operasi ditolak.'), findsOneWidget);
        expect(find.byType(ChangePasswordDialog), findsOneWidget);
      } else {
        expect(repo.calls, ['password:old-password:new-password-2026']);
        expect(find.byType(ChangePasswordDialog), findsNothing);
      }
    });
  }

  for (final confirm in [false, true]) {
    testWidgets('Duplicate transaction confirmation=$confirm', (tester) async {
      final repo = ActionRepository()..duplicate = true;
      await mount(tester, repo, const TransactionEntry());
      await tester.enterText(find.byKey(const Key('amount_input')), '5000');
      await tester.enterText(
          find.widgetWithText(TextField, 'Kategori / tujuan'), 'Kas');
      await tester.enterText(
          find.widgetWithText(TextField, 'Keterangan'), 'Iuran');
      await tester.ensureVisible(find.byKey(const Key('transaction_type_input')));
      await tester.tap(find.byKey(const Key('transaction_type_input')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pengeluaran').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(find.text('Transaksi serupa ditemukan'), findsOneWidget);
      await tester.tap(confirm
          ? find.text('Simpan pembayaran berbeda')
          : find.text('Batal').last);
      await tester.pumpAndSettle();
      expect(repo.calls, confirm ? ['transaction:OUT:true'] : isEmpty);
      expect(find.byType(TransactionEntry),
          confirm ? findsNothing : findsOneWidget);
    });
  }

  for (final fail in [false, true]) {
    testWidgets('Delete requires confirmation and handles failure=$fail',
        (tester) async {
      final repo = ActionRepository()..fail = fail;
      await mount(tester, repo, const HistoryScreen());
      await tester.tap(find.byTooltip('Hapus transaksi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);
      await tester.tap(find.byTooltip('Hapus transaksi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();
      expect(repo.calls, fail ? isEmpty : ['delete:1']);
      if (fail) expect(find.text('Operasi ditolak.'), findsOneWidget);
    });

    testWidgets('Member menu role and activation changes failure=$fail',
        (tester) async {
      final repo = ActionRepository()..fail = fail;
      await mount(tester, repo, const MembersScreen());
      await tester.tap(find.byTooltip('Ubah izin anggota').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ketua').last);
      await tester.pumpAndSettle();
      if (fail) {
        expect(find.text('Operasi ditolak.'), findsOneWidget);
        expect(repo.calls, isEmpty);
      } else {
        expect(repo.calls, ['change:two:ketua:true']);
        await tester.tap(find.byTooltip('Ubah izin anggota').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Nonaktifkan'));
        await tester.pumpAndSettle();
        expect(repo.calls.last, 'change:two:siswa:false');
      }
    });
  }

  for (final role in [Role.ketua, Role.guruWali]) {
    for (final fail in [false, true]) {
      testWidgets('Report ${role.name} action failure=$fail', (tester) async {
        final repo = ActionRepository()..fail = fail;
        await mount(tester, repo, const ReportsScreen(), role: role);
        await tester.enterText(
            find.widgetWithText(TextField, 'Bulan YYYY-MM'), '2026-10');
        await tester.tap(find.text(role == Role.ketua
            ? 'Setujui dan kunci'
            : 'Verifikasi sebagai Guru Wali'));
        await tester.pumpAndSettle();
        if (role == Role.ketua) {
          expect(repo.calls, isEmpty);
          await tester.tap(find.text('Batal'));
          await tester.pumpAndSettle();
          expect(repo.calls, isEmpty);
          await tester.tap(find.text('Setujui dan kunci'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Setujui dan kunci').last);
          await tester.pumpAndSettle();
        }
        if (fail) {
          expect(find.text('Operasi ditolak.'), findsOneWidget);
          expect(repo.calls, isEmpty);
        } else {
          expect(repo.calls,
              ['${role == Role.ketua ? 'approve' : 'verify'}:2026-10']);
          expect(find.text('Selesai.'), findsOneWidget);
        }
      });
    }
  }
}
