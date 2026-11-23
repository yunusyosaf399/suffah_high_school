import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/finance_models.dart';
import 'package:suffah_high_school/data/finance_repository.dart';

void main() {
  test('saved November Firestore salary document decodes correctly', () {
    const id = 'SAL-202611-EMP-2026-0001';
    final bill = FinanceBill.fromData(id, {
      'billId': id,
      'category': 'salary',
      'month': '2026-11',
      'title': 'Monthly salary',
      'staffId': 'EMP-2026-0001',
      'staffName': 'Test Teacher',
      'basicMinor': 10000000,
      'allowanceMinor': 100000,
      'bonusMinor': 50000,
      'amountMinor': 10150000,
      'paidMinor': 0,
      'currency': 'PKR',
      'status': 'unpaid',
    });
    expect(bill.id, id);
    expect(bill.staffName, 'Test Teacher');
    expect(bill.month, '2026-11');
    expect(financeMonthLabel(bill.month), 'November 2026');
    expect(bill.amountMinor, 10150000);
    expect(bill.remainingMinor, 10150000);
    expect(bill.isPaid, false);
    expect(financeMoney(bill.remainingMinor), 'Rs 101,500.00');
    expect(financeSalaryId(bill.month, bill.staffId), id);
  });

  test('salary with a partial payment remains payable', () {
    final bill = FinanceBill.fromData('SAL-202610-EMP-1', {
      'category': 'salary',
      'title': 'Monthly salary',
      'month': '2026-10',
      'staffId': 'EMP-1',
      'staffName': 'Staff One',
      'amountMinor': 2400000,
      'paidMinor': 600000,
      'basicMinor': 2400000,
      'status': 'partial',
    });
    expect(bill.remainingMinor, 1800000);
    expect(bill.isPaid, isFalse);
  });

  test('repository-declared salary bill path matches the rules', () {
    final repository = File('lib/data/finance_repository.dart').readAsStringSync();
    final rules = File('firestore.rules').readAsStringSync();
    expect(repository, contains("_db.collection('finance_salary_bills')"));
    expect(rules, contains('match /finance_salary_bills/{billId} {'));
    expect(rules, contains('allow get, list: if canManageAdmissions();'));
  });
}
