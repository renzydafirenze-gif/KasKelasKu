import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kaskelasku/data/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('Legacy encrypted database is quarantined and a fresh one is created',
      () async {
    databaseFactory = databaseFactoryFfi;
    final directory = await Directory.systemTemp.createTemp('kk-legacy-');
    final path = '${directory.path}/legacy.db';
    try {
      await File(path).writeAsBytes(List.filled(64, 7));
      final repo = TreasuryRepository(pathOverride: path);
      try {
        expect(await repo.open(), isNull);
        expect(await File('$path.legacy').exists(), true);
        expect((await repo.createOwner('Budi')).name, 'Budi');
      } finally {
        await repo.close();
      }
      final again = TreasuryRepository(pathOverride: path);
      try {
        expect((await again.open())!.name, 'Budi');
      } finally {
        await again.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
