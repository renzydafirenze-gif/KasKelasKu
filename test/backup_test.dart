import 'package:flutter_test/flutter_test.dart';
import 'package:kaskelasku/data/backup.dart';
import 'package:kaskelasku/models.dart';

void main() {
  Map<String, dynamic> empty() => {
        'schema': 1,
        'users': <Object?>[],
        'transactions': <Object?>[],
        'monthly_reports': <Object?>[],
        'audit_log': <Object?>[],
        'monthly_targets': <Object?>[],
        'monthly_total_targets': <Object?>[]
      };
  test('Backup validates table shapes and schema', () {
    expect(Backup(empty()).tables['users'], isEmpty);
    for (final source in [
      <String, dynamic>{},
      {...empty(), 'schema': 2},
      {...empty(), 'users': 'bad'},
      {
        ...empty(),
        'users': [
          {'id': 'incomplete'}
        ]
      },
      {
        ...empty(),
        'users': [1]
      }
    ]) {
      expect(() => Backup(source), throwsA(isA<AppError>()));
    }
  });
  test('Backup rejects duplicate identities, unknown roles and invalid periods',
      () {
    final user = {'id': 'one', 'name': 'Siswa', 'role': 'siswa', 'active': 1};
    expect(
        () => Backup({
              ...empty(),
              'users': [user, user]
            }),
        throwsA(isA<AppError>()));
    expect(
        () => Backup({
              ...empty(),
              'users': [
                {...user, 'role': 'admin'}
              ]
            }),
        throwsA(isA<AppError>()));
    expect(
        () => Backup({
              ...empty(),
              'monthly_reports': [
                {
                  'period': '2026-13',
                  'approved_by': null,
                  'approved_at': null,
                  'verified_by': null,
                  'verified_at': null
                }
              ]
            }),
        throwsA(isA<AppError>()));
  });
  test('Backup accepts legacy total target rows without amount', () {
    expect(
        Backup({...empty(), 'monthly_total_targets': [
          {'period': '2026-10'}
        ]}).tables['monthly_total_targets'], hasLength(1));
  });
}
