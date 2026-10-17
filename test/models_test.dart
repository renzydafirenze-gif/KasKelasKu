import 'package:flutter_test/flutter_test.dart';
import 'package:kaskelasku/models.dart';
import 'package:kaskelasku/data/exports.dart';

void main() {
  CashTransaction entry(
          {int amount = 5000,
          String date = '2026-10-15',
          String description = 'Iuran'}) =>
      CashTransaction(
          amount: amount,
          type: 'IN',
          category: 'Kas',
          date: date,
          description: description);
  test('Rupiah whole-integer amount and calendar validation', () {
    entry().validate();
    expect(entry().signedAmount, 5000);
    expect(() => entry(amount: 0).validate(), throwsA(isA<AppError>()));
    expect(() => entry(amount: -1).validate(), throwsA(isA<AppError>()));
    expect(() => entry(amount: 1000000000001).validate(),
        throwsA(isA<AppError>()));
    expect(
        () => entry(date: '2026-02-30').validate(), throwsA(isA<AppError>()));
    expect(() => entry(description: ' ').validate(), throwsA(isA<AppError>()));
    expect(validDate('2024-02-29'), isTrue);
    expect(validDate('2025-02-29'), isFalse);
    expect(validDate('2026-1-01'), isFalse);
    expect(() => validateMonth('2026-13'), throwsA(isA<AppError>()));
    expect(monthOf(DateTime(2026, 10, 15)), '2026-10');
  });
  test('Fingerprint normalizes case and surrounding whitespace', () {
    expect(entry().fingerprint, entry(description: ' iuran ').fingerprint);
    expect(entry().fingerprint, isNot(entry(amount: 10000).fingerprint));
  });
  test('CSV cells cannot become spreadsheet formulas', () {
    for (final value in ['=SUM(A1)', '+1', '-1', '@SUM(A1)', '  =1']) {
      expect(Exports.safeCell(value), startsWith("'"));
    }
    expect(Exports.safeCell('Iuran'), 'Iuran');
  });
}
