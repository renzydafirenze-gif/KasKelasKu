import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kaskelasku/data/vault.dart';
import 'package:kaskelasku/models.dart';
import 'secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Stored credentials list, unlock, rotate and reject missing accounts',
      () async {
    mockSecureStorage();
    final vault = Vault();
    const password = 'KelasSepuluh-2026!';
    expect(await vault.accounts(), isEmpty);
    await Vault.storage.write(key: 'setting:dark', value: 'true');
    await vault.enroll('z', password, 'database-key');
    await vault.enroll('a', password, 'other-key');
    expect(await vault.accounts(), ['a', 'z']);
    expect(await vault.unlock('z', password), 'database-key');
    await expectLater(
        vault.unlock('missing', password), throwsA(isA<AppError>()));
    await expectLater(
        vault.unlock('z', 'wrong-password'), throwsA(isA<AppError>()));
    await vault.enroll('z', 'New-password-2026!', 'database-key');
    await expectLater(vault.unlock('z', password), throwsA(isA<AppError>()));
    expect(await vault.unlock('z', 'New-password-2026!'), 'database-key');
    expect(const AppError('pesan').toString(), 'pesan');
    expect(
        const DuplicateTransaction().toString(), contains('Transaksi serupa'));
  }, timeout: const Timeout(Duration(minutes: 3)));
  test('AES-GCM roundtrip, tampering, password and context rejection',
      () async {
    const password = 'KelasSepuluh-2026!';
    const context = 'KasKelasKu/backup/v1';
    final bytes = utf8.encode('data kas sensitif');
    final sealed = await Vault.seal(bytes, password, context);
    expect(await Vault.unseal(sealed, password, context), bytes);
    expect(Vault.unseal(sealed, 'wrong-password', context),
        throwsA(isA<AppError>()));
    expect(Vault.unseal(sealed, password, 'different-context'),
        throwsA(isA<AppError>()));
    final damaged = jsonDecode(sealed) as Map<String, dynamic>;
    damaged['tag'] = base64Encode(List.filled(16, 0));
    expect(Vault.unseal(jsonEncode(damaged), password, context),
        throwsA(isA<AppError>()));
    expect(() => Vault.validatePassword('1234'), returnsNormally);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
