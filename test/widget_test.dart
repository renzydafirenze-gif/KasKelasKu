import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kaskelasku/main.dart';
import 'package:kaskelasku/models.dart';
import 'package:kaskelasku/view_model.dart';
import 'package:kaskelasku/data/repository.dart';
import 'package:kaskelasku/data/vault.dart';

class EntryRepository extends TreasuryRepository {
  EntryRepository() : super(Vault());
  final saved = <CashTransaction>[];
  @override
  Future<void> addTransaction(CashTransaction entry, String submissionId,
      {bool confirmDuplicate = false}) async {
    entry.validate();
    saved.add(entry);
  }
}

void main() {
  testWidgets('Valid entry submits fields and closes dialog', (tester) async {
    final repo = EntryRepository();
    final model = TreasuryViewModel(repo);
    await tester.pumpWidget(ProviderScope(
        overrides: [treasuryProvider.overrideWithValue(model)],
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => const TransactionEntry()),
                        child: const Text('Buka')))))));
    await tester.tap(find.text('Buka'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('amount_input')), '15000');
    await tester.enterText(find.widgetWithText(TextField, 'Kategori'), 'Iuran');
    await tester.enterText(
        find.byKey(const Key('description_input')), 'Kas pekan pertama');
    await tester.tap(find.byKey(const Key('submit_tx_btn')));
    await tester.pumpAndSettle();
    expect(repo.saved.single.amount, 15000);
    expect(repo.saved.single.category, 'Iuran');
    expect(repo.saved.single.description, 'Kas pekan pertama');
    expect(find.byType(TransactionEntry), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(model.dispose);
  });
  testWidgets('Entry remains usable with 200 percent text on small screen',
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
                child: Scaffold(body: TransactionEntry())))));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('submit_tx_btn')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Transaction entry rejects invalid amount without database write',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: TransactionEntry()))));
    await tester.enterText(find.byKey(const Key('amount_input')), '0');
    await tester.tap(find.byKey(const Key('submit_tx_btn')));
    await tester.pump();
    expect(find.text('Isian transaksi tidak valid.'), findsOneWidget);
    expect(find.byType(TransactionEntry), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('Student has no transaction creation action', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      sessionProvider.overrideWithValue(StateController<Member?>(
          const Member('student', 'Siswa', Role.siswa))),
    ], child: const MaterialApp(home: HomeScreen())));
    await tester.pump();
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
