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
}
