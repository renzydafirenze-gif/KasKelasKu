import 'package:kaskelasku/data/backup.dart';
import 'package:kaskelasku/data/repository.dart';
import 'package:kaskelasku/models.dart';

CashTransaction sampleEntry(
        {int id = 1,
        int amount = 10000,
        String type = 'IN',
        String category = 'Kas',
        String? contributorId,
        String? contributorName,
        String date = '2026-10-15',
        String description = 'Iuran kelas'}) =>
    CashTransaction(
        id: id,
        amount: amount,
        type: type,
        category: category,
        contributorId: contributorId,
        contributorName: contributorName,
        date: date,
        description: description);

class FakeRepository extends TreasuryRepository {
  FakeRepository({this.active = const Member('one', 'Budi', Role.bendahara)});
  Member? active;
  bool fail = false;
  bool failOpen = false;
  bool failHistory = false;
  bool duplicate = false;
  bool failDelete = false;
  bool closed = false;
  int openCalls = 0;
  final calls = <String>[];
  final historyCalls = <(String, String?, int)>[];
  List<Member> people = const [
    Member('one', 'Budi', Role.bendahara),
    Member('two', 'Siti', Role.siswa),
    Member('three', 'Ketua', Role.ketua)
  ];
  List<CashTransaction> entries = [
    sampleEntry(),
    sampleEntry(
        id: 2,
        amount: 3000,
        type: 'OUT',
        category: 'Alat',
        description: 'Sapu'),
  ];
  int target = 20000;

  void record(String value) {
    if (fail) throw const AppError('Operasi ditolak.');
    calls.add(value);
  }

  @override
  Future<Member?> open() async {
    if (failOpen) throw const AppError('Data rusak.');
    openCalls++;
    return active;
  }

  @override
  Future<Member> createOwner(String name) async {
    if (name.trim().isEmpty) throw const AppError('Nama harus 1–80 karakter.');
    record('owner:$name');
    active = Member('one', name.trim(), Role.bendahara);
    return active!;
  }

  @override
  Future<Member> switchUser(String id) async {
    record('switch:$id');
    if (id == active?.id) return active!;
    active = people.firstWhere((member) => member.id == id);
    return active!;
  }

  @override
  Future<Member> currentMember() async {
    final member = active;
    if (member == null) throw const AppError('Pilih pengguna terlebih dahulu.');
    return member;
  }

  @override
  Future<Overview> overview(String period) async {
    if (fail) throw const AppError('Ringkasan gagal.');
    final income = entries
        .where((row) => row.isIncome)
        .fold<int>(0, (sum, row) => sum + row.amount);
    final expense = entries
        .where((row) => !row.isIncome)
        .fold<int>(0, (sum, row) => sum + row.amount);
    return Overview(
        balance: income + 5000 - expense,
        income: income,
        expense: expense,
        target: target,
        paid: income,
        recent: entries,
        trends: [
          {'period': '2026-09', 'net': 5000},
          {'period': '2026-10', 'net': income - expense}
        ]);
  }

  @override
  Future<Map<String, Object?>> monthSnapshot(String period) async => {
        'opening': 5000,
        'income': 12000,
        'expense': 3000,
        'closing': 14000,
        'target': target,
        'paid': 12000
      };

  @override
  Future<List<CashTransaction>> history(
      {String category = '',
      String keyword = '',
      String? from,
      String? to,
      int limit = 100,
      int offset = 0}) async {
    historyCalls.add((keyword, from, limit));
    if (failHistory) throw const AppError('Riwayat gagal.');
    var rows = entries;
    if (keyword.isNotEmpty) {
      rows = rows
          .where((row) =>
              row.description.toLowerCase().contains(keyword.toLowerCase()) ||
              (row.contributorName ?? '')
                  .toLowerCase()
                  .contains(keyword.toLowerCase()))
          .toList();
    }
    return rows.skip(offset).take(limit).toList();
  }

  @override
  Future<List<Member>> members() async {
    if (fail) throw const AppError('Operasi ditolak.');
    return people;
  }

  @override
  Future<void> addTransaction(CashTransaction entry,
      {bool confirmDuplicate = false}) async {
    entry.validate();
    if (duplicate && !confirmDuplicate) throw const DuplicateTransaction();
    record('transaction:${entry.type}:${entry.amount}:${entry.category}:'
        '${entry.description}:${entry.contributorId}:$confirmDuplicate');
  }

  @override
  Future<void> deleteTransaction(int id) async {
    if (failDelete) throw const AppError('Operasi ditolak.');
    record('delete:$id');
  }

  @override
  Future<void> setTotalMonthlyTarget(String period, int amount) async {
    if (amount < 0) throw const AppError('Target tidak valid.');
    target = amount;
    record('target:$period:$amount');
  }

  @override
  Future<void> close() async {
    closed = true;
    await super.close();
  }

  @override
  Future<void> addMember(String name, Role role) async {
    if (name.trim().isEmpty || name.length > 80) {
      throw const AppError('Nama harus 1–80 karakter.');
    }
    record('member:$name:${role.name}');
  }

  @override
  Future<void> changeMember(Member target, Role role, bool active) async =>
      record('change:${target.id}:${role.name}:$active');

  @override
  Future<void> approve(String period) async => record('approve:$period');

  @override
  Future<void> verify(String period) async => record('verify:$period');

  @override
  Future<Map<String, Object?>> reportSnapshot(String period) async => {
        'period': period,
        'rows': [
          for (final row in entries)
            {
              'tx_date': row.date,
              'type': row.type,
              'category': row.category,
              'contributor_name': row.contributorName,
              'amount': row.amount,
              'description': row.description
            }
        ],
        'status': <String, Object?>{}
      };

  @override
  Future<Map<String, Object?>> backupSnapshot() async {
    if (fail) throw const AppError('Operasi ditolak.');
    return {
      'schema': 1,
      'users': [
        {'id': 'one', 'name': 'Budi', 'role': 'bendahara', 'active': 1}
      ],
      'transactions': <Object?>[],
      'monthly_reports': <Object?>[],
      'monthly_total_targets': <Object?>[],
      'audit_log': <Object?>[]
    };
  }

  @override
  Future<Member> restore(Backup backup) async {
    record('restore:${backup.tables['users']!.length}');
    return active ?? const Member('one', 'Budi', Role.bendahara);
  }
}
