import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kaskelasku/data/vault.dart';
import 'package:kaskelasku/main.dart';
import 'package:kaskelasku/models.dart';
import 'package:kaskelasku/view_model.dart';
import 'exports_test.dart' show SnapshotRepository;
import 'secure_storage_mock.dart';

void main() {
  const password = 'Laporan-kelas-2026';
  late Directory directory;
  late SnapshotRepository repo;
  late TreasuryViewModel model;
  String? picked;
  final shares = <MethodCall>[];
  const picker = MethodChannel(
      'miguelruivo.flutter.plugins.filepicker', JSONMethodCodec());
  const share = MethodChannel('dev.fluttercommunity.plus/share');
  const paths = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    mockSecureStorage();
    directory = Directory.systemTemp.createTempSync('kk-file-ui-');
    repo = SnapshotRepository();
    model = TreasuryViewModel(repo);
    picked = null;
    shares.clear();
    FilePickerIO.registerWith();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    messenger.setMockMethodCallHandler(
        picker,
        (_) async => picked == null
            ? null
            : [
                {'path': picked, 'name': picked!.split('/').last, 'size': 1}
              ]);
    messenger.setMockMethodCallHandler(share, (call) async {
      shares.add(call);
      return 'success';
    });
  });
  tearDown(() async {
    await model.dispose();
    directory.deleteSync(recursive: true);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [paths, picker, share]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> mount(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      treasuryProvider.overrideWithValue(model),
      sessionProvider.overrideWithValue(StateController<Member?>(
          const Member('one', 'Budi', Role.bendahara))),
    ], child: MaterialApp(home: Scaffold(body: screen))));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
  }

  Future<void> tapAndWait(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.runAsync(() => tester.tap(finder));
    // Real PBKDF2 and filesystem operations run outside Flutter's fake clock.
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.text('Mengenkripsi…').evaluate().isEmpty) break;
      if (i == 299) fail('File action did not finish within 30 seconds.');
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Report export shares encrypted files and reports invalid password',
      (tester) async {
    await mount(tester, const ReportsScreen());
    await tester.tap(find.text('Buat PDF dan CSV terenkripsi'));
    await tester.pumpAndSettle();
    expect(find.text('Kata sandi harus 12–128 karakter.'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Kata sandi ekspor minimal 12 karakter'),
        password);
    await tapAndWait(tester, find.text('Buat PDF dan CSV terenkripsi'));
    expect(shares, hasLength(1));
    final files = (shares.single.arguments as Map)['paths'] as List;
    expect(files, hasLength(2));
    expect((files.first as String), endsWith('KasKelasKu.pdf'));
    expect((files.last as String), endsWith('KasKelasKu.csv'));
    expect(File(files.first as String).existsSync(), true);
    expect(File(files.last as String).existsSync(), true);
    expect(find.text('Selesai.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Backup creation shares encrypted backup and clears password',
      (tester) async {
    await mount(tester, const SettingsScreen());
    final field = find.widgetWithText(
        TextField, 'Kata sandi cadangan minimal 12 karakter');
    await tester.ensureVisible(field);
    await tester.enterText(field, password);
    await tapAndWait(tester, find.text('Buat cadangan lokal'));
    expect(shares, hasLength(1));
    final path =
        ((shares.single.arguments as Map)['paths'] as List).single as String;
    expect(path, endsWith('.kkbackup'));
    expect((tester.widget<TextField>(field).controller!).text, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Import dialog cancellation, malformed file and authenticated restore',
      (tester) async {
    final backup =
        (await tester.runAsync(() => model.exports.backup(password)))!;
    await mount(tester, const SettingsScreen());
    await tester.tap(find.text('Buka laporan / pulihkan cadangan'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    await tapAndWait(tester, find.text('Pilih dan buka laporan'));
    expect(find.byType(ImportExportDialog), findsOneWidget);
    picked = backup.path;
    await tester.enterText(
        find.widgetWithText(TextField, 'Kata sandi berkas'), password);
    await tester.runAsync(
        () => tester.tap(find.text('Pilih cadangan untuk pemulihan')));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => tester.tap(find.text('Batal')));
    await tester.pumpAndSettle();
    expect(repo.restored, isNull);
    await tester.runAsync(
        () => tester.tap(find.text('Pilih cadangan untuk pemulihan')));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 300));
    await tapAndWait(tester, find.text('Pulihkan'));
    expect(repo.restored, isNotNull);
    expect(find.byType(ImportExportDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Opened report shared plaintext then temporary directory deleted',
      (tester) async {
    final report = (await tester
        .runAsync(() => model.exports.report('2026-10', password)))!;
    picked = report.csv.path;
    await mount(tester, const SettingsScreen());
    await tester.tap(find.text('Buka laporan / pulihkan cadangan'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Kata sandi berkas'), 'wrong-password');
    await tapAndWait(tester, find.text('Pilih dan buka laporan'));
    expect(shares, isEmpty);
    expect(find.byType(ImportExportDialog), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Kata sandi berkas'), password);
    await tapAndWait(tester, find.text('Pilih dan buka laporan'));
    expect(shares, hasLength(1));
    final path =
        ((shares.single.arguments as Map)['paths'] as List).single as String;
    expect(File(path).parent.existsSync(), false);
    expect(find.byType(ImportExportDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Automatic report selection opens without export password',
      (tester) async {
    await tester
        .runAsync(() => model.exports.automaticReports(DateTime(2026, 10)));
    await mount(tester, const SettingsScreen());
    await tester.runAsync(
        () => tester.tap(find.text('Buka laporan / pulihkan cadangan')));
    await tester.runAsync(() => tester.pump());
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    final dropdown = find.byType(DropdownButtonFormField<String>);
    expect(dropdown, findsOneWidget);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('.csv.kkreport').last);
    await tester.pumpAndSettle();
    await tapAndWait(tester, find.text('Pilih dan buka laporan'));
    expect(shares, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Backup errors and dark-mode storage errors remain visible',
      (tester) async {
    await mount(tester, const SettingsScreen());
    await tapAndWait(tester, find.text('Buat cadangan lokal'));
    expect(shares, isEmpty);
    expect(find.text('Kata sandi harus 12–128 karakter.'), findsOneWidget);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (_) async => throw PlatformException(code: 'storage_failure'));
    await tester.ensureVisible(find.byType(Switch));
    await tester.pump(const Duration(seconds: 5));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('Operasi gagal.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
