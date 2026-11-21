import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/payroll_repository.dart';

void main() {
  test('payroll receipt numbers are stable and sequential', () {
    expect(payrollReceiptNumber(2026, 1), 'SAL-2026-0001');
    expect(payrollReceiptNumber(2026, 19), 'SAL-2026-0019');
    expect(() => payrollReceiptNumber(2026, 0), throwsArgumentError);
    expect(() => payrollReceiptNumber(2026, 10000), throwsArgumentError);
  });

  test('payroll input calculates net salary and validates amounts', () {
    const input = PayrollInput(
      staffId: 'EMP-2026-0001',
      period: '2026-11',
      basicSalary: 50000,
      allowances: 5000,
      deductions: 2500,
      status: 'unpaid',
      paymentMethod: '',
    );
    expect(input.netSalary, 52500);
    expect(input.validate(), isNull);
  });

  test('payroll rejects invalid period, negative amounts and excess deductions', () {
    const invalidPeriod = PayrollInput(
      staffId: 'EMP-2026-0001',
      period: 'Nov 2026',
      basicSalary: 50000,
      allowances: 0,
      deductions: 0,
      status: 'unpaid',
      paymentMethod: '',
    );
    expect(invalidPeriod.validate(), 'Enter the pay period as YYYY-MM.');

    const excessDeduction = PayrollInput(
      staffId: 'EMP-2026-0001',
      period: '2026-11',
      basicSalary: 10000,
      allowances: 0,
      deductions: 12000,
      status: 'unpaid',
      paymentMethod: '',
    );
    expect(excessDeduction.validate(),
      'Deductions cannot exceed gross salary.');

    const missingPaidDate = PayrollInput(
      staffId: 'EMP-2026-0001',
      period: '2026-11',
      basicSalary: 10000,
      allowances: 0,
      deductions: 0,
      status: 'paid',
      paymentMethod: 'Cash',
    );
    expect(missingPaidDate.validate(),
      'Enter the payment date for a paid salary.');
  });
}
