import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kaskelasku/data/repository.dart';

Future<Database> openPlain(String path) => databaseFactoryFfi.openDatabase(path,
    options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          for (final sql in (await rootBundle.loadString('lib/data/schema.sql'))
              .split('-- @statement')) {
            await db.execute(sql);
          }
        }));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('10,000 entries: pagination and aggregates stay bounded', () async {
    final directory = await Directory.systemTemp.createTemp('kk-perf-');
    final repo = TreasuryRepository(
        pathOverride: '${directory.path}/perf.db', openForTesting: openPlain);
    try {
      final actor = await repo.createOwner('Benchmark');
      final db = await repo.database;
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (var i = 0; i < 10000; i++) {
          batch.insert('transactions', {
            'amount': 1000,
            'type': 'IN',
            'category': 'Iuran',
            'tx_date': '2026-10-01',
            'description': 'Kas $i',
            'created_by': actor.id,
            'created_at': '2026-10-01T00:00:00Z',
            'fingerprint': '$i',
            'submission_id': '$i'
          });
        }
        await batch.commit(noResult: true);
      });
      final watch = Stopwatch()..start();
      expect(await repo.history(limit: 100, offset: 9900), hasLength(100));
      expect((await repo.overview('2026-10')).balance, 10000000);
      watch.stop();
      expect(watch.elapsedMilliseconds, lessThan(1000));
    } finally {
      await repo.close();
      await directory.delete(recursive: true);
    }
  });
}
