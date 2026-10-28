import 'package:flutter_test/flutter_test.dart';
import 'package:kaskelasku/data/backup.dart';
import 'package:kaskelasku/models.dart';

void main() {
  Map<String, dynamic> empty() => {
        'schema': 1,
        'users': <Object?>[],
        'transactions': <Object?>[],
        'monthly_reports': <Object?>[],
        'monthly_total_targets': <Object?>[],
        'audit_log': <Object?>[]
      };
  Map<String, Object?> user([String id = 'one']) =>
      {'id': id, 'name': 'Siswa', 'role': 'siswa', 'active': 1};
  Map<String, Object?> tx([String actor = 'one']) => {
        'id': 1,
        'amount': 5000,
        'type': 'IN',
        'category': 'Kas',
        'contributor_id': null,
        'tx_date': '2026-10-15',
        'description': 'Iuran',
        'created_by': actor,
        'created_at': '2026-10-15T00:00:00Z',
        'fingerprint': 'hash',
        'submission_id': 'sub'
      };

  test('Backup validates table shapes and required columns', () {
    expect(Backup(empty()).tables['users'], isEmpty);
    for (final source in [
      <String, dynamic>{},
      {...empty(), 'schema': 2},
      {...empty(), 'users': 'bad'},
      {
        ...empty(),
        'users': [1]
      },
      {
        ...empty(),
        'transactions': [tx()..remove('amount')]
      },
      {
        ...empty(),
        'monthly_total_targets': [
          {'period': '2026-10'}
        ]
      },
    ]) {
      expect(() => Backup(source), throwsA(isA<AppError>()));
    }
  });

  test('Backup rejects duplicate identities, unknown roles and invalid periods',
      () {
    for (final broken in [
      [user(), user()],
      [user()..['role'] = 'tidakAda'],
      [user()..['name'] = '  '],
      [user()..['active'] = 3],
      [user()..['id'] = ''],
    ]) {
      expect(() => Backup({...empty(), 'users': broken}),
          throwsA(isA<AppError>()));
    }
    expect(
        () => Backup({
              ...empty(),
              'users': [user()],
              'monthly_reports': [
                {'period': '2026-13'}
              ]
            }),
        throwsA(isA<AppError>()));
    expect(
        () => Backup({
              ...empty(),
              'users': [user()],
              'monthly_reports': [
                {
                  'period': '2026-10',
                  'approved_by': null,
                  'approved_at': null,
                  'verified_by': 'one',
                  'verified_at': 'now'
                }
              ]
            }),
        throwsA(isA<AppError>()));
    expect(
        () => Backup({
              ...empty(),
              'users': [user()],
              'monthly_reports': [
                {
                  'period': '2026-10',
                  'approved_by': 'one',
                  'approved_at': null,
                  'verified_by': null,
                  'verified_at': null
                }
              ]
            }),
        throwsA(isA<AppError>()));
    expect(
        () => Backup({
              ...empty(),
              'users': [user()],
              'monthly_total_targets': [
                {'period': '2026-10', 'amount': -1}
              ]
            }),
        throwsA(isA<AppError>()));
  });

  test('Backup rejects invalid transactions, approvals and audit rows', () {
    for (final broken in [
      {
        ...empty(),
        'users': [user()],
        'transactions': [tx('missing')]
      },
      {
        ...empty(),
        'users': [user()],
        'transactions': [tx()..['amount'] = 0]
      },
      {
        ...empty(),
        'users': [user()],
        'transactions': [tx()..['id'] = 'x']
      },
      {
        ...empty(),
        'users': [user()],
        'transactions': [tx()..['submission_id'] = '']
      },
      {
        ...empty(),
        'users': [user()],
        'transactions': [tx()..['created_at'] = 'bad']
      },
      {
        ...empty(),
        'users': [user()],
        'audit_log': [
          {
            'id': 1,
            'actor': 'missing',
            'action': 'x',
            'target': 'y',
            'at': 'bad'
          }
        ]
      },
    ]) {
      expect(() => Backup(broken), throwsA(isA<AppError>()));
    }
    expect(
        Backup({
          ...empty(),
          'users': [user()],
          'transactions': [tx()]
        }).tables['transactions'],
        hasLength(1));
  });
}
