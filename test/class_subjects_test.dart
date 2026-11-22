import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/class_subject_repository.dart';
import 'package:suffah_high_school/data/school_repository.dart';
import 'package:suffah_high_school/screens/class_subjects_page.dart';

void main() {
  test('subject IDs are stable and class-specific documents can share names', () {
    expect(classSubjectId(' Mathematics '), 'mathematics');
    expect(classSubjectId('Computer Science'), 'computer-science');
    expect(classSubjectId(''), '');
  });

  testWidgets('owner can add a subject with details to a class', (tester) async {
    String? name;
    String? code;
    String? details;
    int? periods;
    await tester.pumpWidget(MaterialApp(
      home: ClassSubjectsPage(
        schoolClass: const SchoolClass(
          id: 'grade-5-a', name: 'Grade 5', section: 'A', active: true),
        subjectsStream: Stream.value(<ClassSubject>[]),
        onSave: (existing, enteredName, enteredCode, description, weekly) async {
          expect(existing, isNull);
          name = enteredName;
          code = enteredCode;
          details = description;
          periods = weekly;
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No subjects yet. Add subjects here before assigning teachers.'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('add_class_subject')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('subject_name_field')), 'Mathematics');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Subject code'), 'MATH-05');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Periods per week (0–30)'), '5');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description / syllabus details'),
      'Fractions, decimals and geometry');
    await tester.tap(find.byKey(const Key('save_class_subject')));
    await tester.pumpAndSettle();
    expect(name, 'Mathematics');
    expect(code, 'MATH-05');
    expect(details, 'Fractions, decimals and geometry');
    expect(periods, 5);
    expect(tester.takeException(), isNull);
  });
}
