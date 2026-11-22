import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/finance_models.dart';
import 'package:suffah_high_school/data/finance_repository.dart';
import 'package:suffah_high_school/screens/finance_common.dart';
import 'package:suffah_high_school/screens/finance_fees_tab.dart';
import 'package:suffah_high_school/screens/finance_page.dart';

class _FakeFinanceRepository extends FinanceRepository {
  @override
  Future<Map<String, Map<String, dynamic>>> loadTuitionRates() async => {};
  @override
  Future<Map<String, Map<String, dynamic>>> loadTransportRates() async => {};
  @override
  Future<Map<String, Map<String, dynamic>>> loadSalaryRates() async => {};
  @override
  Stream<List<FinanceBill>> watchFeeBills() =>
      Stream.value(const <FinanceBill>[]);
  @override
  Stream<List<FinanceBill>> watchSalaryBills() =>
      Stream.value(const <FinanceBill>[]);
  @override
  Future<FinanceOverview> loadOverview({DateTime? at}) async =>
      const FinanceOverview(
        months: [
          FinanceMonthSummary(month: '2026-11', creditsMinor: 10000),
        ],
        unpaidFeesMinor: 0,
        unpaidSalariesMinor: 0,
        unpaidExpensesMinor: 0,
        recentEntries: [],
      );
}

void main() {
  testWidgets('finance page shows owner tabs and can switch to generation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FinancePage(
        role: 'owner',
        repository: _FakeFinanceRepository(),
        scopeLoader: () async => const FinanceScope(
          classes: [], students: [], teachers: []),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Fees & Finance'), findsOneWidget);
    expect(find.text('Monthly fee setup'), findsOneWidget);
    expect(find.text('Tuition fee setup'), findsOneWidget);
    await tester.tap(find.text('Generate Finance').first);
    await tester.pumpAndSettle();
    expect(find.text('Generate monthly finance'), findsOneWidget);
    expect(find.byKey(const Key('generate_finance_button')), findsOneWidget);
    expect(find.text('Monthly schedule preferences'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-administrator cannot open finances',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: FinancePage(role: 'teacher'),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Only the school owner or principal'),
        findsOneWidget);
    expect(find.text('Fee Setup'), findsNothing);
  });

  testWidgets('payment dialog tracks partial payment and receipt',
      (tester) async {
    const bill = FinanceBill(
      id: 'FEE-202611-tuition-ST-001',
      amountMinor: 600000,
      paidMinor: 150000,
      month: '2026-11',
      category: 'tuition',
      title: 'Monthly tuition',
      studentId: 'ST-001',
      studentName: 'Ali Khan',
    );
    int? submitted;
    String? receipt;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => FilledButton(
        onPressed: () async {
          receipt = await showDialog<String>(
            context: context,
            builder: (_) => FinancePaymentDialog(
              bill: bill,
              title: 'Collect fee',
              submitLabel: 'Record credit',
              onPay: (amount, method, reference, notes, payerName) async {
                submitted = amount;
                return 'TXN-001';
              },
            ),
          );
        },
        child: const Text('Open payment'),
      )),
    )));
    await tester.tap(find.text('Open payment'));
    await tester.pumpAndSettle();
    expect(find.text('Outstanding: Rs 4,500.00'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('finance_payment_amount')), '2000');
    await tester.pumpAndSettle();
    expect(find.text('Remains after payment: Rs 2,500.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('finance_confirm_payment')));
    await tester.pumpAndSettle();
    expect(submitted, 200000);
    expect(receipt, 'TXN-001');
    expect(tester.takeException(), isNull);
  });
}
