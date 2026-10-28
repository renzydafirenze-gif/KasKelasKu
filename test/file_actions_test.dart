import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kaskelasku/main.dart';
import 'package:kaskelasku/models.dart';
import 'package:kaskelasku/view_model.dart';
import 'fakes.dart';

void main() {
  late Directory directory;
  late FakeRepository repo;
  late TreasuryViewModel model;
  String? picked;
  final shares = <MethodCall>[];
  const picker = MethodChannel(
      'miguelruivo.flutter.plugins.filepicker', JSONMethodCodec());
  const share = MethodChannel('dev.fluttercommunity.plus/share');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  late TestDefaultBinaryMessenger messenger;

  setUp(() async {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    directory = await Directory.systemTemp.createTemp('kk-file-ui-');
    repo = FakeRepository();
    model = TreasuryViewModel(repo);
    picked = null;
    shares.clear();
    FilePickerIO.registerWith();
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
    for (final channel in [paths, picker, share]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      treasuryProvider.overrideWithValue(model),
      sessionProvider.overrideWithValue(StateController<Member?>(repo.active)),
    ], child: MaterialApp(home: Scaffold(body: screen))));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
  }

  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(430, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 400; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump();
      if (done()) {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 50));
        }
        return;
      }
    }
    fail('File action did not finish.');
  }

  testWidgets('Reports share plain PDF and CSV files', (tester) async {
    tallView(tester);
    await mount(tester, const ReportsScreen());
    await tester.ensureVisible(find.byKey(const Key('share_pdf_btn')));
    await tester.tap(find.byKey(const Key('share_pdf_btn')));
    await waitFor(tester, () => shares.isNotEmpty);
    final pdf =
        ((shares.single.arguments as Map)['paths'] as List).single as String;
    expect(pdf, endsWith('.pdf'));
    expect(File(pdf).existsSync(), true);
    await tester.pumpAndSettle();
    expect(find.text('Selesai.'), findsOneWidget);

    shares.clear();
    await tester.ensureVisible(find.byKey(const Key('share_csv_btn')));
    await tester.tap(find.byKey(const Key('share_csv_btn')));
    await waitFor(tester, () => shares.isNotEmpty);
    final csv =
        ((shares.single.arguments as Map)['paths'] as List).single as String;
    expect(csv, endsWith('.csv'));
    expect(File(csv).existsSync(), true);
  });

  testWidgets('Settings shares a plain JSON backup and reports failures',
      (tester) async {
    tallView(tester);
    await mount(tester, const SettingsScreen());
    await tester.tap(find.text('Cadangkan data'));
    await waitFor(tester, () => shares.isNotEmpty);
    await waitFor(
        tester, () => find.byType(LinearProgressIndicator).evaluate().isEmpty);
    final path =
        ((shares.single.arguments as Map)['paths'] as List).single as String;
    expect(path, endsWith('.json'));
    expect(File(path).existsSync(), true);

    shares.clear();
    repo.fail = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cadangkan data'));
    await waitFor(
        tester, () => find.text('Operasi ditolak.').evaluate().isNotEmpty);
    expect(shares, isEmpty);
    expect(find.text('Operasi ditolak.'), findsOneWidget);
  });

  testWidgets('Restore reads a backup after confirmation', (tester) async {
    final backup = (await tester.runAsync(() => model.exports.backup()))!;
    picked = backup.path;
    tallView(tester);
    await mount(tester, const SettingsScreen());
    await tester.tap(find.text('Pulihkan cadangan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);

    await tester.tap(find.text('Pulihkan cadangan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pulihkan'));
    await waitFor(tester, () => repo.calls.isNotEmpty);
    await waitFor(
        tester, () => find.byType(LinearProgressIndicator).evaluate().isEmpty);
    expect(repo.calls, ['restore:1']);
    expect(find.text('Cadangan dipulihkan.'), findsOneWidget);
  });

  testWidgets('Restore surfaces malformed backup files', (tester) async {
    final file = File('${directory.path}/bad.json');
    file.writeAsStringSync('not-json');
    picked = file.path;
    tallView(tester);
    await mount(tester, const SettingsScreen());
    await tester.tap(find.text('Pulihkan cadangan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pulihkan'));
    await waitFor(tester,
        () => find.textContaining('Operasi gagal').evaluate().isNotEmpty);
    expect(repo.calls, isEmpty);
  });
}
