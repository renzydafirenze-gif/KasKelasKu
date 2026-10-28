import '../models.dart';

/// Untrusted backup boundary, validated before touching a live database.
class Backup {
  Backup(Map<String, dynamic> source) {
    if (source['schema'] != 1) {
      throw const AppError('Versi cadangan tidak didukung.');
    }
    for (final table in columns.keys) {
      final raw = source[table];
      if (raw is! List || raw.length > 100000) {
        throw const AppError('Isi cadangan tidak valid atau terlalu besar.');
      }
      tables[table] = raw.map((value) {
        final keys = value is Map ? value.keys.toSet() : <Object?>{};
        if (value is! Map || !keys.containsAll(columns[table]!)) {
          throw const AppError('Kolom cadangan tidak valid.');
        }
        return Map<String, Object?>.from(value);
      }).toList();
    }
    final ids = <String>{};
    for (final row in tables['users']!) {
      final id = row['id'];
      if (id is! String ||
          id.isEmpty ||
          id.length > 100 ||
          !ids.add(id) ||
          row['name'] is! String ||
          (row['name']! as String).trim().isEmpty ||
          (row['name']! as String).length > 80 ||
          !Role.values.any((role) => role.name == row['role']) ||
          ![0, 1].contains(row['active'])) {
        throw const AppError('Anggota cadangan tidak valid.');
      }
    }
    for (final row in tables['transactions']!) {
      try {
        CashTransaction.fromMap(row).validate();
        if (!ids.contains(row['created_by']) ||
            row['id'] is! int ||
            (row['id']! as int) <= 0 ||
            row['submission_id'] is! String ||
            (row['submission_id']! as String).isEmpty ||
            (row['submission_id']! as String).length > 100 ||
            row['fingerprint'] is! String ||
            row['created_at'] is! String ||
            DateTime.tryParse(row['created_at']! as String) == null) {
          throw const FormatException();
        }
      } catch (_) {
        throw const AppError('Transaksi cadangan tidak valid.');
      }
    }
    for (final row in tables['monthly_reports']!) {
      if (row['period'] is! String) {
        throw const AppError('Periode cadangan tidak valid.');
      }
      validateMonth(row['period']! as String);
      if (row['verified_by'] != null && row['approved_by'] == null) {
        throw const AppError('Verifikasi tanpa persetujuan tidak valid.');
      }
      for (final prefix in ['approved', 'verified']) {
        final id = row['${prefix}_by'];
        final at = row['${prefix}_at'];
        if ((id == null) != (at == null) ||
            (id != null && !ids.contains(id)) ||
            (at != null && (at is! String || DateTime.tryParse(at) == null))) {
          throw const AppError('Persetujuan cadangan tidak valid.');
        }
      }
    }
    for (final row in tables['monthly_total_targets']!) {
      if (row['period'] is! String || row['amount'] is! int) {
        throw const AppError('Target cadangan tidak valid.');
      }
      validateMonth(row['period']! as String);
      if ((row['amount']! as int) < 0 ||
          (row['amount']! as int) > 1000000000000) {
        throw const AppError('Target cadangan tidak valid.');
      }
    }
    for (final row in tables['audit_log']!) {
      if (row['id'] is! int ||
          !ids.contains(row['actor']) ||
          row['action'] is! String ||
          row['target'] is! String ||
          row['at'] is! String ||
          DateTime.tryParse(row['at']! as String) == null) {
        throw const AppError('Audit cadangan tidak valid.');
      }
    }
  }

  static const columns = <String, Set<String>>{
    'users': {'id', 'name', 'role', 'active'},
    'transactions': {
      'id',
      'amount',
      'type',
      'category',
      'contributor_id',
      'tx_date',
      'description',
      'created_by',
      'created_at',
      'fingerprint',
      'submission_id'
    },
    'monthly_reports': {
      'period',
      'approved_by',
      'approved_at',
      'verified_by',
      'verified_at'
    },
    'monthly_total_targets': {'period', 'amount'},
    'audit_log': {'id', 'actor', 'action', 'target', 'at'},
  };
  final tables = <String, List<Map<String, Object?>>>{};
}
