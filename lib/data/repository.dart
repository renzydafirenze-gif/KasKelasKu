import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models.dart';
import 'backup.dart';

class TreasuryRepository {
  TreasuryRepository({this.pathOverride, this.openForTesting});
  final String? pathOverride;
  // Test transport only: host tests inject an in-memory/FFI database.
  final Future<Database> Function(String path)? openForTesting;
  Database? _db;
  Member? _actor;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  static final _random = Random.secure();

  static String newId() => base64Url
      .encode(List.generate(18, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  static Future<String> databasePath() async =>
      '${(await getApplicationSupportDirectory()).path}/kaskelasku.db';

  late final Future<Database> _database = _open();

  Future<Database> _open() async {
    final path = pathOverride ?? await databasePath();
    if (openForTesting != null) {
      return _db = await openForTesting!(path);
    }
    await _quarantineLegacy(path);
    return _db = await openDatabase(path, version: 1, onConfigure: (db) async {
      // busy_timeout dan journal_mode mengembalikan baris, jadi pakai rawQuery
      // agar tidak error di Android execSQL; foreign_keys tidak.
      await db.rawQuery('PRAGMA busy_timeout=5000');
      await db.rawQuery('PRAGMA journal_mode=WAL');
      await db.execute('PRAGMA foreign_keys=ON');
    }, onCreate: (db, _) async {
      final schema = await rootBundle.loadString('lib/data/schema.sql');
      for (final statement in schema.split('-- @statement')) {
        if (statement.trim().isNotEmpty) await db.execute(statement);
      }
    });
  }

  /// Database lama memakai SQLCipher. Berkas seperti itu tidak bisa dibuka
  /// tanpa kunci, jadi dipindahkan sekali agar aplikasi tetap bisa mulai.
  static Future<void> _quarantineLegacy(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final handle = await file.open();
    List<int> header;
    try {
      header = await handle.read(16);
    } finally {
      await handle.close();
    }
    if (String.fromCharCodes(header) == 'SQLite format 3\u0000') return;
    var target = '$path.legacy';
    if (await File(target).exists()) {
      target = '$path.legacy-${DateTime.now().millisecondsSinceEpoch}';
    }
    await file.rename(target);
  }

  /// Opens the database and selects the first active treasurer.
  /// Returns null when the database has no members yet.
  Future<Member?> open() async {
    final db = await _database;
    final rows = await db.query('users', where: 'active=1', orderBy: 'name');
    if (rows.isEmpty) return null;
    final owner = rows.firstWhere((row) => row['role'] == Role.bendahara.name,
        orElse: () => rows.first);
    _actor = Member.fromMap(owner);
    return _actor;
  }

  Future<Member> createOwner(String name) async {
    _validateName(name);
    final db = await _database;
    if ((await db.query('users', limit: 1)).isNotEmpty) {
      throw const AppError('Data sudah ada. Buka aplikasi kembali.');
    }
    final id = newId();
    await db.insert(
        'users', {'id': id, 'name': name.trim(), 'role': Role.bendahara.name});
    _actor = Member(id, name.trim(), Role.bendahara);
    _changes.add(null);
    return _actor!;
  }

  Future<Member> switchUser(String id) async {
    final db = await _database;
    final rows =
        await db.query('users', where: 'id=? AND active=1', whereArgs: [id]);
    if (rows.isEmpty) throw const AppError('Anggota tidak aktif.');
    _actor = Member.fromMap(rows.single);
    _changes.add(null);
    return _actor!;
  }

  Future<Member> _authorize(DatabaseExecutor executor,
      [Set<Role>? roles]) async {
    final actor = _actor;
    if (actor == null) {
      throw const AppError('Pilih pengguna terlebih dahulu.');
    }
    final rows = await executor
        .query('users', where: 'id=? AND active=1', whereArgs: [actor.id]);
    if (rows.isEmpty) {
      throw const AppError('Pengguna tidak aktif. Pilih pengguna lain.');
    }
    final member = Member.fromMap(rows.single);
    if (roles != null && !roles.contains(member.role)) {
      throw const AppError('Peran tidak memiliki izin.');
    }
    return member;
  }

  Future<Member> currentMember() async => _authorize(await _database);

  Future<Database> get database => _database;

  Future<void> close() async {
    _actor = null;
    await _db?.close();
    _db = null;
  }

  Future<T> _write<T>(
      Set<Role> roles, Future<T> Function(Transaction, Member) action) async {
    // DatabaseException branches mirror the triggers in schema.sql.
    // coverage:ignore-start
    try {
      final db = await _database;
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
    // coverage:ignore-end
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

  Future<Overview> overview(String period) async {
    validateMonth(period);
    final db = await _database;
    await _authorize(db);
    final totals = (await db.rawQuery('''SELECT
      COALESCE(SUM(CASE type WHEN 'IN' THEN amount ELSE -amount END),0) balance,
      COALESCE(SUM(CASE WHEN type='IN' AND substr(tx_date,1,7)=? THEN amount ELSE 0 END),0) income,
      COALESCE(SUM(CASE WHEN type='OUT' AND substr(tx_date,1,7)=? THEN amount ELSE 0 END),0) expense
      FROM transactions''', [period, period])).single;
    final targetRow = await db
        .query('monthly_total_targets', where: 'period=?', whereArgs: [period]);
    final trends = await db.rawQuery(
        "SELECT substr(tx_date,1,7) AS period, SUM(CASE type WHEN 'IN' THEN amount ELSE -amount END) AS net FROM transactions GROUP BY period ORDER BY period");
    final recent = await _historyRows(limit: 6);
    return Overview(
        balance: totals['balance']! as int,
        income: totals['income']! as int,
        expense: totals['expense']! as int,
        target: targetRow.isEmpty ? 0 : targetRow.single['amount']! as int,
        paid: totals['income']! as int,
        recent: recent,
        trends: trends);
  }

  Future<Map<String, Object?>> monthSnapshot(String period) async {
    validateMonth(period);
    final db = await _database;
    await _authorize(db);
    final opening = (await db.rawQuery(
            "SELECT COALESCE(SUM(CASE type WHEN 'IN' THEN amount ELSE -amount END),0) AS total FROM transactions WHERE tx_date<?",
            ['$period-01']))
        .single['total']! as int;
    final totals = (await db.rawQuery('''SELECT
      COALESCE(SUM(CASE WHEN type='IN' THEN amount ELSE 0 END),0) income,
      COALESCE(SUM(CASE WHEN type='OUT' THEN amount ELSE 0 END),0) expense
      FROM transactions WHERE substr(tx_date,1,7)=?''', [period])).single;
    final targetRow = await db
        .query('monthly_total_targets', where: 'period=?', whereArgs: [period]);
    final target = targetRow.isEmpty ? 0 : targetRow.single['amount']! as int;
    return {
      'opening': opening,
      'income': totals['income']!,
      'expense': totals['expense']!,
      'closing':
          opening + (totals['income']! as int) - (totals['expense']! as int),
      'target': target,
      'paid': totals['income']!
    };
  }

  Future<void> addTransaction(CashTransaction entry,
      {bool confirmDuplicate = false}) async {
    entry.validate();
    await _write({Role.bendahara}, (txn, actor) async {
      if (entry.contributorId != null) {
        final rows = await txn.query('users',
            columns: ['id'],
            where: 'id=? AND role=? AND active=1',
            whereArgs: [entry.contributorId, Role.siswa.name]);
        if (rows.isEmpty) {
          throw const AppError('Nama penyetor tidak valid.');
        }
      }
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
        'submission_id': newId()
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
    final db = await _database;
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
    return _historyRows(
        category: category,
        keyword: keyword,
        from: from,
        to: to,
        limit: limit,
        offset: offset);
  }

  Future<List<CashTransaction>> _historyRows(
      {String category = '',
      String keyword = '',
      String? from,
      String? to,
      int limit = 100,
      int offset = 0}) async {
    final db = await _database;
    final where = <String>[];
    final args = <Object?>[];
    if (category.isNotEmpty) {
      where.add('t.category=?');
      args.add(category);
    }
    if (keyword.isNotEmpty) {
      where.add(
          "(instr(lower(t.description),lower(?))>0 OR instr(lower(COALESCE(u.name,'')),lower(?))>0)");
      args.addAll([keyword, keyword]);
    }
    if (from != null) {
      where.add('t.tx_date>=?');
      args.add(from);
    }
    if (to != null) {
      where.add('t.tx_date<=?');
      args.add(to);
    }
    final rows = await db.rawQuery(
        'SELECT t.*, u.name AS contributor_name FROM transactions t LEFT JOIN users u ON u.id=t.contributor_id ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} ORDER BY t.tx_date DESC,t.id DESC LIMIT ? OFFSET ?',
        [...args, limit, offset]);
    return rows.map(CashTransaction.fromMap).toList();
  }

  Future<List<Member>> members() async {
    final db = await _database;
    await _authorize(db);
    return (await db.query('users', orderBy: 'name'))
        .map(Member.fromMap)
        .toList();
  }

  /// Murid aktif beserta total setoran bulan [period]; belum bayar lebih dulu.
  Future<List<StudentPayment>> studentPayments(String period) async {
    validateMonth(period);
    final db = await _database;
    await _authorize(db);
    final rows = await db.rawQuery('''SELECT u.id,u.name,u.role,u.active,
      COALESCE(SUM(t.amount),0) AS total, COUNT(t.id) AS entries
      FROM users u LEFT JOIN transactions t
        ON t.contributor_id=u.id AND t.type='IN' AND substr(t.tx_date,1,7)=?
      WHERE u.role=? AND u.active=1
      GROUP BY u.id ORDER BY entries=0 DESC, u.name''',
        [period, Role.siswa.name]);
    return rows
        .map((row) => StudentPayment(
            Member.fromMap(row), row['total']! as int, row['entries']! as int))
        .toList();
  }

  Future<void> setTotalMonthlyTarget(String period, int amount) async {
    validateMonth(period);
    if (amount < 0 || amount > 1000000000000) {
      throw const AppError('Target tidak valid.');
    }
    await _write({Role.bendahara}, (txn, actor) async {
      await txn.insert(
          'monthly_total_targets', {'period': period, 'amount': amount},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await _audit(txn, actor, 'target.total.set', '$period:$amount');
    });
  }

  static void _validateName(String name) {
    if (name.trim().isEmpty || name.length > 80) {
      throw const AppError('Nama harus 1–80 karakter.');
    }
  }

  Future<void> addMember(String name, Role role) async {
    _validateName(name);
    await _write({Role.bendahara}, (txn, actor) async {
      final id = newId();
      await txn
          .insert('users', {'id': id, 'name': name.trim(), 'role': role.name});
      await _audit(txn, actor, 'member.add', id);
    });
  }

  /// Tambah banyak murid sekaligus dari daftar nama.
  Future<int> addStudents(List<String> names) async {
    final clean = names.where((name) => name.trim().isNotEmpty).toList();
    if (clean.isEmpty) throw const AppError('Nama harus 1–80 karakter.');
    for (final name in clean) {
      _validateName(name);
    }
    return _write({Role.bendahara}, (txn, actor) async {
      for (final name in clean) {
        final id = newId();
        await txn.insert(
            'users', {'id': id, 'name': name.trim(), 'role': Role.siswa.name});
        await _audit(txn, actor, 'member.add', id);
      }
      return clean.length;
    });
  }

  Future<void> changeMember(Member target, Role role, bool active) =>
      _write({Role.bendahara}, (txn, actor) async {
        if (target.id == actor.id && (!active || role != Role.bendahara)) {
          throw const AppError('Tidak dapat mencabut akses pengelola sendiri.');
        }
        if (await txn.update(
                'users', {'role': role.name, 'active': active ? 1 : 0},
                where: 'id=?', whereArgs: [target.id]) !=
            1) {
          throw const AppError('Anggota tidak ditemukan.');
        }
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
    final db = await _database;
    return db.transaction((txn) async {
      await _authorize(txn);
      final rows = await txn.rawQuery(
          "SELECT t.*, u.name AS contributor_name FROM transactions t LEFT JOIN users u ON u.id=t.contributor_id WHERE substr(t.tx_date,1,7)=? ORDER BY t.tx_date,t.id",
          [period]);
      final status = await txn
          .query('monthly_reports', where: 'period=?', whereArgs: [period]);
      return {
        'period': period,
        'rows': rows,
        'status': status.isEmpty ? <String, Object?>{} : status.single
      };
    });
  }

  Future<Map<String, Object?>> backupSnapshot() async {
    final db = await _database;
    return db.transaction((txn) async {
      await _authorize(txn, {Role.bendahara});
      return {
        'schema': 1,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        for (final table in Backup.columns.keys) table: await txn.query(table)
      };
    });
  }

  Future<Member> restore(Backup backup) async {
    // Empty-ledger-only restore avoids replacing or merging existing data.
    final schema = await rootBundle.loadString('lib/data/schema.sql');
    await _write({Role.bendahara}, (txn, actor) async {
      for (final table in [
        'transactions',
        'monthly_reports',
        'monthly_total_targets',
        'audit_log'
      ]) {
        final count = await txn.rawQuery('SELECT COUNT(*) AS n FROM $table');
        if (count.single['n'] != 0) {
          throw const AppError(
              'Pemulihan hanya untuk data kosong. Data lama tidak ditimpa.');
        }
      }
      final members = await txn.query('users');
      if (members.length != 1 ||
          backup.tables['users']!.any((row) => row['id'] == actor.id)) {
        throw const AppError('Gunakan data baru tanpa anggota tambahan.');
      }
      await txn.delete('users');
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
          await txn.insert(table, Map<String, Object?>.from(original));
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
    });
    final owner = await open();
    if (owner == null) throw const AppError('Cadangan tidak berisi anggota.');
    return owner;
  }
}
