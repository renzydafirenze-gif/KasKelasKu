import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kaskelasku/main.dart';
import 'package:kaskelasku/models.dart';
import 'package:kaskelasku/view_model.dart';
import 'fakes.dart';

Future<TreasuryViewModel> openEntry(
    WidgetTester tester, FakeRepository repo) async {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final model = TreasuryViewModel(repo);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(model.dispose);
  });
  await tester.pumpWidget(ProviderScope(
      overrides: [
        treasuryProvider.overrideWithValue(model),
        sessionProvider
            .overrideWithValue(StateController<Member?>(repo.active)),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => Center(
                      child: FilledButton(
                          onPressed: () => openTransactionEntry(context),
                          child: const Text('Buka'))))))));
  await tester.tap(find.text('Buka'));
  await tester.pumpAndSettle();
  return model;
}

void main() {
  testWidgets('Entry saves amount, contributor and optional description',
      (tester) async {
    final repo = FakeRepository();
    await openEntry(tester, repo);
    await tester.tap(find.text('+Rp 5.000'));
    await tester.pump();
    await tester.tap(find.text('+Rp 10.000'));
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('amount_input')))
            .controller!
            .text,
        '15000');
    await tester.tap(find.widgetWithText(ActionChip, 'Iuran'));
    await tester.tap(find.text('Siti'));
    await tester.enterText(
        find.byKey(const Key('description_input')), 'Kas pekan pertama');
    await tester.tap(find.byKey(const Key('submit_tx_btn')));
    await tester.pumpAndSettle();
    expect(repo.calls.single,
        'transaction:IN:15000:Iuran:Kas pekan pertama:two:false');
    expect(find.byType(TransactionEntry), findsNothing);
  });

  testWidgets('Entry defaults the description to the category', (tester) async {
    final repo = FakeRepository();
    await openEntry(tester, repo);
    await tester.enterText(find.byKey(const Key('amount_input')), '7000');
    await tester.tap(find.widgetWithText(ActionChip, 'Kas'));
    await tester.tap(find.byKey(const Key('submit_tx_btn')));
    await tester.pumpAndSettle();
    expect(repo.calls.single, 'transaction:IN:7000:Kas:Kas:null:false');
  });

  testWidgets('Entry rejects empty category and invalid amount',
      (tester) async {
    final repo = FakeRepository();
    await openEntry(tester, repo);
    await tester.enterText(find.byKey(const Key('amount_input')), '5000');
    await tester.tap(find.byKey(const Key('submit_tx_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Isi kategori.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Kas'));
    await tester.enterText(find.byKey(const Key('amount_input')), '0');
    await tester.tap(find.byKey(const Key('submit_tx_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Isian transaksi tidak valid.'), findsOneWidget);
    expect(find.byType(TransactionEntry), findsOneWidget);
  });

  testWidgets('Expense type hides and clears the contributor selector',
      (tester) async {
    final repo = FakeRepository();
    await openEntry(tester, repo);
    expect(find.text('Penyetor'), findsOneWidget);
    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();
    expect(find.text('Penyetor'), findsNothing);
    await tester.enterText(find.byKey(const Key('amount_input')), '4000');
    await tester.tap(find.widgetWithText(ActionChip, 'Lainnya'));
    await tester.tap(find.byKey(const Key('submit_tx_btn')));
    await tester.pumpAndSettle();
    expect(
        repo.calls.single, 'transaction:OUT:4000:Lainnya:Lainnya:null:false');
  });

  testWidgets('Duplicate entry asks for confirmation', (tester) async {
    final repo = FakeRepository()..duplicate = true;
    await openEntry(tester, repo);
    await tester.enterText(find.byKey(const Key('amount_input')), '5000');
    await tester.tap(find.widgetWithText(ActionChip, 'Kas'));
    await tester.tap(find.byKey(const Key('submit_tx_btn')));
    await tester.pumpAndSettle();
    expect(find.text('Transaksi serupa ditemukan'), findsOneWidget);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
    await tester.tap(find.byKey(const Key('submit_tx_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tetap simpan'));
    await tester.pumpAndSettle();
    expect(repo.calls.single, endsWith(':true'));
    expect(find.byType(TransactionEntry), findsNothing);
  });

  testWidgets('Entry stays usable with large text on a small screen',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
            home: MediaQuery(
                data: MediaQueryData(
                    size: Size(360, 800), textScaler: TextScaler.linear(2)),
                child: Scaffold(
                    body: SizedBox(height: 800, child: TransactionEntry()))))));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('submit_tx_btn')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Trend painter handles empty, single and changed points',
      (tester) async {
    final painter = TrendPainter([], Colors.blue);
    expect(painter.shouldRepaint(TrendPainter([1], Colors.red)), true);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: CustomPaint(
                    painter: TrendPainter([1], Colors.blue),
                    child: const SizedBox(width: 100, height: 100))))));
    expect(tester.takeException(), isNull);
  });
}
