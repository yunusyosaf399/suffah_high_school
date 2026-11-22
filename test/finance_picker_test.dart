import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/school_repository.dart';
import 'package:suffah_high_school/screens/finance_common.dart';

void main() {
  const classes = [
    SchoolClass(id: 'g1-a', name: 'Grade 1', section: 'A', active: true),
    SchoolClass(id: 'g2-a', name: 'Grade 2', section: 'A', active: true),
  ];
  const students = [
    StudentRecord(
      id: 'ST-001', admissionNo: 'ST-001', fullName: 'Ali Khan',
      classId: 'g1-a', guardianName: '', guardianPhone: '',
      gender: '', rollNo: '10001', active: true),
    StudentRecord(
      id: 'ST-002', admissionNo: 'ST-002', fullName: 'Aisha Khan',
      classId: 'g1-a', guardianName: '', guardianPhone: '',
      gender: '', rollNo: '10002', active: true),
    StudentRecord(
      id: 'ST-003', admissionNo: 'ST-003', fullName: 'Usman Khan',
      classId: 'g2-a', guardianName: '', guardianPhone: '',
      gender: '', rollNo: '10003', active: true),
  ];

  testWidgets('fee payer picker selects a single student without other classes',
      (tester) async {
    List<StudentRecord>? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => FilledButton(
        onPressed: () async {
          result = await showDialog<List<StudentRecord>>(
            context: context,
            builder: (_) => const FinanceStudentPicker(
              students: students, classes: classes),
          );
        },
        child: const Text('Choose students'),
      )),
    )));
    await tester.tap(find.text('Choose students'));
    await tester.pumpAndSettle();
    expect(find.text('Ali Khan'), findsOneWidget);
    expect(find.text('Usman Khan'), findsOneWidget);
    await tester.tap(find.byKey(const Key('finance_select_ST-002')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
      const Key('finance_apply_student_selection')));
    await tester.pumpAndSettle();
    expect(result?.map((s) => s.id).toList(), ['ST-002']);
  });

  testWidgets('student selection can select all matching students',
      (tester) async {
    List<StudentRecord>? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => FilledButton(
        onPressed: () async {
          result = await showDialog<List<StudentRecord>>(
            context: context,
            builder: (_) => const FinanceStudentPicker(
              students: students, classes: classes),
          );
        },
        child: const Text('Choose students'),
      )),
    )));
    await tester.tap(find.text('Choose students'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select shown'));
    await tester.pumpAndSettle();
    expect(find.text('3 selected · 3 shown'), findsOneWidget);
    await tester.tap(find.byKey(
      const Key('finance_apply_student_selection')));
    await tester.pumpAndSettle();
    expect(result?.length, 3);
  });
}
