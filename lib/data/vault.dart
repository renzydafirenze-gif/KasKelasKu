import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models.dart';

class Vault {
  static const storage = FlutterSecureStorage();
  static final cipher = AesGcm.with256bits();
  static const iterations = 600000;
  static final random = Random.secure();
  static List<int> randomBytes(int count) =>
      List.generate(count, (_) => random.nextInt(256));
  static String token() => base64UrlEncode(randomBytes(24));
  static void validatePassword(String password) {
    if (password.length < 12 || password.length > 128) {
      throw const AppError('Kata sandi harus 12–128 karakter.');
    }
  }

  static Future<SecretKey> derive(String password, List<int> salt) => Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  static Future<String> seal(
      List<int> bytes, String password, String context) async {
    validatePassword(password);
    final salt = randomBytes(32);
    final box = await cipher.encrypt(bytes,
        secretKey: await derive(password, salt), aad: utf8.encode(context));
    return jsonEncode({
      'v': 1,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes)
    });
  }

  static Future<List<int>> unseal(
      String envelope, String password, String context) async {
    try {
      validatePassword(password);
      if (envelope.length > 64 * 1024 * 1024) throw const FormatException();
      final data = jsonDecode(envelope) as Map<String, dynamic>;
      if (data['v'] != 1 ||
          data['iterations'] != iterations ||
          data['kdf'] != 'PBKDF2-HMAC-SHA256') throw const FormatException();
      final salt = base64Decode(data['salt'] as String);
      final nonce = base64Decode(data['nonce'] as String);
      final tag = base64Decode(data['tag'] as String);
      if (salt.length != 32 || nonce.length != 12 || tag.length != 16) {
        throw const FormatException();
      }
      return await cipher.decrypt(
          SecretBox(base64Decode(data['ciphertext'] as String),
              nonce: nonce, mac: Mac(tag)),
          secretKey: await derive(password, salt),
          aad: utf8.encode(context));
    } catch (_) {
      throw const AppError('Kata sandi salah atau data terenkripsi rusak.');
    }
  }

  Future<List<String>> accounts() async {
    final entries = await storage.readAll();
    return entries.keys
        .where((k) => k.startsWith('account:'))
        .map((k) => k.substring(8))
        .toList()
      ..sort();
  }

  Future<void> enroll(String id, String password, String databaseKey) async {
    await storage.write(
        key: 'account:$id',
        value: await seal(
            utf8.encode(databaseKey), password, 'KasKelasKu/account/$id'));
  }

  Future<String> unlock(String id, String password) async {
    final envelope = await storage.read(key: 'account:$id');
    if (envelope == null) throw const AppError('Akun tidak ditemukan.');
    return utf8
        .decode(await unseal(envelope, password, 'KasKelasKu/account/$id'));
  }
}
