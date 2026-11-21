import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/admission_repository.dart';
import 'package:suffah_high_school/data/school_repository.dart';
import 'package:suffah_high_school/screens/admission_wizard_page.dart';

void main() {
  const record = AdmissionRecord(
    id: 'ST-2026-0001',
    registrationNo: 'ST-2026-0001',
    rollNo: '10000',
    status: 'draft',
    step: 0,
    details: {
      'academic': {'admissionDate': '2026-11-21', 'campus': 'Main'},
    },
  );
  const classes = [
    SchoolClass(id: 'grade-1-a', name: 'Grade 1', section: 'A', active: true),
  ];

  testWidgets('admission form shows reserved read-only identifiers and tabs',
      (tester) async {
    final saves = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AdmissionWizardPage(
          record: record,
          classes: classes,
          saveOverride: (details, step, complete) async {
            saves.add(step);
          },
        ),
      ),
    );
    expect(find.text('Reg: ST-2026-0001'), findsOneWidget);
    expect(find.text('Roll: 10000'), findsOneWidget);
    expect(find.text('1. Student'), findsOneWidget);
    expect(find.text('2. Contact'), findsOneWidget);
    expect(find.text('6. Review'), findsOneWidget);
    expect(find.text('6. Documents'), findsNothing);
    expect(find.text('Student personal details'), findsOneWidget);
    expect(find.text('Save draft'), findsWidgets);

    await tester.tap(find.text('2. Contact'));
    await tester.pumpAndSettle();
    expect(find.text('Contact and residential address'), findsOneWidget);
    await tester.tap(find.text('1. Student'));
    await tester.pumpAndSettle();
    expect(find.text('Student personal details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save draft closes without demanding mandatory fields',
      (tester) async {
    bool saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AdmissionWizardPage(
          record: record,
          classes: classes,
          saveOverride: (details, step, complete) async {
            saved = true;
            expect(complete, isFalse);
          },
        ),
      ),
    );
    // Bottom navigation has a separate Save draft action.
    await tester.tap(find.text('Save draft').last);
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(find.byType(AdmissionWizardPage), findsNothing);
  });

  testWidgets('completed details require a final review and confirm admission',
      (tester) async {
    var confirmed = false;
    const reviewRecord = AdmissionRecord(
      id: 'ST-2026-0002',
      registrationNo: 'ST-2026-0002',
      rollNo: '10001',
      status: 'draft',
      step: 5,
      details: {
        'student': {
          'firstName': 'Bilal',
          'lastName': 'Khan',
          'dateOfBirth': '2017-06-04',
        },
        'guardian': {
          'firstName': 'Yousaf',
          'lastName': 'Khan',
          'phone': '03001234567',
          'relationship': 'Father',
        },
        'academic': {
          'classId': 'grade-1-a',
          'campus': 'Main',
          'admissionDate': '2026-11-21',
        },
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: AdmissionWizardPage(
        record: reviewRecord,
        classes: classes,
        saveOverride: (details, step, complete) async {
          confirmed = complete;
          expect(step, 5);
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Review admission'), findsOneWidget);
    expect(find.text('Review & admit'), findsOneWidget);
    expect(find.text('Reg: ST-2026-0002'), findsOneWidget);
    await tester.tap(find.text('Review & admit'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm student admission'), findsOneWidget);
    await tester.tap(find.text('Apply admission'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('admitted student review saves changes instead of readmitting',
      (tester) async {
    const existing = AdmissionRecord(
      id: 'ST-2026-0003',
      registrationNo: 'ST-2026-0003',
      rollNo: '10002',
      status: 'admitted',
      step: 5,
      details: {
        'student': {
          'firstName': 'Mariam', 'lastName': 'Khan',
          'dateOfBirth': '2018-02-02',
        },
        'guardian': {
          'firstName': 'Faisal', 'lastName': 'Khan',
          'phone': '03001234567', 'relationship': 'Father',
        },
        'academic': {'classId': 'grade-1-a', 'campus': 'Main'},
      },
    );
    var changed = false;
    await tester.pumpWidget(MaterialApp(
      home: AdmissionWizardPage(
        record: existing,
        classes: classes,
        saveOverride: (details, step, complete) async {
          changed = complete;
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Save reviewed changes'), findsOneWidget);
    await tester.tap(find.text('Save reviewed changes'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm student changes'), findsOneWidget);
    await tester.tap(find.text('Save changes').last);
    await tester.pumpAndSettle();
    expect(changed, isTrue);
  });
}
