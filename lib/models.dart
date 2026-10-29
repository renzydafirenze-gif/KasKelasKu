import 'dart:convert';
import 'package:crypto/crypto.dart';

enum Role {
  bendahara('Bendahara'),
  ketua('Ketua'),
  guruWali('Guru Wali'),
  siswa('Siswa');

  const Role(this.label);
  final String label;
  static Role parse(String value) =>
      Role.values.firstWhere((r) => r.name == value);
}

class Member {
  const Member(this.id, this.name, this.role, {this.active = true});
  final String id;
  final String name;
  final Role role;
  final bool active;
  factory Member.fromMap(Map<String, Object?> row) => Member(
      row['id']! as String,
      row['name']! as String,
      Role.parse(row['role']! as String),
      active: row['active'] == 1);
}

class CashTransaction {
  CashTransaction(
      {this.id,
      required this.amount,
      required this.type,
      required this.category,
      this.contributorId,
      this.contributorName,
      required this.date,
      required this.description});
  final int? id;
  final int amount;
  final String type;
  final String category;
  final String? contributorId;
  final String? contributorName;
  final String date;
  final String description;
  bool get isIncome => type == 'IN';
  int get signedAmount => isIncome ? amount : -amount;
  void validate() {
    if (amount <= 0 ||
        amount > 1000000000000 ||
        !['IN', 'OUT'].contains(type) ||
        category.trim().isEmpty ||
        category.length > 80 ||
        description.trim().isEmpty ||
        description.length > 1000 ||
        !validDate(date)) {
      throw const AppError('Isian transaksi tidak valid.');
    }
  }

  String get fingerprint => sha256
      .convert(utf8.encode(jsonEncode([
        amount,
        type,
        category.trim().toLowerCase(),
        date,
        description.trim().toLowerCase(),
      ])))
      .toString();
  factory CashTransaction.fromMap(Map<String, Object?> row) => CashTransaction(
      id: row['id']! as int,
      amount: row['amount']! as int,
      type: row['type']! as String,
      category: row['category']! as String,
      contributorId: row['contributor_id'] as String?,
      contributorName: row['contributor_name'] as String?,
      date: row['tx_date']! as String,
      description: row['description']! as String);
}

class StudentPayment {
  const StudentPayment(this.member, this.total, this.count);
  final Member member;
  final int total;
  final int count;
  bool get paid => count > 0;
}

class Overview {
  const Overview(
      {required this.balance,
      required this.income,
      required this.expense,
      required this.target,
      required this.paid,
      required this.recent,
      required this.trends});
  final int balance;
  final int income;
  final int expense;
  final int target;
  final int paid;
  final List<CashTransaction> recent;
  final List<Map<String, Object?>> trends;
}

bool validDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final date = DateTime.tryParse(value);
  return date != null &&
      date.year >= 2000 &&
      date.year <= 9999 &&
      date.toIso8601String().substring(0, 10) == value;
}

String isoDate(DateTime date) => date.toIso8601String().substring(0, 10);
String monthOf(DateTime date) => isoDate(date).substring(0, 7);
void validateMonth(String period) {
  if (!validDate('$period-01')) throw const AppError('Bulan tidak valid.');
}

class AppError implements Exception {
  const AppError(this.message);
  final String message;
  @override
  String toString() => message;
}

class DuplicateTransaction extends AppError {
  // coverage:ignore-start
  const DuplicateTransaction()
      : super('Transaksi serupa sudah ada. Tetap simpan?');
  // coverage:ignore-end
}
