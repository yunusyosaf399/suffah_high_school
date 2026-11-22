import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/finance_models.dart';
import 'package:suffah_high_school/data/finance_repository.dart';
import 'package:suffah_high_school/screens/finance_common.dart';
import 'package:suffah_high_school/screens/finance_fees_tab.dart';
import 'package:suffah_high_school/screens/finance_page.dart';
import 'package:suffah_high_school/screens/finance_salary_tab.dart';

class _FinanceTestRepository extends FinanceRepository {
  int salarySubscriptions = 0;
  int feeSubscriptions = 0;

  static const salaryBill = FinanceBill(
    id: 'SAL-202611-EMP-001',
    amountMinor: 2500000,
    paidMinor: 0,
    month: '2026-11',
    category: 'salary',
    title: 'Monthly salary',
    staffId: 'EMP-001',
    staffName: 'Teacher Muhammad Khan',
    basicMinor: 2200000,
    allowanceMinor: 200000,
    bonusMinor: 100000,
  );

  static const feeBill = FinanceBill(
    id: 'FEE-202611-tuition-ST-001',
    amountMinor: 120000,
    paidMinor: 0,
    month: '2026-11',
    category: 'tuition',
    title: 'Monthly tuition',
    studentId: 'ST-001',
    studentName: 'Salah Uddin Khan',
    classId: 'nursery-a',
    className: 'Nursery – A',
  );

  @override
  Stream<List<FinanceBill>> watchSalaryBills() {
    salarySubscriptions++;
    return Stream.value([salaryBill]);
  }

  @override
  Stream<List<FinanceBill>> watchFeeBills() {
    feeSubscriptions++;
    return Stream.value([feeBill]);
  }

  @override
  Future<Map<String, Map<String, dynamic>>> loadTuitionRates() async => {};

  @override
  Future<Map<String, Map<String, dynamic>>> loadTransportRates() async => {};

  @override
  Future<Map<String, Map<String, dynamic>>> loadSalaryRates() async => {};
}

void main() {
  testWidgets('pay salary list shows generated bills and keeps one stream while filtering',
      (tester) async {
    final repository = _FinanceTestRepository();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FinancePaySalaryTab(repository: repository)),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Teacher Muhammad Khan'), findsWidgets);
    expect(find.textContaining('Remaining Rs 25,000.00'), findsOneWidget);
    expect(find.byKey(const Key('finance_pay_salary_SAL-202611-EMP-001')),
        findsOneWidget);
    expect(repository.salarySubscriptions, 1);

    await tester.enterText(find.byKey(const Key('salary_bill_search')), 'muhammad');
    await tester.pumpAndSettle();
    expect(find.textContaining('Teacher Muhammad Khan'), findsWidgets);
    await tester.tap(find.text('Show fully paid salaries'));
    await tester.pumpAndSettle();
    expect(repository.salarySubscriptions, 1,
        reason: 'Typing and toggling filters must not open more Firestore streams.');

    await tester.tap(find.byKey(const Key('finance_refresh_salaries')));
    await tester.pumpAndSettle();
    expect(repository.salarySubscriptions, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collection cards fit narrow Android screens without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(335, 730);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FinanceTestRepository();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FinanceCollectionsTab(repository: repository)),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Salah Uddin Khan'), findsWidgets);
    expect(find.byKey(const Key('finance_collect_FEE-202611-tuition-ST-001')),
        findsOneWidget);
    expect(repository.feeSubscriptions, 1);
    expect(tester.takeException(), isNull,
        reason: 'The Collect action must not overflow its card.');
    await tester.enterText(
      find.byKey(const Key('finance_collections_search')), 'Salah');
    await tester.pumpAndSettle();
    expect(repository.feeSubscriptions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('salary tab is accessible before roster loading and swipes back',
      (tester) async {
    final deferredScope = Completer<FinanceScope>();
    final repository = _FinanceTestRepository();
    await tester.pumpWidget(MaterialApp(
      home: FinancePage(
        role: 'owner',
        repository: repository,
        scopeLoader: () => deferredScope.future,
      ),
    ));
    await tester.pump();

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('finance_next_tab')));
      await tester.pump(const Duration(milliseconds: 450));
    }
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 5);
    expect(find.text('Pay monthly salaries'), findsOneWidget);
    expect(find.textContaining('Teacher Muhammad Khan'), findsWidgets);

    // Drag on the salary list itself, not on the tab strip.
    await tester.drag(find.byType(FinancePaySalaryTab),
      const Offset(300, 0));
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 4);

    await tester.tap(find.byKey(const Key('finance_next_tab')));
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 5);
    expect(find.text('Pay monthly salaries'), findsOneWidget);
    expect(tester.takeException(), isNull);
    deferredScope.complete(const FinanceScope(
      classes: [], students: [], teachers: []));
    await tester.pump();
  });
}
