import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/admission_repository.dart';
import 'package:suffah_high_school/data/school_repository.dart';
import 'package:suffah_high_school/screens/student_profile_page.dart';

void main() {
  const classes = [
    SchoolClass(
      id: 'grade-1-a',
      name: 'Grade 1',
      section: 'A',
      active: true,
    ),
  ];
  final record = AdmissionRecord.fromData('ST-2026-0001', {
    'admissionNo': 'ST-2026-0001',
    'rollNo': '10000',
    'status': 'admitted',
    'details': {
      'student': {
        'firstName': 'Aisha',
        'middleName': 'Noor',
        'lastName': 'Khan',
        'dateOfBirth': '2019-04-11',
        'gender': 'Female',
      },
      'guardian': {
        'firstName': 'Khalid',
        'lastName': 'Khan',
        'relationship': 'Father',
        'phone': '03001234567',
      },
      'academic': {
        'classId': 'grade-1-a',
        'campus': 'Main',
      },
      'contact': {
        'city': 'Peshawar',
      },
      'health': {
        'bloodGroup': 'O+',
      },
    },
  });

  test('admitted student editing roles are owner and principal only', () {
    expect(canEditAdmittedStudent('owner'), true);
    expect(canEditAdmittedStudent('principal'), true);
    expect(canEditAdmittedStudent('teacher'), false);
    expect(canEditAdmittedStudent('parent'), false);
    expect(canEditAdmittedStudent('accountant'), false);
    expect(canEditAdmittedStudent('viewer'), false);
  });

  testWidgets('parent profile is read-only and displays student details',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StudentProfilePage(
          studentId: record.id,
          role: 'parent',
          classes: classes,
          initialRecord: record,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Student profile'), findsOneWidget);
    expect(find.text('Aisha Noor Khan'), findsOneWidget);
    expect(find.text('ST-2026-0001'), findsOneWidget);
    expect(find.text('10000'), findsOneWidget);
    expect(find.text('Admitted · Details locked'), findsOneWidget);
    expect(find.text('Edit student'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byKey(const Key('student_profile_sections')), findsOneWidget);
  });

  testWidgets('principal profile offers explicit edit action', (tester) async {
    var edited = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StudentProfilePage(
          studentId: record.id,
          role: 'principal',
          classes: classes,
          initialRecord: record,
          onEditOverride: () async { edited = true; },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final action = find.text('Edit student');
    expect(action, findsOneWidget);
    await tester.tap(action);
    await tester.pump();
    expect(edited, isTrue);
    expect(tester.takeException(), isNull);
  });
}
