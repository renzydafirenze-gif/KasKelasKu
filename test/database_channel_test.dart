import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaskelasku/data/repository.dart';
import 'package:kaskelasku/models.dart';
import 'repository_test.dart' show MemoryVault;
import 'secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final condition in ['ok', 'plaintext', 'corrupt', 'authentication']) {
    test('Database channel verifies SQLCipher and integrity: $condition',
        () async {
      mockSecureStorage();
      final directory =
          await Directory.systemTemp.createTemp('kk-native-channel-');
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('com.davidmartos96.sqflite_sqlcipher');
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        final args = call.arguments as Map? ?? {};
        switch (call.method) {
          case 'openDatabase':
            return {'id': 1};
          case 'query':
            final sql = (args['sql'] as String).toLowerCase();
            if (sql.contains('user_version'))
              return [
                {'user_version': 0}
              ];
            if (sql.contains('cipher_version'))
              return condition == 'plaintext'
                  ? []
                  : [
                      {'cipher_version': '4.5.3'}
                    ];
            if (sql.contains('cipher_integrity_check'))
              return condition == 'authentication'
                  ? [
                      {'error': 'invalid HMAC'}
                    ]
                  : [];
            if (sql.contains('integrity_check'))
              return [
                {'integrity_check': condition == 'corrupt' ? 'corrupt' : 'ok'}
              ];
            throw StateError('Unexpected query: $sql');
          case 'insert':
            return 1;
          case 'execute':
          case 'closeDatabase':
          case 'options':
            return null;
          default:
            throw StateError('Unexpected method: ${call.method}');
        }
      });
      final repo = TreasuryRepository(MemoryVault());
      try {
        if (condition == 'ok') {
          expect(
              (await repo.setup('Budi', 'Password-kelas-2026')).name, 'Budi');
          expect(repo.unlocked, true);
        } else {
          await expectLater(repo.setup('Budi', 'Password-kelas-2026'),
              throwsA(isA<AppError>()));
          expect(repo.unlocked, false);
          expect(calls, contains('closeDatabase'));
        }
      } finally {
        await repo.lock(forgetBiometric: true);
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(paths, null);
        await directory.delete(recursive: true);
      }
    });
  }
}
