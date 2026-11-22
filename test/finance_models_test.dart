import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/finance_models.dart';
import 'package:suffah_high_school/data/finance_repository.dart';

void main() {
  test('PKR amounts use integer minor units and reject invalid money', () {
    expect(financeMinorUnits('2500'), 250000);
    expect(financeMinorUnits('2,500.75'), 250075);
    expect(financeMinorUnits('1.5'), 150);
    expect(financeMinorUnits('0.01'), 1);
    expect(financeMoney(250075), 'Rs 2,500.75');
    expect(financeMoney(-150), '-Rs 1.50');
    expect(financeMoney(0), 'Rs 0.00');
    expect(() => financeMinorUnits('0'), throwsArgumentError);
    expect(() => financeMinorUnits('10.333'), throwsArgumentError);
    expect(() => financeMinorUnits('-3'), throwsArgumentError);
    expect(() => financeMinorUnits('word'), throwsArgumentError);
  });

  test('month generation is limited to this month or one previous', () {
    final now = DateTime(2027, 1, 16);
    expect(financeMonth(now), '2027-01');
    expect(previousFinanceMonth(now), '2026-12');
    expect(financeMonthLabel('2026-12'), 'December 2026');
    expect(financeSalaryMonthAllowed('2027-01', now), isTrue);
    expect(financeSalaryMonthAllowed('2026-12', now), isTrue);
    expect(financeSalaryMonthAllowed('2026-11', now), isFalse);
    expect(financeSalaryMonthAllowed('2027-02', now), isFalse);
  });

  test('monthly IDs make repeated generation idempotent', () {
    expect(financeFeeId('2026-11', 'tuition', 'ST-2026-0002'),
      'FEE-202611-tuition-ST-2026-0002');
    expect(financeFeeId('2026-11', 'transport', 'ST-2026-0002'),
      isNot(financeFeeId('2026-11', 'tuition', 'ST-2026-0002')));
    expect(financeSalaryId('2026-11', 'EMP-2026-001'),
      'SAL-202611-EMP-2026-001');
    expect(financeExpenseId('2026-11', 'rent'),
      'EXP-202611-rent');
  });

  test('fee obligations have outstanding balances without cash movement', () {
    const bill = FinanceBill(
      id: 'FEE-202611-tuition-ST-001',
      amountMinor: 600000,
      paidMinor: 200000,
      month: '2026-11',
      category: 'tuition',
      title: 'Monthly tuition',
      studentId: 'ST-001');
    expect(bill.remainingMinor, 400000);
    expect(bill.isPaid, isFalse);
    const fullyPaid = FinanceBill(
      id: 'FEE-202611-transport-ST-001',
      amountMinor: 100000,
      paidMinor: 100000,
      month: '2026-11',
      category: 'transport',
      title: 'Monthly transport');
    expect(fullyPaid.isPaid, isTrue);
    expect(fullyPaid.remainingMinor, 0);
  });

  test('credit and debit analytics exclude unpaid generated bills', () {
    const report = FinanceOverview(
      months: [
        FinanceMonthSummary(
          month: '2026-10',
          creditsMinor: 300000,
          debitsMinor: 80000),
        FinanceMonthSummary(
          month: '2026-11',
          creditsMinor: 200000,
          debitsMinor: 150000),
      ],
      unpaidFeesMinor: 450000,
      unpaidSalariesMinor: 95000,
      unpaidExpensesMinor: 120000,
      recentEntries: [],
    );
    expect(report.creditsMinor, 500000);
    expect(report.debitsMinor, 230000);
    expect(report.netMinor, 270000);
    expect(report.unpaidFeesMinor, 450000);
    expect(report.unpaidSalariesMinor, 95000);
    expect(report.unpaidExpensesMinor, 120000);
  });

  test('one-time and expense categories include all requested types', () {
    expect(financeOneTimeCategories, contains('Certificate Fee'));
    expect(financeOneTimeCategories, contains('Second Tuition Fee'));
    expect(financeOneTimeCategories, contains('Other'));
    expect(financeExpenseCategories['Stationery'],
      containsAll(['Ink', 'Copy Paper', 'Printer']));
    expect(financeExpenseCategories['Transport'],
      containsAll(['Vehicle Fuel', 'Vehicle Maintenance']));
    expect(financeExpenseCategories['Staff Support'],
      contains('Second Tuition Payment to Teacher'));
  });
}
