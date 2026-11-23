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
  _FinanceTestRepository({List<FinanceBill>? salaries})
      : salaryRecords = salaries ?? [salaryBill];

  final List<FinanceBill> salaryRecords;
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
  Future<List<FinanceBill>> loadSalaryBills() async {
    salarySubscriptions++;
    return salaryRecords;
  }

  @override
  Stream<List<FinanceBill>> watchSalaryBills() =>
      Stream.value(salaryRecords);

  @override
  Future<FinanceBill?> probeSalaryBill(String billId) async {
    for (final bill in salaryRecords) {
      if (bill.id == billId) return bill;
    }
    return null;
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

class _PendingSalaryRepository extends FinanceRepository {
  final Completer<List<FinanceBill>> pending = Completer<List<FinanceBill>>();

  @override
  Future<List<FinanceBill>> loadSalaryBills() => pending.future;
}

class _FailedSalaryRepository extends FinanceRepository {
  @override
  Future<List<FinanceBill>> loadSalaryBills() async {
    throw StateError('The test server rejected the salary read.');
  }
}

void main() {
  testWidgets('salary status and bills are visible on a real phone-sized screen',
      (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _PendingSalaryRepository();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FinancePaySalaryTab(repository: repository)),
    ));
    await tester.pump();

    expect(find.byKey(const Key('salary_pay_scroll')), findsOneWidget);
    expect(find.byKey(const Key('salary_server_view_version')), findsOneWidget);
    expect(find.textContaining('Redesign v5'), findsOneWidget);
    expect(find.text('Read status: Loading saved salaries…'), findsOneWidget);
    expect(find.byKey(const Key('salary_read_status')), findsOneWidget);
    expect(
      tester.getBottomRight(find.byKey(const Key('salary_read_status'))).dy,
      lessThan(760),
      reason: 'The salary loading status must be on screen without scrolling.',
    );

    repository.pending.complete(const [
      FinanceBill(
        id: 'SAL-202610-EMP-A', month: '2026-10', category: 'salary',
        title: 'Monthly salary', staffId: 'EMP-A',
        staffName: 'Teacher Ali', amountMinor: 1000000,
        paidMinor: 0, basicMinor: 1000000,
      ),
      FinanceBill(
        id: 'SAL-202611-EMP-B', month: '2026-11', category: 'salary',
        title: 'Monthly salary', staffId: 'EMP-B',
        staffName: 'Teacher Bilal', amountMinor: 1200000,
        paidMinor: 0, basicMinor: 1200000,
      ),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Read status: 2 saved salaries loaded · 2 shown'), findsOneWidget);
    expect(find.textContaining('Teacher Ali'), findsOneWidget);
    expect(find.textContaining('Teacher Bilal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('four fetched Firestore salaries render actual payment cards on phone',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FinanceTestRepository(salaries: [
      for (var i = 0; i < 4; i++)
        FinanceBill.fromData('SAL-2026${i.isEven ? '11' : '10'}-EMP-$i', {
          'staffName': 'Teacher ${i + 1}',
          'staffId': 'EMP-$i',
          'month': i.isEven ? '2026-11' : '2026-10',
          'category': 'salary',
          'amountMinor': 10150000,
          'basicMinor': 10000000,
          'allowanceMinor': 100000,
          'bonusMinor': 50000,
          'paidMinor': 0,
          'status': 'unpaid',
          'title': 'Monthly salary',
        }),
    ]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: FinancePaySalaryTab(repository: repository),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Read status: 4 saved salaries loaded · 4 shown'),
        findsOneWidget);
    expect(find.byKey(const Key('salary_results_heading')), findsOneWidget);
    expect(find.byKey(const Key('salary_bill_SAL-202611-EMP-0')),
        findsOneWidget);
    expect(find.textContaining('Teacher 1'), findsOneWidget);
    expect(find.text('Remaining balance'), findsAtLeastNWidgets(1));
    expect(find.text('Rs 101,500.00'), findsAtLeastNWidgets(1));
    expect(find.byKey(const Key('finance_pay_salary_SAL-202611-EMP-0')),
        findsOneWidget);
    final firstTop = tester.getTopLeft(
      find.byKey(const Key('salary_bill_SAL-202611-EMP-0')));
    expect(firstTop.dy, lessThan(915),
        reason: 'A loaded salary must actually appear inside the phone viewport.');
    expect(
      tester.getTopLeft(find.byKey(const Key('salary_results_heading'))).dy,
      greaterThan(tester.getTopLeft(find.text('Pay monthly salaries')).dy),
      reason: 'Results heading must render below the page title.',
    );
    expect(
      firstTop.dy,
      greaterThan(tester.getTopLeft(
        find.byKey(const Key('salary_results_heading'))).dy),
      reason: 'Salary cards must render below the results heading.',
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('salary_bill_SAL-202610-EMP-3')),
      150,
      scrollable: find.descendant(
        of: find.byKey(const Key('salary_pay_scroll')),
        matching: find.byType(Scrollable),
      ).first,
    );
    expect(find.textContaining('Teacher 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed salary server request leaves a visible error and retry',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FinancePaySalaryTab(
        repository: _FailedSalaryRepository(),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('salary_server_view_version')), findsOneWidget);
    expect(find.text('Read status: Failed to load salaries'), findsOneWidget);
    expect(find.byKey(const Key('salary_server_error')), findsOneWidget);
    expect(find.textContaining('test server rejected'), findsOneWidget,
      reason: 'A failed Firestore read must expose an actionable diagnostic.');
    expect(find.byKey(const Key('finance_salary_retry')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pay salary list shows generated bills and keeps one stream while filtering',
      (tester) async {
    final repository = _FinanceTestRepository();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FinancePaySalaryTab(repository: repository)),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Teacher Muhammad Khan'), findsWidgets);
    expect(find.text('Remaining balance'), findsOneWidget);
    expect(find.text('Rs 25,000.00'), findsAtLeastNWidgets(1));
    expect(find.byKey(const Key('salary_read_status')), findsOneWidget);
    expect(find.byKey(const Key('finance_pay_salary_SAL-202611-EMP-001')),
        findsOneWidget);
    expect(repository.salarySubscriptions, 1);

    await tester.enterText(find.byKey(const Key('salary_bill_search')), 'muhammad');
    await tester.pumpAndSettle();
    expect(find.textContaining('Teacher Muhammad Khan'), findsWidgets);
    await tester.tap(find.text('Show fully paid salaries'));
    await tester.pumpAndSettle();
    expect(repository.salarySubscriptions, 1,
        reason: 'Typing and toggling filters must not repeat salary server queries.');

    await tester.tap(find.byKey(const Key('finance_refresh_salaries')));
    await tester.pumpAndSettle();
    expect(repository.salarySubscriptions, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only salary document probe checks exact bill without writes',
      (tester) async {
    final repository = _FinanceTestRepository();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: FinancePaySalaryTab(repository: repository),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('finance_salary_probe')));
    await tester.pumpAndSettle();
    expect(find.text('Check a saved salary document'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('salary_probe_document_id')),
      'SAL-202611-EMP-001',
    );
    await tester.tap(find.byKey(const Key('salary_probe_read')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Document GET succeeded'), findsOneWidget);
    expect(find.textContaining('Teacher Muhammad Khan'), findsWidgets);
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

  testWidgets('two existing October salaries remain visible across finance tab changes',
      (tester) async {
    final repository = _FinanceTestRepository(salaries: const [
      FinanceBill(
        id: 'SAL-202610-EMP-001', month: '2026-10',
        category: 'salary', title: 'Monthly salary',
        staffId: 'EMP-001', staffName: 'Teacher One',
        amountMinor: 2000000, paidMinor: 0, basicMinor: 2000000,
      ),
      FinanceBill(
        id: 'SAL-202610-EMP-002', month: '2026-10',
        category: 'salary', title: 'Monthly salary',
        staffId: 'EMP-002', staffName: 'Teacher Two',
        amountMinor: 2200000, paidMinor: 0, basicMinor: 2200000,
      ),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: FinancePage(
        role: 'owner',
        repository: repository,
        scopeLoader: () async => const FinanceScope(
          classes: [], students: [], teachers: []),
      ),
    ));
    await tester.pumpAndSettle();
    expect(repository.salarySubscriptions, 0,
        reason: 'Inactive finance tabs must not query the salary collection.');

    // Visit Generate Finance, then advance to Pay Salary.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const Key('finance_next_tab')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Pay monthly salaries'), findsOneWidget);
    expect(find.textContaining('Teacher One'), findsOneWidget);
    expect(find.text('Read status: 2 saved salaries loaded · 2 shown'), findsOneWidget);
    // Flutter lazily mounts cards below the fold. Scroll to verify both
    // existing records rather than assuming both fit the viewport.
    await tester.scrollUntilVisible(
      find.textContaining('Teacher Two'),
      140,
      scrollable: find.descendant(
        of: find.byKey(const Key('salary_pay_scroll')),
        matching: find.byType(Scrollable),
      ).first,
    );
    expect(find.textContaining('Teacher Two'), findsOneWidget);
    expect(repository.salarySubscriptions, 1);

    // Navigate away and return; the visible content must match selected tab.
    await tester.tap(find.byKey(const Key('finance_previous_tab')));
    await tester.pumpAndSettle();
    expect(find.text('Teacher salary setup'), findsOneWidget);
    expect(find.text('Pay monthly salaries'), findsNothing);
    await tester.tap(find.byKey(const Key('finance_next_tab')));
    await tester.pumpAndSettle();
    expect(find.text('Pay monthly salaries'), findsOneWidget);
    expect(find.text('Read status: 2 saved salaries loaded · 2 shown'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Teacher Two'),
      140,
      scrollable: find.descendant(
        of: find.byKey(const Key('salary_pay_scroll')),
        matching: find.byType(Scrollable),
      ).first,
    );
    expect(find.textContaining('Teacher Two'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('salary tab is accessible before roster loading and swipes back',
      (tester) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
    }
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 5);
    expect(find.text('Pay monthly salaries'), findsOneWidget);
    // The StreamBuilder subscribes only after the salary page first mounts;
    // allow the Stream.value event and its next frame to be delivered.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Teacher Muhammad Khan'), findsWidgets);

    // Drag on the salary list itself, not on the tab strip.
    await tester.fling(
      find.byType(FinancePaySalaryTab),
      const Offset(280, 0),
      1300,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 4);

    await tester.tap(find.byKey(const Key('finance_next_tab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 5);
    expect(find.text('Pay monthly salaries'), findsOneWidget);
    expect(tester.takeException(), isNull);
    deferredScope.complete(const FinanceScope(
      classes: [], students: [], teachers: []));
    await tester.pump();
  });
}
