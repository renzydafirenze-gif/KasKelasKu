import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../models.dart';
import 'vault.dart';
import 'backup.dart';

class TreasuryRepository {
  TreasuryRepository(this.vault, {this.pathOverride, this.openForTesting});
  final Vault vault;
  final String? pathOverride;
  // Test transport only: host business tests use SQLite, device tests SQLCipher.
  final Future<Database> Function(String path, String key, bool create)?
      openForTesting;
  Database? _db;
  String? _key;
  String? _actor;
  Role? _sessionRole;
  String? _biometricId;
  String? _biometricKey;
  Role? _biometricRole;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  bool get unlocked => _db != null && _actor != null;
  Database get db {
    if (!unlocked) throw const AppError('Sesi terkunci.');
    return _db!;
  }

  static Future<String> databasePath() async =>
      '${(await getApplicationSupportDirectory()).path}/kaskelasku.db';

  Future<Database> _open(String key, {bool create = false}) async {
    final path = pathOverride ?? await databasePath();
    if (!create && !await File(path).exists()) {
      throw const AppError('Database tidak ditemukan. Pulihkan dari cadangan.');
    }
    if (openForTesting != null) return openForTesting!(path, key, create);
    final database = await openDatabase(path, password: key, version: 2,
        onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys=ON');
    }, // coverage:ignore-start
        onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) {
        await db.execute(
            'ALTER TABLE transactions ADD COLUMN contributor_id TEXT REFERENCES users(id)');
        await db.execute(
            'CREATE TABLE monthly_targets (period TEXT NOT NULL, member_id TEXT NOT NULL REFERENCES users(id), amount INTEGER NOT NULL, PRIMARY KEY(period, member_id))');
        await db.execute(
            'CREATE INDEX idx_tx_contributor_date ON transactions(contributor_id,tx_date)');
      }
    }, // coverage:ignore-end
        onCreate: (db, _) async {
      final schema = await rootBundle.loadString('lib/data/schema.sql');
      for (final statement in schema.split('-- @statement')) {
        if (statement.trim().isNotEmpty) await db.execute(statement);
      }
    });
    try {
      final cipher = await database.rawQuery('PRAGMA cipher_version');
      if (cipher.isEmpty) throw const AppError('SQLCipher tidak aktif.');
      final check = await database.rawQuery('PRAGMA integrity_check');
      final auth = await database.rawQuery('PRAGMA cipher_integrity_check');
      if (check.single.values.single != 'ok' || auth.isNotEmpty) {
        throw const AppError('Database rusak. Data asli tidak dihapus.');
      }
      return database;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  Future<Member> setup(String name, String password) async {
    Vault.validatePassword(password);
    _validateName(name);
    if ((await vault.accounts()).isNotEmpty ||
        await File(pathOverride ?? await databasePath()).exists()) {
      throw const AppError('Brankas sudah ada. Gunakan akun terdaftar.');
    }
    final id = Vault.token();
    final key = base64Encode(Vault.randomBytes(32));
    // Persist pending enrollment before database creation. Login resumes only
    // when the authenticated pending identity matches an empty database.
    await Vault.storage.write(key: 'setup:$id', value: name.trim());
    await vault.enroll(id, password, key);
    final database = await _open(key, create: true);
    await database
        .insert('users', {'id': id, 'name': name.trim(), 'role': 'bendahara'});
    await Vault.storage.delete(key: 'setup:$id');
    _db = database;
    _key = key;
    _actor = id;
    _sessionRole = Role.bendahara;
    _biometricId = id;
    _biometricKey = key;
    _biometricRole = Role.bendahara;
    return Member(id, name.trim(), Role.bendahara);
  }

  Future<Member> login(String id, String password, Role selectedRole) async {
    final waitUntil =
        int.tryParse(await Vault.storage.read(key: 'login:until:$id') ?? '0') ??
            0;
    if (DateTime.now().millisecondsSinceEpoch < waitUntil) {
      throw const AppError('Terlalu banyak percobaan. Tunggu 30 detik.');
    }
    String key;
    try {
      key = await vault.unlock(id, password);
    } catch (_) {
      final tries = (int.tryParse(
                  await Vault.storage.read(key: 'login:tries:$id') ?? '0') ??
              0) +
          1;
      await Vault.storage.write(key: 'login:tries:$id', value: '$tries');
      if (tries >= 5) {
        await Vault.storage.write(
            key: 'login:until:$id',
            value:
                '${DateTime.now().add(const Duration(seconds: 30)).millisecondsSinceEpoch}');
        await Vault.storage.write(key: 'login:tries:$id', value: '0');
      }
      rethrow;
    }
    await Vault.storage.delete(key: 'login:tries:$id');
    final pendingName = await Vault.storage.read(key: 'setup:$id');
    final database = await _open(key, create: pendingName != null);
    if (pendingName != null) {
      await database.transaction((txn) async {
        final members = await txn.query('users');
        if (members.isEmpty) {
          await txn.insert(
              'users', {'id': id, 'name': pendingName, 'role': 'bendahara'});
        }
      });
      await Vault.storage.delete(key: 'setup:$id');
    }
    final rows = await database
        .query('users', where: 'id=? AND active=1', whereArgs: [id]);
    if (rows.isEmpty || rows.single['role'] != selectedRole.name) {
      await database.close();
      throw const AppError('Akun tidak aktif atau peran tidak sesuai.');
    }
    _db = database;
    _key = key;
    _actor = id;
    _sessionRole = selectedRole;
    _biometricId = id;
    _biometricKey = key;
    _biometricRole = selectedRole;
    return Member.fromMap(rows.single);
  }

  bool get canResumeBiometric => _biometricId != null && _biometricKey != null;
  Future<Member> resumeBiometric() async {
    final id = _biometricId;
    final key = _biometricKey;
    if (id == null || key == null) {
      throw const AppError('Masuk dengan kata sandi terlebih dahulu.');
    }
    final auth = LocalAuthentication();
    if (!await auth.canCheckBiometrics ||
        !await auth.authenticate(
            localizedReason:
                'Buka kembali akun KasKelasKu yang terakhir terautentikasi',
            options: const AuthenticationOptions(
                biometricOnly: true, stickyAuth: true))) {
      throw const AppError('Biometrik gagal. Gunakan kata sandi akun.');
    }
    final database = await _open(key);
    final rows = await database
        .query('users', where: 'id=? AND active=1', whereArgs: [id]);
    if (rows.isEmpty || rows.single['role'] != _biometricRole?.name) {
      await database.close();
      _biometricId = null;
      _biometricKey = null;
      _biometricRole = null;
      throw const AppError('Akun atau peran berubah. Gunakan kata sandi.');
    }
    _db = database;
    _actor = id;
    _key = key;
    _sessionRole = Member.fromMap(rows.single).role;
    return Member.fromMap(rows.single);
  }

  Future<void> lock({bool forgetBiometric = false}) async {
    if (forgetBiometric) {
      _biometricId = null;
      _biometricKey = null;
      _biometricRole = null;
    }
    final database = _db;
    _actor = null;
    _sessionRole = null;
    _key = null;
    _db = null;
    await database?.close();
    _changes.add(null);
  }

  Future<Member> _authorize(DatabaseExecutor executor,
      [Set<Role>? roles]) async {
    if (_actor == null) throw const AppError('Sesi terkunci.');
    final rows = await executor
        .query('users', where: 'id=? AND active=1', whereArgs: [_actor]);
    if (rows.isEmpty) {
      _biometricId = null;
      _biometricKey = null;
      _biometricRole = null;
      throw const AppError('Akun dinonaktifkan. Masuk kembali.');
    }
    final member = Member.fromMap(rows.single);
    if (member.role != _sessionRole) {
      _biometricId = null;
      _biometricKey = null;
      _biometricRole = null;
      throw const AppError(
          'Peran berubah. Masuk kembali dengan peran terbaru.');
    }
    if (roles != null && !roles.contains(member.role)) {
      throw const AppError('Peran tidak memiliki izin.');
    }
    return member;
  }

  Future<Member> currentMember() => _authorize(db);

  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    Vault.validatePassword(newPassword);
    final actor = await currentMember();
    final currentKey = await vault.unlock(actor.id, currentPassword);
    if (currentKey != _key) {
      throw const AppError('Kredensial tidak sesuai dengan brankas.');
    }
    await currentMember();
    await vault.enroll(actor.id, newPassword, currentKey);
    _biometricId = null;
    _biometricKey = null;
    _biometricRole = null;
  }

  Future<String> automaticReportPassword() async {
    await _authorize(db);
    return _key!;
  }

  Future<void> restore(Backup backup) async {
    // Empty-vault-only restore avoids replacing or merging any existing ledger.
    // SQL DDL is transactional: failed import restores both data and triggers.
    final schema = await rootBundle.loadString('lib/data/schema.sql');
    await _write({Role.bendahara}, (txn, actor) async {
      for (final table in [
        'transactions',
        'monthly_reports',
        'monthly_targets',
        'audit_log'
      ]) {
        final count = await txn.rawQuery('SELECT COUNT(*) AS n FROM $table');
        if (count.single['n'] != 0) {
          throw const AppError(
              'Pemulihan hanya untuk brankas baru kosong. Data lama tidak ditimpa.');
        }
      }
      final members = await txn.query('users');
      if (members.length != 1 ||
          backup.tables['users']!.any((row) => row['id'] == actor.id)) {
        throw const AppError('Gunakan brankas baru tanpa anggota tambahan.');
      }
      final triggers = await txn
          .rawQuery("SELECT name FROM sqlite_master WHERE type='trigger'");
      for (final trigger in triggers) {
        final name = trigger['name']! as String;
        if (!RegExp(r'^[a-z_]+$').hasMatch(name)) {
          throw const AppError('Skema tidak valid.');
        }
        await txn.execute('DROP TRIGGER $name');
      }
      for (final table in Backup.columns.keys) {
        for (final original in backup.tables[table]!) {
          final row = Map<String, Object?>.from(original);
          // Credentials are never transferred. Re-enroll members explicitly.
          if (table == 'users') row['active'] = 0;
          await txn.insert(table, row);
        }
      }
      for (final statement in schema.split('-- @statement')) {
        if (statement.trim().startsWith('CREATE TRIGGER')) {
          await txn.execute(statement);
        }
      }
      if ((await txn.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
        throw const AppError('Relasi cadangan rusak. Pemulihan dibatalkan.');
      }
      await _audit(txn, actor, 'backup.restore', 'schema:1');
    });
  }

  Future<List<String>> completedMonths(DateTime now) async {
    await _authorize(db);
    final first =
        await db.rawQuery('SELECT MIN(tx_date) AS first FROM transactions');
    final date = first.single['first'] as String?;
    if (date == null) return [];
    final start = DateTime.parse(date);
    var cursor = DateTime(start.year, start.month);
    final end = DateTime(now.year, now.month);
    final periods = <String>[];
    while (cursor.isBefore(end)) {
      periods.add(monthOf(cursor));
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return periods;
  }

  Future<T> _write<T>(
      Set<Role> roles, Future<T> Function(Transaction, Member) action) async {
    try {
      final result = await db.transaction((txn) async {
        final actor = await _authorize(txn, roles);
        return action(txn, actor);
      });
      _changes.add(null);
      return result;
    } on DatabaseException catch (error) {
      if (error.toString().contains('ERR_PERIOD_LOCKED')) {
        throw const AppError('Bulan sudah dikunci Ketua.');
      }
      if (error.toString().contains('SQLITE_FULL') ||
          error.toString().contains('database or disk is full')) {
        throw const AppError(
            'Penyimpanan penuh. Transaksi dibatalkan, data lama tetap utuh.');
      }
      rethrow;
    }
  }

  Future<void> _audit(
      Transaction txn, Member actor, String action, String target) async {
    await txn.insert('audit_log', {
      'actor': actor.id,
      'action': action,
      'target': target,
      'at': DateTime.now().toUtc().toIso8601String()
    });
  }

  Future<void> addTransaction(CashTransaction entry, String submissionId,
      {bool confirmDuplicate = false}) async {
    entry.validate();
    if (submissionId.isEmpty || submissionId.length > 100) {
      throw const AppError('ID pengiriman tidak valid.');
    }
    await _write({Role.bendahara}, (txn, actor) async {
      if ((await txn.query('transactions',
              columns: ['id'],
              where: 'submission_id=?',
              whereArgs: [submissionId]))
          .isNotEmpty) return;
      if (!confirmDuplicate &&
          (await txn.query('transactions',
                  columns: ['id'],
                  where: 'fingerprint=?',
                  whereArgs: [entry.fingerprint],
                  limit: 1))
              .isNotEmpty) {
        throw const DuplicateTransaction();
      }
      final id = await txn.insert('transactions', {
        'amount': entry.amount,
        'type': entry.type,
        'category': entry.category.trim(),
        'contributor_id': entry.contributorId,
        'tx_date': entry.date,
        'description': entry.description.trim(),
        'created_by': actor.id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'fingerprint': entry.fingerprint,
        'submission_id': submissionId
      });
      await _audit(txn, actor, 'transaction.add', '$id');
    });
  }

  Future<void> deleteTransaction(int id) =>
      _write({Role.bendahara}, (txn, actor) async {
        if (await txn.delete('transactions', where: 'id=?', whereArgs: [id]) !=
            1) {
          throw const AppError('Transaksi tidak ditemukan.');
        }
        await _audit(txn, actor, 'transaction.delete', '$id');
      });

  Future<List<CashTransaction>> history(
      {String category = '',
      String keyword = '',
      String? from,
      String? to,
      int limit = 100,
      int offset = 0}) async {
    await _authorize(db);
    if (limit < 1 ||
        limit > 500 ||
        offset < 0 ||
        keyword.length > 100 ||
        (from != null && !validDate(from)) ||
        (to != null && !validDate(to)) ||
        (from != null && to != null && from.compareTo(to) > 0)) {
      throw const AppError('Filter tidak valid.');
    }
    final where = <String>[];
    final args = <Object?>[];
    if (category.isNotEmpty) {
      where.add('category=?');
      args.add(category);
    }
    if (keyword.isNotEmpty) {
      where.add('instr(lower(description),lower(?))>0');
      args.add(keyword);
    }
    if (from != null) {
      where.add('tx_date>=?');
      args.add(from);
    }
    if (to != null) {
      where.add('tx_date<=?');
      args.add(to);
    }
    final rows = await db.query('transactions',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
        orderBy: 'tx_date DESC,id DESC',
        limit: limit,
        offset: offset);
    return rows.map(CashTransaction.fromMap).toList();
  }

  Future<int> balance() async {
    await _authorize(db);
    final rows = await db.rawQuery(
        "SELECT COALESCE(SUM(CASE type WHEN 'IN' THEN amount ELSE -amount END),0) AS balance FROM transactions");
    return rows.single['balance']! as int;
  }

  Future<List<Map<String, Object?>>> trends() async {
    await _authorize(db);
    return db.rawQuery(
        "SELECT substr(tx_date,1,7) AS period, SUM(CASE type WHEN 'IN' THEN amount ELSE -amount END) AS net FROM transactions GROUP BY period ORDER BY period");
  }

  Future<List<Member>> members() async {
    await _authorize(db);
    return (await db.query('users', orderBy: 'name'))
        .map(Member.fromMap)
        .toList();
  }

  Future<void> setMonthlyTarget(
      String period, String memberId, int amount) async {
    validateMonth(period);
    if (amount < 0 || amount > 1000000000000)
      throw const AppError('Target tidak valid.');
    await _write({Role.bendahara}, (txn, actor) async {
      await txn.insert('monthly_targets',
          {'period': period, 'member_id': memberId, 'amount': amount},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await _audit(txn, actor, 'target.set', '$period:$memberId');
    });
  }

  Future<List<Map<String, Object?>>> monthlyTargetStatus(String period) async {
    validateMonth(period);
    await _authorize(db);
    return db.rawQuery('''SELECT u.id, u.name, COALESCE(t.amount, 0) target,
      COALESCE(SUM(CASE WHEN x.type='IN' THEN x.amount ELSE 0 END),0) paid
      FROM users u LEFT JOIN monthly_targets t ON t.member_id=u.id AND t.period=?
      LEFT JOIN transactions x ON x.contributor_id=u.id AND substr(x.tx_date,1,7)=?
      WHERE u.role='siswa' AND u.active=1 GROUP BY u.id,u.name,t.amount ORDER BY u.name''',
        [period, period]);
  }

  static void _validateName(String name) {
    if (name.trim().isEmpty || name.length > 80) {
      throw const AppError('Nama harus 1–80 karakter.');
    }
  }

  Future<void> addMember(String name, Role role, String password) async {
    _validateName(name);
    Vault.validatePassword(password);
    final actor = await _authorize(db, {Role.bendahara});
    final id = Vault.token();
    await vault.enroll(id, password, _key!);
    try {
      await _write({Role.bendahara}, (txn, live) async {
        if (live.id != actor.id) throw const AppError('Sesi berubah.');
        await txn.insert(
            'users', {'id': id, 'name': name.trim(), 'role': role.name});
        await _audit(txn, live, 'member.add', id);
      });
    } catch (_) {
      await Vault.storage.delete(key: 'account:$id');
      rethrow;
    }
  }

  Future<void> changeMember(Member target, Role role, bool active) =>
      _write({Role.bendahara}, (txn, actor) async {
        if (target.id == actor.id && (!active || role != Role.bendahara)) {
          throw const AppError('Tidak dapat mencabut akses pengelola sendiri.');
        }
        if (await txn.update(
                'users', {'role': role.name, 'active': active ? 1 : 0},
                where: 'id=?', whereArgs: [target.id]) !=
            1) throw const AppError('Anggota tidak ditemukan.');
        await _audit(txn, actor, 'member.change', target.id);
      });

  Future<void> approve(String period) {
    validateMonth(period);
    return _write({Role.ketua}, (txn, actor) async {
      await txn.rawInsert(
          'INSERT OR IGNORE INTO monthly_reports(period) VALUES(?)', [period]);
      final changed = await txn.update(
          'monthly_reports',
          {
            'approved_by': actor.id,
            'approved_at': DateTime.now().toUtc().toIso8601String()
          },
          where: 'period=? AND approved_by IS NULL',
          whereArgs: [period]);
      if (changed != 1) throw const AppError('Laporan sudah dikunci.');
      await _audit(txn, actor, 'report.approve', period);
    });
  }

  Future<void> verify(String period) {
    validateMonth(period);
    return _write({Role.guruWali}, (txn, actor) async {
      final changed = await txn.update(
          'monthly_reports',
          {
            'verified_by': actor.id,
            'verified_at': DateTime.now().toUtc().toIso8601String()
          },
          where: 'period=? AND approved_by IS NOT NULL AND verified_by IS NULL',
          whereArgs: [period]);
      if (changed != 1) {
        throw const AppError('Laporan belum dikunci atau sudah diverifikasi.');
      }
      await _audit(txn, actor, 'report.verify', period);
    });
  }

  Future<Map<String, Object?>> reportSnapshot(String period) async {
    validateMonth(period);
    return db.transaction((txn) async {
      await _authorize(txn);
      final rows = await txn.query('transactions',
          where: 'substr(tx_date,1,7)=?',
          whereArgs: [period],
          orderBy: 'tx_date,id');
      final previous = await txn.rawQuery(
          "SELECT COALESCE(SUM(CASE type WHEN 'IN' THEN amount ELSE -amount END),0) AS total FROM transactions WHERE tx_date<?",
          ['$period-01']);
      final status = await txn
          .query('monthly_reports', where: 'period=?', whereArgs: [period]);
      return {
        'period': period,
        'opening': previous.single['total'],
        'rows': rows,
        'status': status.isEmpty ? <String, Object?>{} : status.single
      };
    });
  }

  Future<Map<String, Object?>> backupSnapshot() async =>
      db.transaction((txn) async {
        await _authorize(txn, {Role.bendahara});
        return {
          'schema': 1,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          for (final table in [
            'users',
            'transactions',
            'monthly_reports',
            'audit_log'
          ])
            table: await txn.query(table)
        };
      });
}
