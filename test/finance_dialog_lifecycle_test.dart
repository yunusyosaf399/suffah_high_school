import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/finance_repository.dart';
import 'package:suffah_high_school/data/school_repository.dart';
import 'package:suffah_high_school/data/staff_repository.dart';
import 'package:suffah_high_school/screens/finance_common.dart';
import 'package:suffah_high_school/screens/finance_fees_tab.dart';
import 'package:suffah_high_school/screens/finance_salary_tab.dart';

class _FakeFinanceRepository extends FinanceRepository {
  final Map<String, Map<String, dynamic>> tuition = {};
  final Map<String, Map<String, dynamic>> transport = {};
  final Map<String, Map<String, dynamic>> salaries = {};

  int savedTuition = 0;
  int savedTransport = 0;
  int savedSalary = 0;

  @override
  Future<Map<String, Map<String, dynamic>>> loadTuitionRates() async => tuition;

  @override
  Future<Map<String, Map<String, dynamic>>> loadTransportRates() async => transport;

  @override
  Future<Map<String, Map<String, dynamic>>> loadSalaryRates() async => salaries;

  @override
  Future<void> setTuition({
    required SchoolClass schoolClass,
    required int amountMinor,
  }) async {
    savedTuition++;
    tuition[schoolClass.id] = {'amountMinor': amountMinor};
  }

  @override
  Future<int> setTransport({
    required List<StudentRecord> students,
    required Map<String, SchoolClass> classes,
    required int amountMinor,
  }) async {
    savedTransport++;
    for (final student in students) {
      transport[student.id] = {'amountMinor': amountMinor, 'active': amountMinor > 0};
    }
    return students.length;
  }

  @override
  Future<void> setSalary({
    required StaffMember teacher,
    required int basicMinor,
    required int allowanceMinor,
    required int bonusMinor,
    required String notes,
  }) async {
    savedSalary++;
    salaries[teacher.id] = {
      'basicMinor': basicMinor,
      'allowanceMinor': allowanceMinor,
      'bonusMinor': bonusMinor,
      'amountMinor': basicMinor + allowanceMinor + bonusMinor,
    };
  }
}

void main() {
  const classes = [
    SchoolClass(id: 'nursery-a', name: 'Nursery', section: 'A', active: true),
    SchoolClass(id: 'one-a', name: 'Class One', section: 'A', active: true),
  ];
  const students = [
    StudentRecord(
      id: 'ST-001', admissionNo: 'ST-001', fullName: 'Ali Khan',
      classId: 'nursery-a', guardianName: '', guardianPhone: '',
      gender: '', rollNo: '10001', active: true),
  ];
  const teacher = StaffMember(
    id: 'EMP-001', staffNo: 'EMP-001', fullName: 'Teacher One',
    roleType: 'teacher', designation: 'Teacher', phone: '', active: true,
  );

  testWidgets('tuition dialog can close, reopen, validate and save without crash',
      (tester) async {
    final repo = _FakeFinanceRepository();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: FinanceFeeSetupTab(
        role: 'owner',
        scope: const FinanceScope(
          classes: classes, students: students, teachers: []),
        repository: repo,
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tuition fee setup'));
    await tester.pumpAndSettle();
    expect(find.text('Monthly tuition fee setup'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Tuition fee setup'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_tuition_rate')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter an amount'), findsWidgets);
    await tester.enterText(find.byType(TextFormField).last, '2500');
    await tester.tap(find.byKey(const Key('save_tuition_rate')));
    await tester.pumpAndSettle();

    expect(repo.savedTuition, 1);
    expect(repo.tuition['nursery-a']!['amountMinor'], 250000);
    expect(find.text('Monthly tuition fee setup'), findsNothing);
    expect(tester.takeException(), isNull);

    // Re-enter after Navigator's pop transition finishes: no stale controller.
    await tester.tap(find.text('Tuition fee setup'));
    await tester.pumpAndSettle();
    expect(find.text('Monthly tuition fee setup'), findsOneWidget);
    expect(find.text('2500.00'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('transport dialog can select student and apply zero without crash',
      (tester) async {
    final repo = _FakeFinanceRepository();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: FinanceFeeSetupTab(
        role: 'owner',
        scope: const FinanceScope(
          classes: classes, students: students, teachers: []),
        repository: repo,
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transport fee setup'));
    await tester.pumpAndSettle();
    expect(find.text('Monthly transport fee setup'), findsOneWidget);
    await tester.tap(find.byKey(const Key('select_transport_students')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finance_select_ST-001')));
    // Rebuild the picker so its initially disabled Apply button becomes enabled.
    await tester.pumpAndSettle();
    expect(find.text('Apply (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('finance_apply_student_selection')));
    await tester.pumpAndSettle();
    expect(find.text('1 students selected'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, '0');
    await tester.tap(find.byKey(const Key('save_transport_rates')));
    await tester.pumpAndSettle();
    expect(repo.savedTransport, 1);
    expect(repo.transport['ST-001']!['amountMinor'], 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('salary dialog remains mounted until pop animation completes',
      (tester) async {
    final repo = _FakeFinanceRepository();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: FinanceSalarySetupTab(
        scope: const FinanceScope(
          classes: [], students: [], teachers: [teacher]),
        repository: repo,
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('salary_setup_EMP-001')));
    await tester.pumpAndSettle();
    expect(find.text('Salary setup · Teacher One'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '20000');
    await tester.tap(find.byKey(const Key('save_salary_setup')));
    await tester.pumpAndSettle();
    expect(repo.savedSalary, 1);
    expect(repo.salaries['EMP-001']!['amountMinor'], 2000000);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('salary_setup_EMP-001')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
